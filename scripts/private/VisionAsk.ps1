# iOS Vision Ask contract - models, validation, handler seam, provenance, telemetry.
# Vision never enters Resolve-MetraAskLane / Get-MetraDeskAskResult / Capture objective / TT assess drafts.

Set-StrictMode -Version Latest

$script:MetraVisionAskContractVersion = '1'
$script:MetraVisionAskHandlerRegistered = $true
$script:MetraVisionAskHandlerName = 'vision-engine'

function Get-MetraVisionAskContractVersion {
    [CmdletBinding()]
    param()
    return [string]$script:MetraVisionAskContractVersion
}

function Test-MetraVisionAskHandlerRegistered {
    [CmdletBinding()]
    param()
    return [bool]$script:MetraVisionAskHandlerRegistered
}

function Get-MetraVisionAskSystemPrompt {
    <#
    .SYNOPSIS
        Load engines/vision-ask/system.md (Vision handler ownership - not AskLane).
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Join-Path $MetraRoot 'engines\vision-ask\system.md'
    if (-not (Test-Path -LiteralPath $path)) {
        return 'You are Metra Vision: relational companion only. No portfolio grounding, no Capture chrome, no durable writes.'
    }
    try {
        return [System.IO.File]::ReadAllText($path).Trim()
    }
    catch {
        return 'You are Metra Vision: relational companion only. No portfolio grounding, no Capture chrome, no durable writes.'
    }
}

function Get-MetraAskRoutedTelemetryRoot {
    [CmdletBinding()]
    param()
    Join-Path $env:LOCALAPPDATA 'Metra\ask'
}

function Get-MetraAskRoutedTelemetryEventsPath {
    [CmdletBinding()]
    param()
    Join-Path (Get-MetraAskRoutedTelemetryRoot) 'events.jsonl'
}

function Get-MetraVisionAskValidCombinations {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ surface = 'ios'; mode = 'vision'; intent = 'relational'; path = 'vision' }
        [pscustomobject]@{ surface = 'ios'; mode = 'bounded'; intent = 'desk'; path = 'desk' }
        [pscustomobject]@{ surface = 'ios'; mode = 'bounded'; intent = 'capture'; path = 'capture' }
        [pscustomobject]@{ surface = 'desk'; mode = 'bounded'; intent = 'desk'; path = 'desk' }
        [pscustomobject]@{ surface = 'desk'; mode = 'bounded'; intent = 'capture'; path = 'capture' }
    )
}

function Get-MetraVisionAskErrorCodes {
    [CmdletBinding()]
    param()

    @(
        'invalid_contract'
        'unsupported_contract_version'
        'vision_unavailable'
        'ops_unreachable'
        'desk_requires_connectivity'
        'write_not_allowed'
        'route_boundary_violation'
        'engine_failure'
    )
}

function Test-MetraVisionAskFieldCombination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Surface,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Mode,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Intent
    )

    $s = $Surface.Trim().ToLowerInvariant()
    $m = $Mode.Trim().ToLowerInvariant()
    $i = $Intent.Trim().ToLowerInvariant()
    foreach ($row in @(Get-MetraVisionAskValidCombinations)) {
        if ($row.surface -eq $s -and $row.mode -eq $m -and $row.intent -eq $i) {
            return [pscustomobject]@{ ok = $true; path = [string]$row.path; error = $null }
        }
    }
    return [pscustomobject]@{ ok = $false; path = $null; error = 'invalid_contract' }
}

