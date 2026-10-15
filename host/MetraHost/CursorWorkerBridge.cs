using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Metra.Host;

/// <summary>
/// Calls Invoke-MetraCursorWorkerBridge.ps1. Host supervises the Cursor worker; Ops does not.
/// </summary>
internal sealed class CursorWorkerBridge
{
    private readonly string _metraRoot;
    private readonly string _bridgeScript;
    private readonly string _shellExe;

    public CursorWorkerBridge(string metraRoot)
    {
        _metraRoot = Path.GetFullPath(metraRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        _bridgeScript = Path.Combine(_metraRoot, "scripts", "bootstrap", "Invoke-MetraCursorWorkerBridge.ps1");
        if (!File.Exists(_bridgeScript))
        {
            throw new FileNotFoundException("Missing Cursor worker bridge script.", _bridgeScript);
        }

        _shellExe = ResolveShell();
    }

    public static string ConfigPath =>
        Path.Combine(HostPaths.DataDir, "host", "cursor-worker.local.json");

    /// <summary>
    /// Cheap gate: skip ensure spawn when config missing or enabled=false.
    /// </summary>
    public static bool IsEnabledInConfig()
    {
        var path = ConfigPath;
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            return doc.RootElement.TryGetProperty("enabled", out var en) &&
                   en.ValueKind == JsonValueKind.True;
        }
        catch
        {
            return false;
        }
    }

    public CursorWorkerBridgeResult Invoke(string action, int timeoutMs = 120_000, bool skipDebug = false, bool force = false)
    {
        if (timeoutMs < 1_000)
        {
            timeoutMs = 1_000;
        }

        var psi = new ProcessStartInfo
        {
            FileName = _shellExe,
            WorkingDirectory = _metraRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(_bridgeScript);
        psi.ArgumentList.Add("-Action");
        psi.ArgumentList.Add(action);
        psi.ArgumentList.Add("-MetraRoot");
        psi.ArgumentList.Add(_metraRoot);
        if (skipDebug)
        {
            psi.ArgumentList.Add("-SkipDebug");
        }

        if (force)
        {
            psi.ArgumentList.Add("-Force");
        }

        using var proc = Process.Start(psi)
                         ?? throw new InvalidOperationException("Failed to start Cursor worker bridge PowerShell.");

        var stdoutTask = proc.StandardOutput.ReadToEndAsync();
        var stderrTask = proc.StandardError.ReadToEndAsync();
        if (!proc.WaitForExit(timeoutMs))
        {
            try
            {
                proc.Kill(entireProcessTree: true);
            }
            catch
            {
                // ignore
            }

            return CursorWorkerBridgeResult.Fail($"worker_bridge_timeout after {timeoutMs}ms ({action})");
        }

        Task.WaitAll(stdoutTask, stderrTask);
        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();

        if (proc.ExitCode != 0 && string.IsNullOrWhiteSpace(stdout))
        {
            return CursorWorkerBridgeResult.Fail(
                string.IsNullOrWhiteSpace(stderr) ? $"Bridge exit {proc.ExitCode}" : stderr.Trim());
        }

        try
        {
            var json = ExtractJsonObject(stdout);
            if (json is null)
            {
                return CursorWorkerBridgeResult.Fail(
                    $"Invalid worker bridge JSON. stderr={Trim(stderr)} stdout={Trim(stdout)}");
            }

            using var doc = JsonDocument.Parse(json);
            return CursorWorkerBridgeResult.FromJson(doc.RootElement);
        }
        catch (Exception ex)
        {
            return CursorWorkerBridgeResult.Fail(
                $"Invalid worker bridge JSON: {ex.Message}. stderr={Trim(stderr)} stdout={Trim(stdout)}");
        }
    }

    private static string? ExtractJsonObject(string stdout)
    {
        if (string.IsNullOrWhiteSpace(stdout))
        {
            return null;
        }

        var lines = stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var line = lines[i].Trim();
            if (line.StartsWith('{') && line.EndsWith('}'))
            {
                return line;
            }
        }

        var start = stdout.IndexOf('{');
        var end = stdout.LastIndexOf('}');
        if (start >= 0 && end > start)
        {
            return stdout[start..(end + 1)];
        }

        return null;
    }

    private static string Trim(string s) =>
        s.Length <= 400 ? s : s[..400];

    private static string ResolveShell()
    {
        var pwsh = FindOnPath("pwsh.exe");
        if (pwsh != null)
        {
            return pwsh;
        }

        var ps = FindOnPath("powershell.exe");
        if (ps != null)
        {
            return ps;
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");
    }

    private static string? FindOnPath(string fileName)
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim('"'), fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
                // ignore bad PATH entries
            }
        }

        return null;
    }
}

internal sealed class CursorWorkerBridgeResult
{
    public bool Ok { get; init; }
    public string? State { get; init; }
    public string? Error { get; init; }
    public string? LastError { get; init; }
    public string? Message { get; init; }
    public bool Enabled { get; init; }
    public bool Running { get; init; }
    public bool IdentityOk { get; init; }
    public string? WorkerName { get; init; }

    public static CursorWorkerBridgeResult Fail(string error) => new()
    {
        Ok = false,
        State = "Error",
        Error = error,
        LastError = error,
    };

    public static CursorWorkerBridgeResult FromJson(JsonElement root)
    {
        return new CursorWorkerBridgeResult
        {
            Ok = root.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True,
            State = GetString(root, "state"),
            Error = GetString(root, "error"),
            LastError = GetString(root, "lastError") ?? GetString(root, "error"),
            Message = GetString(root, "message"),
            Enabled = root.TryGetProperty("enabled", out var en) && en.ValueKind == JsonValueKind.True,
            Running = root.TryGetProperty("running", out var run) && run.ValueKind == JsonValueKind.True,
            IdentityOk = root.TryGetProperty("identityOk", out var id) && id.ValueKind == JsonValueKind.True,
            WorkerName = GetString(root, "workerName"),
        };
    }

    private static string? GetString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
}
