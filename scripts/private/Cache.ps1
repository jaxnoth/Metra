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