function ConvertTo-MetraVisionAskRequest {
    <#
    .SYNOPSIS
        Normalize a parsed JSON body into a Vision Ask request object (does not validate).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Body)

    $caps = Get-MetraProp -Object $Body -Name 'capabilities' -Default $null
    $ctx = Get-MetraProp -Object $Body -Name 'context' -Default $null
    $message = [string](Get-MetraProp -Object $Body -Name 'message' -Default '')
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string](Get-MetraProp -Object $Body -Name 'prompt' -Default '')
    }

    $lane = [string](Get-MetraProp -Object $Body -Name 'lane' -Default '')
    $mode = [string](Get-MetraProp -Object $Body -Name 'mode' -Default '')
    if ([string]::IsNullOrWhiteSpace($mode) -and $lane.Trim().ToLowerInvariant() -eq 'companion') {
        $mode = 'vision'
    }

    $durable = $false
    $localAssist = $false
    if ($null -ne $caps) {
        $durable = [bool](Get-MetraProp -Object $caps -Name 'durableWritesAllowed' -Default $false)
        $localAssist = [bool](Get-MetraProp -Object $caps -Name 'localAssistAvailable' -Default $false)
    }

    $intent = [string](Get-MetraProp -Object $Body -Name 'intent' -Default '')
    if ([string]::IsNullOrWhiteSpace($intent) -and $mode.Trim().ToLowerInvariant() -eq 'vision') {
        $intent = 'relational'
    }

    $surface = [string](Get-MetraProp -Object $Body -Name 'surface' -Default '')
    if ([string]::IsNullOrWhiteSpace($surface) -and $mode.Trim().ToLowerInvariant() -eq 'vision') {
        $surface = 'ios'
    }

    return [pscustomobject]@{
        contractVersion = [string](Get-MetraProp -Object $Body -Name 'contractVersion' -Default '')
        surface         = $surface
        mode            = $mode
        intent          = $intent
        message         = $message
        conversationId  = [string](Get-MetraProp -Object $Body -Name 'conversationId' -Default '')
        turnId          = [string](Get-MetraProp -Object $Body -Name 'turnId' -Default '')
        lane            = $lane
        capabilities    = [pscustomobject]@{
            localAssistAvailable = $localAssist
            durableWritesAllowed = $durable
        }
        context         = [pscustomobject]@{
            client        = [string](Get-MetraProp -Object $ctx -Name 'client' -Default '')
            clientVersion = [string](Get-MetraProp -Object $ctx -Name 'clientVersion' -Default '')
        }
    }
}

function Test-MetraVisionAskRequest {
    <#
    .SYNOPSIS
        Validate a Vision Ask request. Never silent-normalizes invalid combinations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [switch]$RequireVisionPath
    )

    $version = [string](Get-MetraProp -Object $Request -Name 'contractVersion' -Default '')
    if ([string]::IsNullOrWhiteSpace($version)) {
        return [pscustomobject]@{ ok = $false; error = 'invalid_contract'; path = $null; detail = 'contractVersion required' }
    }
    if ($version -ne (Get-MetraVisionAskContractVersion)) {
        return [pscustomobject]@{
            ok     = $false
            error  = 'unsupported_contract_version'
            path   = $null
            detail = "unsupported contractVersion '$version'"
        }
    }

    $surface = [string](Get-MetraProp -Object $Request -Name 'surface' -Default '')
    $mode = [string](Get-MetraProp -Object $Request -Name 'mode' -Default '')
    $intent = [string](Get-MetraProp -Object $Request -Name 'intent' -Default '')
    $lane = [string](Get-MetraProp -Object $Request -Name 'lane' -Default '')

    if ($lane.Trim().ToLowerInvariant() -eq 'companion' -and -not (Test-MetraVisionAskHandlerRegistered)) {
        return [pscustomobject]@{
            ok     = $false
            error  = 'vision_unavailable'
            path   = $null
            detail = 'lane=companion without Vision handler'
        }
    }

    $combo = Test-MetraVisionAskFieldCombination -Surface $surface -Mode $mode -Intent $intent
    if (-not $combo.ok) {
        return [pscustomobject]@{
            ok     = $false
            error  = 'invalid_contract'
            path   = $null
            detail = "invalid surface/mode/intent ($surface/$mode/$intent)"
        }
    }

    if ($RequireVisionPath -and $combo.path -ne 'vision') {
        return [pscustomobject]@{
            ok     = $false
            error  = 'invalid_contract'
            path   = $combo.path
            detail = 'Vision endpoint requires mode=vision intent=relational'
        }
    }

    if ($combo.path -eq 'vision') {
        $caps = Get-MetraProp -Object $Request -Name 'capabilities' -Default $null
        if ([bool](Get-MetraProp -Object $caps -Name 'durableWritesAllowed' -Default $false)) {
            return [pscustomobject]@{
                ok     = $false
                error  = 'write_not_allowed'
                path   = 'vision'
                detail = 'Vision forbids durableWritesAllowed'
            }
        }
        if (-not (Test-MetraVisionAskHandlerRegistered)) {
            return [pscustomobject]@{
                ok     = $false
                error  = 'vision_unavailable'
                path   = 'vision'
                detail = 'Vision handler not registered'
            }
        }
        $message = [string](Get-MetraProp -Object $Request -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($message)) {
            return [pscustomobject]@{
                ok     = $false
                error  = 'invalid_contract'
                path   = 'vision'
                detail = 'message required'
            }
        }
    }

    return [pscustomobject]@{
        ok     = $true
        error  = $null
        path   = [string]$combo.path
        detail = $null
    }
}

