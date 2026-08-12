# OpenAI-compatible Ask complete/health for ollama, enterprise, and llamacpp (PowerShell-native).
# Context JSON ceiling: evidence maxTotalChars (2400) * 5 for route/continuity/capability headroom.

$script:MetraAskOpenAICompatContextJsonMultiplier = 5

function Get-MetraAskOpenAICompatContextJsonMaxChars {
    $limits = Get-MetraAskEvidenceLimits
    $maxTotal = [int](Get-MetraProp -Object $limits -Name 'maxTotalChars' -Default 2400)
    if ($maxTotal -lt 1) { $maxTotal = 2400 }
    return ($maxTotal * [int]$script:MetraAskOpenAICompatContextJsonMultiplier)
}

function Get-MetraAskOpenAICompatHealthResult {
    <#
    .SYNOPSIS
        Probe OpenAI-compatible / Ollama health with strict status mapping.
    .OUTPUTS
        ok, status (ok|auth_required|forbidden|not_found|unreachable), statusCode, url
    .NOTES
        Only HTTP 2xx counts as healthy. 401/403/404 are reachable-but-not-ready diagnostics.
        Does not probe the base URL root (avoids counting a random 200 HTML page as healthy).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [ValidateSet('ollama', 'openai')][string]$Kind = 'openai',
        [int]$TimeoutSec = 2,
        [hashtable]$Headers = @{}
    )

    $empty = [PSCustomObject]@{
        ok         = $false
        status     = 'unreachable'
        statusCode = $null
        url        = $null
    }
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return $empty }

    $root = $BaseUrl.TrimEnd('/')
    $urls = @()
    if ($Kind -eq 'ollama') {
        $urls += "$root/api/tags"
        $urls += "$root/v1/models"
    }
    else {
        $urls += "$root/v1/models"
        $urls += "$root/health"
    }

    $rank = @{
        ok            = 5
        auth_required = 4
        forbidden     = 3
        not_found     = 2
        unreachable   = 1
    }
    $best = $empty

    foreach ($url in $urls) {
        try {
            $params = @{
                Uri             = $url
                Method          = 'Get'
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
                SkipHttpErrorCheck = $true
            }
            if ($Headers.Count -gt 0) { $params['Headers'] = $Headers }
            $resp = Invoke-WebRequest @params
            $code = [int]$resp.StatusCode
            $mapped = 'unreachable'
            if ($code -ge 200 -and $code -lt 300) {
                return [PSCustomObject]@{
                    ok         = $true
                    status     = 'ok'
                    statusCode = $code
                    url        = $url
                }
            }
            elseif ($code -eq 401) { $mapped = 'auth_required' }
            elseif ($code -eq 403) { $mapped = 'forbidden' }
            elseif ($code -eq 404) { $mapped = 'not_found' }

            if ([int]$rank[$mapped] -gt [int]$rank[[string]$best.status]) {
                $best = [PSCustomObject]@{
                    ok         = $false
                    status     = $mapped
                    statusCode = $code
                    url        = $url
                }
            }
        }
        catch { }
    }
    return $best
}

function Test-MetraAskOpenAICompatHealth {
    <#
    .SYNOPSIS
        True when an OpenAI-compatible / Ollama probe returns HTTP 2xx.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [ValidateSet('ollama', 'openai')][string]$Kind = 'openai',
        [int]$TimeoutSec = 2,
        [hashtable]$Headers = @{}
    )

    $result = Get-MetraAskOpenAICompatHealthResult -BaseUrl $BaseUrl -Kind $Kind -TimeoutSec $TimeoutSec -Headers $Headers
    return [bool]$result.ok
}

