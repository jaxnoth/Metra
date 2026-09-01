# Slice 3 — branch runner (clean tree, isolated run dir, implementer, path enforcement; no commit).

function Get-LoomActiveTransitionMap {
    [CmdletBinding()]
    param()

    return @{
        '@new'         = @('queued')
        'queued'       = @('claimed', 'blocked')
        'claimed'      = @('implementing', 'blocked', 'failed')
        'implementing' = @('reviewing', 'blocked', 'failed', 'claimed')
        'blocked'      = @()
        'reviewing'    = @()
        'completed'    = @()
        'accepted'     = @()
        'failed'       = @()
        'rejected'     = @()
        'needsManualTest' = @()
        'superseded'   = @()
    }
}

function Get-LoomSlice3Transitions {
    return Get-LoomActiveTransitionMap
}

function Invoke-LoomGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string[]]$GitArgs
    )

    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
        throw "Project root is not a git repository: $ProjectRoot"
    }
    $argList = @('-C', $ProjectRoot) + @($GitArgs)
    $merged = @(& git @argList 2>&1 | ForEach-Object { "$_" })
    $stdout = ($merged -join "`n")
    $stderr = if ($LASTEXITCODE -ne 0 -and -not [string]::IsNullOrWhiteSpace($stdout)) { $stdout } else { '' }
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Stdout   = $stdout
        Stderr   = $stderr
    }
}

function Get-LoomGitErrorDetail {
    param($GitResult)
    $detail = [string](Get-LoomProp -Object $GitResult -Name 'Stderr' -Default '')
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detail = [string](Get-LoomProp -Object $GitResult -Name 'Stdout' -Default '')
    }
    return $detail
}

function Get-LoomGitCurrentBranch {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($r.ExitCode -ne 0) {
        throw "git rev-parse --abbrev-ref HEAD failed: $(Get-LoomGitErrorDetail $r)"
    }
    return ($r.Stdout.Trim())
}

function Get-LoomGitUntrackedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('ls-files', '--others', '--exclude-standard')
    if ($r.ExitCode -ne 0) {
        throw "git ls-files --others failed in ${ProjectRoot}: $(Get-LoomGitErrorDetail $r)"
    }
    return @(
        @($r.Stdout -split "`r?`n") |
            ForEach-Object { ([string]$_).Trim().Replace('\', '/') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Remove-LoomRunCreatedUntracked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [AllowEmptyCollection()][string[]]$BeforeUntracked = @(),
        [string]$RunDir = ''
    )

    $afterUntracked = @(Get-LoomGitUntrackedPaths -ProjectRoot $ProjectRoot)
    $beforeSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($b in @($BeforeUntracked)) {
        $norm = ([string]$b).Replace('\', '/').Trim()
        if (-not [string]::IsNullOrWhiteSpace($norm)) { [void]$beforeSet.Add($norm) }
    }
    $createdByRun = @($afterUntracked | Where-Object { -not $beforeSet.Contains($_) })

    if (-not [string]::IsNullOrWhiteSpace($RunDir)) {
        try {
            New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
            $evidence = [PSCustomObject]@{
                schemaVersion  = 1
                beforeUntracked = @($BeforeUntracked)
                afterUntracked  = @($afterUntracked)
                createdByRun    = @($createdByRun)
                recordedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
            }
            Write-LoomAtomicUtf8Text -Path (Join-Path $RunDir 'untracked-cleanup.json') -Text (($evidence | ConvertTo-Json -Depth 6) + "`n")
        }
        catch {
            Write-Warning ("Could not write untracked cleanup evidence: $($_.Exception.Message)")
        }
    }

    foreach ($rel in @($createdByRun)) {
        $full = Join-Path $ProjectRoot ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot)
            $targetFull = [System.IO.Path]::GetFullPath($full)
            $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $targetFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                Write-Warning ("Skipping untracked cleanup outside project root: $rel")
                continue
            }
        }
        catch {
            Write-Warning ("Skipping untracked cleanup; path resolution failed for '$rel': $($_.Exception.Message)")
            continue
        }
        if (Test-Path -LiteralPath $full) {
            try {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Warning ("Failed to remove run-created untracked path '$rel': $($_.Exception.Message)")
            }
        }
    }
}

