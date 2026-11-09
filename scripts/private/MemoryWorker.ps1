# MemoryWorker.ps1 - detached Ask summary / brief queue (Bite 2+).
# Queue is append-only jsonl; workers may repeat computation but must not regress
# ask-summary lastSummarizedTurnIndex or apply duplicate logical updates.

function Get-MetraAskContinuitySettings {
    <#
    .SYNOPSIS
        Reads ask.continuity.* kill switches from metra.config.json (defaults on).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $cfg = $null
    $configPath = Get-MetraAskConfigPath -MetraRoot $MetraRoot
    $moduleRoot = Get-MetraRoot
    if ($MetraRoot -eq $moduleRoot) {
        try { $cfg = Get-MetraConfig } catch { $cfg = $null }
    }
    if ($null -eq $cfg -and (Test-Path -LiteralPath $configPath)) {
        try { $cfg = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json } catch { $cfg = $null }
    }
    $ask = Get-MetraProp -Object $cfg -Name 'ask' -Default $null
    $continuity = Get-MetraProp -Object $ask -Name 'continuity' -Default $null
    $modelSummary = Get-MetraProp -Object $continuity -Name 'modelSummary' -Default $null
    $brief = Get-MetraProp -Object $ask -Name 'brief' -Default $null
    if ($null -eq $brief) {
        $brief = Get-MetraProp -Object $continuity -Name 'brief' -Default $null
    }

    $modelEnabled = $true
    if ($null -ne $modelSummary) {
        $modelEnabled = [bool](Get-MetraProp -Object $modelSummary -Name 'enabled' -Default $true)
    }
    $briefEnabled = $true
    if ($null -ne $brief) {
        $briefEnabled = [bool](Get-MetraProp -Object $brief -Name 'enabled' -Default $true)
    }

    return [PSCustomObject]@{
        modelSummaryEnabled = $modelEnabled
        briefEnabled        = $briefEnabled
        summaryEveryTurns   = 8
    }
}

function Test-MetraAskModelSummaryEnabled {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return [bool]((Get-MetraAskContinuitySettings -MetraRoot $MetraRoot).modelSummaryEnabled)
}

function Get-MetraAskSummaryRefreshInterval {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $n = [int](Get-MetraAskContinuitySettings -MetraRoot $MetraRoot).summaryEveryTurns
    if ($n -lt 1) { return 8 }
    return $n
}

function Read-MetraAskSummaryCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraAskSummaryCachePath -SessionId $SessionId -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    catch {
        return $null
    }
    return [PSCustomObject]@{
        sessionId               = [string](Get-MetraProp -Object $raw -Name 'sessionId' -Default $SessionId)
        text                    = [string](Get-MetraProp -Object $raw -Name 'text' -Default '')
        lastSummarizedTurnIndex = [int](Get-MetraProp -Object $raw -Name 'lastSummarizedTurnIndex' -Default 0)
        sourceRevision          = [string](Get-MetraProp -Object $raw -Name 'sourceRevision' -Default '')
        updatedAt               = [string](Get-MetraProp -Object $raw -Name 'updatedAt' -Default '')
        engine                  = [string](Get-MetraProp -Object $raw -Name 'engine' -Default '')
        model                   = [string](Get-MetraProp -Object $raw -Name 'model' -Default '')
        derived                 = $true
    }
}

function Write-MetraAskSummaryCache {
    <#
    .SYNOPSIS
        Monotonic write of ask-summary cache. Rejects stale lastSummarizedTurnIndex.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$LastSummarizedTurnIndex,
        [string]$SourceRevision = '',
        [string]$Engine = '',
        [string]$Model = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ($LastSummarizedTurnIndex -lt 1) {
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = 'invalid_turn_index'
            Written = $false
            Cache   = $null
        }
    }

    return Invoke-MetraWithNamedMutex -Name 'ask-summary' -Script {
        $path = Get-MetraAskSummaryCachePath -SessionId $SessionId -MetraRoot $MetraRoot
        $current = Read-MetraAskSummaryCache -SessionId $SessionId -MetraRoot $MetraRoot
        $currentIdx = 0
        if ($null -ne $current) {
            $currentIdx = [int]$current.lastSummarizedTurnIndex
        }
        if ($LastSummarizedTurnIndex -le $currentIdx) {
            return [PSCustomObject]@{
                Ok      = $true
                Reason  = 'stale_or_duplicate'
                Written = $false
                Cache   = $current
            }
        }

        $payload = [ordered]@{
            schemaVersion           = 1
            sessionId               = $SessionId.Trim()
            text                    = [string]$Text
            lastSummarizedTurnIndex = [int]$LastSummarizedTurnIndex
            sourceRevision          = [string]$SourceRevision
            updatedAt               = (Get-Date).ToUniversalTime().ToString('o')
            engine                  = $(if ([string]::IsNullOrWhiteSpace($Engine)) { $null } else { $Engine })
            model                   = $(if ([string]::IsNullOrWhiteSpace($Model)) { $null } else { $Model })
            derived                 = $true
        }
        $json = ($payload | ConvertTo-Json -Depth 6 -Compress)
        $dir = Split-Path -Parent $path
        [void][System.IO.Directory]::CreateDirectory($dir)
        $tmp = Join-Path $dir (([IO.Path]::GetFileName($path)) + '.tmp.' + [guid]::NewGuid().ToString('n'))
        [System.IO.File]::WriteAllText($tmp, $json + "`n", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Copy($tmp, $path, $true)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        $written = Read-MetraAskSummaryCache -SessionId $SessionId -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Ok      = $true
            Reason  = 'written'
            Written = $true
            Cache   = $written
        }
    }
}

