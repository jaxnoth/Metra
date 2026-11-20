# Desk façade for Loom ship-cycle. No parallel business logic.

function ConvertFrom-MetraBiteArgs {
    param([string[]]$ArgsRest = @())

    $map = @{
        Name           = $null
        Bite           = $null
        Message        = $null
        ProjectRoot    = $null
        Summary        = $null
        Repos          = @()
        TargetBranch   = $null
        ContentHash    = $null
        Verdict        = $null
        Reset          = $false
        SkipQuickCheck = $false
        SkipInspectEngine = $false
        SkipFullTests  = $false
        NoPush         = $false
        NoDeleteBranch = $false
        OwnerAffirm    = $false
        Resume         = $false
        WhatIf         = $false
        Confirm        = $false
    }

    for ($i = 0; $i -lt @($ArgsRest).Count; $i++) {
        $tok = [string]$ArgsRest[$i]
        $needsValue = $tok -match '^(?i)-Name$|^(?i)-Bite$|^(?i)-m$|^(?i)-Message$|^(?i)-ProjectRoot$|^(?i)-Summary$|^(?i)-TargetBranch$|^(?i)-ContentHash$|^(?i)-Verdict$'
        if ($needsValue -and (($i + 1) -ge @($ArgsRest).Count)) {
            throw ("bite flag {0} requires a value." -f $tok)
        }
        switch -Regex ($tok) {
            '^(?i)-Name$' {
                $i++; $map.Name = [string]$ArgsRest[$i]
            }
            '^(?i)-Bite$' {
                $i++; $map.Bite = [string]$ArgsRest[$i]
            }
            '^(?i)-m$|^(?i)-Message$' {
                $i++; $map.Message = [string]$ArgsRest[$i]
            }
            '^(?i)-ProjectRoot$' {
                $i++; $map.ProjectRoot = [string]$ArgsRest[$i]
            }
            '^(?i)-Summary$' {
                $i++; $map.Summary = [string]$ArgsRest[$i]
            }
            '^(?i)-TargetBranch$' {
                $i++; $map.TargetBranch = [string]$ArgsRest[$i]
            }
            '^(?i)-ContentHash$' {
                $i++; $map.ContentHash = [string]$ArgsRest[$i]
            }
            '^(?i)-Verdict$' {
                $i++; $map.Verdict = [string]$ArgsRest[$i]
            }
            '^(?i)-Repos$' {
                $i++
                while ($i -lt $ArgsRest.Count -and [string]$ArgsRest[$i] -notmatch '^-') {
                    $map.Repos += [string]$ArgsRest[$i]
                    $i++
                }
                $i--
            }
            '^(?i)-Reset$' { $map.Reset = $true }
            '^(?i)-SkipQuickCheck$' { $map.SkipQuickCheck = $true }
            '^(?i)-SkipInspectEngine$' { $map.SkipInspectEngine = $true }
            '^(?i)-SkipFullTests$' { $map.SkipFullTests = $true }
            '^(?i)-NoPush$' { $map.NoPush = $true }
            '^(?i)-NoDeleteBranch$' { $map.NoDeleteBranch = $true }
            '^(?i)-OwnerAffirm$' { $map.OwnerAffirm = $true }
            '^(?i)-Resume$' { $map.Resume = $true }
            '^(?i)-WhatIf$' { $map.WhatIf = $true }
            '^(?i)-Confirm$' { $map.Confirm = $true }
            default { }
        }
    }
    return [PSCustomObject]$map
}

