# Slice 3 — branch runner (clean tree, isolated run dir, implementer, path enforcement; no commit).

function Get-AutoProgramActiveTransitionMap {
    [CmdletBinding()]
    param()

    return @{
        '@new'         = @('queued')
        'queued'       = @('claimed', 'blocked')
        'claimed'      = @('implementing', 'blocked', 'failed')
        'implementing' = @('reviewing', 'blocked', 'failed')
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

function Get-AutoProgramSlice3Transitions {
    return Get-AutoProgramActiveTransitionMap
}

function Invoke-AutoProgramGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string[]]$GitArgs
    )

    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
        throw "Project root is not a git repository: $ProjectRoot"
    }
    $argList = @('-C', $ProjectRoot) + @($GitArgs)
    $merged = & git @argList 2>&1 | ForEach-Object { "$_" }
    $stdout = ($merged -join "`n")
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Stdout   = $stdout
        Stderr   = ''
    }
}

function Test-AutoProgramGitWorkingTreeClean {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $r = Invoke-AutoProgramGit -ProjectRoot $ProjectRoot -GitArgs @('status', '--porcelain')
    if ($r.ExitCode -ne 0) {
        throw "git status failed in ${ProjectRoot}: $($r.Stderr)"
    }
    return [string]::IsNullOrWhiteSpace($r.Stdout)
}

function Get-AutoProgramGitHeadCommit {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $r = Invoke-AutoProgramGit -ProjectRoot $ProjectRoot -GitArgs @('rev-parse', 'HEAD')
    if ($r.ExitCode -ne 0) { throw "git rev-parse HEAD failed: $($r.Stderr)" }
    return ($r.Stdout.Trim())
}

function Get-AutoProgramGitChangedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    $r = Invoke-AutoProgramGit -ProjectRoot $ProjectRoot -GitArgs @('status', '--porcelain')
    if ($r.ExitCode -ne 0) {
        throw "git status failed: $($r.Stderr)"
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

function Test-AutoProgramChangedPathsAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$ChangedPaths,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string[]]$AllowedPaths = @(),
        [string[]]$ForbiddenPaths = @()
    )

    $violations = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @($ChangedPaths)) {
        $norm = ($rel -replace '\\', '/').TrimStart('./')
        foreach ($fb in @($ForbiddenPaths)) {
            $fbNorm = ($fb -replace '\\', '/').TrimStart('./')
            if ($norm -like "$fbNorm*" -or $norm -eq $fbNorm) {
                [void]$violations.Add("forbidden:$norm")
            }
        }
        if (@($AllowedPaths).Count -eq 0) { continue }
        $ok = $false
        foreach ($ap in @($AllowedPaths)) {
            $apNorm = ($ap -replace '\\', '/').TrimStart('./')
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

function Get-AutoProgramImplementerFailureClass {
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

function Get-MetraAutoprogramRunDirectory {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [int]$RunNumber = 1
    )
    return Join-Path (Join-Path (Join-Path $Root 'runs') $ItemId) ('run-{0:D3}' -f $RunNumber)
}

function Get-MetraAutoprogramNextRunNumber {
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

function New-AutoProgramRunRequestPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Item,
        [Parameter(Mandatory)][string]$RunDir,
        [string]$MetraRoot = (Get-AutoProgramHostRoot)
    )

    $planBody = $null
    $planPath = [string](Get-AutoProgramProp -Object $Item.source -Name 'path' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($planPath) -and (Test-Path -LiteralPath $planPath)) {
        $planBody = [System.IO.File]::ReadAllText($planPath, (Get-AutoProgramUtf8NoBomEncoding))
    }

    $projectRoot = [string](Get-AutoProgramProp -Object $Item.project -Name 'root' -Default '')
    if ([string]::IsNullOrWhiteSpace($projectRoot)) {
        $projectRoot = $MetraRoot
    }

    $allowed = @()
    $contract = $Item.contract
    if ($contract) {
        $allowed = @($(Get-AutoProgramProp -Object $contract -Name 'allowedPaths' -Default @()))
    }

    $pkg = [ordered]@{
        schemaVersion = 1
        itemId        = [string]$Item.id
        summary       = [string]$Item.summary
        projectRoot   = $projectRoot
        registryName  = [string](Get-AutoProgramProp -Object $Item.project -Name 'registryName' -Default '')
        branch        = [string](Get-AutoProgramProp -Object $Item.execution -Name 'branch' -Default '')
        allowedPaths  = @($allowed)
        forbiddenPaths = @($(Get-AutoProgramProp -Object $contract -Name 'forbiddenPaths' -Default @()))
        doneWhen      = @($(Get-AutoProgramProp -Object $contract -Name 'doneWhen' -Default @()))
        verifyCommands = @($(Get-AutoProgramProp -Object $contract -Name 'verifyCommands' -Default @()))
        source        = $Item.source
        planPath      = $planPath
        planBody      = $planBody
        createdAt     = (Get-Date).ToString('o')
    }

    if (-not (Test-Path -LiteralPath $RunDir)) {
        [void][System.IO.Directory]::CreateDirectory($RunDir)
    }
    $reqPath = Join-Path $RunDir 'request.json'
    Write-AutoProgramAtomicUtf8Text -Path $reqPath -Text (($pkg | ConvertTo-Json -Depth 12) + "`n")
    return [PSCustomObject]$pkg
}

function Invoke-AutoProgramGitCreateItemBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BranchName
    )

    $co = Invoke-AutoProgramGit -ProjectRoot $ProjectRoot -GitArgs @('checkout', '-b', $BranchName)
    if ($co.ExitCode -ne 0) {
        throw "git checkout -b failed: $($co.Stdout)"
    }
    return $BranchName
}

