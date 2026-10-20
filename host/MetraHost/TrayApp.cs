using System.Diagnostics;

namespace Metra.Host;

internal sealed class TrayApp : ApplicationContext
{
    private readonly string _metraRoot;
    private readonly int _port;
    private readonly bool _noBrowser;
    private readonly OpsBridge _bridge;
    private readonly CursorWorkerBridge _workerBridge;
    private readonly HostStateStore _state;
    private readonly NotifyIcon _notify;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly ToolStripMenuItem _startupItem;
    private readonly Mutex _mutex;

    private int? _childPid;
    private bool _deskStopped;
    private bool _cleanedUp;
    private bool _intentionalExit;
    private bool _shortcutsPending = true;
    private DateTime _nextAttemptUtc = DateTime.MinValue;
    private DateTime _nextUpdateCheckUtc = DateTime.UtcNow;
    private DateTime _nextCadenceEvalUtc = DateTime.MinValue;
    private DateTime _nextWorkerEnsureUtc = DateTime.MinValue;
    private int _cadenceBusy;
    private int _workerBusy;
    private int _proposalSyncBusy;
    private Task? _cadenceTask;
    private Task? _workerTask;
    private string? _lastError;
    private string? _updateNotifiedKey;
    private string _workerStateLabel = "Disabled";
    private DateTime _nextProposalSyncUtc = DateTime.MinValue;
    private const int WorkerEnsureThrottleSeconds = 45;
    private const int ProposalSyncThrottleSeconds = 30;

    private TrayApp(string metraRoot, int port, bool noBrowser, Mutex mutex, bool startupEnabled)
    {
        _metraRoot = metraRoot;
        _port = port;
        _noBrowser = noBrowser;
        _mutex = mutex;
        _bridge = new OpsBridge(metraRoot);
        _workerBridge = new CursorWorkerBridge(metraRoot);
        _state = new HostStateStore(port, DateTime.UtcNow.ToString("o"));
        RefreshTrayTooltip();

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

        Application.ApplicationExit += OnApplicationExit;
    }

    private void OnApplicationExit(object? sender, EventArgs e) =>
        Cleanup(writeUnsupervised: !_intentionalExit);

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

        // Yarn cadence and Cursor worker are Host-owned; keep evaluating even if desk is stopped.
        MaybeCadenceTick();
        MaybeWorkerEnsure();

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
        // Atomic recycle under ops-desk-lifecycle. Do not split stop-desk + start-child -
        // that raced CLI ask-engine restart and force-killed the replacement child (exit -1).
        var started = _bridge.Invoke(
            "recycle-desk",
            _port,
            new Dictionary<string, string> { ["-Quick"] = string.Empty },
            timeoutMs: 180_000);
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
        _intentionalExit = true;
        // Prevent a racing ensure from restarting the worker after we stop it.
        _nextWorkerEnsureUtc = DateTime.MaxValue;
        WaitForWorkerShutdown();

        // MetraHost/tray exit owns worker shutdown. Stop desk does not.
        try
        {
            var stop = _workerBridge.Invoke("stop", timeoutMs: 60_000, skipDebug: true);
            if (!stop.Ok)
            {
                HostLog.Write($"Cursor worker stop on exit failed - {stop.Error ?? stop.LastError}", "warn");
            }
            else if (!string.IsNullOrWhiteSpace(stop.State))
            {
                _workerStateLabel = stop.State!;
            }
        }
        catch (Exception ex)
        {
            HostLog.Write($"Cursor worker stop on exit exception - {ex.Message}", "warn");
        }

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

