# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraRoot {
    return $script:MetraModuleRoot
}

function Get-MetraConfig {
    $root = Get-MetraRoot
    $preferred = Join-Path $root 'metra.config.json'
    $legacy = Join-Path $root 'meta.config.json'
    if (Test-Path -LiteralPath $preferred) {
        $configPath = $preferred
    }
    elseif (Test-Path -LiteralPath $legacy) {
        Write-Warning 'Using legacy meta.config.json; rename to metra.config.json when convenient.'
        $configPath = $legacy
    }
    else {
        throw "Missing config: $preferred (also checked meta.config.json)"
    }
    return Get-Content -Raw -Path $configPath | ConvertFrom-Json
}

function Get-MetraProp {
    <#
    .SYNOPSIS
        Reads an optional property from a JSON-derived object without tripping StrictMode.
    #>
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Get-MetraRoots {
    <#
    .SYNOPSIS
        Resolves the configured project roots (multi-root aware, env vars expanded).
    .DESCRIPTION
        Reads config.roots when present, else falls back to the legacy single projectsRoot.
        Roots marked optional may be absent (for example a cloud-synced folder that is not
        set up on this machine); they are reported with Exists = $false instead of throwing.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$IncludeMissing
    )

    $cfg = Get-MetraConfig
    $metraRoot = Get-MetraRoot

    $defs = @(Get-MetraProp -Object $cfg -Name 'roots' -Default @())
    if ($defs.Count -eq 0) {
        $legacy = Get-MetraProp -Object $cfg -Name 'projectsRoot'
        if ($legacy) {
            $defs = @([PSCustomObject]@{ name = 'projects'; path = $legacy; primary = $true })
        }
    }
    if ($defs.Count -eq 0) {
        throw 'metra.config.json defines no project roots (expected a roots array or projectsRoot).'
    }

    $primarySeen = $false
    $results = foreach ($def in $defs) {
        $rootName = [string](Get-MetraProp -Object $def -Name 'name' -Default 'projects')
        $rawPath = [string](Get-MetraProp -Object $def -Name 'path' -Default '..')
        $expanded = [System.Environment]::ExpandEnvironmentVariables($rawPath)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $metraRoot $expanded
        }

        $exists = Test-Path -LiteralPath $expanded
        $fullPath = if ($exists) {
            (Resolve-Path -LiteralPath $expanded).Path
        }
        else {
            [System.IO.Path]::GetFullPath($expanded)
        }

        $isPrimary = [bool](Get-MetraProp -Object $def -Name 'primary' -Default $false)
        if ($isPrimary) { $primarySeen = $true }

        [PSCustomObject]@{
            Name      = $rootName
            Path      = $fullPath
            RawPath   = $rawPath
            Primary   = $isPrimary
            Optional  = [bool](Get-MetraProp -Object $def -Name 'optional' -Default $false)
            Cloud     = [bool](Get-MetraProp -Object $def -Name 'cloud' -Default $false)
            ScanDepth = Get-MetraProp -Object $def -Name 'scanDepth'
            Audit     = [string](Get-MetraProp -Object $def -Name 'audit' -Default 'full')
            Registry  = [string](Get-MetraProp -Object $def -Name 'registry' -Default 'shared')
            RegistryFile = [string](Get-MetraProp -Object $def -Name 'registryFile' -Default '')
            Exclude   = @(Get-MetraProp -Object $def -Name 'exclude' -Default @())
            Exists    = $exists
        }
    }

    $results = @($results)
    if (-not $primarySeen -and $results.Count -gt 0) {
        $results[0].Primary = $true
    }

    foreach ($r in $results) {
        if (-not $r.Exists -and -not $r.Optional) {
            throw ("Project root '{0}' not found: {1}" -f $r.Name, $r.Path)
        }
    }

    if ($Name -and $Name.Count -gt 0) {
        $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
        $results = @($results | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() })
        if ($results.Count -eq 0) {
            throw ("No configured root matches: {0}" -f ($Name -join ', '))
        }
    }

    if ($IncludeMissing) { return @($results) }
    return @($results | Where-Object { $_.Exists })
}

function Get-ProjectsRoot {
    <#
    .SYNOPSIS
        Returns the primary project root (creation target and legacy single-root callers).
    #>
    $roots = @(Get-MetraRoots -IncludeMissing)
    $primary = @($roots | Where-Object { $_.Primary }) | Select-Object -First 1
    if (-not $primary) { $primary = $roots[0] }
    return $primary.Path
}

function Test-MetraSelfFolderName {
    <#
    .SYNOPSIS
        True when the folder is this orchestration checkout (Metra product, _metra convention).
    #>
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name.Trim()
    return @('_metra', '_meta', 'meta', 'Metra', 'metra') -contains $n
}

function Test-ExcludedProjectName {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Config,
        $Root
    )

    # Always skip the Metra orchestration folder under any accepted name.
    if (Test-MetraSelfFolderName -Name $Name) { return $true }

    $exclude = @(Get-MetraProp -Object $Config -Name 'exclude' -Default @())
    if ($exclude -contains $Name) { return $true }

    if ($Root) {
        foreach ($rootExclude in @($Root.Exclude)) {
            if ([string]$rootExclude -eq $Name) { return $true }
        }
    }

    foreach ($pattern in @(Get-MetraProp -Object $Config -Name 'excludeNamePatterns' -Default @())) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