function Get-MetraAskSummarySourceRevision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Turns,
        [int]$ThroughTurnIndex
    )

    $sb = [System.Text.StringBuilder]::new()
    foreach ($t in @($Turns)) {
        $ti = [int](Get-MetraProp -Object $t -Name 'turnIndex' -Default 0)
        if ($ti -lt 1 -or $ti -gt $ThroughTurnIndex) { continue }
        [void]$sb.Append($ti).Append('|')
        [void]$sb.Append([string](Get-MetraProp -Object $t -Name 'prompt' -Default '')).Append('|')
        [void]$sb.Append([string](Get-MetraProp -Object $t -Name 'message' -Default '')).Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Select-MetraAskSummaryCitedLines {
    <#
    .SYNOPSIS
        Keep only summary lines that cite an allowed Turn N; drop invented indexes.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [int[]]$AllowedTurnIndexes = @()
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $allow = @($AllowedTurnIndexes | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    $kept = foreach ($line in @($Text -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t -or $t -match '^\s*#') { continue }
        if ($t -notmatch '(?i)\bTurn\s+(\d+)\b') { continue }
        $n = [int]$Matches[1]
        if ($allow.Count -gt 0 -and ($allow -notcontains $n)) { continue }
        $t
    }
    return (($kept -join "`n").Trim())
}

function Test-MetraAskSummaryCitations {
    <#
    .SYNOPSIS
        True when every non-empty summary line cites a Turn N marker in AllowedTurnIndexes.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [int[]]$AllowedTurnIndexes = @()
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $lines = @(
        $Text -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and ($_ -notmatch '^\s*#') }
    )
    if ($lines.Count -eq 0) { return $false }
    $allow = @($AllowedTurnIndexes | Where-Object { $_ -gt 0 } | Select-Object -Unique)
    foreach ($line in $lines) {
        if ($line -notmatch '(?i)\bTurn\s+(\d+)\b') { return $false }
        $n = [int]$Matches[1]
        if ($allow.Count -gt 0 -and ($allow -notcontains $n)) { return $false }
    }
    return $true
}

function New-MetraAskExtractiveCitedSummary {
    <#
    .SYNOPSIS
        Fallback / mock-friendly extractive summary where every line cites a turn.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Turns,
        [int]$MaxBullets = 12,
        [int]$HeadCount = 3
    )

    return (New-MetraAskSessionSummaryText -Turns $Turns -MaxBullets $MaxBullets -HeadCount $HeadCount)
}

function Invoke-MetraAskSessionSummarizer {
    <#
    .SYNOPSIS
        Model-written Ask session summary via Inspect pin (ask-fallback when unset).
    .NOTES
        Derived evidence only. On failure/timeout returns Ok=false; callers keep extractive path.
        Tests may inject -SummarizerScript (including a hang mock that never returns).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Turns,
        [AllowNull()][string]$PriorSummary,
        [Parameter(Mandatory)][int]$ThroughTurnIndex,
        [scriptblock]$SummarizerScript,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 90
    )

    $scoped = @(
        $Turns | Where-Object {
            $ti = [int](Get-MetraProp -Object $_ -Name 'turnIndex' -Default 0)
            $ti -ge 1 -and $ti -le $ThroughTurnIndex
        }
    )
    if ($scoped.Count -eq 0) {
        return [PSCustomObject]@{
            Ok       = $false
            Reason   = 'no_turns'
            Text     = ''
            Engine   = ''
            Model    = ''
            CitedOk  = $false
        }
    }

    $allowed = @($scoped | ForEach-Object { [int](Get-MetraProp -Object $_ -Name 'turnIndex' -Default 0) })

    if ($null -ne $SummarizerScript) {
        $text = & $SummarizerScript -SessionId $SessionId -Turns $scoped -PriorSummary $PriorSummary -ThroughTurnIndex $ThroughTurnIndex
        $cited = Test-MetraAskSummaryCitations -Text ([string]$text) -AllowedTurnIndexes $allowed
        return [PSCustomObject]@{
            Ok      = $cited
            Reason  = $(if ($cited) { 'mock' } else { 'mock_uncited' })
            Text    = [string]$text
            Engine  = 'mock'
            Model   = 'mock'
            CitedOk = $cited
        }
    }

    # Detached-worker / integration test hook (no live engine).
    $envMock = [string]$env:METRA_MEMORY_WORKER_MOCK
    if ($envMock -eq 'cited') {
        $text = New-MetraAskExtractiveCitedSummary -Turns $scoped
        $cited = Test-MetraAskSummaryCitations -Text $text -AllowedTurnIndexes $allowed
        return [PSCustomObject]@{
            Ok      = $cited
            Reason  = 'env_mock_cited'
            Text    = $text
            Engine  = 'env-mock'
            Model   = 'cited'
            CitedOk = $cited
            Path    = 'env-mock'
        }
    }
    if ($envMock -eq 'hang') {
        Start-Sleep -Seconds ([Math]::Max(600, $TimeoutSec + 60))
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = 'env_mock_hang'
            Text    = ''
            Engine  = 'env-mock'
            Model   = 'hang'
            CitedOk = $false
            Path    = 'hang'
        }
    }

    $override = $null
    if (Get-Variable -Name MetraAskSummarizerOverride -Scope Script -ErrorAction SilentlyContinue) {
        $override = $script:MetraAskSummarizerOverride
    }
    if ($override -is [scriptblock]) {
        $text = & $override -SessionId $SessionId -Turns $scoped -PriorSummary $PriorSummary -ThroughTurnIndex $ThroughTurnIndex
        $cited = Test-MetraAskSummaryCitations -Text ([string]$text) -AllowedTurnIndexes $allowed
        return [PSCustomObject]@{
            Ok      = $cited
            Reason  = $(if ($cited) { 'override' } else { 'override_uncited' })
            Text    = [string]$text
            Engine  = 'override'
            Model   = 'override'
            CitedOk = $cited
        }
    }

    $selection = $null
    if (Get-Command Resolve-MetraInspectEngineSelection -ErrorAction SilentlyContinue) {
        $selection = Resolve-MetraInspectEngineSelection -MetraRoot $MetraRoot
    }
    $engine = 'ollama'
    $model = ''
    if ($null -ne $selection) {
        $engine = [string](Get-MetraProp -Object $selection -Name 'Engine' -Default 'ollama')
        $model = [string](Get-MetraProp -Object $selection -Name 'RequestedModel' -Default '')
    }

    $turnBlock = New-MetraAskExtractiveCitedSummary -Turns $scoped -MaxBullets 24 -HeadCount 3
    $prior = if ([string]::IsNullOrWhiteSpace($PriorSummary)) { '(none)' } else { $PriorSummary.Trim() }
    # Same secret scrub as journal - never send raw secrets into the summarizer prompt.
    if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
        $prior = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $prior) -Name 'Text' -Default $prior)
        $turnBlock = [string](Get-MetraProp -Object (Invoke-MetraAskSecretsScrubText -Text $turnBlock) -Name 'Text' -Default $turnBlock)
    }
    $configSource = [string](Get-MetraProp -Object $selection -Name 'ConfigurationSource' -Default '')
    if ([string]::IsNullOrWhiteSpace($configSource)) {
        $configSource = [string](Get-MetraProp -Object $selection -Name 'configurationSource' -Default '')
    }
    $prompt = @"
