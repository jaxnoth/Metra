# Short-lived in-memory caches for routing hot paths (desk session speed).

$script:MetraCacheTtlSeconds = 60

function Initialize-MetraRoutingCacheState {
    $script:MetraCache = @{
        ConfigPath         = $null
        ConfigLwt          = [datetime]::MinValue
        Config             = $null
        ProjectsDefault    = $null
        ProjectsUtc        = [datetime]::MinValue
        RegistryByKey      = @{}
        SolutionsPath      = $null
        SolutionsLwt       = [datetime]::MinValue
        SolutionsKeywords  = @()
    }
}

Initialize-MetraRoutingCacheState

function Clear-MetraRoutingCache {
    <#
    .SYNOPSIS
        Clears Metra routing caches (projects scan, registry, solutions keywords, config).
    .DESCRIPTION
        Registry merges also invalidate automatically when projects.json, a root
        registryFile, or projects.local.json LastWriteTimeUtc changes. Solutions keywords
        invalidate on solutions/README.md LastWriteTimeUtc. Call this after metra.config.json
        edits (or when you need a hard reset) in the same PowerShell session.
    #>
    [CmdletBinding()]
    param()

    Initialize-MetraRoutingCacheState
}

function Test-MetraCacheEntryFresh {
    param([datetime]$CachedUtc)

    if ($CachedUtc -eq [datetime]::MinValue) { return $false }
    $age = ([datetime]::UtcNow - $CachedUtc).TotalSeconds
    return ($age -ge 0 -and $age -lt [double]$script:MetraCacheTtlSeconds)
}

function Get-MetraCacheTtlSeconds {
    return [int]$script:MetraCacheTtlSeconds
}

if ($null -eq (Get-Variable -Name MetraFileTextCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraFileTextCache = @{}
}

function Get-MetraCachedFileText {
    <#
    .SYNOPSIS
        Read a UTF-8 text file with in-process cache keyed by path + LastWriteTimeUtc.
        On mtime read failure, returns an uncached read (never stale forever).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$CacheKey = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    $key = if ($CacheKey) { $CacheKey } else { $Path }
    $lwt = $null
    try {
        $lwt = (Get-Item -LiteralPath $Path).LastWriteTimeUtc
    }
    catch {
        try {
            return [System.IO.File]::ReadAllText($Path).Trim()
        }
        catch {
            return ''
        }
    }

    $hit = $script:MetraFileTextCache[$key]
    if ($hit -and $hit.Lwt -eq $lwt -and $null -ne $hit.Text) {
        return [string]$hit.Text
    }

    try {
        $text = [System.IO.File]::ReadAllText($Path).Trim()
    }
    catch {
        return ''
    }
    $script:MetraFileTextCache[$key] = @{ Lwt = $lwt; Text = $text }
    return $text
}