function New-MetraVisionAskCorrelation {
    [CmdletBinding()]
    param(
        [string]$ConversationId = '',
        [string]$TurnId = '',
        [string]$ServerRequestId = ''
    )

    if ([string]::IsNullOrWhiteSpace($ServerRequestId)) {
        $ServerRequestId = [guid]::NewGuid().ToString('n')
    }
    return [ordered]@{
        conversationId  = $ConversationId
        turnId          = $TurnId
        serverRequestId = $ServerRequestId
    }
}

function New-MetraVisionAskErrorResponse {
    <#
    .SYNOPSIS
        Fail-closed error envelope. Never status=answered with a deceptive source.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet(
            'invalid_contract',
            'unsupported_contract_version',
            'vision_unavailable',
            'ops_unreachable',
            'desk_requires_connectivity',
            'write_not_allowed',
            'route_boundary_violation',
            'engine_failure'
        )]
        [string]$Reason,
        [ValidateSet('ops-vision', 'local-assist', 'ops-desk', 'capture', 'client')]
        [string]$Source = 'client',
        [string]$Mode = '',
        [string]$Intent = '',
        [string]$Handler = 'none',
        [bool]$AskLaneUsed = $false,
        [bool]$CaptureSuggested = $false,
        [bool]$OpsReached = $false,
        [bool]$PortfolioGrounded = $false,
        [bool]$EngineInvoked = $false,
        $Correlation = @{},
        [string]$Detail = ''
    )

    $corr = New-MetraVisionAskCorrelation `
        -ConversationId ([string](Get-MetraProp -Object $Correlation -Name 'conversationId' -Default '')) `
        -TurnId ([string](Get-MetraProp -Object $Correlation -Name 'turnId' -Default '')) `
        -ServerRequestId ([string](Get-MetraProp -Object $Correlation -Name 'serverRequestId' -Default ''))

    return [pscustomobject]@{
        contractVersion = (Get-MetraVisionAskContractVersion)
        status          = 'unavailable'
        source          = $Source
        mode            = $Mode
        intent          = $Intent
        reason          = $Reason
        detail          = $Detail
        response        = $null
        grounding       = [ordered]@{
            opsReached        = $OpsReached
            portfolioGrounded = $PortfolioGrounded
        }
        routing         = [ordered]@{
            handler          = $Handler
            askLaneUsed      = $AskLaneUsed
            captureSuggested = $CaptureSuggested
            engineInvoked    = $EngineInvoked
        }
        writes          = [ordered]@{
            attempted    = $false
            committed    = $false
            durableWrite = 'not_attempted'
        }
        correlation     = $corr
    }
}

function New-MetraVisionAskAnsweredResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)]
        [ValidateSet('ops-vision', 'local-assist', 'ops-desk', 'capture', 'client')]
        [string]$Source,
        [Parameter(Mandatory)][string]$Mode,
        [Parameter(Mandatory)][string]$Intent,
        [Parameter(Mandatory)][string]$Handler,
        [bool]$AskLaneUsed = $false,
        [bool]$CaptureSuggested = $false,
        [bool]$OpsReached = $false,
        [bool]$PortfolioGrounded = $false,
        [bool]$EngineInvoked = $false,
        $Correlation = @{}
    )

    if ($Source -eq 'ops-vision' -and ($AskLaneUsed -or -not $EngineInvoked)) {
        throw 'route_boundary_violation: ops-vision requires engineInvoked=true and askLaneUsed=false'
    }

    $corr = New-MetraVisionAskCorrelation `
        -ConversationId ([string](Get-MetraProp -Object $Correlation -Name 'conversationId' -Default '')) `
        -TurnId ([string](Get-MetraProp -Object $Correlation -Name 'turnId' -Default '')) `
        -ServerRequestId ([string](Get-MetraProp -Object $Correlation -Name 'serverRequestId' -Default ''))

    return [pscustomobject]@{
        contractVersion = (Get-MetraVisionAskContractVersion)
        status          = 'answered'
        source          = $Source
        mode            = $Mode
        intent          = $Intent
        response        = [ordered]@{ text = $Text }
        grounding       = [ordered]@{
            opsReached        = $OpsReached
            portfolioGrounded = $PortfolioGrounded
        }
        routing         = [ordered]@{
            handler          = $Handler
            askLaneUsed      = $AskLaneUsed
            captureSuggested = $CaptureSuggested
            engineInvoked    = $EngineInvoked
        }
        writes          = [ordered]@{
            attempted    = $false
            committed    = $false
            durableWrite = 'not_attempted'
        }
        correlation     = $corr
    }
}

