# Loom ship cycle: shared desk (bite) + queue path for branch work and protected merge.
# Invoke-LoomShip is the only protected-branch mutation authority.

function Get-LoomShipStateRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)
    $safe = ($Project -replace '[^\w\.-]', '_').Trim('.').Trim()
    if ([string]::IsNullOrWhiteSpace($safe) -or $safe -eq '.' -or $safe -eq '..') { $safe = 'default' }
    $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Metra\loom\ship'
    $path = Join-Path $root $safe
    $full = [System.IO.Path]::GetFullPath($path)
    if (-not (Test-LoomPathWithinRoot -Path $full -Root $root)) {
        throw ("Ship state path escaped root for project '{0}'." -f $Project)
    }
    return $full
}

function Get-LoomShipStatePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)
    return Join-Path (Get-LoomShipStateRoot -Project $Project) 'state.json'
}

function Get-LoomShipLockPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)
    return Join-Path (Get-LoomShipStateRoot -Project $Project) 'ship.lock.json'
}

function New-LoomShipStateObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$WorkBranch,
        [Parameter(Mandatory)][string]$TargetBranch,
        [string]$BaseSha = '',
        [string]$HeadSha = '',
        [string]$ContentHash = '',
        [string]$BiteId = '',
        [string[]]$Repos = @('root'),
        [string]$PrimaryRepoKey = 'root',
        [object[]]$RepoStates = @(),
        [string]$ShipPhase = 'active'
    )
    return [PSCustomObject]@{
        schemaVersion    = 2
        project          = $Project
        biteId           = $BiteId
        workBranch       = $WorkBranch
        # Legacy compatibility slice: always the root repo when present (N1).
        primaryRepoKey   = $PrimaryRepoKey
        targetBranch     = $TargetBranch
        baseSha          = $BaseSha
        headSha          = $HeadSha
        contentHash      = $ContentHash
        repos            = @($Repos)
        repoStates       = @($RepoStates)
        shipPhase        = $ShipPhase
        packIdentity     = $null
        reviewVerdict    = $null
        reviewProvenance = $null
        reviewedAtUtc    = $null
        updatedAtUtc     = [datetime]::UtcNow.ToString('o')
    }
}

function Save-LoomShipState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State
    )
    $project = [string](Get-LoomProp -Object $State -Name 'project' -Default '')
    if ([string]::IsNullOrWhiteSpace($project)) { throw 'Ship state missing project.' }
    $dir = Get-LoomShipStateRoot -Project $project
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $State.updatedAtUtc = [datetime]::UtcNow.ToString('o')
    $path = Get-LoomShipStatePath -Project $project
    $json = $State | ConvertTo-Json -Depth 8
    Write-LoomAtomicUtf8Text -Path $path -Text $json
    return $path
}

function Get-LoomShipState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)
    $path = Get-LoomShipStatePath -Project $Project
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw ("Failed to read ship state for ${Project}: {0}" -f $_.Exception.Message)
    }
}

function Get-LoomShipProjectPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RegistryName)

    $empty = [PSCustomObject]@{
        protectedBranches = @()
        ownerAffirmPaths  = @()
        biteRepos         = @('root')
        biteRepoTargets   = @{}
        resolved          = $true
    }
    $cmd = Get-Command Get-MetraProjectRegistry -ErrorAction SilentlyContinue
    if (-not $cmd) {
        try {
            $hostRoot = $null
            if (Get-Command Get-LoomHostRoot -ErrorAction SilentlyContinue) {
                $hostRoot = Get-LoomHostRoot
            }
            if (-not [string]::IsNullOrWhiteSpace($hostRoot)) {
                $psd1 = Join-Path $hostRoot 'scripts\Metra.psd1'
                if (Test-Path -LiteralPath $psd1) {
                    Import-Module $psd1 -Force -ErrorAction Stop
                    $cmd = Get-Command Get-MetraProjectRegistry -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            $cmd = $null
        }
    }
    if (-not $cmd) { return $null }
    try {
        $registry = & $cmd
    }
    catch {
        return $null
    }
    $entry = $null
    foreach ($project in @($(Get-LoomProp -Object $registry -Name 'projects' -Default @()))) {
        $name = [string](Get-LoomProp -Object $project -Name 'name' -Default '')
        if ([string]::Equals($name, $RegistryName, [StringComparison]::OrdinalIgnoreCase)) {
            $entry = $project
            break
        }
    }
    if (-not $entry) { return $empty }
    $protected = @()
    foreach ($b in @(Get-LoomProp -Object $entry -Name 'protectedBranches' -Default @())) {
        $t = [string]$b
        if (-not [string]::IsNullOrWhiteSpace($t)) { $protected += $t.Trim() }
    }
    $ownerPaths = @()
    foreach ($p in @(Get-LoomProp -Object $entry -Name 'ownerAffirmPaths' -Default @())) {
        $t = [string]$p
        if (-not [string]::IsNullOrWhiteSpace($t)) { $ownerPaths += ($t.Trim() -replace '\\', '/') }
    }
    $repos = @()
    foreach ($r in @(Get-LoomProp -Object $entry -Name 'biteRepos' -Default @('root'))) {
        $t = [string]$r
        if (-not [string]::IsNullOrWhiteSpace($t)) { $repos += $t.Trim() }
    }
    if ($repos.Count -eq 0) { $repos = @('root') }
    $targets = @{}
    $rawTargets = Get-LoomProp -Object $entry -Name 'biteRepoTargets' -Default $null
    if ($null -ne $rawTargets) {
        if ($rawTargets -is [hashtable]) {
            foreach ($k in @($rawTargets.Keys)) {
                $tv = [string]$rawTargets[$k]
                if (-not [string]::IsNullOrWhiteSpace($tv)) { $targets[[string]$k] = $tv.Trim() }
            }
        }
        else {
            foreach ($p in @($rawTargets.PSObject.Properties)) {
                $tv = [string]$p.Value
                if (-not [string]::IsNullOrWhiteSpace($tv)) { $targets[[string]$p.Name] = $tv.Trim() }
            }
        }
    }
    return [PSCustomObject]@{
        protectedBranches = @($protected)
        ownerAffirmPaths  = @($ownerPaths)
        biteRepos         = @($repos)
        biteRepoTargets   = $targets
        resolved          = $true
    }
}

function Resolve-LoomShipRepoTarget {
    <#
    .SYNOPSIS
        Landing branch for one biteRepos key. biteRepoTargets is authoritative;
        protectedBranches is hook deny-list only and does not select a target (N4).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        $Policy,
        [string]$OverrideTarget
    )
    if (-not [string]::IsNullOrWhiteSpace($OverrideTarget)) { return $OverrideTarget.Trim() }
    $map = @{}
    if ($null -ne $Policy) {
        $raw = Get-LoomProp -Object $Policy -Name 'biteRepoTargets' -Default @{}
        if ($raw -is [hashtable]) { $map = $raw }
        elseif ($null -ne $raw) {
            foreach ($p in @($raw.PSObject.Properties)) { $map[[string]$p.Name] = [string]$p.Value }
        }
    }
    if ($map.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$map[$Key])) {
        return [string]$map[$Key].Trim()
    }
    $protected = @()
    if ($null -eq $Policy) {
        if ($Key -eq 'root') { return 'main' }
        throw ("biteRepoTargets missing for repo '{0}'. Set biteRepoTargets.{0}." -f $Key)
    }
    $protected = @(Get-LoomProp -Object $Policy -Name 'protectedBranches' -Default @())
    # Root may fall back to a single protected branch, or main when unprotected (tests / desk default).
    if ($Key -eq 'root') {
        if (@($protected).Count -eq 1) { return [string]$protected[0] }
        if (@($protected) -contains 'main') { return 'main' }
        if (@($protected).Count -gt 0) { return [string]$protected[0] }
        return 'main'
    }
    # Nested repos require an explicit biteRepoTargets entry (N1/N4: protectedBranches does not select).
    throw ("biteRepoTargets missing for repo '{0}'. Set biteRepoTargets.{0} (protectedBranches is hook deny-list only)." -f $Key)
}

function Resolve-LoomShipProjectRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return [System.IO.Path]::GetFullPath($ProjectRoot)
    }
    $hostRoot = Get-LoomHostRoot
    if ([string]::Equals($Name, 'Metra', [StringComparison]::OrdinalIgnoreCase)) {
        return $hostRoot
    }
    $parent = Split-Path -Parent $hostRoot
    $candidate = Join-Path $parent $Name
    if (Test-Path -LiteralPath $candidate) {
        return [System.IO.Path]::GetFullPath($candidate)
    }
    throw "Cannot resolve project root for '$Name'. Pass -ProjectRoot."
}