You compress Metra Ask session journal turns into a short derived summary.
Rules:
- Output plain text bullets only. No markdown fences. No preamble.
- Every line MUST cite a turn as "Turn N:" using only turns present below.
- Do not invent facts. Prefer durable project/routing facts over chit-chat.
- Keep under 1200 characters.

Prior summary:
$prior

Turns through ${ThroughTurnIndex}:
$turnBlock
"@

    $extractiveFallback = {
        $ex = New-MetraAskExtractiveCitedSummary -Turns $scoped
        $exCited = Test-MetraAskSummaryCitations -Text $ex -AllowedTurnIndexes $allowed
        return [PSCustomObject]@{
            Ok      = $exCited
            Reason  = $(if ($exCited) { 'extractive_fallback' } else { 'uncited' })
            Text    = $ex
            Engine  = $engine
            Model   = $model
            CitedOk = $exCited
            Path    = 'extractive'
        }
    }

    if (-not (Get-Command Invoke-MetraAskEngine -ErrorAction SilentlyContinue)) {
        $fb = & $extractiveFallback
        $fb.Reason = 'engine_unavailable_extractive'
        return $fb
    }

    try {
        $engineResult = Invoke-MetraAskEngine -Prompt $prompt -Cwd $MetraRoot -MetraRoot $MetraRoot `
            -Context @{ purpose = 'metra-ask-summary'; sessionId = $SessionId } `
            -TimeoutSec $TimeoutSec -Engine $engine -Model $model
    }
    catch {
        $fb = & $extractiveFallback
        $fb.Reason = 'engine_throw_extractive'
        return $fb
    }

    if (-not [bool](Get-MetraProp -Object $engineResult -Name 'ok' -Default $false)) {
        $fb = & $extractiveFallback
        $fb.Engine = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default $engine)
        $fb.Model = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default $model)
        $fb.Reason = 'engine_failed_extractive'
        return $fb
    }

    $text = [string](Get-MetraProp -Object $engineResult -Name 'text' -Default '')
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = [string](Get-MetraProp -Object $engineResult -Name 'message' -Default '')
    }
    if (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue) {
        $scrubbed = Invoke-MetraAskSecretsScrubText -Text $text
        $text = [string](Get-MetraProp -Object $scrubbed -Name 'Text' -Default $text)
    }
    # Drop lines that cite nonexistent turns; keep valid citations.
    $text = Select-MetraAskSummaryCitedLines -Text $text -AllowedTurnIndexes $allowed
    $cited = Test-MetraAskSummaryCitations -Text $text -AllowedTurnIndexes $allowed
    if (-not $cited) {
        $fb = & $extractiveFallback
        $fb.Engine = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default $engine)
        $fb.Model = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default $model)
        return $fb
    }

    $pathLabel = if ($configSource -match '(?i)ask-fallback|ask_fallback') { 'ask-fallback' } else { 'inspect-pin' }
    return [PSCustomObject]@{
        Ok      = $true
        Reason  = 'model'
        Text    = $text.Trim()
        Engine  = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default $engine)
        Model   = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default $model)
        CitedOk = $true
        Path    = $pathLabel
    }
}

function New-MetraMemoryQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ask-summary', 'project-brief')][string]$Type,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][int]$ThroughTurnIndex,
        [string]$Project = '',
        [string]$SourceRevision = '',
        [datetime]$QueuedAt = (Get-Date).ToUniversalTime()
    )

    return [PSCustomObject]@{
        id               = [guid]::NewGuid().ToString('N')
        type             = $Type
        sessionId        = $SessionId.Trim()
        project          = $(if ([string]::IsNullOrWhiteSpace($Project)) { $null } else { $Project.Trim() })
        throughTurnIndex = [int]$ThroughTurnIndex
        sourceRevision   = [string]$SourceRevision
        queuedAt         = $QueuedAt.ToUniversalTime().ToString('o')
        status           = 'pending'
        attempts         = 0
    }
}

function Add-MetraMemoryQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    return Invoke-MetraWithNamedMutex -Name 'memory-queue' -Script {
        $path = Get-MetraOpsMemoryQueuePath -MetraRoot $MetraRoot
        $type = [string](Get-MetraProp -Object $Item -Name 'type' -Default '')
        $sid = [string](Get-MetraProp -Object $Item -Name 'sessionId' -Default '')
        $through = [int](Get-MetraProp -Object $Item -Name 'throughTurnIndex' -Default 0)
        $rev = [string](Get-MetraProp -Object $Item -Name 'sourceRevision' -Default '')

        # Dedupe pending twin for same type/session/through/revision.
        $pending = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending)
        foreach ($p in $pending) {
            if ([string](Get-MetraProp -Object $p -Name 'type' -Default '') -ne $type) { continue }
            if ([string](Get-MetraProp -Object $p -Name 'sessionId' -Default '') -ne $sid) { continue }
            if ([int](Get-MetraProp -Object $p -Name 'throughTurnIndex' -Default 0) -ne $through) { continue }
            if ([string](Get-MetraProp -Object $p -Name 'sourceRevision' -Default '') -ne $rev) { continue }
            return [PSCustomObject]@{
                Ok      = $true
                Reason  = 'duplicate_pending'
                Queued  = $false
                Item    = $p
            }
        }

        $line = ($Item | ConvertTo-Json -Depth 6 -Compress)
        [System.IO.File]::AppendAllText($path, $line + "`n", [System.Text.UTF8Encoding]::new($false))
        return [PSCustomObject]@{
            Ok     = $true
            Reason = 'queued'
            Queued = $true
            Item   = $Item
        }
    }
}

