using System.Diagnostics;

namespace Metra.Host;

internal sealed class TrayApp : ApplicationContext
{
    private readonly string _metraRoot;
    private readonly int _port;
    private readonly bool _noBrowser;
    private readonly OpsBridge _bridge;
    private readonly HostStateStore _state;
    private readonly NotifyIcon _notify;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly ToolStripMenuItem _startupItem;
    private readonly Mutex _mutex;

    private int? _childPid;
    private bool _deskStopped;
    private bool _shortcutsPending = true;
    private DateTime _nextAttemptUtc = DateTime.MinValue;
    private DateTime _nextUpdateCheckUtc = DateTime.UtcNow;
    private string? _lastError;
    private string? _updateNotifiedKey;

    private TrayApp(string metraRoot, int port, bool noBrowser, Mutex mutex, bool startupEnabled)
    {
        _metraRoot = metraRoot;
        _port = port;
        _noBrowser = noBrowser;
        _mutex = mutex;
        _bridge = new OpsBridge(metraRoot);
        _state = new HostStateStore(port, DateTime.UtcNow.ToString("o"));

        var iconPath = HostPaths.ResolveIconPath(metraRoot);
        Icon icon;
        if (!string.IsNullOrEmpty(iconPath))
        {
            icon = new Icon(iconPath);
        }
        else
        {
            icon = (Icon)SystemIcons.Application.Clone();
        }

        _notify = new NotifyIcon
        {
            Icon = icon,
            Text = "Metra Ops",
            Visible = true,
        };

        var menu = new ContextMenuStrip();
        var openItem = new ToolStripMenuItem("Open Metra Ops", null, (_, _) => OpenDesk());
        var restartItem = new ToolStripMenuItem("Restart desk", null, (_, _) => RestartDesk());
        _startupItem = new ToolStripMenuItem("Start with Windows", null, (_, _) => ToggleStartup())
        {
            Checked = startupEnabled,
        };
        var stopItem = new ToolStripMenuItem("Stop desk", null, (_, _) => StopDesk());
        var exitItem = new ToolStripMenuItem("Exit Metra Ops", null, (_, _) => ExitMetra());

        menu.Items.Add(openItem);
        menu.Items.Add(restartItem);
        menu.Items.Add(_startupItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(stopItem);
        menu.Items.Add(exitItem);
        _notify.ContextMenuStrip = menu;
        _notify.DoubleClick += (_, _) => OpenDesk();

        _timer = new System.Windows.Forms.Timer { Interval = 5000 };
        _timer.Tick += (_, _) => OnTick();
        _timer.Start();

        Application.ApplicationExit += (_, _) => Cleanup(writeUnsupervised: true);
    }

    public static TrayApp Start(string[] args)
    {
        var noBrowser = args.Any(a => string.Equals(a, "--no-browser", StringComparison.OrdinalIgnoreCase) ||
                                      string.Equals(a, "-NoBrowser", StringComparison.OrdinalIgnoreCase));
        var forceLocal = args.Any(a => string.Equals(a, "--force-local", StringComparison.OrdinalIgnoreCase) ||
                                       string.Equals(a, "-ForceLocal", StringComparison.OrdinalIgnoreCase));
        var rootArg = GetArgValue(args, "--root") ?? GetArgValue(args, "-Root");
        var portArg = GetArgValue(args, "--port") ?? GetArgValue(args, "-Port");

        var metraRoot = HostPaths.ResolveMetraRoot(rootArg);
        var bridge = new OpsBridge(metraRoot);

        if (forceLocal)
        {
            Environment.SetEnvironmentVariable("METRA_OPS_FORCE_LOCAL", "1");
        }

        var port = 0;
        if (!string.IsNullOrWhiteSpace(portArg) && int.TryParse(portArg, out var parsedPort))
        {
            port = parsedPort;
        }

        var mutex = new Mutex(true, @"Local\MetraOpsHost", out var created);
        if (!created)
        {
            mutex.Dispose();
            // Second click: open desk in the existing host's browser via one bridge call.
            try
            {
                if (port <= 0)
                {
                    var resolved = bridge.Invoke("resolve-port", 0);
                    if (resolved.Ok && resolved.Port is > 0)
                    {
                        port = resolved.Port.Value;
                    }
                }

                if (port > 0)
                {
                    bridge.Invoke("open-browser", port);
                }
            }
            catch
            {
                // ignore
            }

            throw new InvalidOperationException("Metra Ops host already running.");
        }

        // One PowerShell import for assert + port + session + desk adopt/start (+ optional browser).
        var extra = new Dictionary<string, string>
        {
            ["-Quick"] = string.Empty,
        };
        if (!noBrowser)
        {
            extra["-OpenBrowser"] = string.Empty;
        }

        var boot = bridge.Invoke("host-bootstrap", port, extra);
        if (!boot.Ok || boot.Port is null or <= 0)
        {
            try
            {
                mutex.ReleaseMutex();
                mutex.Dispose();
            }
            catch
            {
                // ignore
            }

            throw new InvalidOperationException(boot.Error ?? "Host bootstrap failed.");
        }

        port = boot.Port.Value;
        var app = new TrayApp(metraRoot, port, noBrowser, mutex, boot.Enabled);
        app.ApplyBootstrapResult(boot);
        return app;
    }

    private void ApplyBootstrapResult(BridgeResult boot)
    {
        HostLog.Write($"MetraHost starting on port {_port} (root {_metraRoot}).");
        try
        {
            File.WriteAllText(HostPaths.HostPidFile, Environment.ProcessId.ToString());
        }
        catch (Exception ex)
        {
            HostLog.Write($"Could not write host pid file - {ex.Message}", "warn");
        }

        _childPid = boot.ChildPid is > 0 ? boot.ChildPid : DeskProcess.GetChildPid(_port);
        _state.Write("running", _childPid ?? 0);
        if (boot.Started)
        {
            HostLog.Write($"Started desk child {_childPid}.");
        }
        else
        {
            HostLog.Write($"Adopted existing desk (child {_childPid}).");
        }
    }

    private void OnTick()
    {
        if (_shortcutsPending)
        {
            _shortcutsPending = false;
            try
            {
                _bridge.Invoke("refresh-shortcuts", _port);
            }
            catch (Exception ex)
            {
                HostLog.Write($"Start Menu shortcut refresh failed - {ex.Message}", "warn");
            }
        }

        if (_deskStopped)
        {
            return;
        }

        DrainPendingBalloon();
        MaybeCheckUpdates();
        MaybeSyncProposals();

        // Process liveness - not HTTP. A desk mid-Ask must not look dead.
        var childPid = DeskProcess.GetChildPid(_port);
        if (childPid is null)
        {
            var probe = _bridge.Invoke("desk-alive", _port);
            if (probe.Ok && probe.Alive)
            {
                childPid = probe.ChildPid is > 0 ? probe.ChildPid : -1;
            }
        }

        if (childPid is not null)
        {
            var livePid = childPid > 0 ? childPid.Value : 0;
            if (livePid > 0)
            {
                _childPid = livePid;
            }

            if (_state.ConsecutiveFailures > 0)
            {
                HostLog.Write(
                    $"Desk healthy again (child {livePid}) after {_state.ConsecutiveFailures} failed attempt(s).");
                _state.ConsecutiveFailures = 0;
            }

            _nextAttemptUtc = DateTime.MinValue;
            _state.Heartbeat("running", livePid);
            return;
        }

        if (DateTime.UtcNow < _nextAttemptUtc)
        {
            _state.Heartbeat("restarting", lastFailure: _lastError);
            return;
        }

        _state.RestartCount++;
        try
        {
            _bridge.Invoke("stop-desk", _port);
        }
        catch
        {
            // best-effort cleanup before restart
        }

        var started = _bridge.Invoke(
            "start-child",
            _port,
            new Dictionary<string, string> { ["-Quick"] = string.Empty });
        if (started.Ok)
        {
            var wasFailing = _state.ConsecutiveFailures > 0;
            _childPid = started.ChildPid is > 0 ? started.ChildPid : DeskProcess.GetChildPid(_port);
            _state.ConsecutiveFailures = 0;
            _nextAttemptUtc = DateTime.MinValue;
            _lastError = null;
            HostLog.Write($"Restarted desk (child {_childPid}); restart #{_state.RestartCount}.");
            _state.Heartbeat("running", _childPid ?? 0);
            if (wasFailing)
            {
                Balloon("Desk is back online.", ToolTipIcon.Info);
            }
        }
        else
        {
            _state.ConsecutiveFailures++;
            _lastError = started.Error;
            var delay = RestartBackoff.DelaySeconds(_state.ConsecutiveFailures);
            _nextAttemptUtc = DateTime.UtcNow.AddSeconds(delay);
            HostLog.Write(
                $"Desk restart failed (attempt {_state.ConsecutiveFailures}); retrying in {delay}s - {_lastError}",
                "warn");
            _state.Heartbeat("restarting", lastFailure: _lastError);
            if (_state.ConsecutiveFailures == 1)
            {
                Balloon("Desk went down. Retrying automatically.", ToolTipIcon.Warning);
            }
        }
    }

    private void OpenDesk()
    {
        var ensure = _bridge.Invoke("ensure-desk", _port);
        if (ensure.Ok)
        {
            if (ensure.Started)
            {
                _childPid = ensure.ChildPid is > 0 ? ensure.ChildPid : DeskProcess.GetChildPid(_port);
                _state.ConsecutiveFailures = 0;
                _nextAttemptUtc = DateTime.MinValue;
                _deskStopped = false;
                _state.Write("running", _childPid ?? 0);
            }

            _bridge.Invoke("open-browser", _port);
        }
        else
        {
            _state.Write("failed", lastFailure: ensure.Error);
            Balloon(
                "Desk could not start. Try Restart desk, or run .\\metra.ps1 ops to see the error.",
                ToolTipIcon.Warning);
        }
    }

    private void RestartDesk()
    {
        try
        {
            _bridge.Invoke("stop-desk", _port);
        }
        catch
        {
            // ignore
        }

        _state.ConsecutiveFailures = 0;
        _nextAttemptUtc = DateTime.MinValue;
        _deskStopped = false;
        var ensure = _bridge.Invoke("ensure-desk", _port);
        if (ensure.Ok)
        {
            _childPid = ensure.ChildPid is > 0 ? ensure.ChildPid : DeskProcess.GetChildPid(_port);
            _state.RestartCount++;
            _state.Write("running", _childPid ?? 0);
            Balloon("Desk restarted.", ToolTipIcon.Info);
        }
        else
        {
            _state.Write("failed", lastFailure: ensure.Error);
            Balloon("Desk restart failed.", ToolTipIcon.Warning);
        }
    }

    private void StopDesk()
    {
        try
        {
            _bridge.Invoke("stop-desk", _port);
        }
        catch
        {
            // ignore
        }

        _childPid = null;
        _deskStopped = true;
        _state.Write("stopped");
        Balloon("Desk stopped. Exit the tray icon to leave Metra.", ToolTipIcon.Info);
    }

    private void ExitMetra()
    {
        try
        {
            _bridge.Invoke("stop-desk", _port);
        }
        catch
        {
            // ignore
        }

        _state.Write("stopped");
        Cleanup(writeUnsupervised: false);
        ExitThread();
    }

    private void ToggleStartup()
    {
        var next = !_startupItem.Checked;
        var r = _bridge.Invoke(
            "set-startup",
            _port,
            new Dictionary<string, string>
            {
                ["-Startup"] = next ? "true" : "false",
            });
        if (r.Ok)
        {
            _startupItem.Checked = r.Enabled;
        }
        else
        {
            MessageBox.Show(
                r.Error ?? "Could not update Startup shortcut.",
                "Metra Ops",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }
    }

    private void DrainPendingBalloon()
    {
        try
        {
            var path = HostPaths.PendingBalloonFile;
            if (!File.Exists(path))
            {
                return;
            }

            var raw = File.ReadAllText(path);
            File.Delete(path);
            using var doc = System.Text.Json.JsonDocument.Parse(raw);
            var root = doc.RootElement;
            var title = root.TryGetProperty("title", out var t) ? t.GetString() ?? "Metra Ops" : "Metra Ops";
            var text = root.TryGetProperty("text", out var x) ? x.GetString() ?? "" : "";
            var iconName = root.TryGetProperty("icon", out var i) ? i.GetString() ?? "Warning" : "Warning";
            var tip = iconName switch
            {
                "Info" => ToolTipIcon.Info,
                "Error" => ToolTipIcon.Error,
                _ => ToolTipIcon.Warning,
            };
            _notify.ShowBalloonTip(6000, title, text, tip);
        }
        catch
        {
            // ignore balloon errors
        }
    }

    private void MaybeCheckUpdates()
    {
        if (DateTime.UtcNow < _nextUpdateCheckUtc)
        {
            return;
        }

        _nextUpdateCheckUtc = DateTime.UtcNow.AddHours(6);
        try
        {
            var upd = _bridge.Invoke("check-updates", _port);
            if (upd.Ok && upd.AnyUpdate && !string.IsNullOrWhiteSpace(upd.UpdateSummary))
            {
                if (!string.Equals(upd.UpdateSummary, _updateNotifiedKey, StringComparison.Ordinal))
                {
                    _updateNotifiedKey = upd.UpdateSummary;
                    Balloon($"Update available: {upd.UpdateSummary}. Open Settings to update.", ToolTipIcon.Info);
                }
            }
        }
        catch (Exception ex)
        {
            HostLog.Write($"Update check failed - {ex.Message}", "warn");
        }
    }

    private void MaybeSyncProposals()
    {
        try
        {
            var r = _bridge.Invoke("sync-proposals", _port);
            if (r.Ok && r.AppliedOk > 0)
            {
                Balloon("Applied proposal.", ToolTipIcon.Info);
            }
        }
        catch (Exception ex)
        {
            HostLog.Write($"Proposal apply poll failed - {ex.Message}", "warn");
        }
    }

    private void Balloon(string text, ToolTipIcon icon) =>
        _notify.ShowBalloonTip(5000, "Metra Ops", text, icon);

    private void Cleanup(bool writeUnsupervised)
    {
        try
        {
            _timer.Stop();
        }
        catch
        {
            // ignore
        }

        try
        {
            _notify.Visible = false;
            _notify.Dispose();
        }
        catch
        {
            // ignore
        }

        if (writeUnsupervised)
        {
            try
            {
                var child = _childPid ?? DeskProcess.GetChildPid(_port) ?? 0;
                _state.Write(
                    "unsupervised",
                    child,
                    "Tray host exited; desk process may still be running.");
            }
            catch
            {
                // ignore
            }
        }

        try
        {
            if (File.Exists(HostPaths.HostPidFile))
            {
                File.Delete(HostPaths.HostPidFile);
            }
        }
        catch
        {
            // ignore
        }

        try
        {
            _mutex.ReleaseMutex();
            _mutex.Dispose();
        }
        catch
        {
            // ignore
        }
    }

    private static string? GetArgValue(string[] args, string name)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }

        return null;
    }
}
