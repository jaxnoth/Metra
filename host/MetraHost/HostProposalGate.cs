using System.Text.Json;

namespace Metra.Host;

/// <summary>
/// Cheap in-process gate so MetraHost does not spawn pwsh for sync-proposals
/// when nothing is pendingApply. Full apply stays in the bridge.
/// </summary>
internal static class HostProposalGate
{
    public static string StoreDir => Path.Combine(HostPaths.DataDir, "proposals");

    /// <summary>
    /// True when Host should invoke bridge sync-proposals.
    /// </summary>
    public static bool ShouldInvokeBridgeSync()
    {
        var dir = StoreDir;
        if (!Directory.Exists(dir))
        {
            return false;
        }

        try
        {
            foreach (var path in Directory.EnumerateFiles(dir, "*.json"))
            {
                // Skip body sidecars (*.body.json).
                var name = Path.GetFileName(path);
                if (name.EndsWith(".body.json", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (FileLooksPendingApply(path))
                {
                    return true;
                }
            }

            return false;
        }
        catch (Exception ex)
        {
            HostLog.Write($"Proposal gate read failed - {ex.Message}; invoking bridge", "warn");
            return true;
        }
    }

    private static bool FileLooksPendingApply(string path)
    {
        string text;
        try
        {
            text = File.ReadAllText(path);
        }
        catch (Exception ex)
        {
            // Fail open on transient read/lock errors so the bridge can re-read.
            HostLog.Write($"Proposal pendingApply probe read failed - {ex.Message}; treating as pending", "warn");
            return true;
        }

        if (text.IndexOf("pendingApply", StringComparison.OrdinalIgnoreCase) < 0)
        {
            return false;
        }

        try
        {
            using var doc = JsonDocument.Parse(text);
            if (!doc.RootElement.TryGetProperty("status", out var status) &&
                !doc.RootElement.TryGetProperty("Status", out status))
            {
                return false;
            }

            return status.ValueKind == JsonValueKind.String &&
                   string.Equals(status.GetString(), "pendingApply", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            // Fail open on parse errors when the file mentions pendingApply.
            return true;
        }
    }
}
