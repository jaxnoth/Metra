# Generated from the original Metra.psm1 domain split. Edit this file directly.

$script:MetraProjectActivityExcludeDirNames = @(
    '.git', 'node_modules', 'bin', 'obj', 'dist', 'out', '.venv', 'venv',
    '__pycache__', 'packages', 'vendor', '.turbo', '.next', 'coverage'
)

function ConvertFrom-MetraCommandLine {
    <#
    .SYNOPSIS
        Splits a simple command line into executable + arguments (no Invoke-Expression).
    .DESCRIPTION
        Supports whitespace-separated tokens and double/single-quoted segments.
        Rejects shell metacharacters that would require a shell ($ `|;&<>).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CommandLine
    )

    $raw = $CommandLine.Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw 'Command line is empty.'
    }
    if ($raw -match '[\r\n`$|;<>&]') {
        throw 'Command line contains unsupported shell metacharacters. Use -Executable/-ArgumentList or -ScriptBlock instead.'
    }

    $tokens = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new()
    $quote = $null
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $ch = $raw[$i]
        if ($null -ne $quote) {
            if ($ch -eq $quote) {
                $quote = $null
            }
            else {
                [void]$sb.Append($ch)
            }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") {
            $quote = $ch
            continue
        }
        if ([char]::IsWhiteSpace($ch)) {
            if ($sb.Length -gt 0) {
                $tokens.Add($sb.ToString())
                [void]$sb.Clear()
            }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($null -ne $quote) {
        throw 'Command line has an unclosed quote.'
    }
    if ($sb.Length -gt 0) {
        $tokens.Add($sb.ToString())
    }
    if ($tokens.Count -eq 0) {
        throw 'Command line produced no tokens.'
    }

    return [PSCustomObject]@{
        Executable   = $tokens[0]
        ArgumentList = @($tokens | Select-Object -Skip 1)
    }
}

