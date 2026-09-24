using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace Metra.Host;

/// <summary>
/// Calls Metra PowerShell helpers for Ops start/stop/open. Host never starts Ask directly.
/// </summary>
internal sealed class OpsBridge
{
    private readonly string _metraRoot;
    private readonly string _bridgeScript;
    private readonly string _shellExe;

    public OpsBridge(string metraRoot)
    {
        // Trim trailing separators so quoted -MetraRoot paths do not escape the closing quote.
        _metraRoot = Path.GetFullPath(metraRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        _bridgeScript = Path.Combine(_metraRoot, "scripts", "bootstrap", "Invoke-MetraOpsHostBridge.ps1");
        if (!File.Exists(_bridgeScript))
        {
            throw new FileNotFoundException("Missing Ops host bridge script.", _bridgeScript);
        }

        _shellExe = ResolveShell();
    }

    public BridgeResult Invoke(string action, int port, IDictionary<string, string>? extra = null)
    {
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

        // ArgumentList avoids manual quoting bugs for spaces and trailing backslashes.
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(_bridgeScript);
        psi.ArgumentList.Add("-Action");
        psi.ArgumentList.Add(action);
        psi.ArgumentList.Add("-Port");
        psi.ArgumentList.Add(port.ToString());
        psi.ArgumentList.Add("-MetraRoot");
        psi.ArgumentList.Add(_metraRoot);
        if (extra != null)
        {
            foreach (var kv in extra)
            {
                if (string.IsNullOrWhiteSpace(kv.Key))
                {
                    continue;
                }

                psi.ArgumentList.Add(kv.Key);
                if (!string.IsNullOrEmpty(kv.Value))
                {
                    psi.ArgumentList.Add(kv.Value);
                }
            }
        }

        using var proc = Process.Start(psi)
                         ?? throw new InvalidOperationException("Failed to start Ops bridge PowerShell.");

        // Read stdout and stderr concurrently. Sequential ReadToEnd can deadlock if the
        // unread stream fills its OS pipe buffer before WaitForExit.
        var stdoutTask = proc.StandardOutput.ReadToEndAsync();
        var stderrTask = proc.StandardError.ReadToEndAsync();
        if (!proc.WaitForExit(120_000))
        {
            try
            {
                proc.Kill(entireProcessTree: true);
            }
            catch
            {
                // ignore
            }

            return BridgeResult.Fail("bridge_timeout", "Ops bridge timed out.");
        }

        Task.WaitAll(stdoutTask, stderrTask);
        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();

        if (proc.ExitCode != 0 && string.IsNullOrWhiteSpace(stdout))
        {
            return BridgeResult.Fail(
                "bridge_exit",
                string.IsNullOrWhiteSpace(stderr) ? $"Bridge exit {proc.ExitCode}" : stderr.Trim());
        }

        try
        {
            var json = ExtractJsonObject(stdout);
            if (json is null)
            {
                return BridgeResult.Fail(
                    "bridge_parse",
                    $"Invalid bridge JSON (no object). stderr={Trim(stderr)} stdout={Trim(stdout)}");
            }

            using var doc = JsonDocument.Parse(json);
            return BridgeResult.FromJson(doc.RootElement);
        }
        catch (Exception ex)
        {
            return BridgeResult.Fail(
                "bridge_parse",
                $"Invalid bridge JSON: {ex.Message}. stderr={Trim(stderr)} stdout={Trim(stdout)}");
        }
    }

    /// <summary>
    /// Module imports may leak WARNING text onto stdout; take the last JSON object line.
    /// </summary>
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

        var start = stdout.LastIndexOf('{');
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

internal sealed class BridgeResult
{
    public bool Ok { get; init; }
    public string? Error { get; init; }
    public string? ErrorCode { get; init; }
    public int? ChildPid { get; init; }
    public int? Port { get; init; }
    public bool Started { get; init; }
    public bool Alive { get; init; }
    public bool Enabled { get; init; }
    public string? Message { get; init; }
    public string? Url { get; init; }
    public bool AnyUpdate { get; init; }
    public string? UpdateSummary { get; init; }
    public int AppliedOk { get; init; }

    public static BridgeResult Fail(string code, string error) => new()
    {
        Ok = false,
        ErrorCode = code,
        Error = error,
    };

    public static BridgeResult FromJson(JsonElement root)
    {
        return new BridgeResult
        {
            Ok = root.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True,
            Error = GetString(root, "error"),
            ErrorCode = GetString(root, "errorCode"),
            ChildPid = GetInt(root, "childPid"),
            Port = GetInt(root, "port"),
            Started = root.TryGetProperty("started", out var st) && st.ValueKind == JsonValueKind.True,
            Alive = root.TryGetProperty("alive", out var al) && al.ValueKind == JsonValueKind.True,
            Enabled = root.TryGetProperty("enabled", out var en) && en.ValueKind == JsonValueKind.True,
            Message = GetString(root, "message"),
            Url = GetString(root, "url"),
            AnyUpdate = root.TryGetProperty("anyUpdate", out var au) && au.ValueKind == JsonValueKind.True,
            UpdateSummary = GetString(root, "updateSummary"),
            AppliedOk = GetInt(root, "appliedOk") ?? 0,
        };
    }

    private static string? GetString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;

    private static int? GetInt(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var p))
        {
            return null;
        }

        if (p.ValueKind == JsonValueKind.Number && p.TryGetInt32(out var n))
        {
            return n;
        }

        if (p.ValueKind == JsonValueKind.String && int.TryParse(p.GetString(), out var s))
        {
            return s;
        }

        return null;
    }
}