function New-MetraVisionAskOfflineDeskResponse {
    <#
    .SYNOPSIS
        Client-boundary fail-closed shape when Desk is requested offline.
    #>
    [CmdletBinding()]
    param(
        [string]$Mode = 'bounded',
        [string]$Intent = 'desk',
        $Correlation = @{}
    )

    return New-MetraVisionAskErrorResponse `
        -Reason 'desk_requires_connectivity' `
        -Source 'client' `
        -Mode $Mode `
        -Intent $Intent `
        -Handler 'client' `
        -OpsReached:$false `
        -PortfolioGrounded:$false `
        -Correlation $Correlation `
        -Detail 'ops_unreachable'
}

function New-MetraVisionAskLocalAssistProvenance {
    <#
    .SYNOPSIS
        Expected LocalAssist response provenance (client boundary; no LocalAssist impl).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        $Correlation = @{}
    )

    return New-MetraVisionAskAnsweredResponse `
        -Text $Text `
        -Source 'local-assist' `
        -Mode 'vision' `
        -Intent 'relational' `
        -Handler 'local-assist' `
        -AskLaneUsed:$false `
        -CaptureSuggested:$false `
        -OpsReached:$false `
        -PortfolioGrounded:$false `
        -EngineInvoked:$false `
        -Correlation $Correlation
}

function Add-MetraAskRoutedTelemetryEvent {
    <#
    .SYNOPSIS
        Append metra.ask.routed observe-only JSONL under %LOCALAPPDATA%\Metra\ask.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Envelope,
        [string]$Result = 'answered',
        [string]$Surface = '',
        [bool]$EngineInvoked = $false
    )

    try {
        $root = Get-MetraAskRoutedTelemetryRoot
        if (-not (Test-Path -LiteralPath $root)) {
            $null = New-Item -ItemType Directory -Path $root -Force
        }
        $path = Get-MetraAskRoutedTelemetryEventsPath
        $corr = Get-MetraProp -Object $Envelope -Name 'correlation' -Default $null
        $routing = Get-MetraProp -Object $Envelope -Name 'routing' -Default $null
        $grounding = Get-MetraProp -Object $Envelope -Name 'grounding' -Default $null
        $writes = Get-MetraProp -Object $Envelope -Name 'writes' -Default $null
        $engineFlag = if ($PSBoundParameters.ContainsKey('EngineInvoked')) {
            $EngineInvoked
        }
        else {
            [bool](Get-MetraProp -Object $routing -Name 'engineInvoked' -Default $false)
        }
        $event = [ordered]@{
            event                 = 'metra.ask.routed'
            ts                    = (Get-Date).ToUniversalTime().ToString('o')
            contractVersion       = [string](Get-MetraProp -Object $Envelope -Name 'contractVersion' -Default '')
            surface               = $Surface
            mode                  = [string](Get-MetraProp -Object $Envelope -Name 'mode' -Default '')
            intent                = [string](Get-MetraProp -Object $Envelope -Name 'intent' -Default '')
            handler               = [string](Get-MetraProp -Object $routing -Name 'handler' -Default '')
            source                = [string](Get-MetraProp -Object $Envelope -Name 'source' -Default '')
            askLaneUsed           = [bool](Get-MetraProp -Object $routing -Name 'askLaneUsed' -Default $false)
            captureSuggested      = [bool](Get-MetraProp -Object $routing -Name 'captureSuggested' -Default $false)
            opsReached            = [bool](Get-MetraProp -Object $grounding -Name 'opsReached' -Default $false)
            engineInvoked         = $engineFlag
            durableWriteAttempted = [bool](Get-MetraProp -Object $writes -Name 'attempted' -Default $false)
            result                = $Result
            turnId                = [string](Get-MetraProp -Object $corr -Name 'turnId' -Default '')
            serverRequestId       = [string](Get-MetraProp -Object $corr -Name 'serverRequestId' -Default '')
        }
        $line = ($event | ConvertTo-Json -Compress -Depth 6)
        # Best-effort append; concurrent writers may interleave lines - readers
        # must tolerate malformed JSONL. Telemetry must never fail the ask path.
        Add-Content -LiteralPath $path -Value $line -Encoding utf8
    }
    catch {
        # Observe-only: directory create / append / serialize failures are swallowed.
    }
}

