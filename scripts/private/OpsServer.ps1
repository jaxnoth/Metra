# HTML Ops local HTTP server (loopback only). Face = ops/dist; brain = desk payload helpers.

function Get-MetraOpsDistPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Join-Path $MetraRoot 'ops\dist'
}

function Get-MetraOpsContentType {
    param([Parameter(Mandatory)][string]$Path)

    switch -Regex ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '^\.html?$' { return 'text/html; charset=utf-8' }
        '^\.js$' { return 'application/javascript; charset=utf-8' }
        '^\.css$' { return 'text/css; charset=utf-8' }
        '^\.json$' { return 'application/json; charset=utf-8' }
        '^\.svg$' { return 'image/svg+xml' }
        '^\.png$' { return 'image/png' }
        '^\.ico$' { return 'image/x-icon' }
        '^\.woff2?$' { return 'font/woff2' }
        default { return 'application/octet-stream' }
    }
}

function Read-MetraOpsRequestBody {
    param([Parameter(Mandatory)]$Request)

    if (-not $Request.HasEntityBody) { return '' }
    $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Close()
    }
}

function Read-MetraOpsRequestBytes {
    param([Parameter(Mandatory)]$Request)

    if (-not $Request.HasEntityBody) { return [byte[]]@() }
    $ms = New-Object System.IO.MemoryStream
    try {
        $Request.InputStream.CopyTo($ms)
        return $ms.ToArray()
    }
    finally {
        $ms.Dispose()
    }
}

function ConvertFrom-MetraOpsMultipartUpload {
    <#
    .SYNOPSIS
        Extracts the first file part from a multipart/form-data body (field name file preferred).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ContentType
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        throw 'Empty multipart body'
    }
    $ct = $ContentType
    $boundaryMatch = [regex]::Match($ct, 'boundary=(?:"([^"]+)"|([^;]+))', 'IgnoreCase')
    if (-not $boundaryMatch.Success) {
        throw 'multipart boundary missing'
    }
    $boundary = $boundaryMatch.Groups[1].Value
    if (-not $boundary) { $boundary = $boundaryMatch.Groups[2].Value.Trim() }
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    $marker = '--' + $boundary
    $parts = $text -split [regex]::Escape($marker)
    foreach ($part in $parts) {
        if ($part -match 'Content-Disposition:\s*form-data;.*filename="([^"]+)"') {
            $fileName = $Matches[1]
            $contentTypePart = 'application/octet-stream'
            if ($part -match 'Content-Type:\s*([^\r\n]+)') {
                $contentTypePart = $Matches[1].Trim()
            }
            $idx = $part.IndexOf("`r`n`r`n")
            if ($idx -lt 0) { $idx = $part.IndexOf("`n`n") }
            if ($idx -lt 0) { continue }
            $headerLen = if ($part.Substring($idx, 4) -eq "`r`n`r`n") { 4 } else { 2 }
            $bodyStartInPart = $idx + $headerLen
            # Map back to raw bytes via UTF8 is unsafe for binary - locate filename header in raw bytes instead.
            $fileNameBytes = [System.Text.Encoding]::UTF8.GetBytes('filename="' + $fileName + '"')
            $startSearch = [System.Text.Encoding]::UTF8.GetBytes($part.Substring(0, [Math]::Min(800, $part.Length)))
            # Fall through: for binary integrity, find CRLFCRLF after filename in original bytes
            $ascii = [System.Text.Encoding]::ASCII
            $needle = $ascii.GetBytes('filename="' + $fileName + '"')
            $pos = Find-MetraByteSequence -Haystack $Bytes -Needle $needle
            if ($pos -lt 0) { continue }
            $headerEnd = Find-MetraByteSequence -Haystack $Bytes -Needle $ascii.GetBytes("`r`n`r`n") -Start $pos
            $sepLen = 4
            if ($headerEnd -lt 0) {
                $headerEnd = Find-MetraByteSequence -Haystack $Bytes -Needle $ascii.GetBytes("`n`n") -Start $pos
                $sepLen = 2
            }
            if ($headerEnd -lt 0) { continue }
            $dataStart = $headerEnd + $sepLen
            $nextBoundary = Find-MetraByteSequence -Haystack $Bytes -Needle ($ascii.GetBytes("`r`n--" + $boundary)) -Start $dataStart
            if ($nextBoundary -lt 0) {
                $nextBoundary = Find-MetraByteSequence -Haystack $Bytes -Needle ($ascii.GetBytes("`n--" + $boundary)) -Start $dataStart
            }
            if ($nextBoundary -lt 0) { $nextBoundary = $Bytes.Length }
            $len = $nextBoundary - $dataStart
            if ($len -lt 0) { continue }
            $fileBytes = New-Object byte[] $len
            [Array]::Copy($Bytes, $dataStart, $fileBytes, 0, $len)
            # Trim trailing CRLF
            while ($fileBytes.Length -gt 0 -and ($fileBytes[$fileBytes.Length - 1] -eq 10 -or $fileBytes[$fileBytes.Length - 1] -eq 13)) {
                $fileBytes = $fileBytes[0..($fileBytes.Length - 2)]
            }
            return [PSCustomObject]@{
                FileName    = $fileName
                ContentType = $contentTypePart
                Bytes       = $fileBytes
            }
        }
    }
    throw 'No file part found in multipart body'
}

function Find-MetraByteSequence {
    param(
        [byte[]]$Haystack,
        [byte[]]$Needle,
        [int]$Start = 0
    )
    if ($null -eq $Haystack -or $null -eq $Needle -or $Needle.Length -eq 0) { return -1 }
    $limit = $Haystack.Length - $Needle.Length
    for ($i = $Start; $i -le $limit; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) { $ok = $false; break }
        }
        if ($ok) { return $i }
    }
    return -1
}