function Get-MetraMemoryQueueItems {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [ValidateSet('pending', 'done', 'failed', 'all')]
        [string]$Status = 'all'
    )

    $path = Get-MetraOpsMemoryQueuePath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
        }
        catch { continue }
        $st = [string](Get-MetraProp -Object $obj -Name 'status' -Default 'pending')
        if ($Status -ne 'all' -and $st -ne $Status) { continue }
        [void]$rows.Add($obj)
    }
    return @($rows)
}

function Set-MetraMemoryQueueItemStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('pending', 'done', 'failed')][string]$Status,
        [string]$Detail = '',
        [int]$Attempts = -1,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    return Invoke-MetraWithNamedMutex -Name 'memory-queue' -Script {
        $path = Get-MetraOpsMemoryQueuePath -MetraRoot $MetraRoot
        if (-not (Test-Path -LiteralPath $path)) {
            return [PSCustomObject]@{ Ok = $false; Reason = 'missing_queue' }
        }
        $out = [System.Collections.Generic.List[string]]::new()
        $found = $false
        foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json
            }
            catch {
                [void]$out.Add($line)
                continue
            }
            $rowId = [string](Get-MetraProp -Object $obj -Name 'id' -Default '')
            if ($rowId -eq $Id) {
                $found = $true
                $obj | Add-Member -NotePropertyName status -NotePropertyValue $Status -Force
                if ($Status -in @('done', 'failed')) {
                    $obj | Add-Member -NotePropertyName completedAt -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
                }
                if (-not [string]::IsNullOrWhiteSpace($Detail)) {
                    $obj | Add-Member -NotePropertyName detail -NotePropertyValue $Detail -Force
                }
                if ($Attempts -ge 0) {
                    $obj | Add-Member -NotePropertyName attempts -NotePropertyValue $Attempts -Force
                }
                [void]$out.Add((($obj | ConvertTo-Json -Depth 6 -Compress)))
            }
            else {
                [void]$out.Add(($obj | ConvertTo-Json -Depth 6 -Compress))
            }
        }
        [System.IO.File]::WriteAllLines($path, @($out), [System.Text.UTF8Encoding]::new($false))
        return [PSCustomObject]@{ Ok = $found; Reason = $(if ($found) { 'updated' } else { 'not_found' }) }
    }
}

function Request-MetraAskSummaryRefreshIfDue {
    <#
    .SYNOPSIS
        Enqueue ask-summary when turnIndex hits K=8 boundaries. Never blocks Ask.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][int]$ThroughTurnIndex,
        [string]$Project = '',
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$StartWorker
    )

    if (-not (Test-MetraAskModelSummaryEnabled -MetraRoot $MetraRoot)) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'disabled'; Queued = $false }
    }
    $k = Get-MetraAskSummaryRefreshInterval -MetraRoot $MetraRoot
    if ($ThroughTurnIndex -lt $k -or ($ThroughTurnIndex % $k) -ne 0) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'not_due'; Queued = $false }
    }

    $cache = Read-MetraAskSummaryCache -SessionId $SessionId -MetraRoot $MetraRoot
    if ($null -ne $cache -and [int]$cache.lastSummarizedTurnIndex -ge $ThroughTurnIndex) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'already_current'; Queued = $false }
    }

    $turns = @(Get-MetraDeskAskSessionTurns -SessionId $SessionId -MetraRoot $MetraRoot -Limit 0)
    $rev = Get-MetraAskSummarySourceRevision -Turns $turns -ThroughTurnIndex $ThroughTurnIndex
    $item = New-MetraMemoryQueueItem -Type ask-summary -SessionId $SessionId `
        -ThroughTurnIndex $ThroughTurnIndex -Project $Project -SourceRevision $rev
    $queued = Add-MetraMemoryQueueItem -Item $item -MetraRoot $MetraRoot
    if ($StartWorker -or [bool]$queued.Queued) {
        Start-MetraMemoryWorkerBestEffort -MetraRoot $MetraRoot | Out-Null
    }
    return $queued
}

function Get-MetraAskSummaryItemTimeoutSec {
    [CmdletBinding()]
    param()
    $raw = [string]$env:METRA_ASK_SUMMARY_TIMEOUT_SEC
    if ($raw -match '^\d+$') {
        $n = [int]$raw
        if ($n -ge 1) { return $n }
    }
    return 90
}

function Get-MetraMemoryWorkerMaxHoldSec {
    [CmdletBinding()]
    param()
    $raw = [string]$env:METRA_MEMORY_WORKER_MAX_HOLD_SEC
    if ($raw -match '^\d+$') {
        $n = [int]$raw
        if ($n -ge 1) { return $n }
    }
    return 300
}

function Get-MetraMemoryWorkerLeasePath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $dir = Join-Path (Get-MetraMachineDataRoot -MetraRoot $MetraRoot) 'ops'
    [void][System.IO.Directory]::CreateDirectory($dir)
    return Join-Path $dir 'memory-worker.lease.json'
}

function Get-MetraMemoryWorkerProcessFingerprint {
    <#
    .SYNOPSIS
        PID + ProcessName + Process.StartTime for lease identity (PID reuse safe).
    #>
    [CmdletBinding()]
    param([int]$ProcessId = $PID)
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $null }
    $startUtc = ''
    try {
        $startUtc = $p.StartTime.ToUniversalTime().ToString('o')
    }
    catch {
        $startUtc = ''
    }
    return [PSCustomObject]@{
        Pid                 = $ProcessId
        ProcessName         = [string]$p.ProcessName
        ProcessStartTimeUtc = $startUtc
        Process             = $p
    }
}

function Test-MetraMemoryWorkerLeaseMatchesProcess {
    <#
    .SYNOPSIS
        True only when lease PID still refers to the same process identity we recorded.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)]$Process
    )
    $name = [string](Get-MetraProp -Object $Lease -Name 'processName' -Default '')
    if ([string]::IsNullOrWhiteSpace($name)) { return $false }
    if (-not [string]::Equals($name, [string]$Process.ProcessName, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $leaseStart = [string](Get-MetraProp -Object $Lease -Name 'processStartTimeUtc' -Default '')
    if ([string]::IsNullOrWhiteSpace($leaseStart)) { return $false }
    try {
        $leaseDt = [datetime]::Parse($leaseStart, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $procDt = $Process.StartTime.ToUniversalTime()
        return [math]::Abs(($leaseDt - $procDt).TotalSeconds) -le 2
    }
    catch {
        return $false
    }
}

function Write-MetraMemoryWorkerLease {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $path = Get-MetraMemoryWorkerLeasePath -MetraRoot $MetraRoot
    $fp = Get-MetraMemoryWorkerProcessFingerprint -ProcessId $PID
    $payload = [ordered]@{
        schemaVersion       = 1
        pid                 = $PID
        processName         = $(if ($null -ne $fp) { [string]$fp.ProcessName } else { '' })
        processStartTimeUtc = $(if ($null -ne $fp) { [string]$fp.ProcessStartTimeUtc } else { '' })
        startedAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
    }
    [System.IO.File]::WriteAllText(
        $path,
        (($payload | ConvertTo-Json -Compress) + "`n"),
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Clear-MetraMemoryWorkerLease {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $path = Get-MetraMemoryWorkerLeasePath -MetraRoot $MetraRoot
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Read-MetraMemoryWorkerLease {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $path = Get-MetraMemoryWorkerLeasePath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json)
    }
    catch { return $null }
}