function Invoke-MetraBiteCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string[]]$Name
    )

    if (-not (Get-Command Invoke-MetraLoomCommand -ErrorAction SilentlyContinue)) {
        $loomManifest = Join-Path $script:MetraModuleRoot 'modules\Loom\Loom.psd1'
        if (Test-Path -LiteralPath $loomManifest) {
            Import-Module $loomManifest -Force
        }
    }

    $parsed = ConvertFrom-MetraBiteArgs -ArgsRest $ArgsRest
    $project = [string]$parsed.Name
    if ([string]::IsNullOrWhiteSpace($project) -and $Name -and @($Name).Count -gt 0) {
        $project = [string]$Name[0]
    }
    if ([string]::IsNullOrWhiteSpace($project)) {
        throw 'bite requires -Name <Project>.'
    }

    switch ($Subcommand.ToLowerInvariant()) {
        'start' {
            if ($parsed.WhatIf) {
                throw 'bite start does not support -WhatIf (mutating). Omit -WhatIf to run.'
            }
            if ([string]::IsNullOrWhiteSpace([string]$parsed.Bite)) {
                throw 'bite start requires -Bite <id>.'
            }
            $p = @{
                Name = $project
                Bite = [string]$parsed.Bite
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.ProjectRoot)) { $p.ProjectRoot = [string]$parsed.ProjectRoot }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.TargetBranch)) { $p.TargetBranch = [string]$parsed.TargetBranch }
            if (@($parsed.Repos).Count -gt 0) { $p.Repos = @($parsed.Repos) }
            if ($parsed.NoPush) { $p.NoPush = $true }
            return Start-LoomShipBranch @p
        }
        'commit' {
            if ($parsed.WhatIf) {
                throw 'bite commit does not support -WhatIf (mutating). Omit -WhatIf to run.'
            }
            if ([string]::IsNullOrWhiteSpace([string]$parsed.Message)) {
                throw 'bite commit requires -Message "<message>".'
            }
            $p = @{
                Name    = $project
                Message = [string]$parsed.Message
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.ProjectRoot)) { $p.ProjectRoot = [string]$parsed.ProjectRoot }
            if ($parsed.SkipQuickCheck) { $p.SkipQuickCheck = $true }
            if ($parsed.NoPush) { $p.NoPush = $true }
            return Invoke-LoomShipCommit @p
        }
        'pack' {
            if ($parsed.WhatIf) {
                throw 'bite pack does not support -WhatIf (mutating). Omit -WhatIf to run.'
            }
            $p = @{ Name = $project }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.ProjectRoot)) { $p.ProjectRoot = [string]$parsed.ProjectRoot }
            if ($parsed.Reset) { $p.Reset = $true }
            if ($parsed.SkipInspectEngine) { $p.SkipInspectEngine = $true }
            return Invoke-LoomShipPack @p
        }
        'ship' {
            $p = @{ Name = $project }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.ProjectRoot)) { $p.ProjectRoot = [string]$parsed.ProjectRoot }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.Summary)) { $p.Summary = [string]$parsed.Summary }
            if ($parsed.SkipFullTests) { $p.SkipFullTests = $true }
            if ($parsed.NoPush) { $p.NoPush = $true }
            if ($parsed.NoDeleteBranch) { $p.NoDeleteBranch = $true }
            if ($parsed.OwnerAffirm) { $p.OwnerAffirm = $true }
            if ($parsed.Resume) { $p.Resume = $true }
            if ($parsed.WhatIf) { $p.WhatIf = $true }
            if ($parsed.Confirm) { $p.Confirm = $true }
            # WhatIf/Confirm map to SupportsShouldProcess on Invoke-LoomShip.
            return Invoke-LoomShip @p
        }
        'status' {
            $p = @{ Name = $project }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.ProjectRoot)) { $p.ProjectRoot = [string]$parsed.ProjectRoot }
            return Get-LoomShipStatus @p
        }
        'review-set' {
            # Test / import helper: record machine review against packed hash.
            if ([string]::IsNullOrWhiteSpace([string]$parsed.Verdict) -or [string]::IsNullOrWhiteSpace([string]$parsed.ContentHash)) {
                throw 'bite review-set requires -Verdict and -ContentHash.'
            }
            return Set-LoomShipReviewEvidence -Name $project -Verdict ([string]$parsed.Verdict) -ContentHash ([string]$parsed.ContentHash) -ContractShape
        }
        default {
            throw "Unknown bite subcommand: $Subcommand. Use start|commit|pack|ship|status."
        }
    }
}