function Restore-LoomGitAfterFailedRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BaselineSha,
        [string]$OriginalBranch,
        [string]$ItemBranch,
        [string[]]$BeforeUntracked = @(),
        [string]$RunDir = ''
    )

    if ([string]::IsNullOrWhiteSpace($BaselineSha)) { return }
    try {
        $reset = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('reset', '--hard', $BaselineSha)
        if ($reset.ExitCode -ne 0) {
            Write-Warning "git reset --hard failed during run cleanup: $(Get-LoomGitErrorDetail $reset)"
        }
        else {
            Remove-LoomRunCreatedUntracked -ProjectRoot $ProjectRoot -BeforeUntracked @($BeforeUntracked) -RunDir $RunDir
        }
        if (-not [string]::IsNullOrWhiteSpace($OriginalBranch)) {
            $co = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('checkout', $OriginalBranch)
            if ($co.ExitCode -ne 0) {
                Write-Warning "git checkout $OriginalBranch failed during run cleanup: $(Get-LoomGitErrorDetail $co)"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($ItemBranch) -and $ItemBranch -ne $OriginalBranch) {
                $null = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('branch', '-D', $ItemBranch)
            }
        }
    }
    catch {
        Write-Warning "Loom git run cleanup failed: $($_.Exception.Message)"
    }
}

function Get-LoomNormalizedRepoRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        $RelativePath
    }
    else {
        Join-Path $ProjectRoot $RelativePath
    }
    try {
        $full = [System.IO.Path]::GetFullPath($candidate)
    }
    catch {
        return $null
    }
    if (-not (Test-LoomPathWithinRoot -Path $full -Root $ProjectRoot)) {
        return $null
    }
    $rootFull = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    if ($full.Length -le $rootFull.Length) {
        return ''
    }
    $rel = $full.Substring($rootFull.Length).TrimStart('\', '/')
    return (($rel -replace '\\', '/') -replace '^\./', '')
}

function Test-LoomForbiddenPathMatch {
    param(
        [Parameter(Mandatory)][string]$NormalizedPath,
        [Parameter(Mandatory)][string]$ForbiddenPattern
    )
    $fbNorm = (($ForbiddenPattern -replace '\\', '/') -replace '^\./', '').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($fbNorm)) { return $false }
    $leaf = Split-Path -Leaf $NormalizedPath
    return (
        $NormalizedPath -like $fbNorm -or
        $NormalizedPath -like "$fbNorm/*" -or
        $leaf -like $fbNorm
    )
}

function Test-LoomGitWorkingTreeClean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('status', '--porcelain')
    if ($r.ExitCode -ne 0) {
        throw "git status failed in ${ProjectRoot}: $(Get-LoomGitErrorDetail $r)"
    }
    return [string]::IsNullOrWhiteSpace($r.Stdout)
}

function Get-LoomGitHeadCommit {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', 'HEAD')
    if ($r.ExitCode -ne 0) { throw "git rev-parse HEAD failed: $(Get-LoomGitErrorDetail $r)" }
    return ($r.Stdout.Trim())
}

function Get-LoomGitChangedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $r = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('status', '--porcelain')
    if ($r.ExitCode -ne 0) {
        throw "git status failed: $(Get-LoomGitErrorDetail $r)"
    }
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($r.Stdout -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -lt 4) { continue }
        $pathPart = $line.Substring(3).Trim()
        if ($pathPart -match ' -> ') {
            $pathPart = ($pathPart -split ' -> ', 2)[1].Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($pathPart)) {
            [void]$paths.Add(($pathPart -replace '\\', '/'))
        }
    }
    return @($paths | Select-Object -Unique)
}

function Test-LoomChangedPathsAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ChangedPaths,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string[]]$AllowedPaths = @(),
        [string[]]$ForbiddenPaths = @()
    )

    $violations = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @($ChangedPaths)) {
        $norm = Get-LoomNormalizedRepoRelativePath -RelativePath $rel -ProjectRoot $ProjectRoot
        if ($null -eq $norm) {
            [void]$violations.Add("escape:$rel")
            continue
        }
        foreach ($fb in @($ForbiddenPaths)) {
            if (Test-LoomForbiddenPathMatch -NormalizedPath $norm -ForbiddenPattern $fb) {
                [void]$violations.Add("forbidden:$norm")
            }
        }
        if (@($AllowedPaths).Count -eq 0) { continue }
        $ok = $false
        foreach ($ap in @($AllowedPaths)) {
            $apNorm = (($ap -replace '\\', '/') -replace '^\./', '').TrimEnd('/')
            if ($norm -eq $apNorm -or $norm -like "$apNorm/*") {
                $ok = $true
                break
            }
        }
        if (-not $ok) {
            [void]$violations.Add("out-of-scope:$norm")
        }
    }
    return [PSCustomObject]@{
        allowed    = ($violations.Count -eq 0)
        violations = @($violations)
    }
}

