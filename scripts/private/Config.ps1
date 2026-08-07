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

    $lwt = (Get-Item -LiteralPath $configPath).LastWriteTimeUtc
    if (
        $null -ne $script:MetraCache.Config -and
        $script:MetraCache.ConfigPath -eq $configPath -and
        $script:MetraCache.ConfigLwt -eq $lwt
    ) {
        return $script:MetraCache.Config
    }

    $cfg = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    $script:MetraCache.ConfigPath = $configPath
    $script:MetraCache.ConfigLwt = $lwt
    $script:MetraCache.Config = $cfg
    return $cfg
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

        $label = [string](Get-MetraProp -Object $def -Name 'label' -Default '')
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $rootName }

        [PSCustomObject]@{
            Name      = $rootName
            Label     = $label
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

function Get-MetraConfigFilePath {
    <#
    .SYNOPSIS
        Resolves metra.config.json (or legacy meta.config.json) under MetraRoot.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $preferred = Join-Path $MetraRoot 'metra.config.json'
    $legacy = Join-Path $MetraRoot 'meta.config.json'
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    throw "Missing config: $preferred (also checked meta.config.json)"
}

function Clear-MetraConfigCache {
    if ($script:MetraCache) {
        $script:MetraCache.Config = $null
        $script:MetraCache.ConfigPath = $null
        $script:MetraCache.ConfigLwt = $null
    }
}

function Get-MetraSettingsPortfolio {
    <#
    .SYNOPSIS
        Consumer-facing portfolio settings for Ops Settings (roots + Ask key status).
    .DESCRIPTION
        Never returns the Cursor API key value - only whether one is present.
        Roots are a labeled list (name = label); one primary; optional roots may be missing.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $roots = @(Get-MetraRoots -IncludeMissing)
    $primary = @($roots | Where-Object { $_.Primary }) | Select-Object -First 1
    if (-not $primary -and $roots.Count -gt 0) { $primary = $roots[0] }

    $apiKeyPresent = $false
    if (Get-Command Get-MetraCursorApiKey -ErrorAction SilentlyContinue) {
        $apiKeyPresent = -not [string]::IsNullOrWhiteSpace((Get-MetraCursorApiKey))
    }

    $rootRows = @(
        foreach ($r in $roots) {
            $label = [string](Get-MetraProp -Object $r -Name 'Label' -Default '')
            if ([string]::IsNullOrWhiteSpace($label)) { $label = [string]$r.Name }
            [PSCustomObject]@{
                name     = [string]$r.Name
                label    = $label
                path     = [string]$r.Path
                rawPath  = [string]$r.RawPath
                primary  = [bool]$r.Primary
                optional = [bool]$r.Optional
                cloud    = [bool]$r.Cloud
                exists   = [bool]$r.Exists
            }
        }
    )

    return [PSCustomObject]@{
        metraRoot    = $MetraRoot
        primaryPath  = $(if ($primary) { [string]$primary.Path } else { '' })
        # Compat: first optional / personal-named root path (older Settings UI).
        personalPath = $(
            $p = @($roots | Where-Object {
                    $_.Optional -or ($_.Name -and $_.Name.ToLowerInvariant() -eq 'personal')
                }) | Select-Object -First 1
            if ($p) { [string]$p.Path } else { '' }
        )
        hint         = 'Each folder is a parent that contains project folders. Give each a label (Work, Personal, Lab). Mark one as primary; optional folders may be offline.'
        roots        = $rootRows
        ask          = [PSCustomObject]@{
            apiKeyPresent = [bool]$apiKeyPresent
        }
    }
}

function ConvertTo-MetraRootNameSlug {
    param([Parameter(Mandatory)][string]$Label)
    $slug = ($Label.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'root' }
    return $slug
}

function Save-MetraSettingsPortfolio {
    <#
    .SYNOPSIS
        Updates consumer portfolio settings (labeled project roots and optional Cursor Ask key).
    .DESCRIPTION
        Preferred input is -Roots (name/label, path, primary, optional). Legacy -PrimaryPath /
        -PersonalPath still work. Writes metra.config.json. Primary folder must exist; optional
        folders may be missing. Extra root fields (registry, cloud, …) are preserved when the
        root name matches an existing entry.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Roots,
        [string]$PrimaryPath,
        [string]$PersonalPath,
        [switch]$ClearPersonal,
        [string]$CursorApiKey,
        [switch]$ClearCursorApiKey,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $touchedRoots = $false
    $hasRootsPayload = $PSBoundParameters.ContainsKey('Roots') -and $null -ne $Roots
    $hasLegacy = -not [string]::IsNullOrWhiteSpace($PrimaryPath) -or
        $PSBoundParameters.ContainsKey('PersonalPath') -or $ClearPersonal

    if ($hasRootsPayload -or $hasLegacy) {
        $touchedRoots = $true
        $configPath = Get-MetraConfigFilePath -MetraRoot $MetraRoot
        $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
        $existing = @(@(Get-MetraProp -Object $cfg -Name 'roots' -Default @()))
        $existingByName = @{}
        foreach ($d in $existing) {
            $n = [string](Get-MetraProp -Object $d -Name 'name' -Default '')
            if ($n) { $existingByName[$n.ToLowerInvariant()] = $d }
        }

        $incoming = @()
        if ($hasRootsPayload) {
            $incoming = @($Roots)
        }
        else {
            # Legacy two-field Settings -> roots list.
            $workPath = $PrimaryPath
            if ([string]::IsNullOrWhiteSpace($workPath)) {
                $prim = @($existing | Where-Object { [bool](Get-MetraProp -Object $_ -Name 'primary' -Default $false) }) |
                    Select-Object -First 1
                if (-not $prim -and $existing.Count -gt 0) { $prim = $existing[0] }
                $workPath = if ($prim) { [string](Get-MetraProp -Object $prim -Name 'path' -Default '') } else { '' }
            }
            $incoming += [PSCustomObject]@{
                name     = 'work'
                label    = 'Work'
                path     = $workPath
                primary  = $true
                optional = $false
            }
            $keepPersonal = -not $ClearPersonal -and (
                ($PSBoundParameters.ContainsKey('PersonalPath') -and -not [string]::IsNullOrWhiteSpace($PersonalPath)) -or
                (-not $PSBoundParameters.ContainsKey('PersonalPath') -and (
                        @($existing | Where-Object {
                                [bool](Get-MetraProp -Object $_ -Name 'optional' -Default $false) -or
                                ([string](Get-MetraProp -Object $_ -Name 'name' -Default '')).ToLowerInvariant() -eq 'personal'
                            }).Count -gt 0
                    ))
            )
            if ($keepPersonal) {
                $pPath = $PersonalPath
                if ([string]::IsNullOrWhiteSpace($pPath)) {
                    $oldP = @($existing | Where-Object {
                            [bool](Get-MetraProp -Object $_ -Name 'optional' -Default $false) -or
                            ([string](Get-MetraProp -Object $_ -Name 'name' -Default '')).ToLowerInvariant() -eq 'personal'
                        }) | Select-Object -First 1
                    $pPath = if ($oldP) { [string](Get-MetraProp -Object $oldP -Name 'path' -Default '') } else { '' }
                }
                if (-not [string]::IsNullOrWhiteSpace($pPath)) {
                    $incoming += [PSCustomObject]@{
                        name     = 'personal'
                        label    = 'Personal'
                        path     = $pPath
                        primary  = $false
                        optional = $true
                    }
                }
            }
        }

        if ($incoming.Count -eq 0) {
            throw 'At least one projects folder is required.'
        }

        $built = [System.Collections.Generic.List[object]]::new()
        $usedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $primaryCount = 0

        foreach ($row in $incoming) {
            $label = [string](Get-MetraProp -Object $row -Name 'label' -Default '')
            if ([string]::IsNullOrWhiteSpace($label)) {
                $label = [string](Get-MetraProp -Object $row -Name 'name' -Default '')
            }
            $label = $label.Trim()
            if ([string]::IsNullOrWhiteSpace($label)) {
                throw 'Each projects folder needs a label.'
            }

            $name = [string](Get-MetraProp -Object $row -Name 'name' -Default '').Trim()
            if ([string]::IsNullOrWhiteSpace($name) -or $name -match '\s') {
                $name = ConvertTo-MetraRootNameSlug -Label $label
            }
            $baseName = $name
            $n = 2
            while (-not $usedNames.Add($name)) {
                $name = "$baseName-$n"
                $n++
            }

            $rawPath = [string](Get-MetraProp -Object $row -Name 'path' -Default '').Trim()
            if ([string]::IsNullOrWhiteSpace($rawPath)) {
                throw "Projects folder '$label' needs a path."
            }
            $expanded = [System.IO.Path]::GetFullPath(
                [System.Environment]::ExpandEnvironmentVariables($rawPath)
            )
            $isPrimary = [bool](Get-MetraProp -Object $row -Name 'primary' -Default $false)
            $isOptional = [bool](Get-MetraProp -Object $row -Name 'optional' -Default $false)
            if ($isPrimary) { $primaryCount++; $isOptional = $false }

            if ($isPrimary -and -not (Test-Path -LiteralPath $expanded)) {
                throw "Primary projects folder not found: $expanded"
            }
            if (-not $isOptional -and -not (Test-Path -LiteralPath $expanded)) {
                throw "Projects folder '$label' not found: $expanded"
            }

            $prev = $null
            if ($existingByName.ContainsKey($name)) { $prev = $existingByName[$name] }
            elseif ($existingByName.ContainsKey($baseName)) { $prev = $existingByName[$baseName] }
            if (-not $prev) {
                foreach ($cand in $existing) {
                    $candPath = [string](Get-MetraProp -Object $cand -Name 'path' -Default '')
                    if ([string]::IsNullOrWhiteSpace($candPath)) { continue }
                    try {
                        $candFull = [System.IO.Path]::GetFullPath(
                            [System.Environment]::ExpandEnvironmentVariables($candPath)
                        )
                        if ($candFull.Equals($expanded, [StringComparison]::OrdinalIgnoreCase)) {
                            $prev = $cand
                            break
                        }
                    }
                    catch { }
                }
            }

            $def = [ordered]@{
                name     = $name
                path     = $expanded
                primary  = $isPrimary
                optional = $isOptional
                label    = $label
            }

            # Preserve operator/registry topology from the previous entry when present.
            if ($prev) {
                foreach ($keep in @('cloud', 'scanDepth', 'audit', 'registry', 'registryFile', 'exclude')) {
                    $val = Get-MetraProp -Object $prev -Name $keep -Default $null
                    if ($null -ne $val -and -not $def.Contains($keep)) {
                        $def[$keep] = $val
                    }
                }
            }
            elseif ($isOptional) {
                $def['cloud'] = [bool](Get-MetraProp -Object $row -Name 'cloud' -Default $true)
                $def['registry'] = 'local'
            }
            else {
                $def['registry'] = 'shared'
            }

            [void]$built.Add([PSCustomObject]$def)
        }

        if ($primaryCount -eq 0) {
            $built[0].primary = $true
            $built[0].optional = $false
        }
        elseif ($primaryCount -gt 1) {
            $seen = $false
            foreach ($d in $built) {
                if ($d.primary -and -not $seen) { $seen = $true }
                elseif ($d.primary) { $d.primary = $false }
            }
        }

        $primaryPathOut = [string](@($built | Where-Object { $_.primary })[0].path)
        $cfg.roots = @($built.ToArray())
        if ($null -eq $cfg.PSObject.Properties['projectsRoot']) {
            $cfg | Add-Member -NotePropertyName projectsRoot -NotePropertyValue $primaryPathOut -Force
        }
        else {
            $cfg.projectsRoot = $primaryPathOut
        }
        $json = $cfg | ConvertTo-Json -Depth 12
        Set-Content -LiteralPath $configPath -Value $json -Encoding UTF8
        Clear-MetraConfigCache
    }

    if ($ClearCursorApiKey) {
        $null = Set-MetraCursorApiKey -ApiKey 'x' -Clear
    }
    elseif (-not [string]::IsNullOrWhiteSpace($CursorApiKey)) {
        $null = Set-MetraCursorApiKey -ApiKey $CursorApiKey
    }

    $portfolio = Get-MetraSettingsPortfolio -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        ok         = $true
        rootsSaved = [bool]$touchedRoots
        portfolio  = $portfolio
    }
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

