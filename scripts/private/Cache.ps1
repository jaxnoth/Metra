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
        Call after editing projects.json / solutions/README.md / metra.config.json in the
        same PowerShell session when you need an immediate re-read before the TTL expires.
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
