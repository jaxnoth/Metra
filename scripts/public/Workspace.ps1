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
    .PARAMETER Months
        Number of months of project activity to include. Uses workspace.months when omitted.
    .PARAMETER ScanDepth
        Maximum depth used when finding recent file activity. Uses workspace.scanDepth when omitted.
    .PARAMETER WhatIfPreview
        Displays intended workspace writes without writing files. This is the native equivalent
        of the metra.ps1 workspace -Preview option.
    .EXAMPLE
        Update-MetraWorkspace
    .EXAMPLE
        Update-MetraWorkspace -Months 3 -WhatIfPreview
    .OUTPUTS
        PSCustomObject containing the lookback, included projects, written files, and skipped outputs.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$Months,
        [int]$ScanDepth,
        [switch]$WhatIfPreview,
        [switch]$Quiet
    )

    $cfg = Get-MetraConfig
    $metraRoot = Get-MetraRoot
    $ws = $cfg.workspace
    if (-not $ws) {
        throw 'metra.config.json is missing a workspace section.'
    }

    if (-not $PSBoundParameters.ContainsKey('Months')) {
        $Months = [int]$ws.months
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth')) {
        $ScanDepth = [int]$ws.scanDepth
    }

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
            # Projects outside the primary root cannot be reached by the relative prefix.
            $folderPath = if ($project.Root -eq $primaryRootName) {
                $prefix + $project.Name
            }
            else {
                $project.Path
            }
            $folders += [ordered]@{
                name = $project.Name
                path = $folderPath
            }
        }

        $doc = [ordered]@{
            folders    = $folders
            settings   = $ws.settings
            extensions = $ws.extensions
        }

        $json = $doc | ConvertTo-Json -Depth 8
        # ConvertTo-Json can emit awkward escaping; normalize to UTF8 workspace JSON
        if ($WhatIfPreview -or $PSCmdlet.ShouldProcess($outPath, 'Write workspace')) {
            if ($WhatIfPreview) {
                if (-not $Quiet) {
                    Write-Host ("Would write: {0}" -f $outPath) -ForegroundColor Yellow
                }
            }
            else {
                $dir = Split-Path -Parent $outPath
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
                [System.IO.File]::WriteAllText($outPath, $json + "`r`n")
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
        ProjectCount = $recent.Count
        Projects     = @(foreach ($project in $recent) { $project.Name })
        Files        = $written
        Skipped      = $skipped
    }
}