function Get-LoomImplementerFailureClass {
    [CmdletBinding()]
    param(
        [string]$Message,
        [int]$ExitCode = -1
    )

    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace($text) -and $ExitCode -eq 0) {
        return [PSCustomObject]@{
            failureClass = 'none'
            tier           = $null
            retryable      = $false
        }
    }
    if ($text -match '(?i)usage limit|billing|quota|licensing|authentication error|api key') {
        return [PSCustomObject]@{
            failureClass = 'licensing_error'
            tier           = 'stop'
            retryable      = $false
        }
    }
    if ($text -match '(?i)timeout|timed out|temporarily|transient|connection reset|503|502|empty SDK') {
        return [PSCustomObject]@{
            failureClass = 'transient'
            tier           = 'auto-recover'
            retryable      = $true
        }
    }
    if ($text -match '(?i)adapter-unavailable|implementer adapter unavailable') {
        return [PSCustomObject]@{
            failureClass = 'adapter-unavailable'
            tier           = 'stop'
            retryable      = $false
        }
    }
    return [PSCustomObject]@{
        failureClass = 'implementer_error'
        tier           = 'stop'
        retryable      = $false
    }
}

function Get-MetraLoomRunDirectory {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [int]$RunNumber = 1
    )
    return Join-Path (Join-Path (Join-Path $Root 'runs') $ItemId) ('run-{0:D3}' -f $RunNumber)
}

function Get-MetraLoomNextRunNumber {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId
    )
    $base = Join-Path (Join-Path $Root 'runs') $ItemId
    if (-not (Test-Path -LiteralPath $base)) { return 1 }
    $max = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
        if ($d.Name -match '^run-(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -gt $max) { $max = $n }
        }
    }
    return $max + 1
}

function New-LoomRunRequestPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$MetraRoot = (Get-LoomHostRoot)
    )

    $planBody = $null
    $planPath = [string](Get-LoomProp -Object $Item.source -Name 'path' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $planBody = [System.IO.File]::ReadAllText($planPath, (Get-LoomUtf8NoBomEncoding))
    }

    $projectRoot = [string](Get-LoomProp -Object $Item.project -Name 'root' -Default '')
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        $projectRoot = $MetraRoot
    }

    $allowed = @()
    $contract = $Item.contract
    if ($contract) {
        $allowed = @($(Get-LoomProp -Object $contract -Name 'allowedPaths' -Default @()))
    }

    $pkg = [ordered]@{
        schemaVersion = 1
        itemId        = [string]$Item.id
        summary       = [string]$Item.summary
        projectRoot   = $projectRoot
        registryName  = [string](Get-LoomProp -Object $Item.project -Name 'registryName' -Default '')
        branch        = [string](Get-LoomProp -Object $Item.execution -Name 'branch' -Default '')
        allowedPaths  = @($allowed)
        forbiddenPaths = @($(Get-LoomProp -Object $contract -Name 'forbiddenPaths' -Default @()))
        doneWhen      = @($(Get-LoomProp -Object $contract -Name 'doneWhen' -Default @()))
        verifyCommands = @($(Get-LoomProp -Object $contract -Name 'verifyCommands' -Default @()))
        source        = $Item.source
        planPath      = $planPath
        planBody      = $planBody
        createdAt     = (Get-Date).ToString('o')
    }

    if (-not (Test-Path -LiteralPath $RunDir)) {
        [void][System.IO.Directory]::CreateDirectory($RunDir)
    }
    $reqPath = Join-Path $RunDir 'request.json'
    Write-LoomAtomicUtf8Text -Path $reqPath -Text (($pkg | ConvertTo-Json -Depth 12) + "`n")
    return [PSCustomObject]$pkg
}

function Invoke-LoomGitCreateItemBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BranchName
    )

    $co = Invoke-LoomGit -ProjectRoot $ProjectRoot -GitArgs @('checkout', '-b', $BranchName)
    if ($co.ExitCode -ne 0) {
        throw "git checkout -b failed: $(Get-LoomGitErrorDetail $co)"
    }
    return $BranchName
}

function Save-LoomImplementationResult {
    param(
        [Parameter(Mandatory)][string]$RunDir,
        [Parameter(Mandatory)][object]$Result
    )
    $toValidate = $Result
    $copy = @{}
    foreach ($p in $Result.PSObject.Properties) {
        if ($null -eq $p.Value) { continue }
        $copy[$p.Name] = $p.Value
    }
    $toValidate = [PSCustomObject]$copy
    Test-LoomContract -Schema 'implementation-result' -Object $toValidate | Out-Null
    $path = Join-Path $RunDir 'implementation.json'
    Write-LoomAtomicUtf8Text -Path $path -Text (($Result | ConvertTo-Json -Depth 8) + "`n")
    return $path
}