    /// <summary>
    /// Host-owned Cursor My Machines worker ensure. Throttled; CreateNoWindow via bridge.
    /// Stop desk must not call worker stop - only ExitMetra / tray exit.
    /// </summary>
    private void MaybeWorkerEnsure()
    {
        if (_intentionalExit || _cleanedUp)
        {
            return;
        }

        if (DateTime.UtcNow < _nextWorkerEnsureUtc)
        {
            return;
        }

        _nextWorkerEnsureUtc = DateTime.UtcNow.AddSeconds(WorkerEnsureThrottleSeconds);

        if (!CursorWorkerBridge.IsEnabledInConfig())
        {
            if (!string.Equals(_workerStateLabel, "Disabled", StringComparison.Ordinal))
            {
                _workerStateLabel = "Disabled";
                RefreshTrayTooltip();
            }

            return;
        }

        // Worker already live -> skip bridge spawn (avoids periodic console flash).
        if (CursorWorkerBridge.IsRuntimeProcessAlive(out _))
        {
            if (!string.Equals(_workerStateLabel, "Running", StringComparison.Ordinal))
            {
                _workerStateLabel = "Running";
                RefreshTrayTooltip();
            }

            return;
        }

        if (Interlocked.CompareExchange(ref _workerBusy, 1, 0) != 0)
        {
            return;
        }

        _workerTask = Task.Run(() =>
        {
            try
            {
                if (_intentionalExit || _cleanedUp)
                {
                    return;
                }

                var r = _workerBridge.Invoke("ensure", timeoutMs: 120_000);
                var state = string.IsNullOrWhiteSpace(r.State) ? (r.Ok ? "Running" : "Error") : r.State!;
                _workerStateLabel = state;
                if (!r.Ok)
                {
                    HostLog.Write(
                        $"Cursor worker ensure failed state={state} - {r.LastError ?? r.Error}",
                        "warn");
                }
                else if (!string.Equals(state, "Running", StringComparison.OrdinalIgnoreCase) &&
                         !string.Equals(state, "Disabled", StringComparison.OrdinalIgnoreCase))
                {
                    HostLog.Write($"Cursor worker ensure state={state} - {r.LastError ?? r.Message}");
                }

                try
                {
                    if (!_cleanedUp)
                    {
                        // Tooltip updates must be on UI thread.
                        if (_notify.ContextMenuStrip?.InvokeRequired == true)
                        {
                            _notify.ContextMenuStrip.BeginInvoke(new Action(RefreshTrayTooltip));
                        }
                        else
                        {
                            RefreshTrayTooltip();
                        }
                    }
                }
                catch
                {
                    // ignore tooltip races during shutdown
                }
            }
            catch (Exception ex)
            {
                _workerStateLabel = "Error";
                HostLog.Write($"Cursor worker ensure exception - {ex.Message}", "warn");
            }
            finally
            {
                Interlocked.Exchange(ref _workerBusy, 0);
            }
        });
    }

    private void WaitForWorkerShutdown()
    {
        var task = _workerTask;
        if (task is null)
        {
            return;
        }

        try
        {
            if (!task.Wait(TimeSpan.FromSeconds(15)))
            {
                HostLog.Write(
                    "Cursor worker ensure still running after 15s shutdown wait - Host exiting.",
                    "warn");
            }
        }
        catch (Exception ex)
        {
            HostLog.Write($"Cursor worker shutdown wait failed - {ex.Message}", "warn");
        }
    }