function Test-MetraAskOllamaModelNameMatch {
    <#
    .SYNOPSIS
        Match a wanted Ollama model name against a tags-list name.
    .NOTES
        Tagged wants (qwen2.5:7b) require the same tag (or :latest equivalence), or an untagged
        inventory row of the same base. Untagged wants (qwen2.5) fuzzy-match any tag of that base.
        Different size tags do not match each other (qwen2.5:7b vs qwen2.5:1.5b).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Want,
        [Parameter(Mandatory)][string]$Have
    )

    $want = $Want.Trim()
    $have = $Have.Trim()
    if ([string]::IsNullOrWhiteSpace($want) -or [string]::IsNullOrWhiteSpace($have)) { return $false }
    if ($have -eq $want) { return $true }

    $wantParts = $want -split ':', 2
    $haveParts = $have -split ':', 2
    $wantBase = $wantParts[0]
    $haveBase = $haveParts[0]
    $wantTag = if ($wantParts.Count -gt 1) { $wantParts[1] } else { '' }
    $haveTag = if ($haveParts.Count -gt 1) { $haveParts[1] } else { '' }

    if ($wantBase -ne $haveBase) { return $false }

    if ($wantTag) {
        # Tagged request: same tag, :latest equivalence, or untagged inventory of same base.
        if (-not $haveTag) { return $true }
        if ($wantTag -eq $haveTag) { return $true }
        if ($wantTag -eq 'latest' -or $haveTag -eq 'latest') { return $true }
        return $false
    }

    # Untagged request: any tag of the same base (documented fuzzy pin behavior).
    return $true
}