function Invoke-MetraVisionAskHandler {
    <#
    .SYNOPSIS
        Online Vision handler: Ops engine + Vision system prompt. Never AskLane / Desk / Capture / TT assess.
    .PARAMETER EngineInvoker
        Test seam. Receives ($Prompt, $MetraRoot). Returns @{ ok=bool; message=string; error=string }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [string]$MetraRoot = (Get-MetraRoot),
        [scriptblock]$EngineInvoker,
        [switch]$SkipEngine,
        [switch]$SkipTelemetry
    )

    # Always normalize: raw client JSON often includes contractVersion but still
    # needs prompt->message and default surface/intent inference. ConvertTo is idempotent.
    $normalized = ConvertTo-MetraVisionAskRequest -Body $Request

    $corr = @{
        conversationId  = [string](Get-MetraProp -Object $normalized -Name 'conversationId' -Default '')
        turnId          = [string](Get-MetraProp -Object $normalized -Name 'turnId' -Default '')
        serverRequestId = [guid]::NewGuid().ToString('n')
    }
    $surface = [string](Get-MetraProp -Object $normalized -Name 'surface' -Default '')

    $validation = Test-MetraVisionAskRequest -Request $normalized -RequireVisionPath
    if (-not $validation.ok) {
        $err = New-MetraVisionAskErrorResponse `
            -Reason $validation.error `
            -Source 'client' `
            -Mode ([string](Get-MetraProp -Object $normalized -Name 'mode' -Default '')) `
            -Intent ([string](Get-MetraProp -Object $normalized -Name 'intent' -Default '')) `
            -Handler 'vision-validate' `
            -Correlation $corr `
            -Detail ([string]$validation.detail)
        if (-not $SkipTelemetry) {
            Add-MetraAskRoutedTelemetryEvent -Envelope $err -Result $validation.error -Surface $surface -EngineInvoked:$false
        }
        return $err
    }

    if (-not (Test-MetraVisionAskHandlerRegistered) -or $SkipEngine) {
        $err = New-MetraVisionAskErrorResponse `
            -Reason 'vision_unavailable' `
            -Source 'client' `
            -Mode 'vision' `
            -Intent 'relational' `
            -Handler 'vision-engine' `
            -Correlation $corr `
            -Detail 'Vision engine handler unavailable'
        if (-not $SkipTelemetry) {
            Add-MetraAskRoutedTelemetryEvent -Envelope $err -Result 'vision_unavailable' -Surface $surface -EngineInvoked:$false
        }
        return $err
    }

    $caps = Get-MetraProp -Object $normalized -Name 'capabilities' -Default $null
    if ([bool](Get-MetraProp -Object $caps -Name 'durableWritesAllowed' -Default $false)) {
        $err = New-MetraVisionAskErrorResponse `
            -Reason 'write_not_allowed' `
            -Source 'ops-vision' `
            -Mode 'vision' `
            -Intent 'relational' `
            -Handler $script:MetraVisionAskHandlerName `
            -Correlation $corr `
            -Detail 'Vision rejects durable writes'
        if (-not $SkipTelemetry) {
            Add-MetraAskRoutedTelemetryEvent -Envelope $err -Result 'write_not_allowed' -Surface $surface -EngineInvoked:$false
        }
        return $err
    }

    $systemPrompt = Get-MetraVisionAskSystemPrompt -MetraRoot $MetraRoot
    $userMessage = [string]$normalized.message
    $enginePrompt = @"
$systemPrompt

---
User turn:
$userMessage
"@

    $invoker = $EngineInvoker
    if (-not $invoker) {
        $invoker = {
            param($Prompt, $Root)
            if (Get-Command -Name Invoke-MetraAskEngine -ErrorAction SilentlyContinue) {
                $engine = Invoke-MetraAskEngine -Prompt $Prompt -Cwd $Root -Context @{
                    surface       = 'ios'
                    mode          = 'vision'
                    intent        = 'relational'
                    askLaneUsed   = $false
                    visionHandler = $true
                } -MetraRoot $Root
                return [pscustomobject]@{
                    ok      = [bool](Get-MetraProp -Object $engine -Name 'ok' -Default $false)
                    message = [string](Get-MetraProp -Object $engine -Name 'message' -Default '')
                    error   = [string](Get-MetraProp -Object $engine -Name 'error' -Default '')
                }
            }
            return [pscustomobject]@{ ok = $false; message = ''; error = 'engine_unavailable' }
        }
    }

    $engineResult = $null
    try {
        $engineResult = & $invoker $enginePrompt $MetraRoot
    }
    catch {
        $err = New-MetraVisionAskErrorResponse `
            -Reason 'engine_failure' `
            -Source 'ops-vision' `
            -Mode 'vision' `
            -Intent 'relational' `
            -Handler $script:MetraVisionAskHandlerName `
            -OpsReached:$true `
            -EngineInvoked:$true `
            -Correlation $corr `
            -Detail $_.Exception.Message
        if (-not $SkipTelemetry) {
            Add-MetraAskRoutedTelemetryEvent -Envelope $err -Result 'engine_failure' -Surface $surface -EngineInvoked:$true
        }
        return $err
    }

    # Hashtable invokers (documented EngineInvoker shape) do not expose note
    # properties via PSObject.Properties['ok']; use Get-MetraProp / Test-MetraPropExists.
    $ok = $false
    if ($null -ne $engineResult) {
        if (Test-MetraPropExists -Object $engineResult -Name 'ok') {
            $ok = [bool](Get-MetraProp -Object $engineResult -Name 'ok' -Default $false)
        }
        elseif (Test-MetraPropExists -Object $engineResult -Name 'answered') {
            $ok = [bool](Get-MetraProp -Object $engineResult -Name 'answered' -Default $false)
        }
    }
    $text = [string](Get-MetraProp -Object $engineResult -Name 'message' -Default '')
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = [string](Get-MetraProp -Object $engineResult -Name 'text' -Default '')
    }

    if (-not $ok -or [string]::IsNullOrWhiteSpace($text)) {
        $engineErr = [string](Get-MetraProp -Object $engineResult -Name 'error' -Default 'engine_failure')
        $err = New-MetraVisionAskErrorResponse `
            -Reason 'engine_failure' `
            -Source 'ops-vision' `
            -Mode 'vision' `
            -Intent 'relational' `
            -Handler $script:MetraVisionAskHandlerName `
            -OpsReached:$true `
            -EngineInvoked:$true `
            -Correlation $corr `
            -Detail $engineErr
        if (-not $SkipTelemetry) {
            Add-MetraAskRoutedTelemetryEvent -Envelope $err -Result 'engine_failure' -Surface $surface -EngineInvoked:$true
        }
        return $err
    }

    $answered = New-MetraVisionAskAnsweredResponse `
        -Text $text `
        -Source 'ops-vision' `
        -Mode 'vision' `
        -Intent 'relational' `
        -Handler $script:MetraVisionAskHandlerName `
        -AskLaneUsed:$false `
        -CaptureSuggested:$false `
        -OpsReached:$true `
        -PortfolioGrounded:$false `
        -EngineInvoked:$true `
        -Correlation $corr

    if (-not $SkipTelemetry) {
        Add-MetraAskRoutedTelemetryEvent -Envelope $answered -Result 'answered' -Surface $surface -EngineInvoked:$true
    }
    return $answered
}