function Write-MetraOpsJsonResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)]$Object,
        [int]$StatusCode = 200,
        [int]$Depth = 10
    )

    $json = ($Object | ConvertTo-Json -Depth $Depth -Compress)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-MetraOpsTextResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$Text,
        [int]$StatusCode = 200,
        [string]$ContentType = 'text/plain; charset=utf-8'
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Write-MetraOpsFileResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$FilePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.StatusCode = 200
    $Response.ContentType = Get-MetraOpsContentType -Path $FilePath
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

function Invoke-MetraOpsApi {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $method = $Request.HttpMethod.ToUpperInvariant()
    $path = $Request.Url.AbsolutePath.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) { $path = '/' }

    try {
        if ($method -eq 'GET' -and $path -eq '/api/meta') {
            # Read the version without Import-PowerShellDataFile: that command does not always
            # resolve from module scope under Windows PowerShell, which 500s this endpoint.
            $manifestVersion = [string](Get-Module -Name Metra | Select-Object -First 1).Version
            if (-not $manifestVersion) {
                $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
                if (Test-Path -LiteralPath $psd1) {
                    $match = [regex]::Match((Get-Content -LiteralPath $psd1 -Raw), "ModuleVersion\s*=\s*'([^']+)'")
                    if ($match.Success) { $manifestVersion = $match.Groups[1].Value }
                }
            }
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    version   = $manifestVersion
                    metraRoot = $MetraRoot
                    homeLabel = $MetraRoot
                })
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/snapshot') {
            $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/refresh') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $full = $false
            if ($body) {
                try {
                    $parsed = $body | ConvertFrom-Json
                    $full = [bool](Get-MetraProp -Object $parsed -Name 'full' -Default $false)
                }
                catch { }
            }
            $payload = Get-MetraDeskPayload -Refresh -Full:$full -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/preferences') {
            Write-MetraOpsJsonResponse -Response $Response -Object (Get-MetraDeskPreferences -MetraRoot $MetraRoot)
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/settings') {
            Write-MetraOpsJsonResponse -Response $Response -Object (Get-MetraSettingsPortfolio -MetraRoot $MetraRoot) -Depth 8
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/updates') {
            $force = $false
            try {
                $q = [string]$Request.Url.Query
                if ($q -match '[?&]force=1' -or $q -match '[?&]force=true') { $force = $true }
            }
            catch { }
            Write-MetraOpsJsonResponse -Response $Response -Object (Get-MetraProductUpdates -MetraRoot $MetraRoot -Force:$force) -Depth 8
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/updates') {
            $isLocalCaller = Test-MetraOpsRequestIsSameMachine -Request $Request
            $sessionToken = ''
            try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
            if (-not $isLocalCaller -and -not (Test-MetraOpsLocalSessionToken -SessionToken $sessionToken)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Updates run on the operator machine only.'
                        reasonCode = 'updatesLocalOnly'
                    })
                return
            }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = if ($body) { $body | ConvertFrom-Json } else { [PSCustomObject]@{} }
                $target = [string](Get-MetraProp -Object $parsed -Name 'target' -Default '').Trim().ToLowerInvariant()
                if ($target -notin @('metra', 'ollama')) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = 'target must be metra or ollama'
                        })
                    return
                }
                $result = Invoke-MetraProductUpdate -Target $target -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $result -Depth 8
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'PUT' -and $path -eq '/api/settings') {
            # Config + API key writes stay on the operator machine (loopback or Host session).
            $isLocalCaller = Test-MetraOpsRequestIsSameMachine -Request $Request
            $sessionToken = ''
            try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
            if (-not $isLocalCaller -and -not (Test-MetraOpsLocalSessionToken -SessionToken $sessionToken)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Settings changes run on the operator machine only.'
                        reasonCode = 'settingsLocalOnly'
                    })
                return
            }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = if ($body) { $body | ConvertFrom-Json } else { [PSCustomObject]@{} }
                $setArgs = @{ MetraRoot = $MetraRoot }
                $rootsPayload = Get-MetraProp -Object $parsed -Name 'roots' -Default $null
                if ($null -ne $rootsPayload) {
                    $setArgs['Roots'] = @($rootsPayload)
                }
                else {
                    # Legacy two-field Settings body.
                    $primaryPath = Get-MetraProp -Object $parsed -Name 'primaryPath' -Default $null
                    if ($null -ne $primaryPath -and -not [string]::IsNullOrWhiteSpace([string]$primaryPath)) {
                        $setArgs['PrimaryPath'] = [string]$primaryPath
                    }
                    if ($null -ne (Get-MetraProp -Object $parsed -Name 'personalPath' -Default $null) -or
                        [bool](Get-MetraProp -Object $parsed -Name 'clearPersonal' -Default $false)) {
                        $clearPersonal = [bool](Get-MetraProp -Object $parsed -Name 'clearPersonal' -Default $false)
                        $personalPath = [string](Get-MetraProp -Object $parsed -Name 'personalPath' -Default '')
                        if ($clearPersonal -or [string]::IsNullOrWhiteSpace($personalPath)) {
                            $setArgs['ClearPersonal'] = $true
                        }
                        else {
                            $setArgs['PersonalPath'] = $personalPath
                        }
                    }
                }
                if ([bool](Get-MetraProp -Object $parsed -Name 'clearCursorApiKey' -Default $false)) {
                    $setArgs['ClearCursorApiKey'] = $true
                }
                else {
                    $cursorKey = Get-MetraProp -Object $parsed -Name 'cursorApiKey' -Default $null
                    if ($null -ne $cursorKey -and -not [string]::IsNullOrWhiteSpace([string]$cursorKey)) {
                        $setArgs['CursorApiKey'] = [string]$cursorKey
                    }
                }
                $result = Save-MetraSettingsPortfolio @setArgs
                Write-MetraOpsJsonResponse -Response $Response -Object $result -Depth 8
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/local-session') {
            # Loopback-only: browser / webview on the operator machine may fetch the Host session marker.
            if (-not (Test-MetraOpsRequestIsLoopback -Request $Request)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Local session token is only available on loopback.'
                        reasonCode = 'localSessionLoopbackOnly'
                    })
                return
            }
            $issued = Initialize-MetraOpsLocalSessionToken
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    token   = [string]$issued.Token
                    created = [bool]$issued.Created
                    header  = 'X-Metra-Local-Session'
                })
            return
        }

        if ($method -eq 'PUT' -and $path -eq '/api/preferences') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $body | ConvertFrom-Json
            $setArgs = @{ MetraRoot = $MetraRoot }
            if ($null -ne (Get-MetraProp -Object $parsed -Name 'deskMode' -Default $null)) {
                $mode = [string](Get-MetraProp -Object $parsed -Name 'deskMode' -Default 'general')
                if ($mode -notin @('general', 'advanced')) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'deskMode must be general or advanced' })
                    return
                }
                $setArgs['DeskMode'] = $mode
            }
            if ($null -ne (Get-MetraProp -Object $parsed -Name 'attentionVisibleCount' -Default $null)) {
                try {
                    $vis = [int](Get-MetraProp -Object $parsed -Name 'attentionVisibleCount' -Default 1)
                }
                catch {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'attentionVisibleCount must be an integer 1-10' })
                    return
                }
                $setArgs['AttentionVisibleCount'] = $vis
            }
            if ($null -ne (Get-MetraProp -Object $parsed -Name 'editorCommand' -Default $null)) {
                $setArgs['EditorCommand'] = [string](Get-MetraProp -Object $parsed -Name 'editorCommand' -Default 'auto')
            }
            if ($setArgs.Keys.Count -le 1) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'deskMode, attentionVisibleCount, or editorCommand required' })
                return
            }
            $prefs = Set-MetraDeskPreferences @setArgs
            Write-MetraOpsJsonResponse -Response $Response -Object $prefs
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/open') {
            # Desk process launches the editor; the browser cannot. Reach is split from authority:
            # loopback, or a Host-issued local session marker for non-loopback surfaces.
            $isLocalCaller = Test-MetraOpsRequestIsSameMachine -Request $Request
            $sessionToken = ''
            try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
            if (-not $isLocalCaller -and -not (Test-MetraOpsLocalSessionToken -SessionToken $sessionToken)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Open in editor runs on the operator machine only. Use the desk on that machine, or open the folder there manually.'
                        reasonCode = 'openLocalOnly'
                    })
                return
            }
            $body = Read-MetraOpsRequestBody -Request $Request
            $openPath = ''
            if ($body) {
                try {
                    $parsed = $body | ConvertFrom-Json
                    $openPath = [string](Get-MetraProp -Object $parsed -Name 'path' -Default '')
                }
                catch { }
            }
            try {
                $result = Invoke-MetraOpsOpenInEditor -Path $openPath -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $result
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        $attnMatch = [regex]::Match($path, '^/api/attention/([^/]+)/(dismiss|snooze|reopen|hold|release|note)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($method -eq 'POST' -and $attnMatch.Success) {
            $attnKey = [System.Uri]::UnescapeDataString($attnMatch.Groups[1].Value)
            $action = $attnMatch.Groups[2].Value.ToLowerInvariant()
            $days = 1
            $note = ''
            $body = Read-MetraOpsRequestBody -Request $Request
            if ($body) {
                try {
                    $parsed = $body | ConvertFrom-Json
                    if ($action -eq 'snooze') {
                        $days = [int](Get-MetraProp -Object $parsed -Name 'days' -Default 1)
                    }
                    $note = [string](Get-MetraProp -Object $parsed -Name 'note' -Default '')
                }
                catch {
                    if ($action -eq 'snooze') { $days = 1 }
                }
            }
            try {
                $null = Invoke-MetraAttentionMutation -Key $attnKey -Action $action -Days $days -Note $note -MetraRoot $MetraRoot
                $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $payload
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 404 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/ask') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $prompt = [string](Get-MetraProp -Object $parsed -Name 'prompt' -Default '')
            $sessionId = [string](Get-MetraProp -Object $parsed -Name 'sessionId' -Default '')
            $recallSessionId = [string](Get-MetraProp -Object $parsed -Name 'recallSessionId' -Default '')
            if ([string]::IsNullOrWhiteSpace($prompt)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'prompt required' })
                return
            }
            $headerClient = ''
            try { $headerClient = [string]$Request.Headers['X-Metra-Client'] } catch { }
            $bodyClient = [string](Get-MetraProp -Object $parsed -Name 'client' -Default '')
            $clientHintBody = [string](Get-MetraProp -Object $parsed -Name 'clientHint' -Default '')
            $userAgent = ''
            try { $userAgent = [string]$Request.UserAgent } catch { }
            $client = Resolve-MetraAskClientId -HeaderClient $headerClient -BodyClient $bodyClient -UserAgent $userAgent
            $clientHint = Resolve-MetraAskClientHint -Client $client -UserAgent $userAgent -BodyHint $clientHintBody
            $isLoopback = Test-MetraOpsRequestIsSameMachine -Request $Request
            $sessionToken = ''
            try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
            $hasLocalSession = Test-MetraOpsLocalSessionToken -SessionToken $sessionToken
            $origin = Resolve-MetraAskOrigin -IsLoopback $isLoopback -HasLocalSession $hasLocalSession

            $ask = Get-MetraDeskAskResult -Prompt $prompt -SessionId $sessionId -RecallSessionId $recallSessionId -MetraRoot $MetraRoot
            $journalSession = [string]$ask.sessionId
            if ([string]::IsNullOrWhiteSpace($journalSession)) { $journalSession = $sessionId }
            $journalPrompt = [string](Get-MetraProp -Object $ask -Name 'scrubbedPrompt' -Default $prompt)
            if ([string]::IsNullOrWhiteSpace($journalPrompt)) { $journalPrompt = $prompt }
            $entry = Add-MetraDeskAskEntry `
                -Prompt $journalPrompt `
                -Handoff $ask.handoff `
                -Message ([string]$ask.message) `
                -SessionId $journalSession `
                -Origin $origin `
                -Client $client `
                -ClientHint $clientHint `
                -Engine ([string]$ask.engine) `
                -Model ([string]$ask.model) `
                -Answered ([bool]$ask.answered) `
                -Capability $ask.capability `
                -MetraRoot $MetraRoot
            $showWhere = Test-MetraAskShowWhere -Handoff $ask.handoff
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    entry           = $entry
                    handoff         = $ask.handoff
                    message         = [string]$ask.message
                    sessionId       = [string]$entry.sessionId
                    capability      = $ask.capability
                    engine          = $ask.engine
                    model           = $ask.model
                    answered        = [bool]$ask.answered
                    showWhere       = [bool]$showWhere
                    continuity      = $ask.continuity
                    secretsScrubbed = [bool](Get-MetraProp -Object $ask -Name 'secretsScrubbed' -Default $false)
                    secretsNotice   = $(Get-MetraProp -Object $ask -Name 'secretsNotice' -Default $null)
                    secretsKinds    = @(Get-MetraProp -Object $ask -Name 'secretsKinds' -Default @())
                    secretsReason   = $(Get-MetraProp -Object $ask -Name 'secretsReason' -Default $null)
                }) -Depth 12
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/ask/engine') {
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    settings       = (Get-MetraAskSettings -MetraRoot $MetraRoot)
                    capability     = (Get-MetraAskCapability -MetraRoot $MetraRoot)
                    recommendation = (Get-MetraAskEngineRecommendation -MetraRoot $MetraRoot)
                    menu           = @(Get-MetraAskEngineMenu -MetraRoot $MetraRoot)
                }) -Depth 10
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/ask/engine') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $action = [string](Get-MetraProp -Object $body -Name 'action' -Default 'set').Trim().ToLowerInvariant()
            if ($action -eq 'accept') {
                $result = Invoke-MetraAskAcceptRecommended -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $result -Depth 10
                return
            }
            if ($action -eq 'set') {
                $engine = [string](Get-MetraProp -Object $body -Name 'engine' -Default '').Trim().ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($engine)) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'engine required' })
                    return
                }
                $model = Get-MetraProp -Object $body -Name 'model' -Default $null
                $band = Get-MetraProp -Object $body -Name 'sizeBand' -Default $null
                $p = @{ Engine = $engine; MetraRoot = $MetraRoot }
                if ($model) { $p['Model'] = [string]$model }
                if ($band) { $p['SizeBand'] = [string]$band }
                try {
                    $cap = Set-MetraAskEngine @p
                    Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                            ok         = $true
                            capability = $cap
                            menu       = @(Get-MetraAskEngineMenu -MetraRoot $MetraRoot)
                        }) -Depth 10
                }
                catch {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                }
                return
            }
            Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'action must be set or accept' })
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/ask/journal') {
            $limit = 40
            $sessionIdFilter = ''
            $searchQuery = ''
            try {
                $q = [string]$Request.Url.Query
                if ($q -match '[?&]limit=(\d+)') { $limit = [Math]::Min(100, [int]$Matches[1]) }
                if ($q -match '[?&]sessionId=([^&]+)') {
                    $sessionIdFilter = [uri]::UnescapeDataString($Matches[1])
                }
                if ($q -match '[?&]q=([^&]+)') {
                    $searchQuery = [uri]::UnescapeDataString($Matches[1])
                }
            }
            catch { }

            if (-not [string]::IsNullOrWhiteSpace($searchQuery)) {
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        query = $searchQuery
                        hits  = @(Search-MetraDeskAskJournal -Query $searchQuery -Limit $limit -MetraRoot $MetraRoot)
                    }) -Depth 12
                return
            }

            if (-not [string]::IsNullOrWhiteSpace($sessionIdFilter)) {
                $turns = @(Get-MetraDeskAskSessionTurns -SessionId $sessionIdFilter -MetraRoot $MetraRoot -Limit $limit)
                $continuity = Get-MetraAskContinuityContext -SessionId $sessionIdFilter -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        sessionId  = $sessionIdFilter
                        turnCount  = $turns.Count
                        continuity = $continuity
                        turns      = $turns
                    }) -Depth 12
                return
            }

            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    sessions = @(Get-MetraDeskAskSessionSummaries -MetraRoot $MetraRoot -Limit 12)
                    turns    = @(Get-MetraDeskAskLog -MetraRoot $MetraRoot -Limit $limit)
                }) -Depth 12
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/capture') {
            $status = 'candidate'
            try {
                $q = [string]$Request.Url.Query
                if ($q -match '[?&]status=(candidate|promoted|dismissed|all)') { $status = $Matches[1] }
            }
            catch { }
            Write-MetraOpsJsonResponse -Response $Response -Object (@(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 40 -Status $status)) -Depth 10
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/capture') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            try {
                $turnId = [string](Get-MetraProp -Object $parsed -Name 'turnId' -Default '')
                $sessionId = [string](Get-MetraProp -Object $parsed -Name 'sessionId' -Default '')
                $summary = [string](Get-MetraProp -Object $parsed -Name 'summary' -Default '')
                $capBody = [string](Get-MetraProp -Object $parsed -Name 'body' -Default '')
                $source = [string](Get-MetraProp -Object $parsed -Name 'source' -Default '')
                $placeId = [string](Get-MetraProp -Object $parsed -Name 'placeId' -Default '')
                $homeId = [string](Get-MetraProp -Object $parsed -Name 'homeId' -Default '')
                $text = [string](Get-MetraProp -Object $parsed -Name 'text' -Default '')
                $attachmentIds = @()
                try {
                    $rawAtt = Get-MetraProp -Object $parsed -Name 'attachmentIds' -Default @()
                    $attachmentIds = @($rawAtt | ForEach-Object { [string]$_ } | Where-Object { $_ })
                }
                catch { }

                $item = $null
                if (-not [string]::IsNullOrWhiteSpace($turnId) -or $source -eq 'ask') {
                    if ([string]::IsNullOrWhiteSpace($turnId)) {
                        Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'turnId required for ask capture' })
                        return
                    }
                    $item = Add-MetraCaptureFromAskTurn -TurnId $turnId -SessionId $sessionId -Summary $summary -Body $capBody -MetraRoot $MetraRoot
                }
                elseif ($source -eq 'place' -or (-not [string]::IsNullOrWhiteSpace($homeId) -and -not [string]::IsNullOrWhiteSpace($text))) {
                    $item = Add-MetraCaptureFromPlace -Text $(if ($text) { $text } else { $summary }) -HomeId $homeId -PlaceId $placeId -AttachmentIds $attachmentIds -MetraRoot $MetraRoot
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($summary)) {
                        Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'summary required for manual capture' })
                        return
                    }
                    $derived = New-MetraCaptureDerivedFrom -Type manual
                    $item = Add-MetraCaptureItem -Summary $summary -Body $capBody -Source manual -DerivedFrom $derived -MetraRoot $MetraRoot
                }
                Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        $captureMut = [regex]::Match($path, '^/api/capture/([^/]+)(?:/(dismiss|promote))?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($captureMut.Success -and $method -in @('POST', 'PATCH', 'PUT')) {
            $capId = [System.Uri]::UnescapeDataString($captureMut.Groups[1].Value)
            $capAction = [string]$captureMut.Groups[2].Value
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) {
                try { $parsed = $body | ConvertFrom-Json } catch { $parsed = $null }
            }
            try {
                if ($capAction -eq 'dismiss' -or ($method -eq 'POST' -and [string](Get-MetraProp -Object $parsed -Name 'status' -Default '') -eq 'dismissed')) {
                    $item = Dismiss-MetraCaptureItem -Id $capId -MetraRoot $MetraRoot
                    Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
                    return
                }
                if ($capAction -eq 'promote') {
                    $home = [string](Get-MetraProp -Object $parsed -Name 'home' -Default '')
                    $item = Invoke-MetraCapturePromote -Id $capId -Home $home -MetraRoot $MetraRoot
                    Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
                    return
                }
                if ($null -ne $parsed -and $parsed.PSObject.Properties.Name -contains 'derivedFrom') {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = 'derivedFrom is immutable after capture creation'
                        })
                    return
                }
                $updParams = @{ Id = $capId; MetraRoot = $MetraRoot }
                $sum = [string](Get-MetraProp -Object $parsed -Name 'summary' -Default '')
                if (-not [string]::IsNullOrWhiteSpace($sum)) { $updParams.Summary = $sum }
                if ($null -ne $parsed -and $parsed.PSObject.Properties.Name -contains 'body') {
                    $updParams.Body = [string](Get-MetraProp -Object $parsed -Name 'body' -Default '')
                }
                $sh = [string](Get-MetraProp -Object $parsed -Name 'suggestedHome' -Default '')
                if (-not [string]::IsNullOrWhiteSpace($sh)) { $updParams.SuggestedHome = $sh }
                $sp = [string](Get-MetraProp -Object $parsed -Name 'suggestedProject' -Default '')
                if (-not [string]::IsNullOrWhiteSpace($sp)) { $updParams.SuggestedProject = $sp }
                $st = [string](Get-MetraProp -Object $parsed -Name 'status' -Default '')
                if ($st -match '^(candidate|promoted|dismissed)$') { $updParams.Status = $st }
                $item = Update-MetraCaptureItem @updParams
                Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/place') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $text = [string](Get-MetraProp -Object $parsed -Name 'text' -Default '')
            if ([string]::IsNullOrWhiteSpace($text)) {
                $text = [string](Get-MetraProp -Object $parsed -Name 'query' -Default '')
            }
            $attachments = @()
            try {
                $rawAtt = Get-MetraProp -Object $parsed -Name 'attachments' -Default @()
                $attachments = @($rawAtt | ForEach-Object { [string]$_ } | Where-Object { $_ })
            }
            catch { }
            $place = Get-MetraDeskPlaceRecommendation -Text $text -AttachmentIds $attachments -MetraRoot $MetraRoot
            if (-not $place.ok) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object $place
                return
            }
            Write-MetraOpsJsonResponse -Response $Response -Object $place -Depth 12
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/place/upload') {
            try {
                $contentType = [string]$Request.ContentType
                $meta = $null
                if ($contentType -match 'multipart/form-data') {
                    $bytes = Read-MetraOpsRequestBytes -Request $Request
                    $part = ConvertFrom-MetraOpsMultipartUpload -Bytes $bytes -ContentType $contentType
                    $meta = Save-MetraPlaceUpload -FileName $part.FileName -Bytes $part.Bytes -ContentType $part.ContentType
                }
                else {
                    $body = Read-MetraOpsRequestBody -Request $Request
                    $parsed = $body | ConvertFrom-Json
                    $fileName = [string](Get-MetraProp -Object $parsed -Name 'fileName' -Default '')
                    $b64 = [string](Get-MetraProp -Object $parsed -Name 'contentBase64' -Default '')
                    $ct = [string](Get-MetraProp -Object $parsed -Name 'contentType' -Default 'application/octet-stream')
                    if ([string]::IsNullOrWhiteSpace($fileName) -or [string]::IsNullOrWhiteSpace($b64)) {
                        Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'fileName and contentBase64 required' })
                        return
                    }
                    $fileBytes = [Convert]::FromBase64String($b64)
                    $meta = Save-MetraPlaceUpload -FileName $fileName -Bytes $fileBytes -ContentType $ct
                }
                Write-MetraOpsJsonResponse -Response $Response -Object $meta
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/place/confirm') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $text = [string](Get-MetraProp -Object $parsed -Name 'text' -Default '')
            $homeId = [string](Get-MetraProp -Object $parsed -Name 'homeId' -Default '')
            $keep = [bool](Get-MetraProp -Object $parsed -Name 'keepInView' -Default $false)
            $saveForPortfolio = [bool](Get-MetraProp -Object $parsed -Name 'saveForPortfolio' -Default $false)
            $confirmAttachments = @()
            try {
                $rawConfirmAtt = Get-MetraProp -Object $parsed -Name 'attachments' -Default @()
                $confirmAttachments = @($rawConfirmAtt | ForEach-Object { [string]$_ } | Where-Object { $_ })
            }
            catch { }
            if ([string]::IsNullOrWhiteSpace($text) -or [string]::IsNullOrWhiteSpace($homeId)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'text and homeId required' })
                return
            }
            try {
                $result = Invoke-MetraPlaceConfirm -Text $text -HomeId $homeId -KeepInView:$keep -SaveForPortfolio:$saveForPortfolio -AttachmentIds $confirmAttachments -MetraRoot $MetraRoot
                # Rebuild desk when Attention or Capture changed.
                $payload = $null
                if ($result.attentionKey -or $result.captureId) { $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot }
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        result = $result
                        desk   = $payload
                    }) -Depth 20
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/place/correct') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $text = [string](Get-MetraProp -Object $parsed -Name 'text' -Default '')
            $homeId = [string](Get-MetraProp -Object $parsed -Name 'homeId' -Default '')
            if ([string]::IsNullOrWhiteSpace($text) -or [string]::IsNullOrWhiteSpace($homeId)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'text and homeId required' })
                return
            }
            try {
                $result = Invoke-MetraPlaceCorrect -Text $text -HomeId $homeId -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $result
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/place/homes') {
            Write-MetraOpsJsonResponse -Response $Response -Object (@(Get-MetraPlaceHomeCatalog))
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/classify') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) { $parsed = $body | ConvertFrom-Json }
            $query = [string](Get-MetraProp -Object $parsed -Name 'query' -Default '')
            if ([string]::IsNullOrWhiteSpace($query)) {
                $query = [string](Get-MetraProp -Object $parsed -Name 'prompt' -Default '')
            }
            $handoff = Get-MetraDeskHandoff -Query $query -MetraRoot $MetraRoot
            Write-MetraOpsJsonResponse -Response $Response -Object $handoff
            return
        }

        if ($path -eq '/api/proposals' -or $path.StartsWith('/api/proposals/', [StringComparison]::OrdinalIgnoreCase)) {
            $body = ''
            if ($method -in @('POST', 'PUT', 'PATCH')) {
                $body = Read-MetraOpsRequestBody -Request $Request
            }
            $sessionToken = ''
            try {
                $sessionToken = [string]$Request.Headers['X-Metra-Local-Session']
            }
            catch { }
            $result = Invoke-MetraOpsProposalCommand `
                -Method $method `
                -Path $path `
                -Body $body `
                -IsLoopback:(Test-MetraOpsRequestIsLoopback -Request $Request) `
                -SessionToken $sessionToken `
                -MetraRoot $MetraRoot
            if ($null -eq $result) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 404 -Object ([PSCustomObject]@{ error = 'not found' })
                return
            }
            if ($result.Text) {
                $contentType = if ($result.ContentType) { [string]$result.ContentType } else { 'text/plain; charset=utf-8' }
                Write-MetraOpsTextResponse -Response $Response -StatusCode ([int]$result.StatusCode) -Text ([string]$result.Text) -ContentType $contentType
                return
            }
            Write-MetraOpsJsonResponse -Response $Response -StatusCode ([int]$result.StatusCode) -Object $result.Object -Depth 30
            return
        }

        Write-MetraOpsJsonResponse -Response $Response -StatusCode 404 -Object ([PSCustomObject]@{ error = 'not found' })
    }
    catch {
        Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                error = [string]$_.Exception.Message
            })
    }
}

