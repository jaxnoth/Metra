# OpenAI-compatible Ask complete/health for ollama, enterprise, and llamacpp (PowerShell-native).

function Test-MetraAskOpenAICompatHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [ValidateSet('ollama', 'openai')][string]$Kind = 'openai',
        [int]$TimeoutSec = 2
    )

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { return $false }
    $root = $BaseUrl.TrimEnd('/')
    $urls = @()
    if ($Kind -eq 'ollama') {
        $urls += "$root/api/tags"
        $urls += "$root/v1/models"
    }
    else {
        $urls += "$root/v1/models"
        $urls += "$root/health"
        $urls += $root
    }
    foreach ($url in $urls) {
        try {
            $null = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec
            return $true
        }
        catch {
            try {
                $resp = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec $TimeoutSec -UseBasicParsing
                if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { return $true }
            }
            catch { }
        }
    }
    return $false
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
        $names = @()
        foreach ($m in @($tags.models)) {
            $n = [string](Get-MetraProp -Object $m -Name 'name' -Default '')
            if ($n) { $names += $n }
        }
        $want = $Model.Trim()
        foreach ($n in $names) {
            if ($n -eq $want) { return $true }
            # Ollama may report tag without :latest suffix mismatch
            if ($n.StartsWith("${want}:") -or $want.StartsWith("${n}:")) { return $true }
            if (($n -split ':')[0] -eq ($want -split ':')[0] -and ($want -notmatch ':') ) { return $true }
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

    $systemParts = @(
        'You are Metra Ask - answer-only portfolio ops assistant.',
        'Follow route-first context. Do not invent live system state without evidence.',
        "Working directory: $Cwd"
    )
    if ($Context -is [hashtable] -or $Context -is [PSCustomObject]) {
        try {
            $ctxJson = ($Context | ConvertTo-Json -Depth 6 -Compress)
            if ($ctxJson -and $ctxJson.Length -lt 12000) {
                $systemParts += "Context JSON: $ctxJson"
            }
        }
        catch { }
    }

    $body = @{
        model       = $model
        messages    = @(
            @{ role = 'system'; content = ($systemParts -join "`n") }
            @{ role = 'user'; content = $Prompt }
        )
        temperature = 0.2
    }
    $url = "$($baseUrl.TrimEnd('/'))/v1/chat/completions"
    $json = $body | ConvertTo-Json -Depth 8 -Compress
    try {
        $irmParams = @{
            Uri         = $url
            Method      = 'Post'
            Body        = $json
            ContentType = 'application/json; charset=utf-8'
            TimeoutSec  = $TimeoutSec
        }
        if ($headers.Count -gt 0) { $irmParams['Headers'] = $headers }
        $response = Invoke-RestMethod @irmParams
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
        return New-MetraAskEngineErrorResult -Settings $Settings -SessionId $SessionId `
            -ErrorMessage $_.Exception.Message -PromptScrub $PromptScrub -CtxScrub $CtxScrub
    }
}