function Resolve-MetraAskHttpDispatch {
    <#
    .SYNOPSIS
        Pre-Desk dispatch: choose vision | desk | capture | reject from a contract body.
        Legacy /api/ask bodies without contractVersion remain desk (prompt path).
    .NOTES
        SCAR: Vision routing must be decided here and applied in OpsServer before any
        Desk AskLane processing. Reordering recreates the 2026-08 Vision fallback defect
        (HTTP success via Desk/Capture treated as Vision success).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Body)

    $version = [string](Get-MetraProp -Object $Body -Name 'contractVersion' -Default '')
    $mode = [string](Get-MetraProp -Object $Body -Name 'mode' -Default '')
    $lane = [string](Get-MetraProp -Object $Body -Name 'lane' -Default '')

    if ([string]::IsNullOrWhiteSpace($version) -and [string]::IsNullOrWhiteSpace($mode) -and [string]::IsNullOrWhiteSpace($lane)) {
        return [pscustomobject]@{ path = 'desk-legacy'; error = $null; request = $null; detail = $null }
    }

    if ([string]::IsNullOrWhiteSpace($version) -and ($mode -or $lane)) {
        return [pscustomobject]@{
            path    = 'reject'
            error   = 'invalid_contract'
            request = $null
            detail  = 'contractVersion required when mode or lane is set'
        }
    }

    $req = ConvertTo-MetraVisionAskRequest -Body $Body
    $validation = Test-MetraVisionAskRequest -Request $req
    if (-not $validation.ok) {
        return [pscustomobject]@{
            path    = 'reject'
            error   = $validation.error
            request = $req
            detail  = $validation.detail
        }
    }

    return [pscustomobject]@{
        path    = [string]$validation.path
        error   = $null
        request = $req
        detail  = $null
    }
}

