# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Get-MetraRoot {
    return $script:MetraModuleRoot
}

function Get-MetraMachineDataRoot {
    <#
    .SYNOPSIS
        Machine-local Metra state root (%LOCALAPPDATA%\Metra), overridable for tests.
    .NOTES
        Explicit sandbox -MetraRoot (≠ live module root) wins over METRA_DATA_ROOT so Pester
        stays isolated. Otherwise METRA_DATA_ROOT forces the root. Live ops ledgers:
        %LOCALAPPDATA%\Metra\ops\ (and sibling *.local.json files).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot)
    $live = $null
    $liveRoot = Get-MetraRoot
    if (-not [string]::IsNullOrWhiteSpace($liveRoot)) {
        try { $live = [System.IO.Path]::GetFullPath($liveRoot) } catch { $live = $null }
    }
    if (-not [string]::IsNullOrWhiteSpace($MetraRoot)) {
        $sandbox = [System.IO.Path]::GetFullPath($MetraRoot)
        if ([string]::IsNullOrWhiteSpace($live) -or
            -not [string]::Equals($sandbox, $live, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void][System.IO.Directory]::CreateDirectory($sandbox)
            return $sandbox
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:METRA_DATA_ROOT)) {
        $p = [System.IO.Path]::GetFullPath($env:METRA_DATA_ROOT.Trim())
        [void][System.IO.Directory]::CreateDirectory($p)
        return $p
    }
    $local = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) {
        $local = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
    }
    if ([string]::IsNullOrWhiteSpace($local)) {
        throw 'LOCALAPPDATA unavailable; set METRA_DATA_ROOT for machine-local Metra state.'
    }
    $p = [System.IO.Path]::GetFullPath((Join-Path $local 'Metra'))
    [void][System.IO.Directory]::CreateDirectory($p)
    return $p
}

function Move-MetraLegacyDocsGeneratedIfNeeded {
    <#
    .SYNOPSIS
        One-shot: move gitignored/docs-generated leaf into DestPath when Dest is missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LegacyRelativeUnderDocs,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (Test-Path -LiteralPath $DestinationPath) { return }
    if ([string]::IsNullOrWhiteSpace($MetraRoot) -or -not [System.IO.Path]::IsPathRooted($MetraRoot)) {
        return
    }
    $legacy = Join-Path $MetraRoot (Join-Path 'docs' $LegacyRelativeUnderDocs)
    if (-not (Test-Path -LiteralPath $legacy)) { return }
    $dir = Split-Path -Parent $DestinationPath
    if ($dir) { [void][System.IO.Directory]::CreateDirectory($dir) }
    try {
        Move-Item -LiteralPath $legacy -Destination $DestinationPath -Force -ErrorAction Stop
    }
    catch {
        Write-Warning ("Move-MetraLegacyDocsGeneratedIfNeeded: could not move '{0}' -> '{1}': {2}" -f $legacy, $DestinationPath, $_.Exception.Message)
    }
}

function Resolve-MetraMachineLedgerPath {
    <#
    .SYNOPSIS
        Machine-local ledger path under Get-MetraMachineDataRoot, with docs\ legacy migrate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativeUnderMachineData,
        [Parameter(Mandatory)][string]$LegacyRelativeUnderDocs,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $dest = Join-Path (Get-MetraMachineDataRoot -MetraRoot $MetraRoot) $RelativeUnderMachineData
    $dir = Split-Path -Parent $dest
    if ($dir) { [void][System.IO.Directory]::CreateDirectory($dir) }
    Move-MetraLegacyDocsGeneratedIfNeeded -LegacyRelativeUnderDocs $LegacyRelativeUnderDocs `
        -DestinationPath $dest -MetraRoot $MetraRoot
    return $dest
}

function Get-MetraOpsAskLogPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ops\ask-log.json' `
        -LegacyRelativeUnderDocs 'ops-ask-log.local.json'
}

function Get-MetraOpsCapturePath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ops\capture.json' `
        -LegacyRelativeUnderDocs 'ops-capture.local.json'
}

function Get-MetraOpsAttentionPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ops\attention.json' `
        -LegacyRelativeUnderDocs 'ops-attention.local.json'
}

function Get-MetraOpsPlacePath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ops\place.json' `
        -LegacyRelativeUnderDocs 'ops-place.local.json'
}

