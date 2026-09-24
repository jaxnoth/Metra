# Porter handoff + publish + Pulse prep CLI.
# Stores handoff state in the pack; does not authorize ship or Bing.
# Prep may invoke Inspect prepare-bing (soft-fail). Porter transport runner stays separate.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('handoff', 'publish', 'refresh', 'prep', 'help')]
    [string]$Action = 'help',

    [Parameter(Position = 1)]
    [ValidateSet('set', 'clear', 'stale', 'show', 'ready', '')]
    [string]$HandoffVerb = '',

    [string]$Stem,
    [string]$CursorLeaf,
    [string]$Sha,
    [string]$PrUrl,
    [string]$Notes,
    [string]$MetraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PorterHandoffPaths {
    param([string]$Root)
    $porterRoot = Join-Path $Root 'porter'
    return [pscustomobject]@{
        PorterRoot    = $porterRoot
        HandoffJson   = Join-Path $porterRoot 'handoff.json'
        DeskHandoffMd = Join-Path $porterRoot 'DESK-HANDOFF.md'
        PlansOut      = Join-Path $porterRoot 'plans'
        OpenPlans     = Join-Path $porterRoot 'OPEN-PLANS.md'
        PendingStamp  = $(
            $lad = [Environment]::GetFolderPath('LocalApplicationData')
            if ([string]::IsNullOrWhiteSpace($lad)) {
                $lad = Join-Path $env:USERPROFILE 'AppData\Local'
            }
            Join-Path $lad 'Metra\porter\HANDOFF-PENDING.txt'
        )
    }
}

function New-PorterHandoffDoc {
    return [ordered]@{
        schemaVersion = 1
        updatedUtc    = $null
        items         = @()
    }
}

function ConvertTo-PorterUtcString {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o')
    }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return $s
}

function ConvertTo-PorterHandoffItem {
    param($Raw)
    return [ordered]@{
        stem          = [string]$Raw.stem
        cursorLeaf    = $(if ($Raw.PSObject.Properties['cursorLeaf'] -and $Raw.cursorLeaf) { [string]$Raw.cursorLeaf } else { $null })
        status        = [string]$Raw.status
        gitSha        = $(if ($Raw.PSObject.Properties['gitSha'] -and $Raw.gitSha) { [string]$Raw.gitSha } else { $null })
        prUrl         = $(if ($Raw.PSObject.Properties['prUrl'] -and $Raw.prUrl) { [string]$Raw.prUrl } else { $null })
        notes         = $(if ($Raw.PSObject.Properties['notes'] -and $Raw.notes) { [string]$Raw.notes } else { $null })
        updatedUtc    = ConvertTo-PorterUtcString -Value $(if ($Raw.PSObject.Properties['updatedUtc']) { $Raw.updatedUtc } else { $null })
        lastPrepError = $(if ($Raw.PSObject.Properties['lastPrepError'] -and $Raw.lastPrepError) { [string]$Raw.lastPrepError } else { $null })
        lastPrepSha   = $(if ($Raw.PSObject.Properties['lastPrepSha'] -and $Raw.lastPrepSha) { [string]$Raw.lastPrepSha } else { $null })
    }
}

function Read-PorterHandoffDoc {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return New-PorterHandoffDoc
    }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return New-PorterHandoffDoc
    }
    $parsed = $raw | ConvertFrom-Json
    $items = @()
    if ($null -ne $parsed.items) {
        foreach ($i in @($parsed.items)) {
            $items += ConvertTo-PorterHandoffItem -Raw $i
        }
    }
    return [ordered]@{
        schemaVersion = 1
        updatedUtc    = ConvertTo-PorterUtcString -Value $(if ($parsed.PSObject.Properties['updatedUtc']) { $parsed.updatedUtc } else { $null })
        items         = $items
    }
}

