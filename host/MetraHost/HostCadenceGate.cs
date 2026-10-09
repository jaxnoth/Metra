using System.Globalization;
using System.Text.Json;

namespace Metra.Host;

/// <summary>
/// Cheap in-process gate so MetraHost does not spawn pwsh for cadence-tick every 30s.
/// Full evaluation stays in HostBridge / HostCadence.ps1; this only asks "might anything be due?".
/// </summary>
internal static class HostCadenceGate
{
    private const int PulseEarlySkewSeconds = 60;
    private const int MaxLeaseHours = 2;

    public static string StatePath => Path.Combine(HostPaths.DataDir, "host-cadence.json");

    /// <summary>
    /// True when Host should invoke bridge cadence-tick (enabled and pulse/daily may be due, or stale lease).
    /// </summary>
    public static bool ShouldInvokeBridgeTick()
    {
        var path = StatePath;
        if (!File.Exists(path))
        {
            return false;
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            if (!TryGetBool(root, "enabled", out var enabled) || !enabled)
            {
                return false;
            }

            var utcNow = DateTime.UtcNow;
            var activeKind = GetString(root, "activeRunKind");
            if (!string.IsNullOrWhiteSpace(activeKind))
            {
                var startedKey = string.Equals(activeKind, "Daily", StringComparison.OrdinalIgnoreCase)
                    ? "lastDailyStartedUtc"
                    : "lastPulseStartedUtc";
                var started = ParseUtc(GetString(root, startedKey));
                if (started is null || utcNow > started.Value.AddHours(MaxLeaseHours))
                {
                    // Missing/expired lease - let PowerShell repair.
                    return true;
                }

                // In-flight within lease - do not spawn another bridge.
                return false;
            }

            if (TryGetBool(root, "pendingPulse", out var pendingPulse) && pendingPulse)
            {
                return true;
            }

            if (TryGetBool(root, "pendingDaily", out var pendingDaily) && pendingDaily)
            {
                return true;
            }

            var nextPulseRaw = GetString(root, "nextPulseDueUtc");
            if (string.IsNullOrWhiteSpace(nextPulseRaw))
            {
                return true;
            }

            var nextPulse = ParseUtc(nextPulseRaw);
            if (nextPulse is null || utcNow >= nextPulse.Value.AddSeconds(-PulseEarlySkewSeconds))
            {
                return true;
            }

            return IsDailyDueLocal(root, DateTime.Now);
        }
        catch (Exception ex)
        {
            HostLog.Write($"Cadence gate read failed - {ex.Message}; invoking bridge", "warn");
            return true;
        }
    }

    private static bool IsDailyDueLocal(JsonElement root, DateTime localNow)
    {
        var lastDate = GetString(root, "lastDailyLocalDate");
        var today = localNow.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (!string.IsNullOrWhiteSpace(lastDate) &&
            string.Equals(lastDate, today, StringComparison.Ordinal))
        {
            var completed = GetString(root, "lastDailyCompletedUtc");
            if (!string.IsNullOrWhiteSpace(completed))
            {
                return false;
            }
        }

        var at = GetString(root, "dailyAtLocal") ?? "02:00";
        if (!TryParseHm(at, out var hour, out var minute))
        {
            hour = 2;
            minute = 0;
        }

        var wall = new DateTime(localNow.Year, localNow.Month, localNow.Day, hour, minute, 0, localNow.Kind);
        return localNow >= wall;
    }

    private static bool TryParseHm(string text, out int hour, out int minute)
    {
        hour = 0;
        minute = 0;
        var parts = text.Trim().Split(':');
        if (parts.Length != 2)
        {
            return false;
        }

        if (!int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out hour) ||
            !int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out minute))
        {
            return false;
        }

        return hour is >= 0 and <= 23 && minute is >= 0 and <= 59;
    }

    private static DateTime? ParseUtc(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        if (!DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt))
        {
            return null;
        }

        return dt.Kind switch
        {
            DateTimeKind.Utc => dt,
            DateTimeKind.Local => dt.ToUniversalTime(),
            _ => DateTime.SpecifyKind(dt, DateTimeKind.Utc),
        };
    }

    private static string? GetString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var el) || el.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        return el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
    }

    private static bool TryGetBool(JsonElement root, string name, out bool value)
    {
        value = false;
        if (!root.TryGetProperty(name, out var el))
        {
            return false;
        }

        if (el.ValueKind == JsonValueKind.True)
        {
            value = true;
            return true;
        }

        if (el.ValueKind == JsonValueKind.False)
        {
            value = false;
            return true;
        }

        return false;
    }
}