function Test-MetraProjectActivityPathExcluded {
    <#
    .SYNOPSIS
        True when a file path sits under a noisy generated/dependency directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FullName,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FullName)
    if (-not $full.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        -not $full.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $rel = $full.Substring($rootFull.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($rel)) { return $false }
    foreach ($seg in ($rel -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($seg)) { continue }
        foreach ($noise in $script:MetraProjectActivityExcludeDirNames) {
            if ($seg.Equals($noise, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

function Get-MetraOrchestrationProject {
    <#
    .SYNOPSIS
        Returns the live Metra checkout as a destination project (Name=Metra).
    .DESCRIPTION
        Sibling root scans skip the orchestration folder (_meta / _metra / Metra).
        This injects it back as the product destination so routing and the Ops desk
        can treat Metra as a real place to stand.
    #>
    [CmdletBinding()]
    param()

    $path = Get-MetraRoot
    $primaryRoot = @(Get-MetraRoots) | Where-Object { $_.Primary } | Select-Object -First 1
    $rootName = if ($primaryRoot) { [string]$primaryRoot.Name } else { 'work' }

    return [PSCustomObject]@{
        Name          = 'Metra'
        Path          = $path
        IsGit         = [bool](Test-Path -LiteralPath (Join-Path $path '.git'))
        Root          = $rootName
        Primary       = $true
        Shadowed      = $false
        PrimaryRoot   = $rootName
        ShadowedRoot  = $null
        Orchestration = $true
    }
}

function Get-MetraProjects {
    <#
    .SYNOPSIS
        Lists project folders across every configured root.
    .DESCRIPTION
        Roots are scanned in configuration order. When the same folder name appears in more
        than one root, the earlier root wins and the later one is marked Shadowed (surfaced
        only with -IncludeShadowed) so a duplicate never silently replaces the primary copy.
        Always includes Metra (orchestration checkout) as Name=Metra when the filter matches.
        The default unfiltered scan is cached briefly (see Clear-MetraRoutingCache).
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Root,
        [switch]$GitOnly,
        [switch]$IncludeNonGit,
        [switch]$IncludeShadowed
    )

    $canCache = (
        $Filter -eq '*' -and
        (-not $Root -or @($Root).Count -eq 0) -and
        -not $GitOnly -and
        -not $IncludeNonGit -and
        -not $IncludeShadowed
    )
    if (
        $canCache -and
        $null -ne $script:MetraCache.ProjectsDefault -and
        (Test-MetraCacheEntryFresh -CachedUtc $script:MetraCache.ProjectsUtc)
    ) {
        return @($script:MetraCache.ProjectsDefault)
    }

    $cfg = Get-MetraConfig
    $roots = @(Get-MetraRoots -Name $Root)
    $seen = @{}

    $items = foreach ($projectRoot in $roots) {
        Get-ChildItem -LiteralPath $projectRoot.Path -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-ExcludedProjectName -Name $_.Name -Config $cfg -Root $projectRoot) -and
                ($_.Name -like $Filter)
            } |
            ForEach-Object {
                $isGit = Test-Path -LiteralPath (Join-Path $_.FullName '.git')
                if ($GitOnly -and -not $isGit) { return }

                $key = $_.Name.ToLowerInvariant()
                $shadowed = $seen.ContainsKey($key)
                if (-not $shadowed) { $seen[$key] = $projectRoot.Name }
                if ($shadowed -and -not $IncludeShadowed) {
                    Write-Verbose ("Shadowed duplicate ignored: {0} in root '{1}' (already provided by '{2}')" -f $_.Name, $projectRoot.Name, $seen[$key])
                    return
                }

                [PSCustomObject]@{
                    Name          = $_.Name
                    Path          = $_.FullName
                    IsGit         = $isGit
                    Root          = $projectRoot.Name
                    Primary       = $projectRoot.Primary
                    Shadowed      = $shadowed
                    PrimaryRoot   = $(if ($shadowed) { [string]$seen[$key] } else { $projectRoot.Name })
                    ShadowedRoot  = $(if ($shadowed) { $projectRoot.Name } else { $null })
                }
            }
    }

    $list = @($items)
    $home = Get-MetraOrchestrationProject
    if ($home.Name -like $Filter) {
        if (-not ($GitOnly -and -not $home.IsGit)) {
            $list = @($home) + @($list | Where-Object { $_.Name -ne 'Metra' })
        }
    }

    $list = @($list | Sort-Object Name, Root)
    if ($canCache) {
        $script:MetraCache.ProjectsDefault = $list
        $script:MetraCache.ProjectsUtc = [datetime]::UtcNow
    }
    return $list
}

function Resolve-MetraProjectSet {
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$GitOnly
    )

    $projects = Get-MetraProjects -Filter $Filter -Root $Root -GitOnly:$GitOnly
    if ($Name -and $Name.Count -gt 0) {
        $wanted = $Name | ForEach-Object { $_.ToLowerInvariant() }
        $projects = $projects | Where-Object { $wanted -contains $_.Name.ToLowerInvariant() }
    }
    return @($projects)
}

function Invoke-AcrossProjects {
    <#
    .SYNOPSIS
        Runs a script block or external program in each matching project directory.
    .DESCRIPTION
        Prefer -Executable/-ArgumentList (or -ScriptBlock). -Command is accepted for
        simple whitespace-separated lines only and never uses Invoke-Expression.
        Supports -WhatIf / -Confirm (per project).
    #>
    [CmdletBinding(DefaultParameterSetName = 'Executable', SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'Executable', Mandatory)]
        [string]$Executable,

        [Parameter(ParameterSetName = 'Executable')]
        [string[]]$ArgumentList = @(),

        [Parameter(ParameterSetName = 'Command', Mandatory, Position = 0)]
        [string]$Command,

        [Parameter(ParameterSetName = 'Script', Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$GitOnly,
        [switch]$ContinueOnError,
        [switch]$Quiet
    )

    $exe = $null
    $argList = @()
    $targetLabel = 'run command'
    if ($PSCmdlet.ParameterSetName -eq 'Command') {
        $parsed = ConvertFrom-MetraCommandLine -CommandLine $Command
        $exe = [string]$parsed.Executable
        $argList = @($parsed.ArgumentList)
        $targetLabel = "run $Command"
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Executable') {
        $exe = $Executable
        $argList = @($ArgumentList)
        $targetLabel = ("run {0} {1}" -f $exe, ($argList -join ' ')).Trim()
    }
    else {
        $targetLabel = 'invoke script block'
    }

    $projects = Resolve-MetraProjectSet -Filter $Filter -Name $Name -Root $Root -GitOnly:$GitOnly
    if ($projects.Count -eq 0) {
        Write-Warning 'No matching projects.'
        return @()
    }

    $results = foreach ($project in $projects) {
        if (-not $PSCmdlet.ShouldProcess($project.Path, $targetLabel)) {
            continue
        }

        if (-not $Quiet) {
            Write-Host ""
            Write-Host ("==== {0} ====" -f $project.Name) -ForegroundColor Cyan
        }

        Push-Location -LiteralPath $project.Path
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Script') {
                $output = & $ScriptBlock
                $exit = $LASTEXITCODE
                if ($null -eq $exit) { $exit = 0 }
            }
            else {
                $output = & $exe @argList 2>&1
                $exit = $LASTEXITCODE
                if ($null -eq $exit) { $exit = 0 }
            }

            if (-not $Quiet -and $null -ne $output) {
                $output | ForEach-Object { Write-Host $_ }
            }

            [PSCustomObject]@{
                Name     = $project.Name
                Path     = $project.Path
                Root     = $project.Root
                ExitCode = $exit
                Success  = ($exit -eq 0)
                Output   = $output
            }
        }
        catch {
            if (-not $Quiet) {
                Write-Host $_.Exception.Message -ForegroundColor Red
            }
            if (-not $ContinueOnError) { throw }
            [PSCustomObject]@{
                Name     = $project.Name
                Path     = $project.Path
                Root     = $project.Root
                ExitCode = 1
                Success  = $false
                Output   = $_.Exception.Message
            }
        }
        finally {
            Pop-Location
        }
    }

    return $results
}