function Get-MetraOpsPreferencesPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ops\preferences.json' `
        -LegacyRelativeUnderDocs 'ops-preferences.local.json'
}

function Get-MetraAzdoLocalConfigPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'azdo.local.json' `
        -LegacyRelativeUnderDocs 'azdo.local.json'
}

function Get-MetraTicketWatchConfigPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'ticket-watch.local.json' `
        -LegacyRelativeUnderDocs 'ticket-watch.local.json'
}

function Get-MetraClientAuthLocalPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'client-auth.local.json' `
        -LegacyRelativeUnderDocs 'client-auth.local.json'
}

function Get-MetraProfileSyncLocalPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'profile-sync.local.json' `
        -LegacyRelativeUnderDocs 'profile-sync.local.json'
}

function Get-MetraDeskFamiliarityLedgerPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'desk-familiarity.local.json' `
        -LegacyRelativeUnderDocs 'desk-familiarity.local.json'
}

function Get-MetraCanvasSnapshotPath {
    <#
    .SYNOPSIS
        Ops/canvas portfolio snapshot JSON (machine-local desk state).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'desk\canvas-snapshot.json' `
        -LegacyRelativeUnderDocs 'canvas-snapshot.json'
}

function Get-MetraContextPackPath {
    <#
    .SYNOPSIS
        Default ctx / context-pack output path under machine-local desk state.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('md', 'json')]
        [string]$Format = 'md',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $leaf = if ($Format -eq 'json') { 'context-pack.json' } else { 'context-pack.md' }
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData ('desk\' + $leaf) `
        -LegacyRelativeUnderDocs $leaf
}

function Get-MetraSelfDocRoutesPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'selfdoc\selfdoc-routes.json' `
        -LegacyRelativeUnderDocs 'selfdoc-routes.json'
}

function Get-MetraSelfDocRoutingExamplesPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData 'selfdoc\selfdoc-routing-examples.json' `
        -LegacyRelativeUnderDocs 'selfdoc-routing-examples.json'
}

function Initialize-MetraConfigCache {
    <#
    .SYNOPSIS
        Ensures $script:MetraCache has config cache slots (StrictMode / split-module safe).
    #>
    if ($null -eq $script:MetraCache) {
        if (Get-Command Initialize-MetraRoutingCacheState -ErrorAction SilentlyContinue) {
            Initialize-MetraRoutingCacheState
        }
        else {
            $script:MetraCache = @{
                ConfigPath = $null
                ConfigLwt  = [datetime]::MinValue
                Config     = $null
            }
        }
    }

    if ($script:MetraCache -is [hashtable]) {
        if (-not $script:MetraCache.ContainsKey('Config')) { $script:MetraCache['Config'] = $null }
        if (-not $script:MetraCache.ContainsKey('ConfigPath')) { $script:MetraCache['ConfigPath'] = $null }
        if (-not $script:MetraCache.ContainsKey('ConfigLwt')) { $script:MetraCache['ConfigLwt'] = [datetime]::MinValue }
        return
    }

    if ($null -eq $script:MetraCache.PSObject.Properties['Config']) {
        $script:MetraCache | Add-Member -NotePropertyName Config -NotePropertyValue $null -Force
    }
    if ($null -eq $script:MetraCache.PSObject.Properties['ConfigPath']) {
        $script:MetraCache | Add-Member -NotePropertyName ConfigPath -NotePropertyValue $null -Force
    }
    if ($null -eq $script:MetraCache.PSObject.Properties['ConfigLwt']) {
        $script:MetraCache | Add-Member -NotePropertyName ConfigLwt -NotePropertyValue $null -Force
    }
}