function Resolve-LoomShipRepoRoots {
    <#
    .SYNOPSIS
        Resolve biteRepos to canonical git worktrees (N3). Requires root (N1).
        Order: cookbook, chef, other nested (alpha), then root last (ship order).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string[]]$Repos = @('root')
    )
    $projectFull = [System.IO.Path]::GetFullPath($ProjectRoot.TrimEnd('\', '/'))
    $keys = @()
    foreach ($repo in @($Repos)) {
        $key = [string]$repo
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $keys += $key.Trim()
    }
    if ($keys.Count -eq 0) { $keys = @('root') }
    if ($keys -notcontains 'root') {
        throw "biteRepos must include 'root' (legacy compatibility slice). Rootless composite bites are not supported yet."
    }

    $seenKeys = @{}
    $seenTops = @{}
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($key in $keys) {
        if ($seenKeys.ContainsKey($key)) {
            throw "Duplicate biteRepos key '$key'."
        }
        $seenKeys[$key] = $true

        $path = if ($key -eq 'root') {
            $projectFull
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $projectFull $key).TrimEnd('\', '/'))
        }
        if (-not (Test-LoomPathWithinRoot -Path $path -Root $projectFull)) {
            throw ("biteRepos '{0}' resolves outside project root: {1}" -f $key, $path)
        }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw ("biteRepos path missing for '{0}': {1}" -f $key, $path)
        }
        $gitMarker = Join-Path $path '.git'
        if (-not (Test-Path -LiteralPath $gitMarker)) {
            throw ("biteRepos '{0}' is not a git worktree: {1}" -f $key, $path)
        }

        $topParse = Invoke-LoomGit -ProjectRoot $path -GitArgs @('rev-parse', '--show-toplevel')
        if ($topParse.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$topParse.Stdout)) {
            throw ("biteRepos '{0}' git rev-parse --show-toplevel failed: {1}" -f $key, (Get-LoomGitErrorDetail $topParse))
        }
        $top = [System.IO.Path]::GetFullPath(([string]$topParse.Stdout).Trim().TrimEnd('\', '/'))
        $topKey = $top.ToLowerInvariant()
        if ($seenTops.ContainsKey($topKey)) {
            throw ("biteRepos '{0}' and '{1}' resolve to the same git top-level '{2}'." -f $seenTops[$topKey], $key, $top)
        }
        $seenTops[$topKey] = $key

        $rel = if ($key -eq 'root') {
            '.'
        }
        else {
            $prefix = $projectFull.TrimEnd('\', '/')
            if ($path.StartsWith($prefix + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
                $path.StartsWith($prefix + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                ($path.Substring($prefix.Length).TrimStart('\', '/') -replace '\\', '/')
            }
            else {
                ($key -replace '\\', '/')
            }
        }

        $order = switch ($key.ToLowerInvariant()) {
            'cookbook' { 10 }
            'chef' { 20 }
            'root' { 100 }
            default { 50 }
        }
        [void]$list.Add([PSCustomObject]@{
                Key          = $key
                Path         = $path
                RelativePath = $rel
                GitTopLevel  = $top
                Order        = $order
            })
    }
    return @($list | Sort-Object Order, Key)
}

function New-LoomShipRepoStateObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$TargetBranch,
        [string]$WorkBranch = '',
        [string]$TargetTipSha = '',
        [string]$BaseSha = '',
        [string]$HeadSha = '',
        [string]$RangeHash = '',
        [string]$MergeCommitSha = '',
        [string]$PushStatus = 'pending'
    )
    return [PSCustomObject]@{
        key            = $Key
        relativePath   = $RelativePath
        targetBranch   = $TargetBranch
        workBranch     = $WorkBranch
        targetTipSha   = $TargetTipSha
        baseSha        = $BaseSha
        headSha        = $HeadSha
        rangeHash      = $RangeHash
        mergeCommitSha = $MergeCommitSha
        pushStatus     = $PushStatus
    }
}

function Get-LoomShipWorkBranchName {
    <#
    .SYNOPSIS
        Work / remote backup branch for a bite repo key.
        Multi-repo (shared remotes like CDM root+chef): bite/<slug>/<id>/<repoKey>.
        Root-only: bite/<slug>/<id> (legacy compatibility).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectSlug,
        [Parameter(Mandatory)][string]$BiteId,
        [Parameter(Mandatory)][string]$RepoKey,
        [bool]$MultiRepo = $false
    )
    $slug = $ProjectSlug.Trim().Trim('-')
    $id = $BiteId.Trim().Trim('-')
    $key = ($RepoKey.Trim() -replace '[^\w\.-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($key)) { $key = 'root' }
    if ($MultiRepo) {
        return ('bite/{0}/{1}/{2}' -f $slug, $id, $key).Replace('\', '/')
    }
    return ('bite/{0}/{1}' -f $slug, $id).Replace('\', '/')
}

function Get-LoomShipRepoWorkBranch {
    <#
    .SYNOPSIS
        Resolve the work branch for one repo from ship state (per-repo, else legacy state.workBranch).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$RepoKey
    )
    $legacy = [string](Get-LoomProp -Object $State -Name 'workBranch' -Default '')
    foreach ($rs in @($(Get-LoomProp -Object $State -Name 'repoStates' -Default @()))) {
        $key = [string](Get-LoomProp -Object $rs -Name 'key' -Default '')
        if (-not [string]::Equals($key, $RepoKey, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $wb = [string](Get-LoomProp -Object $rs -Name 'workBranch' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($wb)) { return $wb }
        break
    }
    return $legacy
}

function Get-LoomShipRangeHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BaseSha,
        [Parameter(Mandatory)][string]$HeadSha
    )
    $diff = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('diff', '--binary', "$BaseSha...$HeadSha")
    if ($diff.ExitCode -ne 0) {
        throw ("range hash diff failed: {0}" -f (Get-LoomGitErrorDetail $diff))
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$diff.Stdout)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-LoomShipCompositeContentHash {
    <#
    .SYNOPSIS
        Bind composite identity in declared ship order (cookbook -> chef -> other -> root).
        Callers must pass RepoStates already ordered by Resolve-LoomShipRepoRoots (N1).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$RepoStates)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($rs in @($RepoStates)) {
        $parts.Add(('{0}|{1}|{2}|{3}|{4}|{5}' -f
                [string](Get-LoomProp -Object $rs -Name 'key' -Default ''),
                [string](Get-LoomProp -Object $rs -Name 'relativePath' -Default ''),
                [string](Get-LoomProp -Object $rs -Name 'targetBranch' -Default ''),
                [string](Get-LoomProp -Object $rs -Name 'baseSha' -Default ''),
                [string](Get-LoomProp -Object $rs -Name 'headSha' -Default ''),
                [string](Get-LoomProp -Object $rs -Name 'rangeHash' -Default '')))
    }
    $payload = ($parts -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Format-LoomShipRepoReviewSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$RepoState,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [int]$MaxDiffChars = 400000
    )
    $key = [string](Get-LoomProp -Object $RepoState -Name 'key' -Default '')
    $base = [string](Get-LoomProp -Object $RepoState -Name 'baseSha' -Default '')
    $head = [string](Get-LoomProp -Object $RepoState -Name 'headSha' -Default '')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('## Repository: {0}' -f $key))
    [void]$sb.AppendLine(('Target: {0}' -f [string](Get-LoomProp -Object $RepoState -Name 'targetBranch' -Default '')))
    [void]$sb.AppendLine(('WorkBranch: {0}' -f [string](Get-LoomProp -Object $RepoState -Name 'workBranch' -Default '')))
    [void]$sb.AppendLine(('RelativePath: {0}' -f [string](Get-LoomProp -Object $RepoState -Name 'relativePath' -Default '')))
    [void]$sb.AppendLine(('Base: {0}' -f $base))
    [void]$sb.AppendLine(('Head: {0}' -f $head))
    [void]$sb.AppendLine(('Target tip (pack-time): {0}' -f [string](Get-LoomProp -Object $RepoState -Name 'targetTipSha' -Default '')))
    [void]$sb.AppendLine(('Range hash: {0}' -f [string](Get-LoomProp -Object $RepoState -Name 'rangeHash' -Default '')))
    $nameStatus = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('diff', '--name-status', "$base...$head")
    if ($nameStatus.ExitCode -ne 0) {
        throw ("git diff --name-status failed for {0}...{1}: {2}" -f $base, $head, (Get-LoomGitErrorDetail $nameStatus))
    }
    [void]$sb.AppendLine('Changed paths:')
    if ([string]::IsNullOrWhiteSpace([string]$nameStatus.Stdout)) {
        [void]$sb.AppendLine('(none)')
    }
    else {
        [void]$sb.AppendLine(([string]$nameStatus.Stdout).TrimEnd())
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Diff: git diff --binary {0}...{1}' -f $base, $head))
    [void]$sb.AppendLine('```diff')
    $diff = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('diff', '--binary', "$base...$head")
    if ($diff.ExitCode -ne 0) {
        throw ("git diff --binary failed for {0}...{1}: {2}" -f $base, $head, (Get-LoomGitErrorDetail $diff))
    }
    $diffRaw = [string]$diff.Stdout
    if ([string]::IsNullOrWhiteSpace($diffRaw)) {
        [void]$sb.AppendLine('(empty range)')
    }
    elseif ($diffRaw.Length -le $MaxDiffChars) {
        [void]$sb.AppendLine($diffRaw.TrimEnd())
    }
    else {
        [void]$sb.AppendLine($diffRaw.Substring(0, $MaxDiffChars).TrimEnd())
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine(('... truncated ({0} chars total; range hash binds full binary diff)' -f $diffRaw.Length))
    }
    [void]$sb.AppendLine('```')
    return $sb.ToString()
}

function Get-LoomShipRepoStatesFromDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string[]]$Repos,
        [Parameter(Mandatory)]$Policy,
        [string]$OverrideRootTarget,
        [string]$WorkBranch,
        [hashtable]$WorkBranchByKey = @{}
    )
    $resolved = @(Resolve-LoomShipRepoRoots -ProjectRoot $ProjectRoot -Repos $Repos)
    $states = @()
    foreach ($meta in $resolved) {
        $override = if ($meta.Key -eq 'root') { $OverrideRootTarget } else { '' }
        $target = Resolve-LoomShipRepoTarget -Key $meta.Key -Policy $Policy -OverrideTarget $override
        if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $meta.Path)) {
            throw ("Dirty worktree blocks ship snapshot ({0}): {1}" -f $meta.Key, $meta.Path)
        }
        $expectedWork = ''
        if ($WorkBranchByKey -and $WorkBranchByKey.ContainsKey($meta.Key) -and
            -not [string]::IsNullOrWhiteSpace([string]$WorkBranchByKey[$meta.Key])) {
            $expectedWork = [string]$WorkBranchByKey[$meta.Key]
        }
        elseif (-not [string]::IsNullOrWhiteSpace($WorkBranch)) {
            $expectedWork = $WorkBranch
        }
        if (-not [string]::IsNullOrWhiteSpace($expectedWork)) {
            $cur = Get-LoomGitCurrentBranchName -ProjectRoot $meta.Path
            if ($cur -ne $expectedWork) {
                throw ("Wrong branch in {0}: current={1}; expected={2}" -f $meta.Key, $cur, $expectedWork)
            }
        }
        $head = Get-LoomGitRevParse -ProjectRoot $meta.Path -Rev 'HEAD'
        $tipParse = Invoke-LoomGit -ProjectRoot $meta.Path -GitArgs @('rev-parse', $target)
        if ($tipParse.ExitCode -ne 0) {
            throw ("Target branch '{0}' missing in repo '{1}'. Fetch or create it before pack/ship." -f $target, $meta.Key)
        }
        $tip = [string]$tipParse.Stdout.Trim()
        $base = Get-LoomShipMergeBaseSha -ProjectRoot $meta.Path -TargetBranch $target `
            -WorkBranch $(if ($expectedWork) { $expectedWork } else { 'HEAD' })
        $rangeHash = Get-LoomShipRangeHash -ProjectRoot $meta.Path -BaseSha $base -HeadSha $head
        $priorPush = 'pending'
        $states += (New-LoomShipRepoStateObject -Key $meta.Key -RelativePath $meta.RelativePath -TargetBranch $target `
                -WorkBranch $expectedWork -TargetTipSha $tip -BaseSha $base -HeadSha $head -RangeHash $rangeHash `
                -PushStatus $priorPush)
    }
    return @($states)
}

function Write-LoomShipMultiRepoReviewPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][object[]]$RepoStates,
        [Parameter(Mandatory)][hashtable]$RepoPathsByKey,
        [Parameter(Mandatory)][string]$CompositeHash
    )
    $dir = Get-LoomShipStateRoot -Project $Project
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $path = Join-Path $dir 'pack-multirepo.md'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Composite bite pack (multi-repository)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine(('Composite contentHash: `{0}`' -f $CompositeHash))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Invariant: every repository that contributes code has a Base-to-HEAD diff below (B1).')
    [void]$sb.AppendLine('Sections appear in declared ship order (cookbook -> chef -> other -> root).')
    [void]$sb.AppendLine('protectedBranches is a hook deny-list only; biteRepoTargets selects landing branches (N4).')
    foreach ($rs in @($RepoStates)) {
        $key = [string](Get-LoomProp -Object $rs -Name 'key' -Default '')
        if (-not $RepoPathsByKey.ContainsKey($key)) {
            throw ("Missing path for repo key '{0}' while writing multi-repo pack." -f $key)
        }
        [void]$sb.Append((Format-LoomShipRepoReviewSection -RepoState $rs -ProjectRoot ([string]$RepoPathsByKey[$key])))
    }
    Write-LoomAtomicUtf8Text -Path $path -Text $sb.ToString()
    return $path
}

function Publish-LoomShipBingEvidencePack {
    <#
    .SYNOPSIS
        Bind composite multi-repo review body into the Inspect/Bing contract pack (B1).
        contentHash in handoff/manifest/pack header is the ship composite identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$CompositeHash,
        [Parameter(Mandatory)][string]$CompositeBodyPath,
        [string]$InspectPackPath,
        [string]$InspectHash,
        [bool]$InspectReadyForBing = $false,
        [bool]$MultiRepo = $false
    )

    if (-not (Test-Path -LiteralPath $CompositeBodyPath -PathType Leaf)) {
        throw ("Composite review body missing: {0}" -f $CompositeBodyPath)
    }
    $compositeBody = Get-Content -LiteralPath $CompositeBodyPath -Raw -Encoding UTF8
    $fileHits = [regex]::Matches([string]$compositeBody, '(?m)^[AMDCRT]\t(.+)$')
    $fileList = @(
        foreach ($hit in $fileHits) {
            $p = [string]$hit.Groups[1].Value.Trim()
            if (-not [string]::IsNullOrWhiteSpace($p)) { $p }
        }
    ) | Select-Object -Unique
    $filesHeader = if (@($fileList).Count -eq 0) { '(none)' } else { (@($fileList) -join ', ') }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Metra Inspect pack (Bing comparison lane)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Mode: diff')
    [void]$sb.AppendLine('Ship identity: composite-Base...HEAD')
    [void]$sb.AppendLine(('Project: {0}' -f $Project))
    [void]$sb.AppendLine(('contentHash: {0}' -f $CompositeHash))
    [void]$sb.AppendLine(('PackedAtUtc: {0}' -f [datetime]::UtcNow.ToString('o')))
    [void]$sb.AppendLine(('Files: {0}' -f $filesHeader))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Ship evidence (authoritative)')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Bing must review every Repository section below. The imported machine verdict binds to contentHash above (composite of those Base-to-HEAD slices).')
    [void]$sb.AppendLine('Inspect quality findings (if present later) are not the ship identity.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($compositeBody.TrimEnd())

    if (-not [string]::IsNullOrWhiteSpace($InspectPackPath) -and (Test-Path -LiteralPath $InspectPackPath -PathType Leaf)) {
        $inspectRaw = Get-Content -LiteralPath $InspectPackPath -Raw -Encoding UTF8
        # Drop any prior composite section if Inspect wrote first and we re-read a mutated file.
        $marker = '## Ship evidence (authoritative)'
        $idx = $inspectRaw.IndexOf($marker)
        if ($idx -ge 0) {
            $inspectRaw = if ($idx -gt 0) { $inspectRaw.Substring(0, $idx).TrimEnd() } else { '' }
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Appendix: Inspect quality gate (root worktree)')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Not the ship contentHash. Root-only Inspect prepare for finding severity; ship approval uses the composite identity above.')
        if (-not [string]::IsNullOrWhiteSpace($InspectHash)) {
            [void]$sb.AppendLine(('Inspect inputHash (informational): `{0}`' -f $InspectHash))
        }
        [void]$sb.AppendLine(('Inspect readyForBing (quality): {0}' -f $InspectReadyForBing))
        [void]$sb.AppendLine('')
        $maxAppendix = 120000
        if ($inspectRaw.Length -le $maxAppendix) {
            [void]$sb.AppendLine($inspectRaw.TrimEnd())
        }
        else {
            [void]$sb.AppendLine($inspectRaw.Substring(0, $maxAppendix).TrimEnd())
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine(('... truncated Inspect appendix ({0} chars total)' -f $inspectRaw.Length))
        }
    }
    elseif ($MultiRepo) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('---')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Appendix: Inspect quality gate')
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('(not run or no packPath; composite ship evidence above remains authoritative)')
    }

    $packText = $sb.ToString()
    $publishCmd = Get-Command Publish-MetraInspectBingPackFromText -ErrorAction SilentlyContinue
    if (-not $publishCmd) {
        # Offline / tests without Metra Inspect exports: keep composite body as the only pack path.
        return [PSCustomObject]@{
            ok           = $true
            published    = $false
            packPath     = $CompositeBodyPath
            contentHash  = $CompositeHash
            readyForBing = $true
            detail       = 'Publish-MetraInspectBingPackFromText unavailable; composite body is pack path.'
        }
    }

    $published = Publish-MetraInspectBingPackFromText -Name $Project -PackText $packText -ContentHash $CompositeHash -NoClipboard
    $skipped = [bool](Get-LoomProp -Object $published -Name 'Skipped' -Default $false)
    $outPath = [string](Get-LoomProp -Object $published -Name 'Path' -Default $CompositeBodyPath)
    $didPublish = -not $skipped
    return [PSCustomObject]@{
        ok           = $true
        published    = $didPublish
        packPath     = $outPath
        contentHash  = $CompositeHash
        readyForBing = $didPublish
        sharePack    = [string](Get-LoomProp -Object $published -Name 'SharePack' -Default '')
        localHandoff = [string](Get-LoomProp -Object $published -Name 'LocalHandoff' -Default '')
        publish      = $published
    }
}

function Test-LoomWorkBranchName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Branch)
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $false }
    $b = $Branch.Replace('\', '/')
    return ($b -like 'bite/*' -or $b -like 'loom/*' -or $b -like 'autoprogram/*')
}

function Get-LoomGitCurrentBranchName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($r.ExitCode -ne 0) { throw "Failed to read current branch: $(Get-LoomGitErrorDetail $r)" }
    return [string]$r.Stdout.Trim()
}

function Get-LoomGitRevParse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$Rev
    )
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', $Rev)
    if ($r.ExitCode -ne 0) { throw ("rev-parse failed for {0}: {1}" -f $Rev, (Get-LoomGitErrorDetail $r)) }
    return [string]$r.Stdout.Trim()
}

function Get-LoomShipMergeBaseSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$TargetBranch,
        [Parameter(Mandatory)][string]$WorkBranch
    )
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('merge-base', $TargetBranch, $WorkBranch)
    if ($r.ExitCode -ne 0) {
        throw ("merge-base failed for {0}..{1}: {2}" -f $TargetBranch, $WorkBranch, (Get-LoomGitErrorDetail $r))
    }
    return [string]$r.Stdout.Trim()
}

function Test-LoomShipProtectedBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Branch,
        [string[]]$ProtectedBranches
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $false }
    foreach ($p in @($ProtectedBranches)) {
        if ([string]::Equals($Branch, [string]$p, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function New-LoomShipLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)]$ReviewedTuple,
        [string[]]$AuthorizedTargetBranches = @(),
        [string[]]$AuthorizedHeadShas = @()
    )
    $dir = Get-LoomShipStateRoot -Project $Project
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $primaryTarget = [string](Get-LoomProp -Object $ReviewedTuple -Name 'targetBranch' -Default '')
    $targets = @()
    foreach ($t in @($AuthorizedTargetBranches)) {
        if (-not [string]::IsNullOrWhiteSpace($t)) { $targets += $t.Trim() }
    }
    if (-not [string]::IsNullOrWhiteSpace($primaryTarget) -and ($targets -notcontains $primaryTarget)) {
        $targets = @($primaryTarget) + $targets
    }
    $targets = @($targets | Select-Object -Unique)
    $heads = @()
    foreach ($h in @($AuthorizedHeadShas)) {
        if (-not [string]::IsNullOrWhiteSpace($h)) { $heads += $h.Trim() }
    }
    $primaryHead = [string](Get-LoomProp -Object $ReviewedTuple -Name 'headSha' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($primaryHead) -and ($heads -notcontains $primaryHead)) {
        $heads = @($primaryHead) + $heads
    }
    $heads = @($heads | Select-Object -Unique)
    $lock = [PSCustomObject]@{
        schemaVersion             = 2
        project                   = $Project
        pid                       = $PID
        createdAtUtc              = [datetime]::UtcNow.ToString('o')
        expiresAtUtc              = ([datetime]::UtcNow.AddMinutes(15)).ToString('o')
        targetBranch              = $primaryTarget
        authorizedTargetBranches  = $targets
        authorizedHeadShas        = $heads
        workBranch                = [string](Get-LoomProp -Object $ReviewedTuple -Name 'workBranch' -Default '')
        baseSha                   = [string](Get-LoomProp -Object $ReviewedTuple -Name 'baseSha' -Default '')
        headSha                   = $primaryHead
        contentHash               = [string](Get-LoomProp -Object $ReviewedTuple -Name 'contentHash' -Default '')
        token                     = [guid]::NewGuid().ToString('n')
    }
    $path = Get-LoomShipLockPath -Project $Project
    Write-LoomAtomicUtf8Text -Path $path -Text ($lock | ConvertTo-Json -Depth 5)
    $env:METRA_LOOM_SHIP_TOKEN = [string]$lock.token
    $env:METRA_LOOM_SHIP = '1'
    $env:METRA_LOOM_SHIP_PROJECT = $Project
    return $lock
}

function Clear-LoomShipLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Project)
    $path = Get-LoomShipLockPath -Project $Project
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:\METRA_LOOM_SHIP -ErrorAction SilentlyContinue
    Remove-Item Env:\METRA_LOOM_SHIP_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:\METRA_LOOM_SHIP_PROJECT -ErrorAction SilentlyContinue
}

function Test-LoomShipHookBypassAllowed {
    <#
    .SYNOPSIS
        True only when env marker AND a valid short-lived ship.lock match this process.
        Bare METRA_LOOM_SHIP=1 is not authorization.
    #>
    [CmdletBinding()]
    param(
        [string]$Project,
        [string]$RepoRoot,
        [string]$TargetBranch,
        [string]$HeadSha
    )

    if ($env:METRA_LOOM_SHIP -ne '1') { return $false }
    $proj = $Project
    if ([string]::IsNullOrWhiteSpace($proj)) {
        $proj = [string]$env:METRA_LOOM_SHIP_PROJECT
    }
    if ([string]::IsNullOrWhiteSpace($proj) -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $leaf = Split-Path -Leaf $RepoRoot
        if ($leaf) { $proj = $leaf }
    }
    if ([string]::IsNullOrWhiteSpace($proj)) { return $false }

    $path = Get-LoomShipLockPath -Project $proj
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    try {
        $lock = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $false
    }
    # Token + unexpired lock authorize; do not require lock.pid -eq $PID. Git pre-push
    # hooks run in a child process and would fail a strict PID match.
    $token = [string](Get-LoomProp -Object $lock -Name 'token' -Default '')
    if ([string]::IsNullOrWhiteSpace($token) -or $token -ne [string]$env:METRA_LOOM_SHIP_TOKEN) { return $false }
    $expiresRaw = [string](Get-LoomProp -Object $lock -Name 'expiresAtUtc' -Default '')
    if ([string]::IsNullOrWhiteSpace($expiresRaw)) { return $false }
    try {
        $expires = [datetime]::Parse($expiresRaw, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ([datetime]::UtcNow -gt $expires.ToUniversalTime()) { return $false }
    }
    catch {
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetBranch)) {
        $authorized = @()
        foreach ($t in @(Get-LoomProp -Object $lock -Name 'authorizedTargetBranches' -Default @())) {
            if (-not [string]::IsNullOrWhiteSpace([string]$t)) { $authorized += [string]$t.Trim() }
        }
        $lockTarget = [string](Get-LoomProp -Object $lock -Name 'targetBranch' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($lockTarget) -and ($authorized -notcontains $lockTarget)) {
            $authorized += $lockTarget.Trim()
        }
        $match = $false
        foreach ($t in $authorized) {
            if ([string]::Equals($TargetBranch.Trim(), $t, [StringComparison]::OrdinalIgnoreCase)) {
                $match = $true
                break
            }
        }
        if (-not $match -and @($authorized).Count -gt 0) { return $false }
        if (-not $match -and -not [string]::IsNullOrWhiteSpace($lockTarget) -and
            -not [string]::Equals($TargetBranch.Trim(), $lockTarget.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($HeadSha)) {
        $authorizedHeads = @()
        foreach ($h in @(Get-LoomProp -Object $lock -Name 'authorizedHeadShas' -Default @())) {
            if (-not [string]::IsNullOrWhiteSpace([string]$h)) { $authorizedHeads += [string]$h.Trim() }
        }
        $lockHead = [string](Get-LoomProp -Object $lock -Name 'headSha' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($lockHead) -and ($authorizedHeads -notcontains $lockHead)) {
            $authorizedHeads += $lockHead.Trim()
        }
        $headMatch = $false
        foreach ($h in $authorizedHeads) {
            if ([string]::Equals($HeadSha.Trim(), $h, [StringComparison]::OrdinalIgnoreCase)) {
                $headMatch = $true
                break
            }
        }
        if (-not $headMatch -and @($authorizedHeads).Count -gt 0) { return $false }
        if (-not $headMatch -and -not [string]::IsNullOrWhiteSpace($lockHead) -and
            -not [string]::Equals($HeadSha.Trim(), $lockHead.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Get-LoomShipOwnerAffirmHits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BaseSha,
        [Parameter(Mandatory)][string]$HeadSha,
        [string[]]$OwnerAffirmPaths,
        [string]$PathPrefix = ''
    )
    if (-not $OwnerAffirmPaths -or @($OwnerAffirmPaths).Count -eq 0) { return @() }
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('diff', '--name-only', "$BaseSha...$HeadSha")
    if ($r.ExitCode -ne 0) { throw ("diff name-only failed: {0}" -f (Get-LoomGitErrorDetail $r)) }
    $prefix = ($PathPrefix -replace '\\', '/').Trim().Trim('.')
    if ($prefix -eq '/' -or $prefix -eq '\') { $prefix = '' }
    $changed = @($r.Stdout -split '[\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            $rel = ($_ -replace '\\', '/').Trim()
            if ([string]::IsNullOrWhiteSpace($prefix) -or $prefix -eq '.') { $rel }
            else { ('{0}/{1}' -f $prefix.TrimEnd('/'), $rel.TrimStart('/')) }
        })
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($path in $changed) {
        foreach ($pat in @($OwnerAffirmPaths)) {
            $norm = ($pat -replace '\\', '/').Trim()
            if ([string]::IsNullOrWhiteSpace($norm)) { continue }
            if ($path -like $norm -or $path.StartsWith($norm.TrimEnd('/') + '/') -or $path -eq $norm.TrimEnd('/')) {
                [void]$hits.Add($path)
                break
            }
        }
    }
    return @($hits | Select-Object -Unique)
}

function Start-LoomShipBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Bite,
        [string]$ProjectRoot,
        [string[]]$Repos,
        [string]$TargetBranch,
        [switch]$NoPush
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    $policy = Get-LoomShipProjectPolicy -RegistryName $Name
    if ($null -eq $policy) {
        $policy = [PSCustomObject]@{
            protectedBranches = @()
            ownerAffirmPaths  = @()
            biteRepos         = @('root')
            biteRepoTargets   = @{}
            resolved          = $false
        }
    }
    if (-not $Repos -or @($Repos).Count -eq 0) { $Repos = @($policy.biteRepos) }
    if (@($Repos) -notcontains 'root') {
        throw "biteRepos must include 'root'."
    }

    $slug = ($Name.ToLowerInvariant() -replace '[^\w]+', '-').Trim('-')
    $biteId = ($Bite.Trim() -replace '[^\w\.-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($biteId)) { throw '-Bite is required.' }

    $repoRoots = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos $Repos)
    $multiRepo = (@($repoRoots).Count -gt 1)
    $primaryWork = Get-LoomShipWorkBranchName -ProjectSlug $slug -BiteId $biteId -RepoKey 'root' -MultiRepo:$multiRepo
    $repoStates = @()
    foreach ($repo in $repoRoots) {
        $branch = Get-LoomShipWorkBranchName -ProjectSlug $slug -BiteId $biteId -RepoKey $repo.Key -MultiRepo:$multiRepo
        $repoTarget = Resolve-LoomShipRepoTarget -Key $repo.Key -Policy $policy -OverrideTarget $(
            if ($repo.Key -eq 'root') { $TargetBranch } else { '' }
        )
        if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $repo.Path)) {
            throw ("Dirty worktree blocks bite start ({0}): {1}" -f $repo.Key, $repo.Path)
        }
        $cur = Get-LoomGitCurrentBranchName -ProjectRoot $repo.Path
        if ($cur -ne $repoTarget) {
            $co = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('checkout', $repoTarget)
            if ($co.ExitCode -ne 0) {
                throw ("checkout {0} failed in {1}: {2}" -f $repoTarget, $repo.Key, (Get-LoomGitErrorDetail $co))
            }
        }
        $existing = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('rev-parse', '--verify', $branch)
        if ($existing.ExitCode -eq 0) {
            $sw = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('checkout', $branch)
            if ($sw.ExitCode -ne 0) { throw ("checkout existing {0} failed: {1}" -f $branch, (Get-LoomGitErrorDetail $sw)) }
        }
        else {
            $null = Invoke-LoomGitCreateItemBranch -ProjectRoot $repo.Path -BranchName $branch
        }
        if (-not $NoPush) {
            $push = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('push', '-u', 'origin', $branch)
            if ($push.ExitCode -ne 0) {
                Write-Warning ("bite start: push failed for {0} ({1}). Branch exists locally." -f $repo.Key, (Get-LoomGitErrorDetail $push))
            }
        }
        $tip = Get-LoomGitRevParse -ProjectRoot $repo.Path -Rev $repoTarget
        $base = Get-LoomShipMergeBaseSha -ProjectRoot $repo.Path -TargetBranch $repoTarget -WorkBranch $branch
        $head = Get-LoomGitRevParse -ProjectRoot $repo.Path -Rev 'HEAD'
        $repoStates += (New-LoomShipRepoStateObject -Key $repo.Key -RelativePath $repo.RelativePath -TargetBranch $repoTarget `
                -WorkBranch $branch -TargetTipSha $tip -BaseSha $base -HeadSha $head -PushStatus 'pending')
    }

    $rootState = @($repoStates | Where-Object { $_.key -eq 'root' })[0]
    if (-not $rootState) { throw 'Internal error: root repo state missing after bite start.' }
    $state = New-LoomShipStateObject -Project $Name -WorkBranch $primaryWork -TargetBranch ([string]$rootState.targetBranch) `
        -BaseSha ([string]$rootState.baseSha) -HeadSha ([string]$rootState.headSha) -BiteId $biteId `
        -Repos @($repoRoots | ForEach-Object { $_.Key }) -PrimaryRepoKey 'root' -RepoStates $repoStates -ShipPhase 'active'
    Save-LoomShipState -State $state | Out-Null

    return [PSCustomObject]@{
        ok             = $true
        project        = $Name
        biteId         = $biteId
        workBranch     = $primaryWork
        primaryRepoKey = 'root'
        targetBranch   = [string]$rootState.targetBranch
        baseSha        = [string]$rootState.baseSha
        headSha        = [string]$rootState.headSha
        repos          = @($repoRoots | ForEach-Object { $_.Key })
        repoStates     = $repoStates
        statePath      = (Get-LoomShipStatePath -Project $Name)
    }
}