function Invoke-MetraOpsStatic {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$DistPath
    )

    $rel = [System.Uri]::UnescapeDataString($Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($rel) -or $rel -eq '/') {
        $rel = 'index.html'
    }
    $rel = $rel -replace '/', '\'
    if ($rel.Contains('..')) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 400 -Text 'Bad path'
        return
    }

    $candidate = Join-Path $DistPath $rel
    if (-not (Test-Path -LiteralPath $candidate) -or (Get-Item -LiteralPath $candidate) -isnot [System.IO.FileInfo]) {
        # SPA fallback
        $candidate = Join-Path $DistPath 'index.html'
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 404 -Text 'Ops UI not built. Run npm run build in ops/ (contributors) or reinstall Metra.'
        return
    }

    Write-MetraOpsFileResponse -Response $Response -FilePath $candidate
}

function Get-MetraOpsPidFile {
    param([int]$Port = 7380)

    $dir = Join-Path $env:LOCALAPPDATA 'Metra'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return Join-Path $dir "ops-$Port.pid"
}

function Test-MetraOpsDeskResponding {
    <#
    .SYNOPSIS
        True when a Metra desk already answers on the loopback port.
    #>
    param(
        [int]$Port = 7380,
        [int]$TimeoutSec = 3
    )

    try {
        $api = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/meta" -UseBasicParsing -TimeoutSec $TimeoutSec
        if ($api.StatusCode -eq 200) { return $true }
    }
    catch { }

    # An API fault still means a desk owns the port, so fall back to the served shell.
    try {
        $root = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($root.StatusCode -eq 200 -and $root.Content -match 'Metra Ops')
    }
    catch {
        return $false
    }
}

