#Requires -Version 5.1
<#
.SYNOPSIS
    JSON bridge for MetraHost.exe (C# tray). Host -> Ops only; never starts Ask directly.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'host-bootstrap',
        'resolve-port',
        'init-session',
        'assert-local',
        'ensure-desk',
        'start-child',
        'stop-desk',
        'open-browser',
        'desk-alive',
        'get-startup',
        'set-startup',
        'sync-proposals',
        'check-updates',
        'refresh-shortcuts'
    )]
    [string]$Action,

    [ValidateRange(0, 65535)]
    [int]$Port = 0,

    [string]$MetraRoot = '',

    [switch]$ForceLocal,
    [switch]$Quick,
    [switch]$NoRefresh,
    [switch]$OpenBrowser,
    [ValidateSet('true', 'false')]
    [string]$Startup = 'true'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Do not silence warnings - Loom/Yarn unapproved verbs are fixed at source.
# Bridge still writes only JSON to stdout; warnings go to the warning stream.

function Write-MetraHostBridgeJson {
    param([Parameter(Mandatory)]$Object)
    $json = $Object | ConvertTo-Json -Compress -Depth 6
    [Console]::Out.WriteLine($json)
}

function Invoke-MetraHostBridgePrivate {
    <#
    .SYNOPSIS
        Run a scriptblock inside the Metra module so private Host helpers resolve.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$ArgumentList
    )

    $mod = Get-Module -Name Metra -ErrorAction Stop
    if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 0) {
        & $mod $Script @ArgumentList
    }
    else {
        & $mod $Script
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    }
    else {
        $MetraRoot = (Resolve-Path -LiteralPath $MetraRoot).Path
    }

    $modulePath = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "Metra module not found: $modulePath"
    }

    # Cold process each call - avoid -Force so nested imports stay cheaper when possible.
    Import-Module $modulePath -ErrorAction Stop

    if ($Port -le 0 -and $Action -notin @('resolve-port', 'host-bootstrap')) {
        $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
    }

    switch ($Action) {
        'host-bootstrap' {
            # One Import-Module for assert + port + session + desk adopt/start (+ optional browser).
            # Shortcuts refresh is deferred to MetraHost timer (not on the critical path).
            Assert-MetraOpsMayStartLocally -ForceLocal:$ForceLocal -MetraRoot $MetraRoot
            if ($Port -le 0) {
                $Port = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
            }

            $sessionCreated = $false
            try {
                $session = Invoke-MetraHostBridgePrivate { Initialize-MetraOpsLocalSessionToken }
                $sessionCreated = [bool](Get-MetraProp -Object $session -Name 'Created' -Default $false)
            }
            catch { }

            $alive = [bool](Test-MetraOpsDeskAlive -Port $Port -TimeoutSec 2)
            $childPid = 0
            $started = $false
            if ($alive) {
                $child = Invoke-MetraHostBridgePrivate { param($p) Get-MetraOpsChildProcessId -Port $p } $Port
                if ($child) { $childPid = [int]$child }
            }
            else {
                $nr = [bool]$NoRefresh
                $qk = $true
                if ($PSBoundParameters.ContainsKey('Quick')) { $qk = [bool]$Quick }
                $child = Invoke-MetraHostBridgePrivate {
                    param($root, $port, $noRefresh, $quick)
                    $params = @{ MetraRoot = $root; Port = $port }
                    if ($noRefresh) { $params.NoRefresh = $true }
                    if ($quick) { $params.Quick = $true }
                    Start-MetraOpsChildProcess @params
                } $MetraRoot $Port $nr $qk
                $started = $true
                $alive = $true
                $childPid = [int]$child.Id
            }

            if ($OpenBrowser) {
                Invoke-MetraHostBridgePrivate { param($p, $root) Open-MetraOpsDeskBrowser -Port $p -MetraRoot $root } $Port $MetraRoot
            }

            $startupEnabled = $false
            try {
                $startupEnabled = [bool](Invoke-MetraHostBridgePrivate { Test-MetraOpsHostStartupEnabled })
            }
            catch { }

            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok              = $true
                    port            = $Port
                    alive           = $alive
                    started         = $started
                    childPid        = $childPid
                    sessionCreated  = $sessionCreated
                    enabled         = $startupEnabled
                    shortcutsDeferred = $true
                })
            return
        }
        'resolve-port' {
            $resolved = [int](Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot).Port
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true; port = $resolved })
            return
        }
        'assert-local' {
            Assert-MetraOpsMayStartLocally -ForceLocal:$ForceLocal -MetraRoot $MetraRoot
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true })
            return
        }
        'init-session' {
            $session = Invoke-MetraHostBridgePrivate { Initialize-MetraOpsLocalSessionToken }
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok      = $true
                    created = [bool](Get-MetraProp -Object $session -Name 'Created' -Default $false)
                })
            return
        }
        'refresh-shortcuts' {
            Install-MetraOpsStartMenuShortcuts -MetraRoot $MetraRoot | Out-Null
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true })
            return
        }
        'desk-alive' {
            $alive = [bool](Test-MetraOpsDeskAlive -Port $Port -TimeoutSec 2)
            $child = Invoke-MetraHostBridgePrivate { param($p) Get-MetraOpsChildProcessId -Port $p } $Port
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok       = $true
                    alive    = $alive
                    childPid = $(if ($child) { [int]$child } else { 0 })
                    port     = $Port
                })
            return
        }
        'ensure-desk' {
            $ensure = Start-MetraOpsDeskIfDown -Port $Port -MetraRoot $MetraRoot
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok       = [bool]$ensure.Ok
                    started  = [bool](Get-MetraProp -Object $ensure -Name 'Started' -Default $false)
                    childPid = [int](Get-MetraProp -Object $ensure -Name 'ChildPid' -Default 0)
                    error    = [string](Get-MetraProp -Object $ensure -Name 'Error' -Default $null)
                    port     = $Port
                })
            return
        }
        'start-child' {
            $nr = [bool]$NoRefresh
            $qk = [bool]$Quick
            $child = Invoke-MetraHostBridgePrivate {
                param($root, $port, $noRefresh, $quick)
                $params = @{
                    MetraRoot = $root
                    Port      = $port
                }
                if ($noRefresh) { $params.NoRefresh = $true }
                if ($quick) { $params.Quick = $true }
                Start-MetraOpsChildProcess @params
            } $MetraRoot $Port $nr $qk
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok       = $true
                    started  = $true
                    childPid = [int]$child.Id
                    port     = $Port
                })
            return
        }
        'stop-desk' {
            Stop-MetraOpsServer -Port $Port
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true; port = $Port })
            return
        }
        'open-browser' {
            Invoke-MetraHostBridgePrivate { param($p, $root) Open-MetraOpsDeskBrowser -Port $p -MetraRoot $root } $Port $MetraRoot
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true; port = $Port })
            return
        }
        'get-startup' {
            $on = [bool](Invoke-MetraHostBridgePrivate { Test-MetraOpsHostStartupEnabled })
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true; enabled = $on })
            return
        }
        'set-startup' {
            $on = $Startup -eq 'true'
            Set-MetraOpsHostStartup -Enabled:$on -MetraRoot $MetraRoot
            $enabled = [bool](Invoke-MetraHostBridgePrivate { Test-MetraOpsHostStartupEnabled })
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok      = $true
                    enabled = $enabled
                })
            return
        }
        'sync-proposals' {
            $appliedOk = 0
            if (Get-Command Sync-MetraProposalHostPending -ErrorAction SilentlyContinue) {
                $applied = @(Sync-MetraProposalHostPending -MaxCount 1 -Surface browser)
                foreach ($item in $applied) {
                    if ($item.Ok) { $appliedOk++ }
                }
            }
            Write-MetraHostBridgeJson ([pscustomobject]@{ ok = $true; appliedOk = $appliedOk })
            return
        }
        'check-updates' {
            $any = $false
            $summary = $null
            if (Get-Command Get-MetraProductUpdates -ErrorAction SilentlyContinue) {
                $upd = Get-MetraProductUpdates -MetraRoot $MetraRoot
                $any = [bool](Get-MetraProp -Object $upd -Name 'anyUpdate' -Default $false)
                if ($any) {
                    $bits = @()
                    if ($upd.metra.updateAvailable) { $bits += "Metra $($upd.metra.available)" }
                    if ($upd.ollama.updateAvailable) { $bits += "Ollama $($upd.ollama.available)" }
                    foreach ($st in @((Get-MetraProp -Object $upd -Name 'stations' -Default @()))) {
                        if ([bool](Get-MetraProp -Object $st -Name 'canUpdate' -Default $false)) {
                            $bits += ("{0} {1}" -f [string]$st.label, [string]$st.availableVersion)
                        }
                    }
                    $summary = ($bits -join ', ')
                }
            }
            Write-MetraHostBridgeJson ([pscustomobject]@{
                    ok            = $true
                    anyUpdate     = $any
                    updateSummary = $summary
                })
            return
        }
        default {
            throw "Unknown action: $Action"
        }
    }
}
catch {
    Write-MetraHostBridgeJson ([pscustomobject]@{
            ok        = $false
            errorCode = 'bridge_exception'
            error     = $_.Exception.Message
        })
    exit 1
}
