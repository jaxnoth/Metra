using System.Diagnostics;
using System.Text.Json;

namespace Metra.Host;

internal static class HostPaths
{
    public static string DataDir
    {
        get
        {
            var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(baseDir))
            {
                baseDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "AppData", "Local");
            }

            var dir = Path.Combine(baseDir, "Metra");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string HostPidFile => Path.Combine(DataDir, "ops-host.pid");
    public static string HostStateFile => Path.Combine(DataDir, "ops-host-state.json");
    public static string PendingBalloonFile => Path.Combine(DataDir, "ops-host-pending-balloon.json");
    public static string HostLogFile => Path.Combine(DataDir, "ops-host.log");

    public static string DeskPidFile(int port) => Path.Combine(DataDir, $"ops-{port}.pid");

    public static string ResolveIconPath(string metraRoot)
    {
        foreach (var rel in new[]
                 {
                     Path.Combine("docs", "assets", "metra.ico"),
                     Path.Combine("ops", "public", "metra.ico"),
                 })
        {
            var full = Path.Combine(metraRoot, rel);
            if (File.Exists(full))
            {
                return full;
            }
        }

        return string.Empty;
    }

    public static string ResolveMetraRoot(string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot))
        {
            var rooted = Path.GetFullPath(explicitRoot.Trim());
            if (LooksLikeMetraRoot(rooted))
            {
                return rooted;
            }

            throw new InvalidOperationException(
                "Explicit Metra root is invalid (expected metra.ps1 and scripts\\Metra.psd1): " + rooted);
        }

        var env = Environment.GetEnvironmentVariable("METRA_ROOT");
        if (!string.IsNullOrWhiteSpace(env))
        {
            var rooted = Path.GetFullPath(env.Trim());
            if (LooksLikeMetraRoot(rooted))
            {
                return rooted;
            }
        }

        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (LooksLikeMetraRoot(dir.FullName))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "Could not locate Metra root (metra.ps1 / scripts\\Metra.psd1). Pass --root.");
    }

    private static bool LooksLikeMetraRoot(string path) =>
        File.Exists(Path.Combine(path, "metra.ps1")) &&
        File.Exists(Path.Combine(path, "scripts", "Metra.psd1"));
}

internal static class HostLog
{
    public static void Write(string message, string level = "info")
    {
        try
        {
            var path = HostPaths.HostLogFile;
            var info = new FileInfo(path);
            if (info.Exists && info.Length > 256 * 1024)
            {
                var old = path + ".old";
                try
                {
                    if (File.Exists(old))
                    {
                        File.Delete(old);
                    }

                    File.Move(path, old);
                }
                catch
                {
                    // ignore rotation failures
                }
            }

            var line =
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] pid {Environment.ProcessId} - {message}{Environment.NewLine}";
            File.AppendAllText(path, line);
        }
        catch
        {
            // logging must not break the tray
        }
    }
}

internal sealed class HostStateStore
{
    private readonly int _opsPort;
    private readonly string _startedAt;
    private int _restartCount;
    private int _consecutiveFailures;
    private string? _lastStatus;
    private int _lastHeartbeatChildPid;
    private DateTime _lastHeartbeatUtc = DateTime.MinValue;

    public HostStateStore(int opsPort, string startedAt)
    {
        _opsPort = opsPort;
        _startedAt = startedAt;
    }

    public int RestartCount
    {
        get => _restartCount;
        set => _restartCount = value;
    }

    public int ConsecutiveFailures
    {
        get => _consecutiveFailures;
        set => _consecutiveFailures = value;
    }

    public void Write(string status, int childPid = 0, string? lastFailure = null)
    {
        var obj = new Dictionary<string, object?>
        {
            ["status"] = status,
            ["startedAt"] = _startedAt,
            ["restartCount"] = _restartCount,
            ["lastFailure"] = lastFailure,
            ["opsPort"] = _opsPort,
            ["childPid"] = childPid,
            ["consecutiveFailures"] = _consecutiveFailures,
            ["hostPid"] = Environment.ProcessId,
            ["updatedAt"] = DateTime.UtcNow.ToString("o"),
            ["hostKind"] = "MetraHost",
        };
        var json = JsonSerializer.Serialize(obj);
        File.WriteAllText(HostPaths.HostStateFile, json);
    }

    public void Heartbeat(string status, int childPid = 0, string? lastFailure = null)
    {
        var now = DateTime.UtcNow;
        var changed = status != _lastStatus || childPid != _lastHeartbeatChildPid;
        if (!changed &&
            _lastHeartbeatUtc != DateTime.MinValue &&
            (now - _lastHeartbeatUtc).TotalSeconds < 30)
        {
            return;
        }

        _lastStatus = status;
        _lastHeartbeatChildPid = childPid;
        _lastHeartbeatUtc = now;
        Write(status, childPid, lastFailure);
    }
}

internal static class DeskProcess
{
    public static int? GetChildPid(int port)
    {
        var path = HostPaths.DeskPidFile(port);
        if (!File.Exists(path))
        {
            return null;
        }

        if (!int.TryParse(File.ReadAllText(path).Trim(), out var recorded) || recorded <= 0)
        {
            try
            {
                File.Delete(path);
            }
            catch
            {
                // ignore
            }

            return null;
        }

        try
        {
            Process.GetProcessById(recorded);
            return recorded;
        }
        catch (ArgumentException)
        {
            try
            {
                File.Delete(path);
            }
            catch
            {
                // ignore
            }

            return null;
        }
    }

    public static bool IsProcessAlive(int pid)
    {
        try
        {
            Process.GetProcessById(pid);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

internal static class RestartBackoff
{
    public static int DelaySeconds(int failureStreak) => failureStreak switch
    {
        <= 1 => 5,
        2 => 15,
        3 => 60,
        _ => 300,
    };
}