function Invoke-MetraLoomRun {
    <#
    .SYNOPSIS
        Slice 3 branch runner: clean tree, branch, run dir, one implementer pass, path enforcement (no commit).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$MetraRoot = (Get-LoomHostRoot),
        [switch]$DryRun,
        [switch]$Confirm,
        [scriptblock]$ImplementerScript
    )

    $item = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
    if (-not $item) { throw "Queue item not found: $ItemId" }
    if ([string]$item.status -ne 'queued') {
        throw "Queue item $ItemId status is '$($item.status)'; expected 'queued' for run."
    }

    $projectRoot = [System.IO.Path]::GetFullPath([string]$item.project.root)
    if (-not (Test-Path -LiteralPath $projectRoot)) {
        throw "Project root not found: $projectRoot"
    }

    $branch = [string]$item.execution.branch
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Queue item $ItemId missing execution.branch"
    }
    if (-not (Test-LoomExecutionBranchPrefix -Branch $branch)) {
        throw "Queue item $ItemId execution.branch has invalid prefix (expected loom/ or autoprogram/): $branch"
    }

    $runNum = Get-MetraLoomNextRunNumber -Root $Root -ItemId $ItemId
    $runDir = Get-MetraLoomRunDirectory -Root $Root -ItemId $ItemId -RunNumber $runNum

    if ($DryRun) {
        $pkg = New-LoomRunRequestPackage -Item $item -RunDir $runDir -MetraRoot $MetraRoot
        $impl = [PSCustomObject]@{
            schemaVersion = 1
            status        = 'dry-run'
            message       = 'Dry run — no git branch or implementer invocation.'
            exitCode      = 0
        }
        Save-LoomImplementationResult -RunDir $runDir -Result $impl | Out-Null
        return [PSCustomObject]@{
            dryRun    = $true
            itemId    = $ItemId
            runDir    = $runDir
            request   = $pkg
            result    = $impl
            status    = [string]$item.status
        }
    }

    if (-not $Confirm) {
        throw 'autoprogram run requires -Confirm for live execution (git branch + implementer).'
    }

    if (-not (Test-LoomGitWorkingTreeClean -ProjectRoot $projectRoot)) {
        $blocked = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'queued' -To 'blocked' `
            -Reason 'dirty-git-baseline'
        throw "Git working tree is not clean in $projectRoot; item blocked."
    }

    $baselineSha = Get-LoomGitHeadCommit -ProjectRoot $projectRoot
    $originalBranch = Get-LoomGitCurrentBranch -ProjectRoot $projectRoot
    $beforeUntracked = @(Get-LoomGitUntrackedPaths -ProjectRoot $projectRoot)
    $gitRunActive = $false
    $claimed = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'queued' -To 'claimed' -Reason 'run-start' -Mutator {
        param($i)
        if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
        $i.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue $baselineSha -Force
        $i.execution | Add-Member -NotePropertyName runNumber -NotePropertyValue $runNum -Force
        $i.execution | Add-Member -NotePropertyName runDir -NotePropertyValue $runDir -Force
        return $i
    }

    try {
        Invoke-LoomGitCreateItemBranch -ProjectRoot $projectRoot -BranchName $branch
        $gitRunActive = $true

        $pkg = New-LoomRunRequestPackage -Item $claimed -RunDir $runDir -MetraRoot $MetraRoot
        $stdoutPath = Join-Path $runDir 'stdout.log'
        $stderrPath = Join-Path $runDir 'stderr.log'

        $implementing = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'claimed' -To 'implementing' -Reason 'implementer-start'

        $implResult = Invoke-LoomImplementerAdapter -Request $pkg -ProjectRoot $projectRoot -RunDir $runDir -ImplementerScript $ImplementerScript

        $stdoutText = [string](Get-LoomProp -Object $implResult -Name 'stdout' -Default '')
        $stderrText = [string](Get-LoomProp -Object $implResult -Name 'stderr' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            Write-LoomAtomicUtf8Text -Path $stdoutPath -Text $stdoutText
        }
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Write-LoomAtomicUtf8Text -Path $stderrPath -Text $stderrText
        }

        $failureClass = Get-LoomImplementerFailureClass -Message ([string](Get-LoomProp -Object $implResult -Name 'message' -Default '')) -ExitCode ([int](Get-LoomProp -Object $implResult -Name 'exitCode' -Default -1))
        $status = [string](Get-LoomProp -Object $implResult -Name 'status' -Default 'failed')

        if ($status -ne 'ok' -and $status -ne 'completed') {
            $record = [PSCustomObject]@{
                schemaVersion = 1
                status        = 'failed'
                failureClass  = $failureClass.failureClass
                tier          = $failureClass.tier
                message       = [string](Get-LoomProp -Object $implResult -Name 'message' -Default '')
                stdoutPath    = $(if (Test-Path $stdoutPath) { $stdoutPath } else { $null })
                stderrPath    = $(if (Test-Path $stderrPath) { $stderrPath } else { $null })
                exitCode      = [int](Get-LoomProp -Object $implResult -Name 'exitCode' -Default 1)
            }
            Save-LoomImplementationResult -RunDir $runDir -Result $record | Out-Null

            if ($failureClass.failureClass -eq 'licensing_error' -or $failureClass.failureClass -eq 'adapter-unavailable') {
                Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'blocked' -Reason $failureClass.failureClass | Out-Null
                throw "Implementer blocked ($($failureClass.failureClass)): $($implResult.message)"
            }
            if ($failureClass.retryable) {
                Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'claimed' -Reason 'implementer-transient-retry' | Out-Null
                throw "Implementer transient failure (retry allowed): $($implResult.message)"
            }
            Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'failed' -Reason $failureClass.failureClass | Out-Null
            throw "Implementer failed: $($implResult.message)"
        }

        $changed = @(Get-LoomGitChangedPaths -ProjectRoot $projectRoot)
        $contract = $implementing.contract
        $scope = Test-LoomChangedPathsAllowed -ChangedPaths $changed -ProjectRoot $projectRoot `
            -AllowedPaths @($(Get-LoomProp -Object $contract -Name 'allowedPaths' -Default @())) `
            -ForbiddenPaths @($(Get-LoomProp -Object $contract -Name 'forbiddenPaths' -Default @()))

        if (-not $scope.allowed) {
            $record = [PSCustomObject]@{
                schemaVersion = 1
                status        = 'failed'
                failureClass  = 'scope-violation'
                tier          = 'stop'
                message       = ('Changed paths violate contract: ' + (($scope.violations) -join ', '))
                stdoutPath    = $(if (Test-Path $stdoutPath) { $stdoutPath } else { $null })
                stderrPath    = $(if (Test-Path $stderrPath) { $stderrPath } else { $null })
                exitCode      = 2
            }
            Save-LoomImplementationResult -RunDir $runDir -Result $record | Out-Null
            Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'blocked' -Reason 'scope-violation' | Out-Null
            throw $record.message
        }

        $record = [PSCustomObject]@{
            schemaVersion = 1
            status        = 'completed'
            failureClass  = 'none'
            tier          = $null
            message       = 'Implementer completed; path scope OK; no commit (Slice 3).'
            stdoutPath    = $(if (Test-Path $stdoutPath) { $stdoutPath } else { $null })
            stderrPath    = $(if (Test-Path $stderrPath) { $stderrPath } else { $null })
            exitCode      = 0
            changedPaths  = @($changed)
        }
        Save-LoomImplementationResult -RunDir $runDir -Result $record | Out-Null

        $reviewing = Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'reviewing' -Reason 'implementer-complete' -Mutator {
            param($i)
            $i.evidence = @($i.evidence) + @([PSCustomObject]@{
                type    = 'implementation'
                runDir  = $runDir
                at      = (Get-Date).ToString('o')
            })
            return $i
        }

        return [PSCustomObject]@{
            dryRun       = $false
            itemId       = $ItemId
            runDir       = $runDir
            branch       = $branch
            baselineSha  = $baselineSha
            changedPaths = @($changed)
            result       = $record
            status       = [string]$reviewing.status
        }
    }
    catch {
        if ($gitRunActive) {
            Restore-LoomGitAfterFailedRun -ProjectRoot $projectRoot -BaselineSha $baselineSha `
                -OriginalBranch $originalBranch -ItemBranch $branch `
                -BeforeUntracked @($beforeUntracked) -RunDir $runDir
        }
        if ($_.Exception.Message -notmatch '^(Git working tree|Implementer|Changed paths)') {
            try {
                $cur = Get-MetraLoomQueueItem -Root $Root -Id $ItemId
                if ($cur -and @('claimed', 'implementing') -contains [string]$cur.status) {
                    Invoke-MetraLoomStateChange -Root $Root -ItemId $ItemId -From ([string]$cur.status) -To 'blocked' -Reason 'run-exception' | Out-Null
                }
            }
            catch { }
        }
        throw
    }
}