function Write-PorterHandoffDoc {
    param(
        [string]$JsonPath,
        [string]$MdPath,
        $Doc
    )
    $Doc['updatedUtc'] = [datetime]::UtcNow.ToString('o')
    $payload = [ordered]@{
        schemaVersion = 1
        updatedUtc    = $Doc.updatedUtc
        items         = @($Doc.items)
    }
    $json = ($payload | ConvertTo-Json -Depth 6)
    [System.IO.File]::WriteAllText($JsonPath, $json + "`n", [System.Text.UTF8Encoding]::new($false))

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('# DESK-HANDOFF (Handoff state storage in Porter pack)')
    [void]$lines.Add('')
    [void]$lines.Add('Handoff owns these statuses. Porter stores the file; Pulse observes and may invoke Inspect prepare-bing. Porter does not authorize ship or Bing.')
    [void]$lines.Add('')
    [void]$lines.Add("UpdatedUtc: $($Doc.updatedUtc)")
    [void]$lines.Add('')
    [void]$lines.Add('| Stem | Status | Cursor leaf | Sha | PR | Notes |')
    [void]$lines.Add('|------|--------|-------------|-----|----|-------|')
    foreach ($item in @($Doc.items)) {
        $leaf = if ($item.cursorLeaf) { $item.cursorLeaf } else { '-' }
        $sha = if ($item.gitSha) { $item.gitSha } else { '-' }
        $pr = if ($item.prUrl) { $item.prUrl } else { '-' }
        $n = if ($item.notes) {
            (($item.notes -replace '[\r\n]+', ' ') -replace '\|', '/').Trim()
        }
        else { '-' }
        [void]$lines.Add("| $($item.stem) | $($item.status) | $leaf | $sha | $pr | $n |")
    }
    if (@($Doc.items).Count -eq 0) {
        [void]$lines.Add('| (none) | - | - | - | - | - |')
    }
    [void]$lines.Add('')
    ($lines -join "`n") + "`n" | Set-Content -LiteralPath $MdPath -Encoding utf8
}