function Invoke-LoomShipCommit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message,
        [string]$ProjectRoot,
        [switch]$SkipQuickCheck,
        [switch]$NoPush
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    $state = Get-LoomShipState -Project $Name
    if (-not $state) { throw "No ship state for $Name. Run bite start first." }
    $primaryBranch = [string]$state.workBranch
    $cur = Get-LoomGitCurrentBranchName -ProjectRoot $root
    $rootExpected = Get-LoomShipRepoWorkBranch -State $state -RepoKey 'root'
    if ($cur -ne $rootExpected) {
        throw ("Wrong branch for ship commit: current={0}; expected={1}" -f $cur, $rootExpected)
    }
    if (-not (Test-LoomWorkBranchName -Branch $cur)) {
        throw "Ship commit refused on non-work branch: $cur"
    }

    $repos = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos @($(Get-LoomProp -Object $state -Name 'repos' -Default @('root'))))
    $biteId = [string](Get-LoomProp -Object $state -Name 'biteId' -Default 'bite')
    $msg = $Message.Trim()
    if ($msg -notmatch '(?i)^wip\(') {
        $msg = ('wip({0}): {1}' -f $biteId, $msg)
    }

    # Validate all repos before mutating any (no partial multi-repo commits).
    foreach ($repo in $repos) {
        $branch = Get-LoomShipRepoWorkBranch -State $state -RepoKey $repo.Key
        $repoCur = Get-LoomGitCurrentBranchName -ProjectRoot $repo.Path
        if ($repoCur -ne $branch) {
            throw ("Wrong branch for ship commit in {0}: current={1}; expected={2}" -f $repo.Key, $repoCur, $branch)
        }
        if (-not $SkipQuickCheck) {
            $check = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('diff', '--check')
            if ($check.ExitCode -ne 0) {
                throw ("Quick check failed in {0} (git diff --check): {1}" -f $repo.Key, (Get-LoomGitErrorDetail $check))
            }
        }
    }

    $committed = @()
    $any = $false
    foreach ($repo in $repos) {
        $branch = Get-LoomShipRepoWorkBranch -State $state -RepoKey $repo.Key
        $status = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('status', '--porcelain', '-uall')
        if ($status.ExitCode -ne 0) { throw (Get-LoomGitErrorDetail $status) }
        if ([string]::IsNullOrWhiteSpace([string]$status.Stdout)) {
            $committed += [PSCustomObject]@{ key = $repo.Key; skipped = $true; workBranch = $branch }
            continue
        }
        $add = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('add', '-A')
        if ($add.ExitCode -ne 0) { throw ("git add failed in {0}: {1}" -f $repo.Key, (Get-LoomGitErrorDetail $add)) }
        $commit = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('commit', '-m', $msg)
        if ($commit.ExitCode -ne 0) { throw ("git commit failed in {0}: {1}" -f $repo.Key, (Get-LoomGitErrorDetail $commit)) }
        $any = $true
        $repoHead = Get-LoomGitRevParse -ProjectRoot $repo.Path -Rev 'HEAD'
        $committed += [PSCustomObject]@{ key = $repo.Key; skipped = $false; headSha = $repoHead; workBranch = $branch }
        if (-not $NoPush) {
            $push = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('push', '-u', 'origin', $branch)
            if ($push.ExitCode -ne 0) {
                Write-Warning ("ship commit push failed in {0}: {1}" -f $repo.Key, (Get-LoomGitErrorDetail $push))
            }
        }
    }

    if (-not $any) {
        return [PSCustomObject]@{ ok = $true; skipped = $true; reason = 'nothing-to-commit'; branch = $primaryBranch; repos = $committed }
    }

    $head = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'
    $state.headSha = $head
    # New commits invalidate prior review tuple binding for ship.
    $state.contentHash = ''
    $state.reviewVerdict = $null
    $state.reviewProvenance = $null
    $state.reviewedAtUtc = $null
    $state.packIdentity = $null
    if ($null -ne (Get-Member -InputObject $state -Name 'shipPhase' -ErrorAction SilentlyContinue)) {
        $state.shipPhase = 'active'
    }
    else {
        $state | Add-Member -NotePropertyName shipPhase -NotePropertyValue 'active' -Force
    }
    Save-LoomShipState -State $state | Out-Null

    return [PSCustomObject]@{
        ok            = $true
        project       = $Name
        branch        = $primaryBranch
        headSha       = $head
        message       = $msg
        reviewCleared = $true
        repos         = $committed
    }
}

function Get-LoomShipInspectSlotContentHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$BaseSha = '',
        [string]$HeadSha = ''
    )

    $safe = ($Project -replace '[^\w\.-]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    $slotRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Metra\inspect'
    $latest = Join-Path $slotRoot ("{0}\latest.json" -f $safe)
    $latestFull = [System.IO.Path]::GetFullPath($latest)
    if (-not (Test-LoomPathWithinRoot -Path $latestFull -Root $slotRoot)) { return '' }
    if (-not (Test-Path -LiteralPath $latestFull -PathType Leaf)) { return '' }
    try {
        $report = Get-Content -LiteralPath $latestFull -Raw -Encoding UTF8 | ConvertFrom-Json
        $prov = Get-LoomProp -Object $report -Name 'provenance' -Default $null
        $hash = [string](Get-LoomProp -Object $prov -Name 'inputHash' -Default '')
        if ([string]::IsNullOrWhiteSpace($hash) -or $hash -eq 'empty') { return '' }
        $reportBase = [string](Get-LoomProp -Object $prov -Name 'base' -Default '')
        $reportHead = [string](Get-LoomProp -Object $prov -Name 'gitHead' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($BaseSha) -and -not [string]::IsNullOrWhiteSpace($reportBase) -and
            -not [string]::Equals($BaseSha, $reportBase, [StringComparison]::OrdinalIgnoreCase)) {
            return ''
        }
        if (-not [string]::IsNullOrWhiteSpace($HeadSha) -and -not [string]::IsNullOrWhiteSpace($reportHead) -and
            -not [string]::Equals($HeadSha, $reportHead, [StringComparison]::OrdinalIgnoreCase)) {
            return ''
        }
        return $hash
    }
    catch {
        return ''
    }
}

