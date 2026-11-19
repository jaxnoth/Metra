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
        [string[]]$Repos = @('root')
    )
    return [PSCustomObject]@{
        schemaVersion   = 1
        project         = $Project
        biteId          = $BiteId
        workBranch      = $WorkBranch
        targetBranch    = $TargetBranch
        baseSha         = $BaseSha
        headSha         = $HeadSha
        contentHash     = $ContentHash
        repos           = @($Repos)
        packIdentity    = $null
        reviewVerdict   = $null
        reviewProvenance = $null
        reviewedAtUtc   = $null
        updatedAtUtc    = [datetime]::UtcNow.ToString('o')
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
    return [PSCustomObject]@{
        protectedBranches = @($protected)
        ownerAffirmPaths  = @($ownerPaths)
        biteRepos         = @($repos)
        resolved          = $true
    }
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string[]]$Repos = @('root')
    )
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($repo in @($Repos)) {
        $key = [string]$repo
        if ([string]::IsNullOrWhiteSpace($key) -or $key -eq 'root') {
            [void]$list.Add([PSCustomObject]@{ Key = 'root'; Path = $ProjectRoot; Order = 100 })
            continue
        }
        $path = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $key))
        if (-not (Test-LoomPathWithinRoot -Path $path -Root $ProjectRoot)) {
            throw ("bite repo path escaped project root: {0}" -f $path)
        }
        if (-not (Test-Path -LiteralPath $path)) {
            throw "bite repo path missing: $path"
        }
        $order = switch ($key.ToLowerInvariant()) {
            'cookbook' { 10 }
            'chef' { 20 }
            default { 50 }
        }
        [void]$list.Add([PSCustomObject]@{ Key = $key; Path = $path; Order = $order })
    }
    return @($list | Sort-Object Order, Key)
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
        [Parameter(Mandatory)]$ReviewedTuple
    )
    $dir = Get-LoomShipStateRoot -Project $Project
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $lock = [PSCustomObject]@{
        schemaVersion = 1
        project       = $Project
        pid           = $PID
        createdAtUtc  = [datetime]::UtcNow.ToString('o')
        expiresAtUtc  = ([datetime]::UtcNow.AddMinutes(15)).ToString('o')
        targetBranch  = [string](Get-LoomProp -Object $ReviewedTuple -Name 'targetBranch' -Default '')
        workBranch    = [string](Get-LoomProp -Object $ReviewedTuple -Name 'workBranch' -Default '')
        baseSha       = [string](Get-LoomProp -Object $ReviewedTuple -Name 'baseSha' -Default '')
        headSha       = [string](Get-LoomProp -Object $ReviewedTuple -Name 'headSha' -Default '')
        contentHash   = [string](Get-LoomProp -Object $ReviewedTuple -Name 'contentHash' -Default '')
        token         = [guid]::NewGuid().ToString('n')
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
        [string]$RepoRoot
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
    return $true
}