function Get-MetraVisionAskHttpStatusCode {
    <#
    .SYNOPSIS
        Map a Vision Ask envelope to an HTTP status code (never 200 for deceptive success).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Envelope)

    $status = [string](Get-MetraProp -Object $Envelope -Name 'status' -Default '')
    if ($status -eq 'answered') { return 200 }

    $reason = [string](Get-MetraProp -Object $Envelope -Name 'reason' -Default '')
    switch ($reason) {
        'invalid_contract' { return 400 }
        'unsupported_contract_version' { return 400 }
        'write_not_allowed' { return 400 }
        'route_boundary_violation' { return 409 }
        'vision_unavailable' { return 503 }
        'ops_unreachable' { return 503 }
        'desk_requires_connectivity' { return 503 }
        'engine_failure' { return 502 }
        default { return 400 }
    }
}

function Test-MetraVisionAskSourceFileBoundary {
    <#
    .SYNOPSIS
        Static boundary: VisionAsk.ps1 must not call Desk AskLane / DeskAsk / TT assess helpers.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Join-Path $MetraRoot 'scripts\private\VisionAsk.ps1'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ ok = $false; violations = @('VisionAsk.ps1 missing') }
    }

    $lines = Get-Content -LiteralPath $path
    $forbidden = @(
        'Resolve-MetraAskLane'
        'Get-MetraDeskAskResult'
        'New-MetraAskChatLaneResult'
        'New-MetraTicketAssessDraft'
    )
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim.StartsWith('#')) { continue }
        if ($trim -match "forbidden\s*=") { continue }
        if ($trim -match "must not call") { continue }
        if ($trim -match "Never enters") { continue }
        foreach ($name in $forbidden) {
            if ($trim -match [regex]::Escape($name)) {
                # Allow the name only inside single-quoted list entries in this function.
                if ($trim -match ("^\s*'" + [regex]::Escape($name) + "'\s*$")) { continue }
                [void]$hits.Add($name)
            }
        }
    }

    $unique = @($hits | Select-Object -Unique)
    return [pscustomobject]@{
        ok         = ($unique.Count -eq 0)
        violations = $unique
    }
}