function Get-MetraConfig {
    Initialize-MetraConfigCache

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

    try {
        $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    }
    catch {
        throw ("Failed to read Metra config '{0}': {1}" -f $configPath, $_.Exception.Message)
    }
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

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            $val = $Object[$Name]
            if ($null -eq $val) { return $Default }
            return $val
        }
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $val = $Object[$key]
                if ($null -eq $val) { return $Default }
                return $val
            }
        }
        return $Default
    }

    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function Test-MetraPropExists {
    <#
    .SYNOPSIS
        True when a PSCustomObject or dictionary has a named property/key (case-insensitive for dictionaries).
    #>
    [CmdletBinding()]
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $false }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $true }
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }

    return [bool]$Object.PSObject.Properties[$Name]
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
        $rootName = $rootName.Trim()
        if ([string]::IsNullOrWhiteSpace($rootName)) {
            $rootName = 'projects'
        }

        $rawPath = [string](Get-MetraProp -Object $def -Name 'path' -Default '..')
        $rawPath = $rawPath.Trim()
        if ([string]::IsNullOrWhiteSpace($rawPath)) {
            $rawPath = '..'
        }

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
    $duplicateNames = @(
        $results |
            Group-Object Name |
            Where-Object { $_.Count -gt 1 } |
            Select-Object -ExpandProperty Name
    )
    if ($duplicateNames.Count -gt 0) {
        throw ("Duplicate root name(s) in metra.config.json: {0}" -f ($duplicateNames -join ', '))
    }

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
    Initialize-MetraConfigCache
    $script:MetraCache.Config = $null
    $script:MetraCache.ConfigPath = $null
    $script:MetraCache.ConfigLwt = $null
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

    $prefs = if (Get-Command Get-MetraDeskPreferences -ErrorAction SilentlyContinue) {
        Get-MetraDeskPreferences -MetraRoot $MetraRoot
    }
    else {
        [PSCustomObject]@{
            machineRole       = 'Standalone'
            preferFriendlyUrl = $false
            bindTailscale     = $false
        }
    }

    $opsBaseUrl = if (Get-Command Get-MetraProfileOpsBaseUrlOrNull -ErrorAction SilentlyContinue) {
        Get-MetraProfileOpsBaseUrlOrNull -MetraRoot $MetraRoot
    }
    else {
        $null
    }

    $bindingSummary = 'loopback'
    $operatorUrl = $null
    $shareUrl = $null
    try {
        if (Get-Command Resolve-MetraOpsDeskBinding -ErrorAction SilentlyContinue) {
            $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
            if ($binding -and $binding.BrowserUrl) {
                $shareUrl = [string]$binding.BrowserUrl
                if (Get-Command Get-MetraOpsOperatorOpenUrl -ErrorAction SilentlyContinue) {
                    $operatorUrl = Get-MetraOpsOperatorOpenUrl -Binding $binding
                }
                if ([bool]$prefs.bindTailscale) {
                    $bindingSummary = "Tailscale reach ($shareUrl)"
                }
                elseif ([bool]$prefs.preferFriendlyUrl -or ($binding.BrowserHost -eq 'metra')) {
                    $bindingSummary = "Friendly URL ($shareUrl)"
                }
                else {
                    $bindingSummary = "Loopback ($shareUrl)"
                }
            }
        }
    }
    catch {
        $bindingSummary = 'unknown'
    }

    return [PSCustomObject]@{
        metraRoot       = $MetraRoot
        primaryPath     = $(if ($primary) { [string]$primary.Path } else { '' })
        # Compat: first optional / personal-named root path (older Settings UI).
        personalPath    = $(
            $p = @($roots | Where-Object {
                    $_.Optional -or ($_.Name -and $_.Name.ToLowerInvariant() -eq 'personal')
                }) | Select-Object -First 1
            if ($p) { [string]$p.Path } else { '' }
        )
        hint            = 'Each folder is a parent that contains project folders. Give each a label (Work, Personal, Lab). Mark one as primary; optional folders may be offline.'
        roots           = $rootRows
        ask             = [PSCustomObject]@{
            apiKeyPresent = [bool]$apiKeyPresent
        }
        machineRole     = $prefs.machineRole
        opsBaseUrl      = $opsBaseUrl
        bindingSummary  = $bindingSummary
        operatorUrl     = $operatorUrl
        shareUrl        = $shareUrl
        preferFriendlyUrl = $prefs.preferFriendlyUrl
        bindTailscale   = [bool]$prefs.bindTailscale
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
        [ValidateSet('Hq', 'Satellite', 'Standalone')]
        [string]$MachineRole,
        [string]$OpsBaseUrl,
        [switch]$ClearOpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $touchedRoots = $false
    $cursorKeyResult = $null
    $pendingRootsWrite = $null
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
            $expandedRaw = [System.Environment]::ExpandEnvironmentVariables($rawPath)
            if (-not [System.IO.Path]::IsPathRooted($expandedRaw)) {
                $expandedRaw = Join-Path $MetraRoot $expandedRaw
            }
            $expanded = [System.IO.Path]::GetFullPath($expandedRaw)
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
                        $candExpanded = [System.Environment]::ExpandEnvironmentVariables($candPath)
                        if (-not [System.IO.Path]::IsPathRooted($candExpanded)) {
                            $candExpanded = Join-Path $MetraRoot $candExpanded
                        }
                        $candFull = [System.IO.Path]::GetFullPath($candExpanded)
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

        if ($null -eq $cfg.PSObject.Properties['roots']) {
            $cfg | Add-Member -NotePropertyName roots -NotePropertyValue @($built.ToArray()) -Force
        }
        else {
            $cfg.roots = @($built.ToArray())
        }

        if ($null -eq $cfg.PSObject.Properties['projectsRoot']) {
            $cfg | Add-Member -NotePropertyName projectsRoot -NotePropertyValue $primaryPathOut -Force
        }
        else {
            $cfg.projectsRoot = $primaryPathOut
        }

        $json = $cfg | ConvertTo-Json -Depth 12
        $pendingRootsWrite = [PSCustomObject]@{ path = $configPath; json = $json }
    }

    if ($ClearCursorApiKey) {
        $cursorKeyResult = Set-MetraCursorApiKey -Clear
    }
    elseif (-not [string]::IsNullOrWhiteSpace($CursorApiKey)) {
        $cursorKeyResult = Set-MetraCursorApiKey -ApiKey $CursorApiKey
    }

    $rootsWritten = $false
    if ($pendingRootsWrite) {
        Set-Content -LiteralPath $pendingRootsWrite.path -Value $pendingRootsWrite.json -Encoding UTF8
        Clear-MetraConfigCache
        $rootsWritten = $true
    }

    if ($PSBoundParameters.ContainsKey('MachineRole') -and $MachineRole) {
        $null = Set-MetraDeskPreferences -MetraRoot $MetraRoot -MachineRole $MachineRole
    }
    if ($ClearOpsBaseUrl) {
        $null = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl '' -MetraRoot $MetraRoot
    }
    elseif ($PSBoundParameters.ContainsKey('OpsBaseUrl')) {
        $null = Set-MetraConfiguredOpsBaseUrl -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot
    }

    $cursorKeyOk = $true
    if ($null -ne $cursorKeyResult) {
        $keyStatusGate = [string](Get-MetraProp -Object $cursorKeyResult -Name 'status' -Default '')
        if ($keyStatusGate -in @('cancelled', 'whatif', 'rolled_back', 'failed')) { $cursorKeyOk = $false }
        if ($null -ne $cursorKeyResult.sidecarRestarted -and -not [bool]$cursorKeyResult.sidecarRestarted) {
            $cursorKeyOk = $false
        }
    }

    $portfolio = Get-MetraSettingsPortfolio -MetraRoot $MetraRoot
    $partialSuccess = [bool]$rootsWritten -and -not [bool]$cursorKeyOk -and ($null -ne $cursorKeyResult)
    $result = [PSCustomObject]@{
        ok             = [bool]$cursorKeyOk
        rootsSaved     = [bool]$rootsWritten
        partialSuccess = $partialSuccess
        portfolio      = $portfolio
    }
    if ($null -ne $cursorKeyResult) {
        $result | Add-Member -NotePropertyName cursorKey -NotePropertyValue $cursorKeyResult -Force
        $keyStatus = [string](Get-MetraProp -Object $cursorKeyResult -Name 'status' -Default '')
        if ($keyStatus) {
            $result | Add-Member -NotePropertyName cursorKeyStatus -NotePropertyValue $keyStatus -Force
        }
        if ($null -ne $cursorKeyResult.sidecarRestarted) {
            $result | Add-Member -NotePropertyName sidecarRestarted -NotePropertyValue ([bool]$cursorKeyResult.sidecarRestarted) -Force
        }
        if ($cursorKeyResult.sidecarRestartWarning) {
            $result | Add-Member -NotePropertyName sidecarRestartWarning -NotePropertyValue ([string]$cursorKeyResult.sidecarRestartWarning) -Force
        }
    }
    return $result
}

function Test-MetraSelfFolderName {
    <#
    .SYNOPSIS
        True when the folder is this orchestration checkout (Metra product, _metra convention).
    #>
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name.Trim()
    return [string]::Equals($n, '_metra', [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($n, '_meta', [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($n, 'metra', [StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($n, 'meta', [StringComparison]::OrdinalIgnoreCase)
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