function Test-MetraAskOllamaModelPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Model,
        [int]$TimeoutSec = 5
    )

    if ([string]::IsNullOrWhiteSpace($Model)) { return $false }
    $root = $BaseUrl.TrimEnd('/')
    try {
        $tags = Invoke-RestMethod -Uri "$root/api/tags" -Method Get -TimeoutSec $TimeoutSec
        foreach ($m in @($tags.models)) {
            $n = [string](Get-MetraProp -Object $m -Name 'name' -Default '')
            if ($n -and (Test-MetraAskOllamaModelNameMatch -Want $Model -Have $n)) {
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-MetraAskEnterpriseApiKey {
    param($Settings)
    $envName = [string]$Settings.enterpriseApiKeyEnv
    if ([string]::IsNullOrWhiteSpace($envName)) { return $null }
    $v = [Environment]::GetEnvironmentVariable($envName, 'Process')
    if ([string]::IsNullOrWhiteSpace($v)) {
        $v = [Environment]::GetEnvironmentVariable($envName, 'User')
    }
    if ([string]::IsNullOrWhiteSpace($v)) {
        $v = [Environment]::GetEnvironmentVariable($envName, 'Machine')
    }
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v.Trim()
}

function Resolve-MetraAskOpenAICompatErrorCode {
    <#
    .SYNOPSIS
        Map transport exceptions to stable operator-safe error codes (no host/URL leakage).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        $Exception
    )

    $msg = ''
    if ($Exception) {
        $msg = [string](Get-MetraProp -Object $Exception -Name 'Message' -Default '')
        if ([string]::IsNullOrWhiteSpace($msg) -and $Exception.Exception) {
            $msg = [string]$Exception.Exception.Message
        }
    }
    Write-Verbose "Ask OpenAI-compat error detail ($($Settings.engine)): $msg"

    if ($msg -match '(?i)(401|unauthorized|authentication|access.?denied)') {
        if ($Settings.engine -eq 'enterprise') { return 'enterprise_auth_failed' }
    }
    if ($msg -match '(?i)(403|forbidden)') {
        if ($Settings.engine -eq 'enterprise') { return 'enterprise_auth_failed' }
    }

    switch ([string]$Settings.engine) {
        'enterprise' { return 'enterprise_request_failed' }
        'ollama' { return 'ollama_unreachable' }
        'llamacpp' { return 'llamacpp_unreachable' }
        default { return 'engine_request_failed' }
    }
}

function Test-MetraAskOpenAICompatResponseFormatRejected {
    <#
    .SYNOPSIS
        True when an OpenAI-compat endpoint rejected response_format / json_object.
    #>
    [CmdletBinding()]
    param(
        $Exception
    )

    $msg = ''
    if ($Exception) {
        $msg = [string](Get-MetraProp -Object $Exception -Name 'Message' -Default '')
        if ([string]::IsNullOrWhiteSpace($msg) -and $Exception.Exception) {
            $msg = [string]$Exception.Exception.Message
        }
    }
    if ([string]::IsNullOrWhiteSpace($msg)) { return $false }
    return $msg -match '(?i)response_format|json_object|structured.?output|unknown field|\bformat\b'
}

function Invoke-MetraAskOpenAICompatComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Settings,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd,
        $Context = @{},
        [string]$SessionId,
        $PromptScrub,
        $CtxScrub,
        [int]$TimeoutSec = 180
    )

    $baseUrl = ''
    $model = ''
    $headers = @{ }
    switch ($Settings.engine) {
        'ollama' {
            $baseUrl = $Settings.ollamaBaseUrl
            $model = $Settings.ollamaModel
        }
        'enterprise' {
            $baseUrl = $Settings.enterpriseBaseUrl
            $model = $Settings.enterpriseModel
            $key = Get-MetraAskEnterpriseApiKey -Settings $Settings
            if ($key) { $headers['Authorization'] = "Bearer $key" }
        }
        'llamacpp' {
            $baseUrl = $Settings.llamacppBaseUrl
            $model = $Settings.llamacppModel
        }
        default {
            return New-MetraAskEngineErrorResult -Settings $Settings -SessionId $SessionId `
                -ErrorMessage "engine_unsupported:$($Settings.engine)" -PromptScrub $PromptScrub -CtxScrub $CtxScrub
        }
    }

    # Enterprise: project leaf only - avoid shipping full local paths to org endpoints.
    $cwdLine = if ($Settings.engine -eq 'enterprise') {
        $leaf = Split-Path -Leaf ([string]$Cwd)
        if ([string]::IsNullOrWhiteSpace($leaf)) { 'Project: (unknown)' } else { "Project: $leaf" }
    }
    else {
        "Working directory: $Cwd"
    }

    $purpose = ''
    if ($Context -is [hashtable] -or $Context -is [PSCustomObject]) {
        $purpose = [string](Get-MetraProp -Object $Context -Name 'purpose' -Default '')
    }
    $isInspect = ($purpose -eq 'metra-inspect')

    if ($isInspect) {
        $systemParts = @(
            'You are Metra Inspect - structured code review for portfolio ops.',
            'Return JSON only. No markdown, prose, or code fences.',
            'Use one object: {"findings":[...]} where each finding includes severity, confidence, category, file, line, finding, recommendation, evidence.',
            'If no issues, return {"findings":[]}.',
            'Never return plan summaries (overview, implementation_steps, steps, title). Review input; output findings only.',
            $cwdLine
        )
    }
    else {
        $systemParts = @(
            'You are Metra Ask - answer-only portfolio ops assistant.',
            'Follow route-first context. Do not invent live system state without evidence.',
            'DESK HONESTY: Be brief. Do not paste routing furniture (Where / What / Why / Next).',
            'Do not invent operator biography or personal observations - journal is continuity, not personal memory.',
            'Do not promise to write files, save notes, or create Capture entries. For park/save/remember asks, point at Save for portfolio or .\metra.ps1 capture note.',
            $cwdLine
        )
    }

    $evQuality = ''
    if (-not $isInspect -and ($Context -is [hashtable] -or $Context -is [PSCustomObject])) {
        $ev = Get-MetraProp -Object $Context -Name 'evidence' -Default $null
        if ($ev) {
            $evQuality = [string](Get-MetraProp -Object $ev -Name 'quality' -Default '')
            $lim = Get-MetraProp -Object $ev -Name 'limits' -Default $null
            $maxItems = if ($lim) { [int](Get-MetraProp -Object $lim -Name 'maxItems' -Default 6) } else { 6 }
            $maxChars = if ($lim) { [int](Get-MetraProp -Object $lim -Name 'maxCharsPerItem' -Default 400) } else { 400 }
            $maxTotal = if ($lim) { [int](Get-MetraProp -Object $lim -Name 'maxTotalChars' -Default 2400) } else { 2400 }
            $systemParts += "EVIDENCE CONTRACT: quality=$evQuality; limits items<=$maxItems chars/item<=$maxChars total<=$maxTotal."
            if ($evQuality -in @('thin', 'none')) {
                $systemParts += 'evidence.quality is thin/none - answer provisionally; do not invent live Orion/iSupport/host status; give one concrete next check.'
            }
            else {
                $systemParts += 'Ground claims in evidence.items. Journal continuity is not factual unless marked factualSupport.'
            }
        }
        else {
            $systemParts += 'No structured evidence bag - stay provisional; do not invent live system state.'
        }
        if (-not $isInspect) {
            try {
                $ctxJson = ($Context | ConvertTo-Json -Depth 6 -Compress)
                # Ceiling = evidence maxTotalChars * 5 (route/continuity/capability headroom).
                $ceiling = Get-MetraAskOpenAICompatContextJsonMaxChars
                if ($ctxJson -and $ctxJson.Length -lt $ceiling) {
                    $systemParts += "Context JSON: $ctxJson"
                }
            }
            catch { }
        }
    }

    $body = @{
        model       = $model
        messages    = @(
            @{ role = 'system'; content = ($systemParts -join "`n") }
            @{ role = 'user'; content = $Prompt }
        )
        temperature = if ($isInspect) { 0.1 } else { 0.2 }
    }
    if ($isInspect) {
        $body['response_format'] = @{ type = 'json_object' }
        if ($Settings.engine -eq 'ollama') {
            $body['format'] = 'json'
        }
    }
    $url = "$($baseUrl.TrimEnd('/'))/v1/chat/completions"
    $jsonDepth = if ($isInspect) { 12 } else { 8 }

    $invokeChat = {
        param(
            [hashtable]$ChatBody,
            [int]$Depth
        )
        $json = $ChatBody | ConvertTo-Json -Depth $Depth -Compress
        $irmParams = @{
            Uri         = $url
            Method      = 'Post'
            Body        = $json
            ContentType = 'application/json; charset=utf-8'
            TimeoutSec  = $TimeoutSec
        }
        if ($headers.Count -gt 0) { $irmParams['Headers'] = $headers }
        return Invoke-RestMethod @irmParams
    }

    try {
        $response = & $invokeChat -ChatBody $body -Depth $jsonDepth
    }
    catch {
        if ($isInspect -and ($body.ContainsKey('response_format') -or $body.ContainsKey('format')) -and (Test-MetraAskOpenAICompatResponseFormatRejected -Exception $_)) {
            Write-Verbose 'Inspect response_format/format rejected; retrying without json_object/format.'
            $bodyNoFormat = @{} + $body
            $bodyNoFormat.Remove('response_format')
            if ($bodyNoFormat.ContainsKey('format')) { $bodyNoFormat.Remove('format') }
            try {
                $response = & $invokeChat -ChatBody $bodyNoFormat -Depth $jsonDepth
            }
            catch {
                $code = Resolve-MetraAskOpenAICompatErrorCode -Settings $Settings -Exception $_
                return New-MetraAskEngineErrorResult -Settings $Settings -SessionId $SessionId `
                    -ErrorMessage $code -PromptScrub $PromptScrub -CtxScrub $CtxScrub
            }
        }
        else {
            $code = Resolve-MetraAskOpenAICompatErrorCode -Settings $Settings -Exception $_
            return New-MetraAskEngineErrorResult -Settings $Settings -SessionId $SessionId `
                -ErrorMessage $code -PromptScrub $PromptScrub -CtxScrub $CtxScrub
        }
    }

    try {
        $rawMessage = ''
        $choice = @($response.choices) | Select-Object -First 1
        if ($choice) {
            $msg = Get-MetraProp -Object $choice -Name 'message' -Default $null
            if ($msg) {
                $rawMessage = [string](Get-MetraProp -Object $msg -Name 'content' -Default '')
            }
            if ([string]::IsNullOrWhiteSpace($rawMessage)) {
                $rawMessage = [string](Get-MetraProp -Object $choice -Name 'text' -Default '')
            }
        }
        $msgScrub = Invoke-MetraAskSecretsScrubText -Text $rawMessage
        $notice = Join-MetraAskSecretsNotices -Notices @(
            $(if ($PromptScrub.Matched) { $PromptScrub.Notice }),
            $(if ($CtxScrub.Matched) { $CtxScrub.Notice }),
            $(if ($msgScrub.Matched) { $msgScrub.Notice })
        )
        $usedModel = [string](Get-MetraProp -Object $response -Name 'model' -Default $model)
        return [PSCustomObject]@{
            ok              = $true
            message         = [string]$msgScrub.Text
            engine          = $Settings.engine
            model           = $usedModel
            sessionId       = $SessionId
            status          = 'finished'
            error           = $null
            secretsRefuse   = $false
            secretsReason   = $null
            secretsNotice   = $notice
            secretsScrubbed = [bool]($PromptScrub.Matched -or $CtxScrub.Matched -or $msgScrub.Matched)
            secretsKinds    = @($PromptScrub.Kinds) + @($CtxScrub.Kinds) + @($msgScrub.Kinds)
            scrubbedPrompt  = [string]$PromptScrub.Text
        }
    }
    catch {
        $code = Resolve-MetraAskOpenAICompatErrorCode -Settings $Settings -Exception $_
        return New-MetraAskEngineErrorResult -Settings $Settings -SessionId $SessionId `
            -ErrorMessage $code -PromptScrub $PromptScrub -CtxScrub $CtxScrub
    }
}
