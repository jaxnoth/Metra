# Metra host adapters for Yarn. Domain never dotsources scripts/private/*.ps1.
# Yarn must not write Loom queue/journal files.

$script:YarnHostRootOverride = $null
$script:YarnCursorPlansDirOverride = $null
$script:YarnCaptureOverride = $null
$script:YarnAtlasOverride = $null
$script:YarnAtlasRootOverride = $null
$script:YarnPackOverride = $null
$script:YarnLoomIngestOverride = $null

function Get-YarnHostRoot {
    [CmdletBinding()]
    param()
    if ($script:YarnHostRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:YarnHostRootOverride)
    }
    $cmd = Get-Command Get-MetraRoot -ErrorAction SilentlyContinue
    if ($cmd) {
        return & $cmd
    }
    $modRoot = $PSScriptRoot
    while ($modRoot -and (Split-Path -Leaf $modRoot) -ne 'Yarn') {
        $modRoot = Split-Path -Parent $modRoot
    }
    if ($modRoot) {
        $candidate = Split-Path -Parent (Split-Path -Parent $modRoot)
        if (Test-Path -LiteralPath (Join-Path $candidate 'metra.ps1')) {
            return $candidate
        }
    }
    throw 'Yarn host root unavailable (Metra not loaded and metra.ps1 not found).'
}

function Test-YarnCaptureAdapterAvailable {
    [CmdletBinding()]
    param()
    if ($script:YarnCaptureOverride) { return $true }
    return $null -ne (Get-Command Get-MetraCaptureLedger -ErrorAction SilentlyContinue)
}

function Get-YarnCaptureLedger {
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 40,
        [string]$Status = 'candidate'
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-YarnHostRoot
    }
    if ($script:YarnCaptureOverride) {
        return @(& $script:YarnCaptureOverride @{
                MetraRoot = $MetraRoot
                Limit     = $Limit
                Status    = $Status
            })
    }
    if (-not (Test-YarnCaptureAdapterAvailable)) {
        return @()
    }
    return @(& (Get-Command Get-MetraCaptureLedger) -MetraRoot $MetraRoot -Limit $Limit -Status $Status)
}

function Get-YarnAtlasProjectPath {
    [CmdletBinding()]
    param([string]$MetraRoot)
    if ($script:YarnAtlasRootOverride) {
        return [System.IO.Path]::GetFullPath([string]$script:YarnAtlasRootOverride)
    }
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-YarnHostRoot
    }
    $cmd = Get-Command Get-MetraAtlasProjectPath -ErrorAction SilentlyContinue
    if ($cmd) {
        $p = & $cmd -MetraRoot $MetraRoot
        if ($p) { return [string]$p }
    }
    $candidates = @(
        (Join-Path (Split-Path -Parent $MetraRoot) 'Atlas')
        'C:\Projects\Atlas'
    )
    foreach ($c in $candidates) {
        $cli = Join-Path $c 'Atlas.ps1'
        if (Test-Path -LiteralPath $cli) {
            return [System.IO.Path]::GetFullPath($c)
        }
    }
    return $null
}

function Test-YarnAtlasAdapterAvailable {
    [CmdletBinding()]
    param([string]$MetraRoot)
    if ($script:YarnAtlasOverride) { return $true }
    return -not [string]::IsNullOrWhiteSpace((Get-YarnAtlasProjectPath -MetraRoot $MetraRoot))
}

function ConvertFrom-YarnAtlasFrontMatter {
    param([Parameter(Mandatory)][string]$Text)
    $map = @{}
    if ($Text -notmatch '(?s)\A---\s*\r?\n(.*?)\r?\n---\s*') {
        return $map
    }
    $block = $Matches[1]
    foreach ($line in ($block -split '\r?\n')) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*:\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val -match '^\[(.*)\]$') {
                $inner = $Matches[1]
                $map[$key] = @($inner -split ',' | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ })
            }
            else {
                $map[$key] = $val.Trim('"').Trim("'")
            }
        }
    }
    return $map
}

function Get-YarnAtlasIntakeCandidates {
    <#
    .SYNOPSIS
        Read Atlas local mirror (sync objects + stub corpora). No Yarn content cache.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot,
        [int]$Limit = 80
    )
    if ([string]::IsNullOrWhiteSpace($MetraRoot)) {
        $MetraRoot = Get-YarnHostRoot
    }
    if ($script:YarnAtlasOverride) {
        return @(& $script:YarnAtlasOverride @{
                MetraRoot = $MetraRoot
                Limit     = $Limit
            })
    }
    $atlasRoot = Get-YarnAtlasProjectPath -MetraRoot $MetraRoot
    if (-not $atlasRoot) {
        throw 'Atlas project path unavailable for Yarn intake.'
    }
    $allowedKinds = @('Plan', 'Roadmap', 'Parked')
    $dirs = @(
        (Join-Path $atlasRoot 'data\sync\objects')
        (Join-Path $atlasRoot 'data\stub')
        (Join-Path $atlasRoot 'data\stub-local')
    )
    $byId = @{}
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            try {
                $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.UTF8Encoding]::new($false))
            }
            catch {
                continue
            }
            $fm = ConvertFrom-YarnAtlasFrontMatter -Text $text
            $stableId = [string](Get-YarnProp -Object $fm -Name 'stableId' -Default '')
            if ([string]::IsNullOrWhiteSpace($stableId)) { continue }
            $kind = [string](Get-YarnProp -Object $fm -Name 'kind' -Default '')
            if ($allowedKinds -notcontains $kind) { continue }
            # sync/objects wins over stub for same StableId (first dirs listed first → skip if present)
            if ($byId.ContainsKey($stableId)) { continue }
            $title = [string](Get-YarnProp -Object $fm -Name 'title' -Default $stableId)
            $project = [string](Get-YarnProp -Object $fm -Name 'project' -Default 'Metra')
            $body = ''
            if ($text -match '(?s)^---.*?---\s*(.*)$') {
                $body = $Matches[1].Trim()
            }
            $byId[$stableId] = [PSCustomObject]@{
                stableId    = $stableId
                title       = $title
                kind        = $kind
                projectKey  = if ($project) { $project } else { 'Metra' }
                sourceText  = if ($body) { $body } else { $title }
                provider    = 'local-mirror'
                mode        = 'local'
            }
            if ($byId.Count -ge $Limit) { break }
        }
        if ($byId.Count -ge $Limit) { break }
    }
    return @($byId.Values)
}

function Test-YarnLoomQueueWriteForbidden {
    <#
    .SYNOPSIS
        Guard: Yarn never mutates Loom queue storage.
    #>
    [CmdletBinding()]
    param()
    # Presence of Loom save cmdlets is fine; Yarn must not call them.
    return $true
}