function Invoke-LoomShipPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot,
        [switch]$Reset,
        [switch]$SkipInspectEngine
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $root)) {
        throw 'bite pack refused: working tree is dirty. Commit or stash first.'
    }
    $state = Get-LoomShipState -Project $Name
    if (-not $state) { throw "No ship state for $Name. Run bite start first." }

    $work = Get-LoomShipRepoWorkBranch -State $state -RepoKey 'root'
    $cur = Get-LoomGitCurrentBranchName -ProjectRoot $root
    if ($cur -ne $work) { throw ("Wrong branch for pack: current={0}; expected={1}" -f $cur, $work) }

    $policy = Get-LoomShipProjectPolicy -RegistryName $Name
    if ($null -eq $policy) {
        $policy = [PSCustomObject]@{
            protectedBranches = @()
            ownerAffirmPaths  = @()
            biteRepos         = @('root')
            biteRepoTargets   = @{}
            resolved          = $false
        }
    }
    $repoKeys = @($(Get-LoomProp -Object $state -Name 'repos' -Default @('root')))
    $legacyRootTarget = [string](Get-LoomProp -Object $state -Name 'targetBranch' -Default '')
    $workByKey = @{}
    foreach ($k in $repoKeys) {
        $workByKey[[string]$k] = Get-LoomShipRepoWorkBranch -State $state -RepoKey ([string]$k)
    }
    $repoStates = @(Get-LoomShipRepoStatesFromDisk -ProjectRoot $root -Repos $repoKeys -Policy $policy `
            -OverrideRootTarget $legacyRootTarget -WorkBranchByKey $workByKey)
    $pathsByKey = @{}
    foreach ($meta in @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos $repoKeys)) {
        $pathsByKey[$meta.Key] = $meta.Path
    }

    $rootSlice = @($repoStates | Where-Object { $_.key -eq 'root' })[0]
    if (-not $rootSlice) { throw 'Pack requires a root repository slice.' }
    $baseSha = [string]$rootSlice.baseSha
    $headSha = [string]$rootSlice.headSha
    $target = [string]$rootSlice.targetBranch
    $multiRepo = (@($repoStates).Count -gt 1)

    # Composite hash always binds every participating repo range in ship order (B1/N1).
    $contentHash = Get-LoomShipCompositeContentHash -RepoStates $repoStates
    $multiPackPath = Write-LoomShipMultiRepoReviewPack -Project $Name -RepoStates $repoStates `
        -RepoPathsByKey $pathsByKey -CompositeHash $contentHash

    $prepare = $null
    $inspectHash = $null
    $inspectPack = ''
    $inspectReady = $false

    # Optional root Inspect quality pass (same review loop). Ship identity remains composite.
    $inspectCli = Get-Command Show-MetraInspectCli -ErrorAction SilentlyContinue
    if (-not $SkipInspectEngine -and $inspectCli) {
        $rest = [System.Collections.Generic.List[string]]::new()
        [void]$rest.Add('prepare-bing')
        if ($Reset) { [void]$rest.Add('-Reset') }
        if (-not [string]::IsNullOrWhiteSpace($baseSha)) {
            [void]$rest.Add('-Base')
            [void]$rest.Add($baseSha)
        }
        $cliParams = @{
            Rest = @($rest.ToArray())
            Name = $Name
        }
        if (-not [string]::IsNullOrWhiteSpace($baseSha)) { $cliParams.Base = $baseSha }
        $prepare = Show-MetraInspectCli @cliParams
        $inspectReady = [bool](Get-LoomProp -Object $prepare -Name 'readyForBing' -Default $false)
        $inspectPack = [string](Get-LoomProp -Object $prepare -Name 'packPath' -Default '')
        $skippedNoDiff = [bool](Get-LoomProp -Object $prepare -Name 'skipped' -Default $false) -and
            ([string](Get-LoomProp -Object $prepare -Name 'reason' -Default '') -eq 'no-diff')
        if ($skippedNoDiff) {
            $rangeCheck = Invoke-LoomGit -ProjectRoot $root -GitArgs @('diff', '--name-only', "$baseSha...$headSha")
            if ($rangeCheck.ExitCode -ne 0) { throw (Get-LoomGitErrorDetail $rangeCheck) }
            if (-not [string]::IsNullOrWhiteSpace([string]$rangeCheck.Stdout)) {
                throw ("bite pack: Inspect reported no-diff but {0}...{1} has changes. Re-run pack with Inspect loaded." -f $baseSha.Substring(0, [Math]::Min(8, $baseSha.Length)), $headSha.Substring(0, [Math]::Min(8, $headSha.Length)))
            }
        }
        $inspectHash = Get-LoomShipInspectSlotContentHash -Project $Name -BaseSha $baseSha -HeadSha $headSha
        if ($skippedNoDiff) { $inspectHash = $null }
    }
    elseif (-not $SkipInspectEngine -and -not $inspectCli) {
        Write-Warning 'bite pack: Show-MetraInspectCli not loaded; publishing composite ship evidence only.'
    }

    if ([string]::IsNullOrWhiteSpace($contentHash)) {
        throw 'Ship pack failed to compute contentHash.'
    }

    # B1: publish composite body as the Bing contract pack bound to composite contentHash.
    $bingPublish = Publish-LoomShipBingEvidencePack -Project $Name -CompositeHash $contentHash `
        -CompositeBodyPath $multiPackPath -InspectPackPath $inspectPack -InspectHash $inspectHash `
        -InspectReadyForBing:$inspectReady -MultiRepo:$multiRepo
    $packPath = [string]$bingPublish.packPath
    $readyForBing = [bool]$bingPublish.readyForBing
    if (-not $SkipInspectEngine -and $inspectCli -and -not $inspectReady) {
        # Composite evidence is published; quality gate must still clear before ship-ready.
        $readyForBing = $false
    }

    $state.primaryRepoKey = 'root'
    $state.targetBranch = $target
    $state.baseSha = $baseSha
    $state.headSha = $headSha
    $state.contentHash = $contentHash
    $state.repos = @($repoStates | ForEach-Object { $_.key })
    $state.repoStates = @($repoStates)
    $state.shipPhase = 'active'
    $state.packIdentity = [PSCustomObject]@{
        packPath          = $packPath
        multiRepoPackPath = $multiPackPath
        readyForBing      = $readyForBing
        packedAtUtc       = [datetime]::UtcNow.ToString('o')
        mode              = 'composite-Base...HEAD'
        multiRepo         = $multiRepo
        inspectHash       = $inspectHash
        primaryRepoKey    = 'root'
        bingEvidenceBound = [bool]$bingPublish.published
        shipContentHash   = $contentHash
    }
    # Pack alone does not import review.
    $state.reviewVerdict = $null
    $state.reviewProvenance = $null
    $state.reviewedAtUtc = $null
    Save-LoomShipState -State $state | Out-Null

    return [PSCustomObject]@{
        ok                = $true
        project           = $Name
        workBranch        = $work
        primaryRepoKey    = 'root'
        targetBranch      = $target
        baseSha           = $baseSha
        headSha           = $headSha
        contentHash       = $contentHash
        packPath          = $packPath
        multiRepoPackPath = $multiPackPath
        readyForBing      = $readyForBing
        bingEvidenceBound  = [bool]$bingPublish.published
        prepare           = $prepare
        repoStates        = $repoStates
        reviewedTuple     = [PSCustomObject]@{
            targetBranch   = $target
            workBranch     = $work
            baseSha        = $baseSha
            headSha        = $headSha
            contentHash    = $contentHash
            primaryRepoKey = 'root'
        }
    }
}