function Get-MetraOpsListenerProcessId {
    <#
    .SYNOPSIS
        Finds the process holding an HTTP.sys registration for the loopback port.
    .DESCRIPTION
        Get-NetTCPConnection reports PID 4 (System) for every HttpListener, so ask HTTP.sys
        which process owns the request queue that registered this URL. Recovers desks whose
        console died while the process kept the port.
    #>
    param([int]$Port = 7380)

    try {
        $lines = netsh http show servicestate view=requestq 2>$null
    }
    catch {
        return $null
    }
    if (-not $lines) { return $null }

    $ownerPid = $null
    foreach ($line in $lines) {
        # The Processes block precedes the URL groups it registered.
        $owner = [regex]::Match($line, 'ID:\s*(\d+),\s*image:')
        if ($owner.Success) {
            $ownerPid = [int]$owner.Groups[1].Value
            continue
        }
        if ($line -match ":$Port(:|/)") {
            if ($ownerPid -and $ownerPid -ne $PID) { return $ownerPid }
        }
    }
    return $null
}

function Stop-MetraOpsServer {
    <#
    .SYNOPSIS
        Stops a Metra Ops desk on a loopback port, including one orphaned by a closed console.
    #>
    [CmdletBinding()]
    param([int]$Port = 7380)

    $pidFile = Get-MetraOpsPidFile -Port $Port
    $target = $null

    if (Test-Path -LiteralPath $pidFile) {
        $recorded = 0
        if ([int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref]$recorded)) {
            if ($recorded -ne $PID -and (Get-Process -Id $recorded -ErrorAction SilentlyContinue)) {
                $target = $recorded
            }
        }
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    }

    if (-not $target) {
        $target = Get-MetraOpsListenerProcessId -Port $Port
    }

    if (-not $target) {
        Write-Host "No Metra Ops desk found on port $Port." -ForegroundColor DarkGray
        return
    }

    try {
        Stop-Process -Id $target -Force -ErrorAction Stop
        Write-Host "Stopped Metra Ops desk on port $Port (process $target)." -ForegroundColor Green
        try { Stop-MetraAskEngine } catch { }
    }
    catch {
        throw "Could not stop process $target holding port $Port - $($_.Exception.Message)"
    }
}