function Test-MetraMemoryWorkerLeaseStale {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$MaxHoldSec = 0
    )
    if ($MaxHoldSec -lt 1) { $MaxHoldSec = Get-MetraMemoryWorkerMaxHoldSec }
    $lease = Read-MetraMemoryWorkerLease -MetraRoot $MetraRoot
    if ($null -eq $lease) {
        return [PSCustomObject]@{
            Stale           = $false
            Reason          = 'no_lease'
            Pid             = 0
            VerifiedWorker  = $false
            AgeSec          = 0
        }
    }
    $pidVal = [int](Get-MetraProp -Object $lease -Name 'pid' -Default 0)
    $started = [string](Get-MetraProp -Object $lease -Name 'startedAtUtc' -Default '')
    $ageSec = 0
    if ($started) {
        try {
            $dt = [datetime]::Parse($started, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $ageSec = [int]([math]::Floor(((Get-Date).ToUniversalTime() - $dt.ToUniversalTime()).TotalSeconds))
        }
        catch { $ageSec = $MaxHoldSec + 1 }
    }
    else {
        $ageSec = $MaxHoldSec + 1
    }

    $proc = $null
    if ($pidVal -gt 0) {
        $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
    }
    if ($null -eq $proc) {
        return [PSCustomObject]@{
            Stale          = $true
            Reason         = 'dead_pid'
            Pid            = $pidVal
            VerifiedWorker = $false
            AgeSec         = $ageSec
        }
    }

    $verified = Test-MetraMemoryWorkerLeaseMatchesProcess -Lease $lease -Process $proc
    if (-not $verified) {
        # PID reused by an unrelated process (or legacy lease without fingerprint).
        return [PSCustomObject]@{
            Stale          = $true
            Reason         = 'dead_pid'
            Pid            = $pidVal
            VerifiedWorker = $false
            AgeSec         = $ageSec
        }
    }
    if ($ageSec -ge $MaxHoldSec) {
        return [PSCustomObject]@{
            Stale          = $true
            Reason         = 'max_hold'
            Pid            = $pidVal
            VerifiedWorker = $true
            AgeSec         = $ageSec
        }
    }
    return [PSCustomObject]@{
        Stale          = $false
        Reason         = 'active'
        Pid            = $pidVal
        VerifiedWorker = $true
        AgeSec         = $ageSec
    }
}

function Invoke-MetraMemoryWorkerReclaimStaleLock {
    <#
    .SYNOPSIS
        If the worker lease is stale, clear it. Stop-Process only a verified worker past max hold.
    .NOTES
        A PID that no longer matches processName/StartTime is treated as dead_pid: clear lease, never kill.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$MaxHoldSec = 0
    )
    $stale = Test-MetraMemoryWorkerLeaseStale -MetraRoot $MetraRoot -MaxHoldSec $MaxHoldSec
    if (-not [bool]$stale.Stale) {
        return [PSCustomObject]@{
            Reclaimed = $false
            Reason    = [string]$stale.Reason
            Pid       = [int]$stale.Pid
            Killed    = $false
        }
    }
    $pidVal = [int]$stale.Pid
    $killed = $false
    $verified = [bool](Get-MetraProp -Object $stale -Name 'VerifiedWorker' -Default $false)
    # Only force-kill a fingerprint-matched worker that exceeded max hold.
    if ($verified -and [string]$stale.Reason -eq 'max_hold' -and $pidVal -gt 0 -and $pidVal -ne $PID) {
        $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
        $lease = Read-MetraMemoryWorkerLease -MetraRoot $MetraRoot
        if ($null -ne $proc -and $null -ne $lease -and
            (Test-MetraMemoryWorkerLeaseMatchesProcess -Lease $lease -Process $proc)) {
            try {
                Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
                $killed = $true
            }
            catch { }
        }
    }
    Clear-MetraMemoryWorkerLease -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Reclaimed = $true
        Reason    = [string]$stale.Reason
        Pid       = $pidVal
        Killed    = $killed
    }
}