function Save-AutoProgramImplementationResult {
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
    Test-AutoProgramContract -Schema 'implementation-result' -Object $toValidate | Out-Null
    $path = Join-Path $RunDir 'implementation.json'
    Write-AutoProgramAtomicUtf8Text -Path $path -Text (($Result | ConvertTo-Json -Depth 8) + "`n")
    return $path
}

function Invoke-MetraAutoprogramRun {
    <#
    .SYNOPSIS
        Slice 3 branch runner: clean tree, branch, run dir, one implementer pass, path enforcement (no commit).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ItemId,
        [string]$MetraRoot = (Get-AutoProgramHostRoot),
        [switch]$DryRun,
        [switch]$Confirm,
        [scriptblock]$ImplementerScript
    )

    $item = Get-MetraAutoprogramQueueItem -Root $Root -Id $ItemId
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

    $runNum = Get-MetraAutoprogramNextRunNumber -Root $Root -ItemId $ItemId
    $runDir = Get-MetraAutoprogramRunDirectory -Root $Root -ItemId $ItemId -RunNumber $runNum

    if ($DryRun) {
        $pkg = New-AutoProgramRunRequestPackage -Item $item -RunDir $runDir -MetraRoot $MetraRoot
        $impl = [PSCustomObject]@{
            schemaVersion = 1
            status        = 'dry-run'
            message       = 'Dry run — no git branch or implementer invocation.'
            exitCode      = 0
        }
        Save-AutoProgramImplementationResult -RunDir $runDir -Result $impl | Out-Null
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

    if (-not (Test-AutoProgramGitWorkingTreeClean -ProjectRoot $projectRoot)) {
        $blocked = Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'queued' -To 'blocked' `
            -Reason 'dirty-git-baseline'
        throw "Git working tree is not clean in $projectRoot; item blocked."
    }

    $baselineSha = Get-AutoProgramGitHeadCommit -ProjectRoot $projectRoot
    $claimed = Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'queued' -To 'claimed' -Reason 'run-start' -Mutator {
        param($i)
        if (-not $i.execution) { $i | Add-Member -NotePropertyName execution -NotePropertyValue ([PSCustomObject]@{}) -Force }
        $i.execution | Add-Member -NotePropertyName baselineSha -NotePropertyValue $baselineSha -Force
        $i.execution | Add-Member -NotePropertyName runNumber -NotePropertyValue $runNum -Force
        $i.execution | Add-Member -NotePropertyName runDir -NotePropertyValue $runDir -Force
        return $i
    }

    try {
        Invoke-AutoProgramGitCreateItemBranch -ProjectRoot $projectRoot -BranchName $branch

        $pkg = New-AutoProgramRunRequestPackage -Item $claimed -RunDir $runDir -MetraRoot $MetraRoot
        $stdoutPath = Join-Path $runDir 'stdout.log'
        $stderrPath = Join-Path $runDir 'stderr.log'

        $implementing = Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'claimed' -To 'implementing' -Reason 'implementer-start'

        $implResult = Invoke-AutoProgramImplementerAdapter -Request $pkg -ProjectRoot $projectRoot -RunDir $runDir -ImplementerScript $ImplementerScript

        $stdoutText = [string](Get-AutoProgramProp -Object $implResult -Name 'stdout' -Default '')
        $stderrText = [string](Get-AutoProgramProp -Object $implResult -Name 'stderr' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($stdoutText)) {
            Write-AutoProgramAtomicUtf8Text -Path $stdoutPath -Text $stdoutText
        }
        if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
            Write-AutoProgramAtomicUtf8Text -Path $stderrPath -Text $stderrText
        }

        $failureClass = Get-AutoProgramImplementerFailureClass -Message ([string](Get-AutoProgramProp -Object $implResult -Name 'message' -Default '')) -ExitCode ([int](Get-AutoProgramProp -Object $implResult -Name 'exitCode' -Default -1))
        $status = [string](Get-AutoProgramProp -Object $implResult -Name 'status' -Default 'failed')

        if ($status -ne 'ok' -and $status -ne 'completed') {
            $record = [PSCustomObject]@{
                schemaVersion = 1
                status        = 'failed'
                failureClass  = $failureClass.failureClass
                tier          = $failureClass.tier
                message       = [string](Get-AutoProgramProp -Object $implResult -Name 'message' -Default '')
                stdoutPath    = $(if (Test-Path $stdoutPath) { $stdoutPath } else { $null })
                stderrPath    = $(if (Test-Path $stderrPath) { $stderrPath } else { $null })
                exitCode      = [int](Get-AutoProgramProp -Object $implResult -Name 'exitCode' -Default 1)
            }
            Save-AutoProgramImplementationResult -RunDir $runDir -Result $record | Out-Null

            if ($failureClass.failureClass -eq 'licensing_error' -or $failureClass.failureClass -eq 'adapter-unavailable') {
                Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'blocked' -Reason $failureClass.failureClass | Out-Null
                throw "Implementer blocked ($($failureClass.failureClass)): $($implResult.message)"
            }
            if ($failureClass.retryable) {
                Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'claimed' -Reason 'implementer-transient-retry' | Out-Null
                throw "Implementer transient failure (retry allowed): $($implResult.message)"
            }
            Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'failed' -Reason $failureClass.failureClass | Out-Null
            throw "Implementer failed: $($implResult.message)"
        }

        $changed = @(Get-AutoProgramGitChangedPaths -ProjectRoot $projectRoot)
        $contract = $implementing.contract
        $scope = Test-AutoProgramChangedPathsAllowed -ChangedPaths $changed -ProjectRoot $projectRoot `
            -AllowedPaths @($(Get-AutoProgramProp -Object $contract -Name 'allowedPaths' -Default @())) `
            -ForbiddenPaths @($(Get-AutoProgramProp -Object $contract -Name 'forbiddenPaths' -Default @()))

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
            Save-AutoProgramImplementationResult -RunDir $runDir -Result $record | Out-Null
            Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'blocked' -Reason 'scope-violation' | Out-Null
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
        Save-AutoProgramImplementationResult -RunDir $runDir -Result $record | Out-Null

        $reviewing = Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From 'implementing' -To 'reviewing' -Reason 'implementer-complete' -Mutator {
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
        if ($_.Exception.Message -notmatch '^(Git working tree|Implementer|Changed paths)') {
            try {
                $cur = Get-MetraAutoprogramQueueItem -Root $Root -Id $ItemId
                if ($cur -and @('claimed', 'implementing') -contains [string]$cur.status) {
                    Invoke-MetraAutoprogramStateChange -Root $Root -ItemId $ItemId -From ([string]$cur.status) -To 'blocked' -Reason 'run-exception' | Out-Null
                }
            }
            catch { }
        }
        throw
    }
}