function Get-MetraStatus {
    <#
    .SYNOPSIS
        Shows git status --short for each git project.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root
    )

    Invoke-AcrossProjects -Executable git -ArgumentList @('status', '-sb') -Filter $Filter -Name $Name -Root $Root -GitOnly -ContinueOnError
}

function Update-MetraProjects {
    <#
    .SYNOPSIS
        Runs git pull --ff-only (or fetch) across git projects.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$FetchOnly
    )

    $gitArgs = if ($FetchOnly) { @('fetch', '--all', '--prune') } else { @('pull', '--ff-only') }
    $invoke = @{
        Executable      = 'git'
        ArgumentList    = $gitArgs
        Filter          = $Filter
        GitOnly         = $true
        ContinueOnError = $true
        WhatIf          = [bool]$WhatIfPreference
    }
    if ($Name) { $invoke.Name = $Name }
    if ($Root) { $invoke.Root = $Root }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $invoke.Confirm = $Confirm }
    Invoke-AcrossProjects @invoke
}

function Copy-AcrossProjects {
    <#
    .SYNOPSIS
        Copies a file into matching projects, preserving relative path under each root.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [string]$RelativePath,
        [string]$Filter = '*',
        [string[]]$Name,
        [string[]]$Root,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw ("Source file not found: {0}" -f $Source)
    }

    $sourcePath = (Resolve-Path -LiteralPath $Source).Path
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        $RelativePath = Split-Path -Leaf $sourcePath
    }
    else {
        if ([System.IO.Path]::IsPathRooted($RelativePath)) {
            throw "RelativePath must be relative, not rooted: $RelativePath"
        }
        if (($RelativePath -split '[\\/]') -contains '..') {
            throw "RelativePath cannot contain '..': $RelativePath"
        }
        if ($RelativePath -match '[\x00-\x1F]') {
            throw 'RelativePath contains invalid control characters.'
        }
    }

    $projects = Resolve-MetraProjectSet -Filter $Filter -Name $Name -Root $Root
    foreach ($project in $projects) {
        $dest = Join-Path $project.Path $RelativePath
        if (-not (Test-MetraPathWithinRoot -Path $dest -Root $project.Path)) {
            throw ("Destination escapes project root '{0}': {1}" -f $project.Name, $dest)
        }
        $destDir = Split-Path -Parent $dest
        if ($PSCmdlet.ShouldProcess($dest, "Copy $sourcePath")) {
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
                [void][System.IO.Directory]::CreateDirectory($destDir)
            }
            Copy-Item -LiteralPath $sourcePath -Destination $dest -Force:$Force
            Write-Host ("Copied -> {0}" -f $dest) -ForegroundColor Green
        }
    }
}

