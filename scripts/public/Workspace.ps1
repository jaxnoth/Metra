# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Update-MetraWorkspace {
    <#
    .SYNOPSIS
        Rebuilds Metra.code-workspace file(s) with Metra plus projects active in the lookback window.
    .DESCRIPTION
        Finds recently active projects across configured roots, adds always-included projects,
        drops names listed in workspace.exclude, and writes each workspace output configured
        in metra.config.json. Outputs whose metraFolderPath does not resolve on disk are
        skipped with a warning; if every output is skipped the command throws.

        Prefer native -WhatIf for dry runs. -WhatIfPreview (alias -Preview) remains for
        metra.ps1 workspace -Preview compatibility and will be treated as legacy.
    .PARAMETER Months
        Number of months of project activity to include (1-120). Uses workspace.months when omitted.
    .PARAMETER ScanDepth
        Maximum depth used when finding recent file activity (1-100). Uses workspace.scanDepth when omitted.
    .PARAMETER WhatIfPreview
        Legacy preview switch (alias Preview). Prefer -WhatIf. Displays intended workspace
        writes without writing files (same planning intent as metra.ps1 workspace -Preview).
    .PARAMETER Quiet
        Suppresses host-formatted lookback and write messages.
    .EXAMPLE
        Update-MetraWorkspace
    .EXAMPLE
        Update-MetraWorkspace -Months 3 -WhatIf
    .EXAMPLE
        Update-MetraWorkspace -WhatIfPreview
    .OUTPUTS
        PSCustomObject containing the lookback, scan depth, preview flag, included projects,
        written files, and skipped outputs.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [ValidateRange(1, 120)]
        [Nullable[int]]$Months,

        [ValidateRange(1, 100)]
        [Nullable[int]]$ScanDepth,

        [Alias('Preview')]
        [switch]$WhatIfPreview,

        [switch]$Quiet
    )

    $cfg = Get-MetraConfig
    $metraRoot = Get-MetraRoot
    $ws = $cfg.workspace
    if (-not $ws) {
        throw 'metra.config.json is missing a workspace section.'
    }

    if (-not $PSBoundParameters.ContainsKey('Months') -or $null -eq $Months) {
        $Months = [int](Get-MetraProp -Object $ws -Name 'months' -Default 6)
    }
    else {
        $Months = [int]$Months
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth') -or $null -eq $ScanDepth) {
        $ScanDepth = [int](Get-MetraProp -Object $ws -Name 'scanDepth' -Default 2)
    }
    else {
        $ScanDepth = [int]$ScanDepth
    }

    if ($Months -lt 1 -or $Months -gt 120) {
        throw ("Months must be between 1 and 120 (got {0})." -f $Months)
    }
    if ($ScanDepth -lt 1 -or $ScanDepth -gt 100) {
        throw ("ScanDepth must be between 1 and 100 (got {0})." -f $ScanDepth)
    }

    $isPreview = [bool]$WhatIfPreview -or $WhatIfPreference
    $recent = Get-RecentMetraProjects -Months $Months -ScanDepth $ScanDepth

    # Registered projects can stay routable while staying out of the mounted workspace,
    # so their AGENTS.md does not load as an always-applied rule.
    $wsExclude = @(Get-MetraProp -Object $ws -Name 'exclude' -Default @())
    if ($wsExclude.Count -gt 0) {
        $excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $wsExclude) { [void]$excludeSet.Add([string]$name) }
        $recent = @($recent | Where-Object { -not $excludeSet.Contains([string]$_.Name) })
    }

    $outputs = @(Get-MetraProp -Object $ws -Name 'outputs' -Default @())
    if ($outputs.Count -eq 0) {
        throw 'workspace.outputs is empty in metra.config.json.'
    }
    if ($outputs.Count -gt 1) {
        Write-Warning ("workspace.outputs has {0} entries. Extra copies split Cursor chat history and can bind a stale Metra folder after a checkout rename. Keep one output unless a second workspace file is deliberate." -f $outputs.Count)
    }

    $primaryRootName = (@(Get-MetraRoots -IncludeMissing) | Where-Object { $_.Primary } | Select-Object -First 1).Name

    if (-not $Quiet) {
        Write-Host ("Lookback: {0} month(s) | {1} project(s) (+ Metra)" -f $Months, $recent.Count) -ForegroundColor Cyan
        $recent | ForEach-Object {
            Write-Host ("  {0,-24} {1,-10} {2:yyyy-MM-dd}" -f $_.Name, $_.Root, $_.LastActivity)
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $written = @()
    $skipped = @()
    foreach ($out in $outputs) {
        $outPath = Join-Path $metraRoot $out.path
        $prefix = [string]$out.projectPathPrefix
        $folderLabel = [string](Get-MetraProp -Object $out -Name 'metraFolderName' -Default $null)
        if ([string]::IsNullOrWhiteSpace($folderLabel)) {
            $folderLabel = [string](Get-MetraProp -Object $out -Name 'metaFolderName' -Default 'Metra')
        }
        if ([string]::IsNullOrWhiteSpace($folderLabel)) { $folderLabel = 'Metra' }
        $folderPathValue = Get-MetraProp -Object $out -Name 'metraFolderPath' -Default $null
        if ($null -eq $folderPathValue -or [string]::IsNullOrWhiteSpace([string]$folderPathValue)) {
            $folderPathValue = Get-MetraProp -Object $out -Name 'metaFolderPath' -Default '.'
        }

        # Cursor cannot bind a Metra folder that does not exist, and an unbound workspace
        # cannot start agent chat. Skip the output instead of writing a broken file.
        $outDir = Split-Path -Parent $outPath
        if ([string]::IsNullOrWhiteSpace($outDir)) { $outDir = $metraRoot }
        $metraFolderFull = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($outDir, [string]$folderPathValue))
        if (-not (Test-Path -LiteralPath $metraFolderFull -PathType Container)) {
            Write-Warning ("Skipping workspace output '{0}': metraFolderPath '{1}' does not resolve to a folder ({2})." -f $out.path, [string]$folderPathValue, $metraFolderFull)
            $skipped += [string]$out.path
            continue
        }

        $folders = @(
            [ordered]@{
                name = $folderLabel
                path = [string]$folderPathValue
            }
        )
        foreach ($project in $recent) {
            $projName = [string]$project.Name
            if ($projName -match '[\\/:*?"<>|]') {
                Write-Warning ("Skipping project with invalid folder name: {0}" -f $projName)
                continue
            }

            # Projects outside the primary root cannot be reached by the relative prefix.
            $folderPath = if ($project.Root -eq $primaryRootName) {
                $prefix + $projName
            }
            else {
                $project.Path
            }
            $folders += [ordered]@{
                name = $projName
                path = $folderPath
            }
        }

        $doc = [ordered]@{
            folders    = $folders
            settings   = $ws.settings
            extensions = $ws.extensions
        }

        $json = $doc | ConvertTo-Json -Depth 8
        # WhatIfPreview keeps CLI Preview; native -WhatIf uses ShouldProcess (no write).
        if ($WhatIfPreview -or $PSCmdlet.ShouldProcess($outPath, 'Write workspace')) {
            if ($isPreview) {
                if (-not $Quiet) {
                    Write-Host ("Would write: {0}" -f $outPath) -ForegroundColor Yellow
                }
            }
            else {
                $dir = Split-Path -Parent $outPath
                if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                    [void][System.IO.Directory]::CreateDirectory($dir)
                }
                [System.IO.File]::WriteAllText($outPath, $json + "`r`n", $utf8NoBom)
                if (-not $Quiet) {
                    Write-Host ("Wrote {0}" -f $outPath) -ForegroundColor Green
                }
                $written += $outPath
            }
        }
    }

    if ($skipped.Count -eq $outputs.Count) {
        throw ("No workspace output could be written. Every metraFolderPath is missing: {0}. Fix workspace.outputs in metra.config.json." -f ($skipped -join ', '))
    }

    return [PSCustomObject]@{
        Months       = $Months
        ScanDepth    = $ScanDepth
        Preview      = $isPreview
        ProjectCount = $recent.Count
        Projects     = @(foreach ($project in $recent) { $project.Name })
        Files        = $written
        Skipped      = $skipped
    }
}