function Set-LoomShipReviewEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('approve', 'changes-requested', 'blocked')][string]$Verdict,
        [Parameter(Mandatory)][string]$ContentHash,
        [string]$ReviewDepth = 'L1',
        [string[]]$EvidenceInspected = @('pack'),
        [string]$Provenance = 'import',
        [switch]$ContractShape
    )

    $state = Get-LoomShipState -Project $Name
    if (-not $state) { throw "No ship state for $Name." }
    if ([string]::IsNullOrWhiteSpace([string]$state.contentHash)) {
        throw 'No packed contentHash. Run bite pack first.'
    }
    if (-not [string]::Equals([string]$state.contentHash, $ContentHash, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("Review contentHash mismatch: review={0}; pack={1}" -f $ContentHash, $state.contentHash)
    }
    if ($ContractShape) {
        if ([string]::IsNullOrWhiteSpace($ReviewDepth)) { throw 'Contract shape requires reviewDepth.' }
        if (-not $EvidenceInspected -or @($EvidenceInspected).Count -eq 0) {
            throw 'Contract shape requires non-empty evidenceInspected.'
        }
    }
    $state.reviewVerdict = $Verdict
    $state.reviewProvenance = [PSCustomObject]@{
        source            = $Provenance
        reviewDepth       = $ReviewDepth
        evidenceInspected = @($EvidenceInspected)
        recordedAtUtc     = [datetime]::UtcNow.ToString('o')
    }
    $state.reviewedAtUtc = [datetime]::UtcNow.ToString('o')
    Save-LoomShipState -State $state | Out-Null
    return $state
}