function Get-LoomShipOwnerAffirmHits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BaseSha,
        [Parameter(Mandatory)][string]$HeadSha,
        [string[]]$OwnerAffirmPaths
    )
    if (-not $OwnerAffirmPaths -or @($OwnerAffirmPaths).Count -eq 0) { return @() }
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('diff', '--name-only', "$BaseSha...$HeadSha")
    if ($r.ExitCode -ne 0) { throw ("diff name-only failed: {0}" -f (Get-LoomGitErrorDetail $r)) }
    $changed = @($r.Stdout -split '[\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ($_ -replace '\\', '/').Trim() })
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
        $policy = [PSCustomObject]@{ protectedBranches = @(); ownerAffirmPaths = @(); biteRepos = @('root'); resolved = $false }
    }
    if (-not $Repos -or @($Repos).Count -eq 0) { $Repos = @($policy.biteRepos) }
    $target = $TargetBranch
    if ([string]::IsNullOrWhiteSpace($target)) {
        if (@($policy.protectedBranches).Count -gt 0) {
            $target = [string]$policy.protectedBranches[0]
        }
        else {
            $target = 'main'
        }
    }

    $slug = ($Name.ToLowerInvariant() -replace '[^\w]+', '-').Trim('-')
    $biteId = ($Bite.Trim() -replace '[^\w\.-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($biteId)) { throw '-Bite is required.' }
    $branch = ('bite/{0}/{1}' -f $slug, $biteId).Replace('\', '/')

    $repoRoots = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos $Repos)
    foreach ($repo in $repoRoots) {
        if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $repo.Path)) {
            throw ("Dirty worktree blocks bite start ({0}): {1}" -f $repo.Key, $repo.Path)
        }
        $cur = Get-LoomGitCurrentBranchName -ProjectRoot $repo.Path
        if ($cur -ne $target) {
            $co = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('checkout', $target)
            if ($co.ExitCode -ne 0) { throw ("checkout {0} failed in {1}: {2}" -f $target, $repo.Key, (Get-LoomGitErrorDetail $co)) }
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
    }

    $baseSha = Get-LoomShipMergeBaseSha -ProjectRoot $root -TargetBranch $target -WorkBranch $branch
    $headSha = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'
    $state = New-LoomShipStateObject -Project $Name -WorkBranch $branch -TargetBranch $target `
        -BaseSha $baseSha -HeadSha $headSha -BiteId $biteId -Repos $Repos
    Save-LoomShipState -State $state | Out-Null

    return [PSCustomObject]@{
        ok           = $true
        project      = $Name
        biteId       = $biteId
        workBranch   = $branch
        targetBranch = $target
        baseSha      = $baseSha
        headSha      = $headSha
        repos        = @($repoRoots | ForEach-Object { $_.Key })
        statePath    = (Get-LoomShipStatePath -Project $Name)
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
    $branch = [string]$state.workBranch
    $cur = Get-LoomGitCurrentBranchName -ProjectRoot $root
    if ($cur -ne $branch) {
        throw ("Wrong branch for ship commit: current={0}; expected={1}" -f $cur, $branch)
    }
    if (-not (Test-LoomWorkBranchName -Branch $cur)) {
        throw "Ship commit refused on non-work branch: $cur"
    }

    if (-not $SkipQuickCheck) {
        $check = Invoke-LoomGit -ProjectRoot $root -GitArgs @('diff', '--check')
        if ($check.ExitCode -ne 0) {
            throw ("Quick check failed (git diff --check): {0}" -f (Get-LoomGitErrorDetail $check))
        }
    }

    $status = Invoke-LoomGit -ProjectRoot $root -GitArgs @('status', '--porcelain', '-uall')
    if ($status.ExitCode -ne 0) { throw (Get-LoomGitErrorDetail $status) }
    if ([string]::IsNullOrWhiteSpace([string]$status.Stdout)) {
        return [PSCustomObject]@{ ok = $true; skipped = $true; reason = 'nothing-to-commit'; branch = $branch }
    }

    $add = Invoke-LoomGit -ProjectRoot $root -GitArgs @('add', '-A')
    if ($add.ExitCode -ne 0) { throw ("git add failed: {0}" -f (Get-LoomGitErrorDetail $add)) }

    $biteId = [string](Get-LoomProp -Object $state -Name 'biteId' -Default 'bite')
    $msg = $Message.Trim()
    if ($msg -notmatch '(?i)^wip\(') {
        $msg = ('wip({0}): {1}' -f $biteId, $msg)
    }
    $commit = Invoke-LoomGit -ProjectRoot $root -GitArgs @('commit', '-m', $msg)
    if ($commit.ExitCode -ne 0) { throw ("git commit failed: {0}" -f (Get-LoomGitErrorDetail $commit)) }

    $head = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'
    $state.headSha = $head
    # New commits invalidate prior review tuple binding for ship.
    $state.contentHash = ''
    $state.reviewVerdict = $null
    $state.reviewProvenance = $null
    $state.reviewedAtUtc = $null
    $state.packIdentity = $null
    Save-LoomShipState -State $state | Out-Null

    if (-not $NoPush) {
        $push = Invoke-LoomGit -ProjectRoot $root -GitArgs @('push', '-u', 'origin', $branch)
        if ($push.ExitCode -ne 0) {
            Write-Warning ("ship commit push failed: {0}" -f (Get-LoomGitErrorDetail $push))
        }
    }

    return [PSCustomObject]@{
        ok         = $true
        project    = $Name
        branch     = $branch
        headSha    = $head
        message    = $msg
        reviewCleared = $true
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

    $work = [string]$state.workBranch
    $target = [string]$state.targetBranch
    $cur = Get-LoomGitCurrentBranchName -ProjectRoot $root
    if ($cur -ne $work) { throw ("Wrong branch for pack: current={0}; expected={1}" -f $cur, $work) }

    $baseSha = Get-LoomShipMergeBaseSha -ProjectRoot $root -TargetBranch $target -WorkBranch $work
    $headSha = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'

    $contentHash = $null
    $packPath = $null
    $readyForBing = $false
    $prepare = $null

    # Prefer exported Metra Inspect CLI (Invoke-MetraInspectPrepareForBing is private to Metra).
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
        $readyForBing = [bool](Get-LoomProp -Object $prepare -Name 'readyForBing' -Default $false)
        $packPath = [string](Get-LoomProp -Object $prepare -Name 'packPath' -Default '')
        $skippedNoDiff = [bool](Get-LoomProp -Object $prepare -Name 'skipped' -Default $false) -and
            ([string](Get-LoomProp -Object $prepare -Name 'reason' -Default '') -eq 'no-diff')
        if ($skippedNoDiff) {
            $rangeCheck = Invoke-LoomGit -ProjectRoot $root -GitArgs @('diff', '--name-only', "$baseSha...$headSha")
            if ($rangeCheck.ExitCode -ne 0) { throw (Get-LoomGitErrorDetail $rangeCheck) }
            if (-not [string]::IsNullOrWhiteSpace([string]$rangeCheck.Stdout)) {
                throw ("bite pack: Inspect reported no-diff but {0}...{1} has changes. Re-run pack with Inspect loaded." -f $baseSha.Substring(0, [Math]::Min(8, $baseSha.Length)), $headSha.Substring(0, [Math]::Min(8, $headSha.Length)))
            }
        }
        $contentHash = Get-LoomShipInspectSlotContentHash -Project $Name -BaseSha $baseSha -HeadSha $headSha
        # Never bind a stale slot hash when prepare skipped or SHA mismatch rejected the slot.
        if ($skippedNoDiff) { $contentHash = $null }
    }
    elseif ($SkipInspectEngine -or -not $inspectCli) {
        if (-not $SkipInspectEngine -and -not $inspectCli) {
            Write-Warning 'bite pack: Show-MetraInspectCli not loaded; using offline Base...HEAD content hash (not a Bing pack).'
        }
    }

    if ([string]::IsNullOrWhiteSpace($contentHash)) {
        # Deterministic fallback / offline: hash of Base...HEAD patch.
        $diff = Invoke-LoomGit -ProjectRoot $root -GitArgs @('diff', '--binary', "$baseSha...$headSha")
        if ($diff.ExitCode -ne 0) { throw (Get-LoomGitErrorDetail $diff) }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$diff.Stdout)
            $contentHash = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
        if ([string]::IsNullOrWhiteSpace($packPath)) {
            $packPath = '(offline-range-hash)'
            if (-not $prepare) { $readyForBing = [bool]$SkipInspectEngine }
        }
    }

    if ([string]::IsNullOrWhiteSpace($contentHash)) {
        throw 'Ship pack failed to compute contentHash.'
    }

    $state.baseSha = $baseSha
    $state.headSha = $headSha
    $state.contentHash = $contentHash
    $state.packIdentity = [PSCustomObject]@{
        packPath      = $packPath
        readyForBing  = $readyForBing
        packedAtUtc   = [datetime]::UtcNow.ToString('o')
        mode          = 'Base...HEAD'
    }
    # Pack alone does not import review.
    $state.reviewVerdict = $null
    $state.reviewProvenance = $null
    $state.reviewedAtUtc = $null
    Save-LoomShipState -State $state | Out-Null

    return [PSCustomObject]@{
        ok            = $true
        project       = $Name
        workBranch    = $work
        targetBranch  = $target
        baseSha       = $baseSha
        headSha       = $headSha
        contentHash   = $contentHash
        packPath      = $packPath
        readyForBing  = $readyForBing
        prepare       = $prepare
        reviewedTuple = [PSCustomObject]@{
            targetBranch = $target
            workBranch   = $work
            baseSha      = $baseSha
            headSha      = $headSha
            contentHash  = $contentHash
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

    if ([string]::IsNullOrWhiteSpace($work) -or [string]::IsNullOrWhiteSpace($target)) {
        [void]$reasons.Add('missing-branch-fields')
    }
    if ([string]::IsNullOrWhiteSpace($baseSha) -or [string]::IsNullOrWhiteSpace($headSha) -or [string]::IsNullOrWhiteSpace($hash)) {
        [void]$reasons.Add('missing-reviewed-tuple')
    }
    if ($verdict -ne 'approve') {
        [void]$reasons.Add(('review-verdict-{0}' -f $(if ($verdict) { $verdict } else { 'missing' })))
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

    try {
        $curBranch = Get-LoomGitCurrentBranchName -ProjectRoot $root
        if ($curBranch -ne $work) { [void]$reasons.Add('wrong-work-branch') }
        $liveHead = Get-LoomGitRevParse -ProjectRoot $root -Rev 'HEAD'
        if ($liveHead -ne $headSha) { [void]$reasons.Add('head-sha-mismatch') }
        $liveBase = Get-LoomShipMergeBaseSha -ProjectRoot $root -TargetBranch $target -WorkBranch $work
        if ($liveBase -ne $baseSha) { [void]$reasons.Add('base-sha-mismatch') }
    }
    catch {
        [void]$reasons.Add(('git-resolve-failed:' + $_.Exception.Message))
    }

    $policy = Get-LoomShipProjectPolicy -RegistryName $Name
    if ($null -eq $policy) {
        # Hooks fail closed when policy is unresolved; ship-ready uses empty defaults here.
        $policy = [PSCustomObject]@{ protectedBranches = @(); ownerAffirmPaths = @(); biteRepos = @('root'); resolved = $false }
    }
    if (-not (Test-LoomShipProtectedBranch -Branch $target -ProtectedBranches $policy.protectedBranches)) {
        # Target not in protected list is allowed for tests; warn via reason only when list non-empty and mismatch.
        if (@($policy.protectedBranches).Count -gt 0) {
            [void]$reasons.Add('target-not-protected-configured')
        }
    }

    $hits = New-Object System.Collections.Generic.List[string]
    try {
        $reposForAffirm = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos @($(Get-LoomProp -Object $state -Name 'repos' -Default @('root'))))
        foreach ($repoAffirm in $reposForAffirm) {
            $repoHead = Get-LoomGitRevParse -ProjectRoot $repoAffirm.Path -Rev 'HEAD'
            $repoBase = Get-LoomShipMergeBaseSha -ProjectRoot $repoAffirm.Path -TargetBranch $target -WorkBranch $work
            foreach ($h in @(Get-LoomShipOwnerAffirmHits -ProjectRoot $repoAffirm.Path -BaseSha $repoBase -HeadSha $repoHead -OwnerAffirmPaths $policy.ownerAffirmPaths)) {
                [void]$hits.Add(('{0}:{1}' -f $repoAffirm.Key, $h))
            }
        }
    }
    catch {
        [void]$reasons.Add(('owner-affirm-check-failed:' + $_.Exception.Message))
    }
    if ($hits.Count -gt 0 -and -not $OwnerAffirm) {
        [void]$reasons.Add('owner-affirm-required')
    }

    if (-not $SkipFullTests -and (Get-Command Invoke-MetraVerify -ErrorAction SilentlyContinue)) {
        # Full suite is project-specific; Metra verify is optional soft gate unless caller requires it.
    }

    return [PSCustomObject]@{
        ok            = ($reasons.Count -eq 0)
        reasons       = @($reasons)
        ownerAffirmHits = $hits
        reviewedTuple = [PSCustomObject]@{
            targetBranch = $target
            workBranch   = $work
            baseSha      = $baseSha
            headSha      = $headSha
            contentHash  = $hash
        }
        verdict       = $verdict
    }
}

function Invoke-LoomShip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ProjectRoot,
        [string]$Summary,
        [switch]$SkipFullTests,
        [switch]$NoPush,
        [switch]$NoDeleteBranch,
        [switch]$OwnerAffirm,
        [switch]$WhatIf
    )

    $root = Resolve-LoomShipProjectRoot -Name $Name -ProjectRoot $ProjectRoot
    $ready = Test-LoomShipReady -Name $Name -ProjectRoot $root -SkipFullTests:$SkipFullTests -OwnerAffirm:$OwnerAffirm
    if (-not $ready.ok) {
        return [PSCustomObject]@{
            ok      = $false
            shipped = $false
            reasons = @($ready.reasons)
            detail  = 'Invoke-LoomShip refused: reviewed tuple / gates failed.'
        }
    }

    $state = Get-LoomShipState -Project $Name
    $work = [string]$state.workBranch
    $target = [string]$state.targetBranch
    $headSha = [string]$state.headSha
    $hash = [string]$state.contentHash
    $biteId = [string](Get-LoomProp -Object $state -Name 'biteId' -Default 'bite')
    $short = if ($headSha.Length -ge 8) { $headSha.Substring(0, 8) } else { $headSha }
    $hash8 = if ($hash.Length -ge 8) { $hash.Substring(0, 8) } else { $hash }
    $sum = if ([string]::IsNullOrWhiteSpace($Summary)) { 'ship' } else { $Summary.Trim() }
    $msg = ('{0}: {1} (reviewed {2}, Bing approve {3})' -f $biteId, $sum, $short, $hash8)

    if ($WhatIf) {
        return [PSCustomObject]@{
            ok      = $true
            whatIf  = $true
            message = $msg
            tuple   = $ready.reviewedTuple
        }
    }

    # Affirm inspect gate when available (machine path).
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
    try {
        $lock = New-LoomShipLock -Project $Name -ReviewedTuple $tuple
        $repos = @(Resolve-LoomShipRepoRoots -ProjectRoot $root -Repos @($state.repos))
        # -NoPush keeps the work branch and ship lock so a later push can still use the hook bypass.
        $deleteWork = (-not $NoDeleteBranch) -and (-not $NoPush)

        # Phase 1: validate all repos before mutating any.
        foreach ($repo in $repos) {
            if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $repo.Path)) {
                throw ("Dirty worktree in {0}" -f $repo.Key)
            }
            $verify = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('rev-parse', '--verify', $work)
            if ($verify.ExitCode -ne 0) {
                throw ("Work branch {0} missing in {1}" -f $work, $repo.Key)
            }
        }

        # Phase 2: merge all repos (abort each failed merge; leave earlier merges for operator repair).
        $mergeShas = New-Object System.Collections.Generic.List[object]
        foreach ($repo in $repos) {
            $co = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('checkout', $target)
            if ($co.ExitCode -ne 0) { throw ("checkout {0} failed in {1}: {2}" -f $target, $repo.Key, (Get-LoomGitErrorDetail $co)) }

            $merge = Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('merge', '--no-ff', $work, '-m', $msg)
            if ($merge.ExitCode -ne 0) {
                Invoke-LoomGit -ProjectRoot $repo.Path -GitArgs @('merge', '--abort') | Out-Null
                throw ("merge --no-ff failed in {0}: {1}" -f $repo.Key, (Get-LoomGitErrorDetail $merge))
            }
            $mergeSha = Get-LoomGitHeadCommit -ProjectRoot $repo.Path
            [void]$mergeShas.Add([PSCustomObject]@{ repo = $repo.Key; path = $repo.Path; mergeSha = $mergeSha })
            # Keep lock as soon as any local merge lands (retry push / partial multi-repo).
            $keepLock = $true
        }

        # Phase 3: push all repos (only after every merge succeeded).
        if (-not $NoPush) {
            foreach ($m in $mergeShas) {
                $push = Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('push', 'origin', $target)
                if ($push.ExitCode -ne 0) {
                    throw ("push {0} failed in {1}: {2}" -f $target, $m.repo, (Get-LoomGitErrorDetail $push))
                }
            }
            # All pushes succeeded; lock can clear after branch delete phase.
            $keepLock = $false
        }

        # Phase 4: delete work branches only after successful pushes (or local-only when delete allowed).
        if ($deleteWork) {
            foreach ($m in $mergeShas) {
                Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('branch', '-d', $work) | Out-Null
                if (-not $NoPush) {
                    Invoke-LoomGit -ProjectRoot $m.path -GitArgs @('push', 'origin', '--delete', $work) | Out-Null
                }
            }
        }

        $mergeArr = @()
        foreach ($m in $mergeShas) { $mergeArr += $m }
        # Successful ship: drop ship state so Porter/pack do not reuse a stale work-branch pointer.
        if (-not $keepLock) {
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

    return [PSCustomObject]@{
        project       = $Name
        state         = $state
        currentBranch = $branch
        commitsSinceTarget = $commits
        shipReady     = if ($ready) { [bool]$ready.ok } else { $false }
        shipReasons   = if ($ready) { @($ready.reasons) } else { @('no-state') }
        statePath     = (Get-LoomShipStatePath -Project $Name)
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