function Get-ProjectLastActivity {
    <#
    .SYNOPSIS
        Estimates last activity for a project folder using directory time, git metadata, and a shallow file scan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$ScanDepth = 2
    )

    $timestamps = [System.Collections.Generic.List[datetime]]::new()
    $item = Get-Item -LiteralPath $Path -Force
    $timestamps.Add($item.LastWriteTime)

    foreach ($rel in @('.git\HEAD', '.git\FETCH_HEAD', '.git\COMMIT_EDITMSG', '.git\logs\HEAD', '.git\index')) {
        $gitPath = Join-Path $Path $rel
        if (Test-Path -LiteralPath $gitPath) {
            $timestamps.Add((Get-Item -LiteralPath $gitPath -Force).LastWriteTime)
        }
    }

    if ($ScanDepth -ge 0) {
        Get-ChildItem -LiteralPath $Path -Recurse -File -Force -Depth $ScanDepth -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-MetraProjectActivityPathExcluded -FullName $_.FullName -ProjectRoot $Path) } |
            ForEach-Object { $timestamps.Add($_.LastWriteTime) }
    }

    return ($timestamps | Measure-Object -Maximum).Maximum
}

function Get-RecentMetraProjects {
    <#
    .SYNOPSIS
        Returns sibling projects with activity within the lookback window (default from config: 6 months).
    #>
    [CmdletBinding()]
    param(
        [int]$Months,
        [int]$ScanDepth,
        [switch]$IncludeAlways
    )

    $cfg = Get-MetraConfig
    $ws = Get-MetraProp -Object $cfg -Name 'workspace'
    if (-not $PSBoundParameters.ContainsKey('Months')) {
        $Months = [int](Get-MetraProp -Object $ws -Name 'months' -Default 6)
    }
    if (-not $PSBoundParameters.ContainsKey('ScanDepth')) {
        $ScanDepth = [int](Get-MetraProp -Object $ws -Name 'scanDepth' -Default 2)
    }

    $cutoff = (Get-Date).AddMonths(-1 * $Months)
    $always = @(Get-MetraProp -Object $ws -Name 'alwaysInclude' -Default @())

    $rootDepths = @{}
    foreach ($r in @(Get-MetraRoots)) {
        $rootDepths[$r.Name] = if ($null -ne $r.ScanDepth) { [int]$r.ScanDepth } else { $ScanDepth }
    }

    # Only the injected Metra home carries Orchestration, so read it StrictMode-safe.
    $projects = Get-MetraProjects |
        Where-Object { -not (Get-MetraProp -Object $_ -Name 'Orchestration' -Default $false) } |
        ForEach-Object {
            $depth = if ($rootDepths.ContainsKey($_.Root)) { $rootDepths[$_.Root] } else { $ScanDepth }
            $last = Get-ProjectLastActivity -Path $_.Path -ScanDepth $depth
            $forced = $always -contains $_.Name
            [PSCustomObject]@{
                Name         = $_.Name
                Path         = $_.Path
                Root         = $_.Root
                IsGit        = $_.IsGit
                LastActivity = $last
                Recent       = ($last -ge $cutoff) -or $forced
                Always       = $forced
                Cutoff       = $cutoff
            }
        }

    if ($IncludeAlways) {
        return @($projects | Sort-Object LastActivity -Descending)
    }
    return @($projects | Where-Object Recent | Sort-Object Name)
}