function Start-MetraOpsServer {
    <#
    .SYNOPSIS
        Starts the HTML Ops localhost server and optionally opens the browser.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [switch]$Quick,
        [switch]$Full,
        [switch]$NoBrowser,
        [switch]$NoRefresh,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $binding = $null
    if ($Port -le 0) {
        $binding = Resolve-MetraOpsDeskBinding -MetraRoot $MetraRoot
        $Port = [int]$binding.Port
    }
    else {
        $binding = Get-MetraOpsDeskBindingForPort -Port $Port -MetraRoot $MetraRoot
    }

    if ($Port -lt 1 -or $Port -gt 65535) {
        throw "Invalid port: $Port"
    }

    # When Tailscale reach is on, orchestrate Serve so the share URL is HTTPS (secure context).
    $isTailscalePref = $false
    try { $isTailscalePref = [bool](Get-MetraProp -Object $binding -Name 'Tailscale' -Default $false) } catch { }
    if ($isTailscalePref) {
        $serve = Enable-MetraOpsTailscaleServe -Port $Port
        $binding = Get-MetraOpsDeskBindingForPort -Port $Port -MetraRoot $MetraRoot
        if (-not $serve.Ok) {
            Write-Warning ("Tailscale Serve HTTPS unavailable: {0}. Desk stays on loopback; do not treat plain http MagicDNS as the primary phone URL." -f $serve.Reason)
        }
    }

    $url = [string]$binding.BrowserUrl
    if (Test-MetraOpsDeskResponding -Port $Port) {
        Write-Host ("Metra Ops desk already serving {0}" -f $url) -ForegroundColor Green
        Write-Host ("Restart it with: .\metra.ps1 ops -Stop -Port {0}" -f $Port) -ForegroundColor DarkGray
        if (-not $NoBrowser) {
            try { Start-Process $url | Out-Null } catch { }
        }
        return
    }

    $dist = Get-MetraOpsDistPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath (Join-Path $dist 'index.html'))) {
        Write-Warning "Missing ops/dist (expected index.html under $dist). Build with: cd ops; npm install; npm run build"
    }

    if (-not $NoRefresh) {
        Write-Host 'Refreshing desk snapshot...' -ForegroundColor Cyan
        $null = Get-MetraDeskPayload -Refresh -Full:$Full -MetraRoot $MetraRoot
    }

    $listener = New-Object System.Net.HttpListener
    foreach ($prefix in @($binding.ListenerPrefixes)) {
        $listener.Prefixes.Add($prefix)
    }
    try {
        $listener.Start()
    }
    catch {
        $held = Get-MetraOpsListenerProcessId -Port $Port
        $hint = if ($held) {
            "Process $held still holds it (a desk whose console closed?). Free it with: .\metra.ps1 ops -Stop -Port $Port"
        }
        else {
            "Try -Port with another number, or run Initialize-MetraOpsDeskBinding after elevating for port 80."
        }
        throw "Could not bind $($binding.ListenerPrefixes -join ', ') - $($_.Exception.Message). $hint"
    }

    $pidFile = Get-MetraOpsPidFile -Port $Port
    Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

    Write-Host ("Metra Ops desk: {0}" -f $url) -ForegroundColor Green
    $isTailscale = $false
    try { $isTailscale = [bool](Get-MetraProp -Object $binding -Name 'Tailscale' -Default $false) } catch { }
    if ($isTailscale) {
        $serveOn = $false
        try { $serveOn = [bool](Get-MetraProp -Object $binding -Name 'Serve' -Default $false) } catch { }
        if ($serveOn) {
            Write-Host 'Tailscale Serve HTTPS share enabled (view/ask for peers). Propose and request-apply need X-Metra-Local-Session; tray Apply once still gates disk writes.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host 'Tailscale reach enabled without Serve HTTPS (view/ask for peers). Clipboard APIs need a secure context - fix Serve or use loopback.' -ForegroundColor DarkYellow
            $serveErr = [string](Get-MetraProp -Object $binding -Name 'ServeError' -Default '')
            if ($serveErr) { Write-Warning $serveErr }
        }
        Write-Host ("Share URL: {0}" -f $url) -ForegroundColor Cyan
    }
    else {
        Write-Host 'Loopback bind. Press Ctrl+C to stop.' -ForegroundColor DarkGray
    }

    try {
        $null = Initialize-MetraOpsLocalSessionToken
    }
    catch {
        Write-Warning "Could not ensure local session token: $($_.Exception.Message)"
    }

    # Operator-tier Ask engine (temporary until installer ships Node + sidecar).
    $askCap = Start-MetraAskEngine -MetraRoot $MetraRoot
    if ($askCap.available) {
        Write-Host ("Ask engine available ({0})." -f $askCap.providerLabel) -ForegroundColor DarkGray
    }
    elseif ($askCap.selected) {
        Write-Host ("Ask engine selected but unavailable ({0})." -f $askCap.reason) -ForegroundColor DarkYellow
    }

    if (-not $NoBrowser) {
        try {
            Start-Process $url | Out-Null
        }
        catch {
            Write-Warning "Could not open browser: $($_.Exception.Message)"
        }
    }

    # GetContext() blocks forever and swallows Ctrl+C, so poll BeginGetContext instead: the
    # timed waits give PowerShell statement boundaries where it can deliver its own Ctrl+C
    # (PipelineStopped) and run the finally block below.
    #
    # Do not register a [System.ConsoleCancelEventHandler] scriptblock here. .NET invokes that
    # delegate on the console control thread, and a scriptblock cannot run there while this
    # runspace is busy in the accept loop - the resulting exception is unhandled on a native
    # callback thread and takes the whole console host down instead of stopping the server.
    try {
        while ($listener.IsListening) {
            $async = $null
            try {
                $async = $listener.BeginGetContext($null, $null)
            }
            catch {
                break
            }

            while (-not $async.IsCompleted) {
                if (-not $listener.IsListening) { break }
                # Timed wait lets Ctrl+C / pipeline stop run between polls.
                if ($async.AsyncWaitHandle.WaitOne(250)) { break }
            }

            if (-not $listener.IsListening) { break }
            if (-not $async.IsCompleted) { continue }

            try {
                $context = $listener.EndGetContext($async)
            }
            catch {
                break
            }

            $req = $context.Request
            $res = $context.Response
            $res.Headers['Access-Control-Allow-Origin'] = '*'
            $res.Headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, OPTIONS'
            $res.Headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Metra-Local-Session'

            if ($req.HttpMethod -eq 'OPTIONS') {
                $res.StatusCode = 204
                $res.Close()
                continue
            }

            if ($req.Url.AbsolutePath.StartsWith('/api/', [StringComparison]::OrdinalIgnoreCase)) {
                Invoke-MetraOpsApi -Request $req -Response $res -MetraRoot $MetraRoot
            }
            else {
                Invoke-MetraOpsStatic -Request $req -Response $res -DistPath $dist
            }
        }
    }
    finally {
        try { Stop-MetraAskEngine -MetraRoot $MetraRoot } catch { }
        try {
            if ($listener.IsListening) { $listener.Stop() }
        }
        catch { }
        try { $listener.Close() } catch { }
        try {
            if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
        }
        catch { }
        Write-Host 'Metra Ops stopped.' -ForegroundColor DarkGray
    }
}