function Update-PorterHandoffPendingStamp {
    param(
        $Doc,
        [string]$StampPath
    )
    $dir = Split-Path -Parent $StampPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $awaiting = @($Doc.items | Where-Object { $_.status -eq 'awaiting-prepare-bing' })
    $ready = @($Doc.items | Where-Object { $_.status -eq 'ready-for-bing' })
    $lines = @(
        "updatedUtc=$($Doc.updatedUtc)"
        "awaitingPrepareBing=$($awaiting.Count)"
        "readyForBing=$($ready.Count)"
    )
    foreach ($a in $awaiting) { $lines += "awaiting:$($a.stem)" }
    foreach ($r in $ready) { $lines += "ready:$($r.stem)" }
    [System.IO.File]::WriteAllText($StampPath, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Save-PorterHandoff {
    param(
        $Paths,
        $Doc
    )
    Write-PorterHandoffDoc -JsonPath $Paths.HandoffJson -MdPath $Paths.DeskHandoffMd -Doc $Doc
    Update-PorterHandoffPendingStamp -Doc $Doc -StampPath $Paths.PendingStamp
}

function Invoke-PorterHandoffSet {
    param(
        $Doc,
        [string]$Stem,
        [string]$CursorLeaf,
        [string]$Sha,
        [string]$PrUrl,
        [string]$Notes
    )
    if ([string]::IsNullOrWhiteSpace($Stem)) { throw 'porter handoff set requires -Stem' }
    $norm = $Stem.Trim().ToLowerInvariant()
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($i in @($Doc.items)) {
        if ([string]$i.stem -ne $norm) { [void]$items.Add($i) }
    }
    [void]$items.Add([ordered]@{
            stem          = $norm
            cursorLeaf    = $(if ($CursorLeaf) { $CursorLeaf } else { $null })
            status        = 'awaiting-prepare-bing'
            gitSha        = $(if ($Sha) { $Sha } else { $null })
            prUrl         = $(if ($PrUrl) { $PrUrl } else { $null })
            notes         = $(if ($Notes) { $Notes } else { 'Implement frozen; desk/Pulse may prepare-bing.' })
            updatedUtc    = [datetime]::UtcNow.ToString('o')
            lastPrepError = $null
            lastPrepSha   = $null
        })
    $Doc['items'] = @($items)
    return $Doc
}

function Set-PorterHandoffItemStatus {
    param(
        $Doc,
        [string]$Stem,
        [ValidateSet('cleared', 'stale', 'ready-for-bing', 'awaiting-prepare-bing')]
        [string]$Status,
        [string]$ErrorNote,
        [string]$PrepSha,
        [switch]$AllAwaiting
    )
    $items = @()
    $found = $false
    $norm = if ($Stem) { $Stem.Trim().ToLowerInvariant() } else { $null }
    foreach ($i in @($Doc.items)) {
        $match = $false
        if ($AllAwaiting) {
            $match = ([string]$i.status -eq 'awaiting-prepare-bing')
        }
        elseif ($norm -and [string]$i.stem -eq $norm) {
            $match = $true
        }
        if ($match) {
            $found = $true
            $i.status = $Status
            $i.updatedUtc = [datetime]::UtcNow.ToString('o')
            if ($Status -eq 'ready-for-bing') { $i.lastPrepError = $null }
            if ($PSBoundParameters.ContainsKey('ErrorNote')) { $i.lastPrepError = $ErrorNote }
            if ($PrepSha) { $i.lastPrepSha = $PrepSha }
        }
        $items += $i
    }
    if (-not $AllAwaiting -and -not $found) {
        throw "No handoff row for stem '$norm'"
    }
    $Doc['items'] = $items
    return $Doc
}

function Invoke-PorterInspectPrep {
    param(
        $Paths,
        [string]$Root
    )
    $doc = Read-PorterHandoffDoc -Path $Paths.HandoffJson
    $awaiting = @($doc.items | Where-Object { $_.status -eq 'awaiting-prepare-bing' })
    if ($awaiting.Count -eq 0) {
        Write-Host 'Porter prep: no awaiting-prepare-bing rows; skipped.'
        return [pscustomobject]@{ skipped = $true; reason = 'no-awaiting'; readyForBing = $false }
    }

    $psd1 = Join-Path $Root 'scripts\Metra.psd1'
    if (-not (Test-Path -LiteralPath $psd1)) {
        throw "Metra module missing: $psd1"
    }

    Import-Module $psd1 -Force
    $result = $null
    try {
        $result = Show-MetraInspectCli -Rest @('prepare-bing') -Name 'Metra'
    }
    catch {
        $err = [string]$_.Exception.Message
        $doc = Set-PorterHandoffItemStatus -Doc $doc -Status awaiting-prepare-bing -ErrorNote $err -AllAwaiting
        Save-PorterHandoff -Paths $Paths -Doc $doc
        Write-Warning "Porter prep soft-fail (Inspect): $err"
        return [pscustomobject]@{ skipped = $false; readyForBing = $false; softFail = $true; error = $err }
    }

    $ready = $false
    if ($null -ne $result -and $result.PSObject.Properties['readyForBing']) {
        $ready = [bool]$result.readyForBing
    }
    $phase = if ($null -ne $result -and $result.PSObject.Properties['phase']) { [string]$result.phase } else { '' }
    $prepNote = if ($ready) { $null } else { "prepare-bing not ready (phase=$phase)" }

    if ($ready) {
        $doc = Set-PorterHandoffItemStatus -Doc $doc -Status ready-for-bing -AllAwaiting
        Save-PorterHandoff -Paths $Paths -Doc $doc
        Write-Host "Porter prep: readyForBing=true; advanced $($awaiting.Count) row(s) to ready-for-bing."
        return [pscustomobject]@{ skipped = $false; readyForBing = $true; advanced = $awaiting.Count; result = $result }
    }

    $doc = Set-PorterHandoffItemStatus -Doc $doc -Status awaiting-prepare-bing -ErrorNote $prepNote -AllAwaiting
    Save-PorterHandoff -Paths $Paths -Doc $doc
    Write-Host "Porter prep: readyForBing=false; left awaiting ($prepNote)."
    return [pscustomobject]@{ skipped = $false; readyForBing = $false; advanced = 0; result = $result }
}

$paths = Get-PorterHandoffPaths -Root $MetraRoot
if (-not (Test-Path -LiteralPath $paths.PorterRoot)) {
    throw "porter missing under $MetraRoot"
}

switch ($Action) {
    'help' {
        Write-Host @'
Porter CLI (transport pack helpers; does not authorize ship or Bing)

  .\metra.ps1 porter refresh
  .\metra.ps1 porter publish
  .\metra.ps1 porter prep
  .\metra.ps1 porter handoff show
  .\metra.ps1 porter handoff set -Stem <stem> [-Path <cursorLeaf>] [-Note <notes>]
  .\metra.ps1 porter handoff clear -Stem <stem>
  .\metra.ps1 porter handoff stale -Stem <stem>
  .\metra.ps1 porter handoff ready -Stem <stem>

Handoff set freezes Project implement for that stem (awaiting-prepare-bing).
Pulse observes awaiting rows and invokes inspect prepare-bing (soft-fail), then may advance ready-for-bing.
'@
        return
    }
    'refresh' {
        # Forward WhatIf into Porter refresh so discovery dry-run still reports; do not short-circuit here.
        $refreshParams = @{ MetraRoot = $MetraRoot }
        if ($WhatIfPreference) { $refreshParams.WhatIf = $true }
        & (Join-Path $PSScriptRoot 'Invoke-MetraPorter.ps1') @refreshParams
        return
    }
    'publish' {
        $toAdd = @()
        if (Test-Path -LiteralPath $paths.OpenPlans) { $toAdd += $paths.OpenPlans }
        Get-ChildItem -LiteralPath $paths.PlansOut -File -Filter '*.plan.md' -ErrorAction SilentlyContinue |
            ForEach-Object { $toAdd += $_.FullName }
        if ($toAdd.Count -eq 0) {
            Write-Warning 'Nothing to publish. Run porter refresh first.'
            return
        }
        if ($PSCmdlet.ShouldProcess(($toAdd -join ', '), 'git add porter pack mirrors')) {
            Push-Location $MetraRoot
            try {
                $staged = 0
                foreach ($f in $toAdd) {
                    git add -- $f
                    if ($LASTEXITCODE -ne 0) {
                        throw "git add failed for $f (exit $LASTEXITCODE)"
                    }
                    $staged++
                }
            }
            finally { Pop-Location }
            Write-Host "Staged $staged porter pack file(s). Commit when ready (no auto-commit)."
        }
        return
    }
    'prep' {
        if ($PSCmdlet.ShouldProcess('Metra', 'Observe handoff and invoke inspect prepare-bing')) {
            return Invoke-PorterInspectPrep -Paths $paths -Root $MetraRoot
        }
        return
    }
    'handoff' {
        if ([string]::IsNullOrWhiteSpace($HandoffVerb)) { $HandoffVerb = 'show' }
        $doc = Read-PorterHandoffDoc -Path $paths.HandoffJson
        switch ($HandoffVerb) {
            'show' {
                $doc | ConvertTo-Json -Depth 6
                return
            }
            'set' {
                $doc = Invoke-PorterHandoffSet -Doc $doc -Stem $Stem -CursorLeaf $CursorLeaf -Sha $Sha -PrUrl $PrUrl -Notes $Notes
            }
            'clear' {
                if ([string]::IsNullOrWhiteSpace($Stem)) { throw 'porter handoff clear requires -Stem' }
                $doc = Set-PorterHandoffItemStatus -Doc $doc -Stem $Stem -Status cleared
            }
            'stale' {
                if ([string]::IsNullOrWhiteSpace($Stem)) { throw 'porter handoff stale requires -Stem' }
                $doc = Set-PorterHandoffItemStatus -Doc $doc -Stem $Stem -Status stale
            }
            'ready' {
                if ([string]::IsNullOrWhiteSpace($Stem)) { throw 'porter handoff ready requires -Stem' }
                $doc = Set-PorterHandoffItemStatus -Doc $doc -Stem $Stem -Status ready-for-bing
            }
            default { throw "Unknown handoff verb: $HandoffVerb" }
        }
        if ($PSCmdlet.ShouldProcess($paths.HandoffJson, "Write handoff $HandoffVerb")) {
            Save-PorterHandoff -Paths $paths -Doc $doc
            Write-Host "Handoff $HandoffVerb ok for stem=$Stem"
        }
        return
    }
}