function Test-LoomShipReady {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot,
        [switch]$SkipFullTests,
        [switch]$OwnerAffirm
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    $state = Get-LoomShipState -Project $Name
    $reasons = New-Object System.Collections.Generic.List[string]
    if (-not $state) {
        return [PSCustomObject]@{ ok = $false; reasons = @('no-ship-state') }
    }

    $work = [string]$state.workBranch
    $target = [string]$state.targetBranch
    $baseSha = [string]$state.baseSha
    $headSha = [string]$state.headSha
    $hash = [string]$state.contentHash
    $verdict = [string]$state.reviewVerdict
    $shipPhase = [string](Get-LoomProp -Object $state -Name 'shipPhase' -Default 'active')
    $repoStates = @($(Get-LoomProp -Object $state -Name 'repoStates' -Default @()))

    if ([string]::IsNullOrWhiteSpace($work) -or [string]::IsNullOrWhiteSpace($target)) {
        [void]$reasons.Add('missing-branch-fields')
    }
    if ([string]::IsNullOrWhiteSpace($baseSha) -or [string]::IsNullOrWhiteSpace($headSha) -or [string]::IsNullOrWhiteSpace($hash)) {
        [void]$reasons.Add('missing-reviewed-tuple')
    }
    if ($verdict -ne 'approve' -and $shipPhase -ne 'partialShip') {
        [void]$reasons.Add(('review-verdict-{0}' -f $(if ($verdict) { $verdict } else { 'missing' })))
    }
    if ($shipPhase -eq 'partialShip' -and $verdict -ne 'approve') {
        [void]$reasons.Add('partial-ship-requires-prior-approve')
    }

    $prov = Get-LoomProp -Object $state -Name 'reviewProvenance' -Default $null
    $depth = [string](Get-LoomProp -Object $prov -Name 'reviewDepth' -Default '')
    $evidence = @(Get-LoomProp -Object $prov -Name 'evidenceInspected' -Default @())
    if ([string]::IsNullOrWhiteSpace($depth) -or $evidence.Count -eq 0) {
        [void]$reasons.Add('review-contract-shape')
    }

    if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $root)) {
        [void]$reasons.Add('dirty-worktree')
    }

    $policy = Get-LoomShipProjectPolicy -RegistryName $Name
    if ($null -eq $policy) {
        $policy = [PSCustomObject]@{
            protectedBranches = @()
            ownerAffirmPaths  = @()
            biteRepos         = @('root')
            biteRepoTargets   = @{}
            resolved          = $false
        }
    }
    if (-not (Test-LoomShipProtectedBranch -Branch $target -ProtectedBranches $policy.protectedBranches)) {
        if (@($policy.protectedBranches).Count -gt 0) {
            [void]$reasons.Add('target-not-protected-configured')
        }
    }

    $hits = New-Object System.Collections.Generic.List[string]
    try {
        $repoKeys = @($(Get-LoomProp -Object $state -Name 'repos' -Default @('root')))
        $resolved = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos $repoKeys)
        $byKey = @{}
        foreach ($r in $resolved) { $byKey[$r.Key] = $r }

        if (@($repoStates).Count -eq 0) {
            # Legacy v1 state: validate root slice only.
            $curBranch = Get-LoomGitCurrentBranchName -ProjectRoot $root
            if ($curBranch -ne $work) { [void]$reasons.Add('wrong-work-branch') }
            $liveHead = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'
            if ($liveHead -ne $headSha) { [void]$reasons.Add('head-sha-mismatch') }
            $liveBase = Get-LoomShipMergeBaseSha -ProjectRoot $root -TargetBranch $target -WorkBranch $work
            if ($liveBase -ne $baseSha) { [void]$reasons.Add('base-sha-mismatch') }
            foreach ($h in @(Get-LoomShipOwnerAffirmHits -ProjectRoot $root -BaseSha $baseSha -HeadSha $headSha -OwnerAffirmPaths $policy.ownerAffirmPaths)) {
                [void]$hits.Add(('root:{0}' -f $h))
            }
        }
        else {
            foreach ($rs in $repoStates) {
                $key = [string](Get-LoomProp -Object $rs -Name 'key' -Default '')
                if (-not $byKey.ContainsKey($key)) {
                    [void]$reasons.Add(('repo-missing:{0}' -f $key))
                    continue
                }
                $path = [string]$byKey[$key].Path
                $rsTarget = [string](Get-LoomProp -Object $rs -Name 'targetBranch' -Default '')
                $rsBase = [string](Get-LoomProp -Object $rs -Name 'baseSha' -Default '')
                $rsHead = [string](Get-LoomProp -Object $rs -Name 'headSha' -Default '')
                $rsTip = [string](Get-LoomProp -Object $rs -Name 'targetTipSha' -Default '')
                $pushStatus = [string](Get-LoomProp -Object $rs -Name 'pushStatus' -Default 'pending')

                if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $path)) {
                    [void]$reasons.Add(('dirty-worktree:{0}' -f $key))
                }
                if ($pushStatus -eq 'pushed') {
                    # Already shipped remote; skip work-branch SHA checks for resume (B2).
                    continue
                }
                $repoWork = Get-LoomShipRepoWorkBranch -State $state -RepoKey $key
                if ([string]::IsNullOrWhiteSpace($repoWork)) { $repoWork = $work }
                $curBranch = Get-LoomGitCurrentBranchName -ProjectRoot $path
                if ($curBranch -ne $repoWork -and $shipPhase -ne 'partialShip') {
                    [void]$reasons.Add(('wrong-work-branch:{0}' -f $key))
                }
                $liveHead = Get-LoomGitRevParse -ProjectRoot $path -Rev 'HEAD'
                # After local merge in partialShip, HEAD may be merge commit; require packed head only pre-merge.
                if ($shipPhase -ne 'partialShip' -and $liveHead -ne $rsHead) {
                    [void]$reasons.Add(('head-sha-mismatch:{0}' -f $key))
                }
                if ($shipPhase -ne 'partialShip') {
                    $liveBase = Get-LoomShipMergeBaseSha -ProjectRoot $path -TargetBranch $rsTarget -WorkBranch $repoWork
                    if ($liveBase -ne $rsBase) {
                        [void]$reasons.Add(('base-sha-mismatch:{0}' -f $key))
                    }
                    $liveTip = Get-LoomGitRevParse -ProjectRoot $path -Rev $rsTarget
                    if ($liveTip -ne $rsTip) {
                        [void]$reasons.Add(('target-tip-moved:{0}-repack-required' -f $key))
                    }
                }
                $relPrefix = [string](Get-LoomProp -Object $rs -Name 'relativePath' -Default $(if ($key -eq 'root') { '.' } else { $key }))
                foreach ($h in @(Get-LoomShipOwnerAffirmHits -ProjectRoot $path -BaseSha $rsBase -HeadSha $rsHead `
                            -OwnerAffirmPaths $policy.ownerAffirmPaths -PathPrefix $relPrefix)) {
                    [void]$hits.Add(('{0}:{1}' -f $key, $h))
                }
            }
        }
    }
    catch {
        [void]$reasons.Add(('git-resolve-failed:' + $_.Exception.Message))
    }
    if ($hits.Count -gt 0 -and -not $OwnerAffirm) {
        [void]$reasons.Add('owner-affirm-required')
    }

    if (-not $SkipFullTests -and (Get-Command Invoke-MetraVerify -ErrorAction SilentlyContinue)) {
        # Full suite is project-specific; Metra verify is optional soft gate unless caller requires it.
    }

    return [PSCustomObject]@{
        ok              = ($reasons.Count -eq 0)
        reasons         = @($reasons)
        ownerAffirmHits = $hits
        shipPhase       = $shipPhase
        reviewedTuple   = [PSCustomObject]@{
            targetBranch   = $target
            workBranch     = $work
            baseSha        = $baseSha
            headSha        = $headSha
            contentHash    = $hash
            primaryRepoKey = [string](Get-LoomProp -Object $state -Name 'primaryRepoKey' -Default 'root')
        }
        verdict         = $verdict
    }
}

function Invoke-LoomShip {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot,
        [string]$Summary,
        [switch]$SkipFullTests,
        [switch]$NoPush,
        [switch]$NoDeleteBranch,
        [switch]$OwnerAffirm,
        [switch]$Resume
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    $state = Get-LoomShipState -Project $Name
    if (-not $state) {
        return [PSCustomObject]@{
            ok      = $false
            shipped = $false
            reasons = @('no-ship-state')
            detail  = 'Invoke-LoomShip refused: no ship state.'
        }
    }
    $shipPhase = [string](Get-LoomProp -Object $state -Name 'shipPhase' -Default 'active')
    if ($shipPhase -eq 'partialShip' -and -not $Resume) {
        return [PSCustomObject]@{
            ok           = $false
            shipped      = $false
            shipPhase    = 'partialShip'
            reasons      = @('partial-ship-resume-required')
            detail       = 'Partial ship in progress. Re-run with -Resume after fixing the failed remote.'
            recovery     = ('.\metra.ps1 bite ship -Name {0} -Resume' -f $Name)
            statusHint   = 'bite status'
        }
    }

    $ready = Test-LoomShipReady -Name $Name -ProjectRoot $root -SkipFullTests:$SkipFullTests -OwnerAffirm:$OwnerAffirm
    if (-not $ready.ok) {
        return [PSCustomObject]@{
            ok        = $false
            shipped   = $false
            shipPhase = $shipPhase
            reasons   = @($ready.reasons)
            detail    = 'Invoke-LoomShip refused: reviewed tuple / gates failed.'
        }
    }

    $state = Get-LoomShipState -Project $Name
    $work = [string]$state.workBranch
    $target = [string]$state.targetBranch
    $headSha = [string]$state.headSha
    $hash = [string]$state.contentHash
    $biteId = [string](Get-LoomProp -Object $state -Name 'biteId' -Default 'bite')
    $repoStates = @($(Get-LoomProp -Object $state -Name 'repoStates' -Default @()))
    $short = if ($headSha.Length -ge 8) { $headSha.Substring(0, 8) } else { $headSha }
    $hash8 = if ($hash.Length -ge 8) { $hash.Substring(0, 8) } else { $hash }
    $sum = if ([string]::IsNullOrWhiteSpace($Summary)) { 'ship' } else { $Summary.Trim() }
    $msg = ('{0}: {1} (reviewed {2}, Bing approve {3})' -f $biteId, $sum, $short, $hash8)

    $targetSummary = (@($repoStates | ForEach-Object { '{0}:{1}' -f $_.key, $_.targetBranch }) -join ', ')
    if ([string]::IsNullOrWhiteSpace($targetSummary)) { $targetSummary = ('root:{0}' -f $target) }
    if (-not $PSCmdlet.ShouldProcess($Name, ("ship {0} -> [{1}]" -f $work, $targetSummary))) {
        return [PSCustomObject]@{
            ok      = $true
            whatIf  = $true
            message = $msg
            tuple   = $ready.reviewedTuple
        }
    }

    if (Get-Command Set-MetraInspectBingGateAffirm -ErrorAction SilentlyContinue) {
        try {
            $null = Set-MetraInspectBingGateAffirm -Name $Name -Confirm:$false -ErrorAction Stop
        }
        catch {
            Write-Warning ("Ship auto-affirm soft-failed: {0}" -f $_.Exception.Message)
        }
    }

    $tuple = $ready.reviewedTuple
    $lock = $null
    $keepLock = $false
    $partial = $false
    try {
        $repos = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos @($(Get-LoomProp -Object $state -Name 'repos' -Default @('root'))))
        $byKey = @{}
        foreach ($r in $repos) { $byKey[$r.Key] = $r }

        # Ensure repoStates exist (legacy v1 -> synthesize root-only).
        if (@($repoStates).Count -eq 0) {
            $repoStates = @(New-LoomShipRepoStateObject -Key 'root' -RelativePath '.' -TargetBranch $target `
                    -WorkBranch $work `
                    -TargetTipSha (Get-LoomGitRevParse -ProjectRoot $root -Rev $target) `
                    -BaseSha ([string]$state.baseSha) -HeadSha $headSha -PushStatus 'pending')
            $state.repoStates = $repoStates
            $state.primaryRepoKey = 'root'
        }

        $authorizedTargets = @($repoStates | ForEach-Object { [string]$_.targetBranch } | Where-Object { $_ } | Select-Object -Unique)
        $authorizedHeads = @($repoStates | ForEach-Object { [string]$_.headSha } | Where-Object { $_ } | Select-Object -Unique)
        $lock = New-LoomShipLock -Project $Name -ReviewedTuple $tuple `
            -AuthorizedTargetBranches $authorizedTargets -AuthorizedHeadShas $authorizedHeads

        $deleteWork = (-not $NoDeleteBranch) -and (-not $NoPush)

        # Phase 1: validate all repos; fetch remotes immediately before first push (B2).
        foreach ($rs in $repoStates) {
            $key = [string]$rs.key
            if (-not $byKey.ContainsKey($key)) { throw ("Repo key '{0}' missing on disk." -f $key) }
            $path = [string]$byKey[$key].Path
            $rsTarget = [string]$rs.targetBranch
            if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $path)) {
                throw ("Dirty worktree in {0}" -f $key)
            }
            $repoWork = Get-LoomShipRepoWorkBranch -State $state -RepoKey $key
            if ([string]::IsNullOrWhiteSpace($repoWork)) { $repoWork = $work }
            if ([string](Get-LoomProp -Object $rs -Name 'pushStatus' -Default 'pending') -ne 'pushed') {
                $verify = Invoke-LoomGit -ProjectRoot $path -GitArgs @('rev-parse', '--verify', $repoWork)
                if ($verify.ExitCode -ne 0 -and $shipPhase -ne 'partialShip') {
                    throw ("Work branch {0} missing in {1}" -f $repoWork, $key)
                }
            }
            if (-not $NoPush) {
                $fetch = Invoke-LoomGit -ProjectRoot $path -GitArgs @('fetch', 'origin', $rsTarget)
                if ($fetch.ExitCode -ne 0) {
                    throw ("fetch origin/{0} failed in {1}: {2}" -f $rsTarget, $key, (Get-LoomGitErrorDetail $fetch))
                }
                $remoteTip = Invoke-LoomGit -ProjectRoot $path -GitArgs @('rev-parse', ('origin/{0}' -f $rsTarget))
                $expectedTip = [string]$rs.targetTipSha
                if ($remoteTip.ExitCode -ne 0) {
                    throw ("origin/{0} missing after fetch in {1}: {2}" -f $rsTarget, $key, (Get-LoomGitErrorDetail $remoteTip))
                }
                $actual = [string]$remoteTip.Stdout.Trim()
                $already = [string](Get-LoomProp -Object $rs -Name 'pushStatus' -Default 'pending')
                if ($already -eq 'pushed') {
                    $mergeSha = [string](Get-LoomProp -Object $rs -Name 'mergeCommitSha' -Default '')
                    if (-not [string]::IsNullOrWhiteSpace($mergeSha) -and $actual -ne $mergeSha) {
                        throw ("Guarded resume refused: {0} remote {1} moved off expected merge {2} (now {3}). Manual recovery required; never auto-rollback." -f $key, $rsTarget, $mergeSha, $actual)
                    }
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($expectedTip)) {
                        throw ("Packed targetTipSha missing for unpushed repo '{0}'. Repack and re-review." -f $key)
                    }
                    if ($actual -ne $expectedTip) {
                        throw ("Remote target moved before push in {0}: expected {1}, origin/{2}={3}. Repack and re-review." -f $key, $expectedTip, $rsTarget, $actual)
                    }
                }
            }
        }

        # Phase 2: merge pending repos (skip already-pushed on resume).
        # On failure: reset earlier local merges back to packed targetTipSha and return to work branch.
        $mergeShas = New-Object System.Collections.Generic.List[object]
        $mergedThisRun = New-Object System.Collections.Generic.List[object]
        $activeMerge = $null
        try {
            foreach ($rs in $repoStates) {
                $key = [string]$rs.key
                $path = [string]$byKey[$key].Path
                $rsTarget = [string]$rs.targetBranch
                $pushStatus = [string](Get-LoomProp -Object $rs -Name 'pushStatus' -Default 'pending')
                $repoWorkEarly = Get-LoomShipRepoWorkBranch -State $state -RepoKey $key
                if ([string]::IsNullOrWhiteSpace($repoWorkEarly)) { $repoWorkEarly = $work }
                if ($pushStatus -eq 'pushed') {
                    [void]$mergeShas.Add([PSCustomObject]@{
                            repo = $key; path = $path; target = $rsTarget; workBranch = $repoWorkEarly
                            mergeSha = [string]$rs.mergeCommitSha; pushStatus = 'pushed'
                        })
                    continue
                }
                $existingMerge = [string](Get-LoomProp -Object $rs -Name 'mergeCommitSha' -Default '')
                if ($shipPhase -eq 'partialShip' -and -not [string]::IsNullOrWhiteSpace($existingMerge)) {
                    $onTarget = Invoke-LoomGit -ProjectRoot $path -GitArgs @('rev-parse', $rsTarget)
                    if ($onTarget.ExitCode -eq 0 -and [string]$onTarget.Stdout.Trim() -eq $existingMerge) {
                        [void]$mergeShas.Add([PSCustomObject]@{
                                repo = $key; path = $path; target = $rsTarget; workBranch = $repoWorkEarly
                                mergeSha = $existingMerge; pushStatus = 'pending'
                            })
                        continue
                    }
                }

                $repoWork = Get-LoomShipRepoWorkBranch -State $state -RepoKey $key
                if ([string]::IsNullOrWhiteSpace($repoWork)) { $repoWork = $work }
                $priorTip = [string](Get-LoomProp -Object $rs -Name 'targetTipSha' -Default '')
                $co = Invoke-LoomGit -ProjectRoot $path -GitArgs @('checkout', $rsTarget)
                if ($co.ExitCode -ne 0) {
                    throw ("checkout {0} failed in {1}: {2}" -f $rsTarget, $key, (Get-LoomGitErrorDetail $co))
                }
                # Track active protected checkout so catch restores work branch even before mergeShas entry.
                $activeMerge = [PSCustomObject]@{
                    repo = $key; path = $path; target = $rsTarget; workBranch = $repoWork; priorTip = $priorTip
                }
                $merge = Invoke-LoomGit -ProjectRoot $path -GitArgs @('merge', '--no-ff', $repoWork, '-m', $msg)
                if ($merge.ExitCode -ne 0) {
                    Invoke-LoomGit -ProjectRoot $path -GitArgs @('merge', '--abort') | Out-Null
                    Invoke-LoomGit -ProjectRoot $path -GitArgs @('checkout', $repoWork) | Out-Null
                    $activeMerge = $null
                    throw ("merge --no-ff failed in {0}: {1}" -f $key, (Get-LoomGitErrorDetail $merge))
                }
                $mergeSha = Get-LoomGitHeadCommit -ProjectRoot $path
                $rs.mergeCommitSha = $mergeSha
                $rs.pushStatus = 'pending'
                $entry = [PSCustomObject]@{
                    repo = $key; path = $path; target = $rsTarget; workBranch = $repoWork
                    mergeSha = $mergeSha; pushStatus = 'pending'
                    priorTip = $priorTip
                }
                [void]$mergeShas.Add($entry)
                [void]$mergedThisRun.Add($entry)
                $activeMerge = $null
                $keepLock = $true
            }
        }
        catch {
            if ($null -ne $activeMerge) {
                $failWork = [string]$activeMerge.workBranch
                if (-not [string]::IsNullOrWhiteSpace($failWork)) {
                    Invoke-LoomGit -ProjectRoot $activeMerge.path -GitArgs @('checkout', $failWork) | Out-Null
                }
            }
            foreach ($m in @($mergedThisRun)) {
                $prior = [string]$m.priorTip
                if ([string]::IsNullOrWhiteSpace($prior)) { continue }
                $rollbackWork = [string](Get-LoomProp -Object $m -Name 'workBranch' -Default $work)
                Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('checkout', '-B', [string]$m.target, $prior) | Out-Null
                Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('checkout', $rollbackWork) | Out-Null
                foreach ($rs in $repoStates) {
                    if ($rs.key -eq $m.repo) {
                        $rs.mergeCommitSha = ''
                        $rs.pushStatus = 'pending'
                    }
                }
            }
            $state.repoStates = @($repoStates)
            Save-LoomShipState -State $state | Out-Null
            $keepLock = $false
            throw
        }
        $state.repoStates = @($repoStates)
        Save-LoomShipState -State $state | Out-Null

        # Phase 3: push in declared order; any push failure after local merges => partialShip (B2).
        # Local merges already mutated targets, so even the first push failure must be recoverable.
        if (-not $NoPush) {
            $anyPushed = $false
            foreach ($m in $mergeShas) {
                if ([string]$m.pushStatus -eq 'pushed') {
                    $anyPushed = $true
                    continue
                }
                $push = Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('push', 'origin', [string]$m.target)
                if ($push.ExitCode -ne 0) {
                    foreach ($rs in $repoStates) {
                        if ($rs.key -eq $m.repo) {
                            $rs.pushStatus = 'failed'
                            $rs.mergeCommitSha = [string]$m.mergeSha
                        }
                    }
                    $state.repoStates = @($repoStates)
                    $state.shipPhase = 'partialShip'
                    $partial = $true
                    $keepLock = $true
                    Save-LoomShipState -State $state | Out-Null
                    $pushed = @($repoStates | Where-Object { $_.pushStatus -eq 'pushed' } | ForEach-Object { $_.key })
                    $pending = @($repoStates | Where-Object { $_.pushStatus -ne 'pushed' } | ForEach-Object { $_.key })
                    $detail = if ($anyPushed) {
                        ("Push failed for {0} after earlier repos succeeded. Branches retained; no auto-rollback. Resume with -Resume when remote is fixed." -f $m.repo)
                    }
                    else {
                        ("Push failed for {0} before any remote update. Local merges retained as partialShip; Resume with -Resume (no auto-rollback of protected branches)." -f $m.repo)
                    }
                    return [PSCustomObject]@{
                        ok          = $false
                        shipped     = $false
                        partialShip = $true
                        shipPhase   = 'partialShip'
                        project     = $Name
                        message     = $msg
                        pushedRepos  = $pushed
                        pendingRepos = $pending
                        repoStates  = @($repoStates)
                        detail      = $detail
                        recovery    = ('.\metra.ps1 bite ship -Name {0} -Resume' -f $Name)
                        pushError   = (Get-LoomGitErrorDetail $push)
                    }
                }
                foreach ($rs in $repoStates) {
                    if ($rs.key -eq $m.repo) {
                        $rs.pushStatus = 'pushed'
                        $rs.mergeCommitSha = [string]$m.mergeSha
                    }
                }
                $m.pushStatus = 'pushed'
                $anyPushed = $true
                $state.repoStates = @($repoStates)
                Save-LoomShipState -State $state | Out-Null
            }
        }

        # Successful local merges (with or without push) clear the ephemeral ship lock.
        $keepLock = $false

        # Phase 4: delete work branches only after every push succeeds (B2).
        if ($deleteWork -and -not $partial) {
            foreach ($m in $mergeShas) {
                $delWork = [string](Get-LoomProp -Object $m -Name 'workBranch' -Default '')
                if ([string]::IsNullOrWhiteSpace($delWork)) {
                    $delWork = Get-LoomShipRepoWorkBranch -State $state -RepoKey ([string]$m.repo)
                }
                if ([string]::IsNullOrWhiteSpace($delWork)) { $delWork = $work }
                Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('branch', '-d', $delWork) | Out-Null
                if (-not $NoPush) {
                    Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('push', 'origin', '--delete', $delWork) | Out-Null
                }
            }
        }

        $mergeArr = @()
        foreach ($m in $mergeShas) { $mergeArr += $m }
        if (-not $keepLock) {
            $state.shipPhase = 'shipped'
            Save-LoomShipState -State $state | Out-Null
            $statePath = Get-LoomShipStatePath -Project $Name
            if (Test-Path -LiteralPath $statePath) {
                Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            }
        }
        return [PSCustomObject]@{
            ok         = $true
            shipped    = $true
            project    = $Name
            message    = $msg
            merges     = $mergeArr
            tuple      = $tuple
            noPush     = [bool]$NoPush
            lockKept   = [bool]$keepLock
            shipPhase  = 'shipped'
            repoStates = @($repoStates)
        }
    }
    finally {
        if (-not $keepLock) {
            Clear-LoomShipLock -Project $Name
        }
    }
}

function Get-LoomShipStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot
    )

    $root = $null
    try {
        $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    }
    catch {
        $root = $null
    }
    $state = Get-LoomShipState -Project $Name
    $ready = $null
    if ($state -and $root) {
        $ready = Test-LoomShipReady -Name $Name -ProjectRoot $root -SkipFullTests
    }
    $branch = $null
    $commits = @()
    if ($root -and $state) {
        try {
            $branch = Get-LoomGitCurrentBranchName -ProjectRoot $root
            $log = Invoke-LoomGit -ProjectRoot $root -GitArgs @('log', '--oneline', ('{0}..HEAD' -f $state.targetBranch))
            if ($log.ExitCode -eq 0) {
                $commits = @($log.Stdout -split '[\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
        }
        catch { }
    }

    $shipPhase = if ($state) { [string](Get-LoomProp -Object $state -Name 'shipPhase' -Default 'active') } else { $null }
    $repoStates = if ($state) { @($(Get-LoomProp -Object $state -Name 'repoStates' -Default @())) } else { @() }
    $pushed = @($repoStates | Where-Object { [string](Get-LoomProp -Object $_ -Name 'pushStatus' -Default '') -eq 'pushed' } | ForEach-Object { $_.key })
    $pending = @($repoStates | Where-Object { [string](Get-LoomProp -Object $_ -Name 'pushStatus' -Default 'pending') -ne 'pushed' } | ForEach-Object { $_.key })
    $recovery = $null
    if ($shipPhase -eq 'partialShip') {
        $recovery = ('.\metra.ps1 bite ship -Name {0} -Resume' -f $Name)
    }

    return [PSCustomObject]@{
        project            = $Name
        state              = $state
        currentBranch      = $branch
        commitsSinceTarget = $commits
        shipReady          = if ($ready) { [bool]$ready.ok } else { $false }
        shipReasons        = if ($ready) { @($ready.reasons) } else { @('no-state') }
        shipPhase          = $shipPhase
        pushedRepos          = $pushed
        pendingRepos         = $pending
        repoStates         = $repoStates
        recovery           = $recovery
        statePath          = (Get-LoomShipStatePath -Project $Name)
    }
}

function Invoke-LoomShipCycleCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [hashtable]$Params = @{}
    )

    switch ($Subcommand.ToLowerInvariant()) {
        'start' { return Start-LoomShipBranch @Params }
        'commit' { return Invoke-LoomShipCommit @Params }
        'pack' { return Invoke-LoomShipPack @Params }
        'ship' { return Invoke-LoomShip @Params }
        'status' { return Get-LoomShipStatus @Params }
        'review-set' { return Set-LoomShipReviewEvidence @Params }
        'ready' { return Test-LoomShipReady @Params }
        default { throw "Unknown ship-cycle subcommand: $Subcommand" }
    }
}
