#Requires -Version 5.1
<#
.SYNOPSIS
    JSON bridge for MetraHost Cursor My Machines worker supervision.
    Host supervises; Ops reports only; ensure never runs repair-sqlite.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('status', 'ensure', 'stop', 'repair-sqlite')]
    [string]$Action,

    [string]$MetraRoot = '',

    [switch]$SkipDebug,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-MetraCursorWorkerBridgeJson {
    param([Parameter(Mandatory)]$Object)
    $json = $Object | ConvertTo-Json -Compress -Depth 8
    [Console]::Out.WriteLine($json)
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

    Import-Module $modulePath -ErrorAction Stop

    switch ($Action) {
        'status' {
            $status = Get-MetraCursorWorkerStatus -MetraRoot $MetraRoot -SkipDebug:$SkipDebug
            Write-MetraCursorWorkerBridgeJson $status
            return
        }
        'ensure' {
            $status = Invoke-MetraCursorWorkerEnsure -MetraRoot $MetraRoot -SkipDebug:$SkipDebug
            Write-MetraCursorWorkerBridgeJson $status
            return
        }
        'stop' {
            $result = Stop-MetraCursorWorkerDaemon -MetraRoot $MetraRoot -SkipDebug:$SkipDebug
            Write-MetraCursorWorkerBridgeJson ([pscustomobject]@{
                    ok        = [bool]$result.ok
                    stopped   = [bool](Get-MetraProp -Object $result -Name 'stopped' -Default $false)
                    state     = [string](Get-MetraProp -Object $result -Name 'state' -Default $null)
                    message   = [string](Get-MetraProp -Object $result -Name 'message' -Default $null)
                    error     = [string](Get-MetraProp -Object $result -Name 'error' -Default $null)
                    processId = [int](Get-MetraProp -Object $result -Name 'processId' -Default 0)
                })
            if (-not $result.ok) { exit 1 }
            return
        }
        'repair-sqlite' {
            $result = Invoke-MetraCursorWorkerRepairSqlite -MetraRoot $MetraRoot -Force:$Force
            Write-MetraCursorWorkerBridgeJson $result
            if (-not $result.ok) { exit 1 }
            return
        }
        default {
            throw "Unknown action: $Action"
        }
    }
}
catch {
    Write-MetraCursorWorkerBridgeJson ([pscustomobject]@{
            ok        = $false
            state     = 'Error'
            errorCode = 'bridge_exception'
            error     = $_.Exception.Message
        })
    exit 1
}