function Invoke-MetraSummarizerWithTimeout {
    <#
    .SYNOPSIS
        Hard-timeout wrapper for Ask summarizer work (hang -> item_timeout).
    .NOTES
        Injected -SummarizerScript (tests) and the production Invoke-MetraAskSessionSummarizer
        path both run under Wait-Job -Timeout so a hang cannot hold the worker forever.
    #>
    [CmdletBinding()]
    param(
        [scriptblock]$SummarizerScript,
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Turns,
        [AllowNull()][string]$PriorSummary,
        [Parameter(Mandatory)][int]$ThroughTurnIndex,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 90
    )

    if ($TimeoutSec -lt 1) { $TimeoutSec = 1 }
    $timeoutFail = {
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = 'item_timeout'
            Text    = ''
            Engine  = 'timeout'
            Model   = 'timeout'
            CitedOk = $false
            Path    = 'timeout'
        }
    }

    if ($null -ne $SummarizerScript) {
        $job = Start-Job -ScriptBlock {
            param($sbText, $sid, $turns, $prior, $through)
            $sb = [scriptblock]::Create($sbText)
            & $sb -SessionId $sid -Turns $turns -PriorSummary $prior -ThroughTurnIndex $through
        } -ArgumentList @(
            $SummarizerScript.ToString()
            $SessionId
            @($Turns)
            [string]$PriorSummary
            $ThroughTurnIndex
        )
        try {
            $ok = Wait-Job -Job $job -Timeout $TimeoutSec
            if (-not $ok) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                return (& $timeoutFail)
            }
            $text = Receive-Job -Job $job -ErrorAction SilentlyContinue
            if ($job.State -eq 'Failed') {
                return [PSCustomObject]@{
                    Ok      = $false
                    Reason  = 'exception'
                    Text    = ''
                    Engine  = 'job'
                    Model   = 'job'
                    CitedOk = $false
                }
            }
            return [PSCustomObject]@{
                Ok      = $true
                Reason  = 'mock_timeout_path'
                Text    = [string]$text
                Engine  = 'mock'
                Model   = 'mock'
                CitedOk = $true
                Path    = 'mock'
                RawText = [string]$text
            }
        }
        finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    # Production path (no injected script): always enter through this wrapper.
    # METRA_MEMORY_WORKER_MOCK=hang is hard-bounded here (Start-Job + Wait-Job).
    # Cited mock + live engine run in-process; engine still gets TimeoutSec, and
    # max-hold lease reclaim remains the last backstop for a wedged worker process.
    $envMock = [string]$env:METRA_MEMORY_WORKER_MOCK
    if ($envMock -eq 'hang') {
        $job = Start-Job -ScriptBlock { Start-Sleep -Seconds 600 }
        try {
            $ok = Wait-Job -Job $job -Timeout $TimeoutSec
            if (-not $ok) {
                Stop-Job -Job $job -ErrorAction SilentlyContinue
                return (& $timeoutFail)
            }
            return [PSCustomObject]@{
                Ok      = $false
                Reason  = 'env_mock_hang'
                Text    = ''
                Engine  = 'env-mock'
                Model   = 'hang'
                CitedOk = $false
                Path    = 'hang'
            }
        }
        finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
    }

    $sum = Invoke-MetraAskSessionSummarizer -SessionId $SessionId -Turns $Turns `
        -PriorSummary $PriorSummary -ThroughTurnIndex $ThroughTurnIndex `
        -MetraRoot $MetraRoot -TimeoutSec $TimeoutSec
    $text = [string](Get-MetraProp -Object $sum -Name 'Text' -Default '')
    return [PSCustomObject]@{
        Ok      = [bool](Get-MetraProp -Object $sum -Name 'Ok' -Default $false)
        Reason  = [string](Get-MetraProp -Object $sum -Name 'Reason' -Default '')
        Text    = $text
        Engine  = [string](Get-MetraProp -Object $sum -Name 'Engine' -Default '')
        Model   = [string](Get-MetraProp -Object $sum -Name 'Model' -Default '')
        CitedOk = [bool](Get-MetraProp -Object $sum -Name 'CitedOk' -Default $false)
        Path    = [string](Get-MetraProp -Object $sum -Name 'Path' -Default 'production')
        RawText = $text
    }
}

function Invoke-MetraMemoryAskSummaryJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Item,
        [scriptblock]$SummarizerScript,
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$TimeoutSec = 0
    )

    $sid = [string](Get-MetraProp -Object $Item -Name 'sessionId' -Default '')
    $through = [int](Get-MetraProp -Object $Item -Name 'throughTurnIndex' -Default 0)
    $rev = [string](Get-MetraProp -Object $Item -Name 'sourceRevision' -Default '')
    if ([string]::IsNullOrWhiteSpace($sid) -or $through -lt 1) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'bad_item'; Written = $false }
    }
    if ($TimeoutSec -lt 1) { $TimeoutSec = Get-MetraAskSummaryItemTimeoutSec }

    $cache = Read-MetraAskSummaryCache -SessionId $sid -MetraRoot $MetraRoot
    if ($null -ne $cache -and [int]$cache.lastSummarizedTurnIndex -ge $through) {
        return [PSCustomObject]@{ Ok = $true; Reason = 'already_applied'; Written = $false }
    }

    $turns = @(Get-MetraDeskAskSessionTurns -SessionId $sid -MetraRoot $MetraRoot -Limit 0)
    if ($turns.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Reason = 'no_turns'; Written = $false }
    }
    $computedRev = Get-MetraAskSummarySourceRevision -Turns $turns -ThroughTurnIndex $through
    if (-not [string]::IsNullOrWhiteSpace($rev) -and $rev -ne $computedRev) {
        # Source moved; still summarize current through index under a fresh revision.
        $rev = $computedRev
    }

    $prior = if ($null -ne $cache) { [string]$cache.text } else { '' }
    # Both injected mocks and the production summarizer share the hard timeout wrapper.
    $timedParams = @{
        SessionId        = $sid
        Turns            = $turns
        PriorSummary     = $prior
        ThroughTurnIndex = $through
        MetraRoot        = $MetraRoot
        TimeoutSec       = $TimeoutSec
    }
    if ($null -ne $SummarizerScript) {
        $timedParams.SummarizerScript = $SummarizerScript
    }
    $timed = Invoke-MetraSummarizerWithTimeout @timedParams
    if (-not [bool]$timed.Ok) {
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = [string](Get-MetraProp -Object $timed -Name 'Reason' -Default 'item_timeout')
            Written = $false
        }
    }

    $sum = $null
    if ($null -ne $SummarizerScript) {
        $rawText = [string](Get-MetraProp -Object $timed -Name 'RawText' -Default $timed.Text)
        $allowed = @($turns | ForEach-Object { [int](Get-MetraProp -Object $_ -Name 'turnIndex' -Default 0) } | Where-Object { $_ -gt 0 })
        $cleaned = Select-MetraAskSummaryCitedLines -Text $rawText -AllowedTurnIndexes $allowed
        if (-not (Test-MetraAskSummaryCitations -Text $cleaned -AllowedTurnIndexes $allowed)) {
            $cleaned = New-MetraAskExtractiveCitedSummary -Turns $turns
        }
        $sum = [PSCustomObject]@{
            Ok     = $true
            Reason = 'mock'
            Text   = $cleaned
            Engine = 'mock'
            Model  = 'mock'
        }
    }
    else {
        $sum = [PSCustomObject]@{
            Ok     = [bool]$timed.Ok
            Reason = [string](Get-MetraProp -Object $timed -Name 'Reason' -Default 'model')
            Text   = [string](Get-MetraProp -Object $timed -Name 'Text' -Default '')
            Engine = [string](Get-MetraProp -Object $timed -Name 'Engine' -Default '')
            Model  = [string](Get-MetraProp -Object $timed -Name 'Model' -Default '')
        }
    }
    if (-not [bool]$sum.Ok -or [string]::IsNullOrWhiteSpace([string]$sum.Text)) {
        return [PSCustomObject]@{
            Ok      = $false
            Reason  = [string](Get-MetraProp -Object $sum -Name 'Reason' -Default 'summarizer_failed')
            Written = $false
        }
    }

    $write = Write-MetraAskSummaryCache -SessionId $sid -Text ([string]$sum.Text) `
        -LastSummarizedTurnIndex $through -SourceRevision $rev `
        -Engine ([string]$sum.Engine) -Model ([string]$sum.Model) -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Ok      = [bool]$write.Ok
        Reason  = [string]$write.Reason
        Written = [bool]$write.Written
        Cache   = $write.Cache
    }
}

function Invoke-MetraMemoryWorkerDrain {
    <#
    .SYNOPSIS
        Process pending memory-queue items until empty (or MaxItems).
    .NOTES
        Single-worker lock (memory-worker mutex + lease). Abandoned mutex is reclaimed.
        Stale lease (dead pid or past max hold) stops the holder and retries acquire.
        Per-item summarizer hang is bounded by TimeoutSec (item_timeout -> failed).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$MaxItems = 20,
        [scriptblock]$SummarizerScript,
        [int]$LockTimeoutMs = 100,
        [int]$ItemTimeoutSec = 0
    )

    if ($ItemTimeoutSec -lt 1) { $ItemTimeoutSec = Get-MetraAskSummaryItemTimeoutSec }

    $drainOnce = {
        return Invoke-MetraWithNamedMutex -Name 'memory-worker' -TimeoutMs $LockTimeoutMs -Script {
            Write-MetraMemoryWorkerLease -MetraRoot $MetraRoot
            try {
                $processed = 0
                $results = [System.Collections.Generic.List[object]]::new()
                $pending = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending)
                foreach ($item in $pending) {
                    if ($processed -ge $MaxItems) { break }
                    $id = [string](Get-MetraProp -Object $item -Name 'id' -Default '')
                    $type = [string](Get-MetraProp -Object $item -Name 'type' -Default '')
                    $outcome = $null
                    try {
                        switch ($type) {
                            'ask-summary' {
                                $jobParams = @{
                                    Item       = $item
                                    MetraRoot  = $MetraRoot
                                    TimeoutSec = $ItemTimeoutSec
                                }
                                if ($null -ne $SummarizerScript) { $jobParams.SummarizerScript = $SummarizerScript }
                                $outcome = Invoke-MetraMemoryAskSummaryJob @jobParams
                            }
                            'project-brief' {
                                $outcome = [PSCustomObject]@{ Ok = $true; Reason = 'brief_deferred'; Written = $false }
                            }
                            default {
                                $outcome = [PSCustomObject]@{ Ok = $false; Reason = 'unknown_type'; Written = $false }
                            }
                        }
                    }
                    catch {
                        $outcome = [PSCustomObject]@{ Ok = $false; Reason = 'exception'; Written = $false; Detail = $_.Exception.Message }
                    }

                    $ok = [bool](Get-MetraProp -Object $outcome -Name 'Ok' -Default $false)
                    $reason = [string](Get-MetraProp -Object $outcome -Name 'Reason' -Default '')
                    $attempts = [int](Get-MetraProp -Object $item -Name 'attempts' -Default 0) + 1
                    if ($ok) {
                        Set-MetraMemoryQueueItemStatus -Id $id -Status done -Detail $reason -Attempts $attempts -MetraRoot $MetraRoot | Out-Null
                    }
                    else {
                        # item_timeout parks immediately so a hung summarizer cannot block the queue.
                        $permanent = $reason -in @('bad_item', 'unknown_type', 'no_turns', 'item_timeout')
                        $maxAttempts = 3
                        if ($permanent -or $attempts -ge $maxAttempts) {
                            Set-MetraMemoryQueueItemStatus -Id $id -Status failed -Detail $reason -Attempts $attempts -MetraRoot $MetraRoot | Out-Null
                        }
                        else {
                            Set-MetraMemoryQueueItemStatus -Id $id -Status pending -Detail $reason -Attempts $attempts -MetraRoot $MetraRoot | Out-Null
                        }
                    }
                    [void]$results.Add([PSCustomObject]@{
                            id       = $id
                            type     = $type
                            ok       = $ok
                            reason   = $reason
                            written  = [bool](Get-MetraProp -Object $outcome -Name 'Written' -Default $false)
                            attempts = $attempts
                        })
                    $processed++
                }

                return [PSCustomObject]@{
                    Busy      = $false
                    Processed = $processed
                    Remaining = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending).Count
                    Results   = @($results)
                }
            }
            finally {
                Clear-MetraMemoryWorkerLease -MetraRoot $MetraRoot
            }
        }
    }

    try {
        return (& $drainOnce)
    }
    catch {
        if ($_.Exception.Message -match '(?i)Timed out waiting for mutex') {
            $reclaim = Invoke-MetraMemoryWorkerReclaimStaleLock -MetraRoot $MetraRoot
            if ([bool]$reclaim.Reclaimed) {
                try {
                    $retry = (& $drainOnce)
                    $retry | Add-Member -NotePropertyName ReclaimedStaleLock -NotePropertyValue $true -Force
                    return $retry
                }
                catch {
                    if ($_.Exception.Message -notmatch '(?i)Timed out waiting for mutex') { throw }
                }
            }
            return [PSCustomObject]@{
                Busy      = $true
                Processed = 0
                Remaining = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending).Count
                Results   = @()
                Reason    = 'worker_busy'
                Reclaimed = [bool]$reclaim.Reclaimed
            }
        }
        throw
    }
}