    private void RefreshTrayTooltip()
    {
        try
        {
            var desk = _deskStopped ? "desk stopped" : "desk";
            var text = $"Metra Ops ({desk}; worker {_workerStateLabel})";
            if (text.Length > 63)
            {
                text = text[..63];
            }

            _notify.Text = text;
        }
        catch
        {
            // ignore tooltip failures
        }
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
        // Off UI thread - bridge Invoke can take up to 120s and freezes the tray menu.
        _ = Task.Run(() =>
        {
            try
            {
                if (_intentionalExit || _cleanedUp)
                {
                    return;
                }

                var upd = _bridge.Invoke("check-updates", _port);
                if (upd.Ok && upd.AnyUpdate && !string.IsNullOrWhiteSpace(upd.UpdateSummary))
                {
                    if (!string.Equals(upd.UpdateSummary, _updateNotifiedKey, StringComparison.Ordinal))
                    {
                        _updateNotifiedKey = upd.UpdateSummary;
                        var summary = upd.UpdateSummary!;
                        try
                        {
                            if (!_cleanedUp && _notify.ContextMenuStrip?.InvokeRequired == true)
                            {
                                _notify.ContextMenuStrip.BeginInvoke(new Action(() =>
                                    Balloon($"Update available: {summary}. Open Settings to update.", ToolTipIcon.Info)));
                            }
                            else if (!_cleanedUp)
                            {
                                Balloon($"Update available: {summary}. Open Settings to update.", ToolTipIcon.Info);
                            }
                        }
                        catch
                        {
                            // ignore balloon races
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                HostLog.Write($"Update check failed - {ex.Message}", "warn");
            }
        });
    }

    /// <summary>
    /// Proposal apply poll. Must not run on the UI thread - a stuck bridge Invoke
    /// freezes the tray ContextMenuStrip (no hover highlight, no clicks).
    /// </summary>
    private void MaybeSyncProposals()
    {
        if (DateTime.UtcNow < _nextProposalSyncUtc)
        {
            return;
        }

        _nextProposalSyncUtc = DateTime.UtcNow.AddSeconds(ProposalSyncThrottleSeconds);

        // No pendingApply -> do not spawn console pwsh (avoids tray flash every poll).
        if (!HostProposalGate.ShouldInvokeBridgeSync())
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _proposalSyncBusy, 1, 0) != 0)
        {
            return;
        }

        _ = Task.Run(() =>
        {
            try
            {
                if (_intentionalExit || _cleanedUp)
                {
                    return;
                }

                var r = _bridge.Invoke("sync-proposals", _port);
                if (r.Ok && r.AppliedOk > 0)
                {
                    try
                    {
                        if (!_cleanedUp && _notify.ContextMenuStrip?.InvokeRequired == true)
                        {
                            _notify.ContextMenuStrip.BeginInvoke(
                                new Action(() => Balloon("Applied proposal.", ToolTipIcon.Info)));
                        }
                        else if (!_cleanedUp)
                        {
                            Balloon("Applied proposal.", ToolTipIcon.Info);
                        }
                    }
                    catch
                    {
                        // ignore balloon races during shutdown
                    }
                }
            }
            catch (Exception ex)
            {
                HostLog.Write($"Proposal apply poll failed - {ex.Message}", "warn");
            }
            finally
            {
                Interlocked.Exchange(ref _proposalSyncBusy, 0);
            }
        });
    }

    /// <summary>
    /// Host-owned Yarn Pulse/Daily cadence. Runs off the UI thread so long schedule
    /// runs do not block desk supervision. Bridge uses CreateNoWindow.
    /// In-process gate skips pwsh spawn when nothing can be due (avoids console flash).
    /// </summary>
    private void MaybeCadenceTick()
    {
        if (DateTime.UtcNow < _nextCadenceEvalUtc)
        {
            return;
        }

        // Evaluate at least every 30s (finer than 60s tolerance floor).
        _nextCadenceEvalUtc = DateTime.UtcNow.AddSeconds(30);

        // Cheap JSON gate - do not start a console-subsystem pwsh when idle.
        if (!HostCadenceGate.ShouldInvokeBridgeTick())
        {
            return;
        }

        if (Interlocked.CompareExchange(ref _cadenceBusy, 1, 0) != 0)
        {
            return;
        }

        _cadenceTask = Task.Run(() =>
        {
            try
            {
                // Daily task limit was 2h; allow long Pulse/Daily without killing Host.
                var r = _bridge.Invoke("cadence-tick", _port, timeoutMs: 7_200_000);
                if (!r.Ok)
                {
                    HostLog.Write($"Cadence tick failed - {r.Error}", "warn");
                    return;
                }

                if (r.Executed)
                {
                    HostLog.Write(
                        $"Cadence ran mode={r.CadenceMode} exit={r.ExitCode} reason={r.Reason}");
                }
            }
            catch (Exception ex)
            {
                HostLog.Write($"Cadence tick exception - {ex.Message}", "warn");
            }
            finally
            {
                Interlocked.Exchange(ref _cadenceBusy, 0);
            }
        });
    }

    private void WaitForCadenceShutdown()
    {
        var task = _cadenceTask;
        if (task is null)
        {
            return;
        }

        try
        {
            // Bound UI-thread wait so logoff/Exit does not freeze WinForms for hours.
            // In-flight schedule may continue briefly after Host exit; state lease expires in 2h.
            if (!task.Wait(TimeSpan.FromSeconds(10)))
            {
                HostLog.Write(
                    "Cadence still running after 10s shutdown wait - Host exiting; lease recovery on next start.",
                    "warn");
            }
        }
        catch (Exception ex)
        {
            HostLog.Write($"Cadence shutdown wait failed - {ex.Message}", "warn");
        }
    }

    private void Balloon(string text, ToolTipIcon icon) =>
        _notify.ShowBalloonTip(5000, "Metra Ops", text, icon);

    private void Cleanup(bool writeUnsupervised)
    {
        if (_cleanedUp)
        {
            return;
        }

        _cleanedUp = true;

        try
        {
            Application.ApplicationExit -= OnApplicationExit;
        }
        catch
        {
            // ignore
        }

        try
        {
            _timer.Stop();
        }
        catch
        {
            // ignore
        }

        WaitForCadenceShutdown();
        WaitForWorkerShutdown();

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