function Start-MetraMemoryWorkerBestEffort {
    <#
    .SYNOPSIS
        Detach a memory worker process when pending items exist. Never throws to Ask.
    .NOTES
        Detach only against the live Metra checkout. Sandbox -MetraRoot (Pester) skips
        Start-Process so tests drain via Invoke-MetraMemoryWorkerDrain instead.
        Integration tests may -Force and set METRA_DATA_ROOT so the child process
        shares the sandbox ledger (inherited env).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Force,
        [switch]$PassThru
    )

    try {
        $liveRoot = Get-MetraRoot
        $sandbox = $false
        try {
            $a = [System.IO.Path]::GetFullPath($MetraRoot)
            $b = [System.IO.Path]::GetFullPath($liveRoot)
            if (-not [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)) {
                $sandbox = $true
            }
        }
        catch { $sandbox = $false }
        if ($sandbox -and -not $Force) {
            return [PSCustomObject]@{ Started = $false; Reason = 'sandbox' }
        }
        # Integration tests suppress auto-spawn from Ask append, then -Force a single child.
        if (([string]$env:METRA_MEMORY_WORKER_AUTOSTART) -eq '0' -and -not $Force) {
            return [PSCustomObject]@{ Started = $false; Reason = 'autostart_disabled' }
        }

        $pending = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending)
        if (-not $Force -and $pending.Count -eq 0) {
            return [PSCustomObject]@{ Started = $false; Reason = 'empty' }
        }

        $cli = Join-Path $liveRoot 'metra.ps1'
        if (-not (Test-Path -LiteralPath $cli)) {
            return [PSCustomObject]@{ Started = $false; Reason = 'missing_cli' }
        }

        $ps = (Get-Command pwsh -ErrorAction SilentlyContinue)
        if (-not $ps) { $ps = Get-Command powershell -ErrorAction SilentlyContinue }
        if (-not $ps) {
            return [PSCustomObject]@{ Started = $false; Reason = 'no_shell' }
        }

        $argList = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-File', $cli
            'memory', 'worker'
        )
        $proc = Start-Process -FilePath $ps.Source -ArgumentList $argList -WorkingDirectory $liveRoot `
            -WindowStyle Hidden -PassThru
        $out = [PSCustomObject]@{
            Started   = $true
            Reason    = 'detached'
            ProcessId = $(if ($null -ne $proc) { [int]$proc.Id } else { 0 })
        }
        if ($PassThru -and $null -ne $proc) {
            $out | Add-Member -NotePropertyName Process -NotePropertyValue $proc -Force
        }
        return $out
    }
    catch {
        return [PSCustomObject]@{ Started = $false; Reason = 'start_failed'; Detail = $_.Exception.Message }
    }
}

function Request-MetraMemoryWorkerNudge {
    <#
    .SYNOPSIS
        Best-effort nudge used from Ask append / ctx touch when queue has work.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    try {
        $pending = @(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status pending)
        if ($pending.Count -eq 0) {
            return [PSCustomObject]@{ Started = $false; Reason = 'empty' }
        }
        return Start-MetraMemoryWorkerBestEffort -MetraRoot $MetraRoot
    }
    catch {
        return [PSCustomObject]@{ Started = $false; Reason = 'nudge_failed' }
    }
}

function Invoke-MetraMemoryCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    switch ($Subcommand.ToLowerInvariant()) {
        'worker' {
            return Invoke-MetraMemoryWorkerDrain -MetraRoot $MetraRoot
        }
        'queue' {
            $status = 'pending'
            if ($ArgsRest.Count -gt 0 -and $ArgsRest[0] -match '^(?i)pending|done|failed|all$') {
                $status = $ArgsRest[0].ToLowerInvariant()
            }
            return ,@(Get-MetraMemoryQueueItems -MetraRoot $MetraRoot -Status $status)
        }
        'nudge' {
            return Start-MetraMemoryWorkerBestEffort -MetraRoot $MetraRoot -Force
        }
        'summary' {
            if ($ArgsRest.Count -lt 1 -or [string]::IsNullOrWhiteSpace([string]$ArgsRest[0])) {
                throw "memory summary requires a sessionId. Example: .\metra.ps1 memory summary <sessionId>"
            }
            return (Read-MetraAskSummaryCache -SessionId ([string]$ArgsRest[0]) -MetraRoot $MetraRoot)
        }
        default {
            throw "Unknown memory subcommand: $Subcommand. Use worker|queue|nudge|summary."
        }
    }
}
