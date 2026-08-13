# HTML Ops local HTTP server. Face = ops/dist; brain = desk payload helpers.
#
# Reach is not authority:
# - Share/Tailscale/Serve may view, ask, upload quarantine files, and create bounded candidate records.
# - Local authority is the Host-minted session token (X-Metra-Local-Session), not the network path.
# - Host Open uses Get-MetraOpsDeskOpenUrl (memorable ShareUrl + hash bootstrap). OperatorUrl is loopback recovery.

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
    param(
        [Parameter(Mandatory)]$Request,
        [int]$MaxBytes = 1048576
    )

    if (-not $Request.HasEntityBody) { return '' }
    $bytes = Read-MetraOpsRequestBytes -Request $Request -MaxBytes $MaxBytes
    if ($null -eq $bytes -or $bytes.Length -eq 0) { return '' }
    # Strict UTF-8 - do not trust ContentEncoding; fail closed on invalid bytes.
    $enc = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        return $enc.GetString($bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        throw [System.ArgumentException]::new('Request body is not valid UTF-8.')
    }
    catch {
        throw [System.ArgumentException]::new('Request body is not valid UTF-8.')
    }
}

function Read-MetraOpsRequestBytes {
    param(
        [Parameter(Mandatory)]$Request,
        [int]$MaxBytes = 1048576
    )

    if (-not $Request.HasEntityBody) { return [byte[]]@() }
    if ($Request.ContentLength64 -ge 0 -and $Request.ContentLength64 -gt $MaxBytes) {
        throw [System.ArgumentException]::new('Request body too large.')
    }
    $ms = New-Object System.IO.MemoryStream
    try {
        $buf = New-Object byte[] 8192
        $total = 0L
        while ($true) {
            $read = $Request.InputStream.Read($buf, 0, $buf.Length)
            if ($read -le 0) { break }
            $total += $read
            if ($total -gt $MaxBytes) {
                throw [System.ArgumentException]::new('Request body too large.')
            }
            $ms.Write($buf, 0, $read)
        }
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
    .DESCRIPTION
        Byte-first parser. Headers are inspected as ASCII; file body bytes are copied from the
        raw request buffer so binary uploads are not corrupted by UTF-8 text splits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$ContentType
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        throw 'Empty multipart body'
    }
    $boundaryMatch = [regex]::Match($ContentType, 'boundary=(?:"([^"]+)"|([^;]+))', 'IgnoreCase')
    if (-not $boundaryMatch.Success) {
        throw 'multipart boundary missing'
    }
    $boundary = $boundaryMatch.Groups[1].Value
    if (-not $boundary) { $boundary = $boundaryMatch.Groups[2].Value.Trim() }
    if ([string]::IsNullOrWhiteSpace($boundary)) {
        throw 'multipart boundary missing'
    }
    if ($boundary.Length -gt 200) {
        throw 'multipart boundary too long'
    }
    if ($boundary -match '[\r\n]') {
        throw 'multipart boundary invalid'
    }

    $ascii = [System.Text.Encoding]::ASCII
    $marker = $ascii.GetBytes('--' + $boundary)
    $positions = [System.Collections.Generic.List[int]]::new()
    $search = 0
    while ($true) {
        $hit = Find-MetraByteSequence -Haystack $Bytes -Needle $marker -Start $search
        if ($hit -lt 0) { break }
        [void]$positions.Add($hit)
        $search = $hit + $marker.Length
        if ($search -ge $Bytes.Length) { break }
    }
    if ($positions.Count -lt 2) {
        throw 'No file part found in multipart body'
    }

    $preferred = $null
    $fallback = $null
    $crlfcrlf = $ascii.GetBytes("`r`n`r`n")
    $lflf = $ascii.GetBytes("`n`n")

    for ($i = 0; $i -lt ($positions.Count - 1); $i++) {
        $partStart = $positions[$i] + $marker.Length
        if ($partStart -lt $Bytes.Length -and $Bytes[$partStart] -eq 45 -and
            ($partStart + 1) -lt $Bytes.Length -and $Bytes[$partStart + 1] -eq 45) {
            # Closing boundary (--boundary--)
            continue
        }
        if (($partStart + 1) -lt $Bytes.Length -and $Bytes[$partStart] -eq 13 -and $Bytes[$partStart + 1] -eq 10) {
            $partStart += 2
        }
        elseif ($partStart -lt $Bytes.Length -and $Bytes[$partStart] -eq 10) {
            $partStart += 1
        }

        $partEnd = $positions[$i + 1]
        if ($partEnd -le $partStart) { continue }

        $headerEnd = Find-MetraByteSequence -Haystack $Bytes -Needle $crlfcrlf -Start $partStart
        $sepLen = 4
        if ($headerEnd -lt 0 -or $headerEnd -ge $partEnd) {
            $headerEnd = Find-MetraByteSequence -Haystack $Bytes -Needle $lflf -Start $partStart
            $sepLen = 2
        }
        if ($headerEnd -lt 0 -or $headerEnd -ge $partEnd) { continue }

        $headerLen = $headerEnd - $partStart
        if ($headerLen -le 0) { continue }
        $headerBytes = New-Object byte[] $headerLen
        [Array]::Copy($Bytes, $partStart, $headerBytes, 0, $headerLen)
        $headerText = $ascii.GetString($headerBytes)
        if ($headerText -notmatch 'Content-Disposition:\s*form-data;') { continue }
        if ($headerText -notmatch 'filename="([^"]*)"') { continue }

        $fileName = $Matches[1]
        if ([string]::IsNullOrWhiteSpace($fileName)) { continue }
        $fieldName = ''
        if ($headerText -match 'name="([^"]+)"') { $fieldName = $Matches[1] }
        $contentTypePart = 'application/octet-stream'
        if ($headerText -match 'Content-Type:\s*([^\r\n]+)') {
            $contentTypePart = $Matches[1].Trim()
        }

        $dataStart = $headerEnd + $sepLen
        $dataEnd = $partEnd
        # Multipart bodies usually end with CRLF immediately before the next boundary marker.
        if ($dataEnd -ge 2 -and $Bytes[$dataEnd - 2] -eq 13 -and $Bytes[$dataEnd - 1] -eq 10) {
            $dataEnd -= 2
        }
        elseif ($dataEnd -ge 1 -and $Bytes[$dataEnd - 1] -eq 10) {
            $dataEnd -= 1
        }
        $len = $dataEnd - $dataStart
        if ($len -lt 0) { continue }

        $fileBytes = New-Object byte[] $len
        if ($len -gt 0) {
            [Array]::Copy($Bytes, $dataStart, $fileBytes, 0, $len)
        }
        # Trim any remaining trailing CR/LF without PowerShell range footguns (0..-1).
        $end = $fileBytes.Length
        while ($end -gt 0 -and ($fileBytes[$end - 1] -eq 10 -or $fileBytes[$end - 1] -eq 13)) {
            $end--
        }
        if ($end -lt $fileBytes.Length) {
            $trimmed = New-Object byte[] $end
            if ($end -gt 0) {
                [Array]::Copy($fileBytes, 0, $trimmed, 0, $end)
            }
            $fileBytes = $trimmed
        }

        $hit = [PSCustomObject]@{
            FileName    = $fileName
            ContentType = $contentTypePart
            Bytes       = $fileBytes
            FieldName   = $fieldName
        }
        if ($fieldName -eq 'file') {
            $preferred = $hit
            break
        }
        if ($null -eq $fallback) { $fallback = $hit }
    }

    $chosen = if ($null -ne $preferred) { $preferred } else { $fallback }
    if ($null -eq $chosen) {
        throw 'No file part found in multipart body'
    }
    return [PSCustomObject]@{
        FileName    = [string]$chosen.FileName
        ContentType = [string]$chosen.ContentType
        Bytes       = [byte[]]$chosen.Bytes
    }
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

function Limit-MetraOpsText {
    <#
    .SYNOPSIS
        Truncates text to a max length for remote-safe ledger / place fields.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [int]$MaxLength = 4000
    )

    if ($null -eq $Text) { return '' }
    if ($Text.Length -le $MaxLength) { return $Text }
    return $Text.Substring(0, $MaxLength)
}

function Get-MetraOpsQueryValue {
    <#
    .SYNOPSIS
        Returns a decoded query-string value by name, or $null when absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $query = [string]$Request.Url.Query
        if ([string]::IsNullOrWhiteSpace($query)) { return $null }
        $trimmed = $query.TrimStart('?')
        foreach ($pair in ($trimmed -split '&')) {
            if ([string]::IsNullOrWhiteSpace($pair)) { continue }
            $parts = $pair -split '=', 2
            $key = [System.Uri]::UnescapeDataString($parts[0])
            if ([string]::Equals($key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($parts.Count -gt 1) {
                    return [System.Uri]::UnescapeDataString($parts[1])
                }
                return ''
            }
        }
    }
    catch { }

    return $null
}

function Write-MetraOpsBadRequest {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$Message
    )

    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
            error = $Message
        })
}

function Test-MetraOpsRequestHasLocalAuthority {
    <#
    .SYNOPSIS
        True when same-machine (Serve-aware) or validated X-Metra-Local-Session.
    .DESCRIPTION
        Local authority is either true same-machine traffic or a host-issued session token.
        Tailscale Serve reach alone must never satisfy this.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)

    if (Test-MetraOpsRequestIsSameMachine -Request $Request) { return $true }
    $sessionToken = ''
    try { $sessionToken = [string]$Request.Headers['X-Metra-Local-Session'] } catch { }
    return [bool](Test-MetraOpsLocalSessionToken -SessionToken $sessionToken)
}

function Assert-MetraOpsLocalAuthority {
    <#
    .SYNOPSIS
        Writes 403 JSON and returns $false when the caller lacks local authority.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [string]$ErrorMessage = 'This action requires the operator machine or a Host-issued local session.',
        [string]$ReasonCode = 'localAuthorityRequired'
    )

    if (Test-MetraOpsRequestHasLocalAuthority -Request $Request) { return $true }
    Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
            error      = $ErrorMessage
            reasonCode = $ReasonCode
        })
    return $false
}

function ConvertFrom-MetraOpsJsonBody {
    <#
    .SYNOPSIS
        Parses a request body as JSON. Empty body becomes {} when -AllowEmpty is set.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Body,
        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        if ($AllowEmpty) { return [PSCustomObject]@{} }
        throw [System.ArgumentException]::new('JSON body required')
    }
    try {
        return $Body | ConvertFrom-Json
    }
    catch {
        throw [System.ArgumentException]::new('invalid JSON body')
    }
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
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = 'application/json; charset=utf-8'
        $Response.Headers['Cache-Control'] = 'no-store'
        $Response.Headers['X-Content-Type-Options'] = 'nosniff'
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Response.OutputStream.Close()
    }
    catch { }
}

function Write-MetraOpsTextResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$Text,
        [int]$StatusCode = 200,
        [string]$ContentType = 'text/plain; charset=utf-8'
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        $Response.Headers['Cache-Control'] = 'no-store'
        $Response.Headers['X-Content-Type-Options'] = 'nosniff'
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Response.OutputStream.Close()
    }
    catch { }
}

function Write-MetraOpsFileResponse {
    param(
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$FilePath,
        [string]$ContentType,
        [string]$DownloadFileName
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    try {
        $Response.StatusCode = 200
        $Response.ContentType = if ($ContentType) { $ContentType } else { Get-MetraOpsContentType -Path $FilePath }
        if (-not [string]::IsNullOrWhiteSpace($DownloadFileName)) {
            $safe = ($DownloadFileName -replace '[\r\n"]', '')
            $Response.Headers['Content-Disposition'] = "attachment; filename=`"$safe`""
        }
        $Response.Headers['Cache-Control'] = 'no-store'
        $Response.Headers['X-Content-Type-Options'] = 'nosniff'
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Response.OutputStream.Close()
    }
    catch { }
}

function Resolve-MetraOpsStaticPath {
    <#
    .SYNOPSIS
        Resolves a URL path to a file under DistPath, or $null when unsafe / outside root.
    .DESCRIPTION
        Rejects rooted / drive-qualified inputs early. Encoded traversal is caught after
        UnescapeDataString + GetFullPath via Test-MetraPathWithinRoot (not substring '..').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DistPath,
        [Parameter(Mandatory)][string]$UrlPath
    )

    try {
        $raw = [string]$UrlPath
        if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '/') {
            $raw = '/index.html'
        }

        $decoded = [System.Uri]::UnescapeDataString($raw.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($decoded)) {
            $decoded = 'index.html'
        }

        # Normalize URL separators to local separators.
        $rel = $decoded -replace '/', [System.IO.Path]::DirectorySeparatorChar

        # Reject rooted / drive-qualified / UNC-like inputs before Join-Path.
        if (
            [System.IO.Path]::IsPathRooted($rel) -or
            $rel -match '^[a-zA-Z]:' -or
            $rel.StartsWith('\') -or
            $rel.StartsWith('/')
        ) {
            return $null
        }

        $root = [System.IO.Path]::GetFullPath($DistPath)
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $rel))

        if (-not (Test-MetraPathWithinRoot -Path $candidate -Root $root)) {
            return $null
        }

        return $candidate
    }
    catch {
        return $null
    }
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

    # Reach is split from authority (see file header).
    # Ask-class remote (Tailscale reach): POST /api/ask, GET ask journal/engine, GET/POST capture
    # (create/dismiss/propose), POST /api/place/upload, POST /api/place, GET place/homes,
    # GET preferences/settings/snapshot/meta - no Assert-MetraOpsLocalAuthority.
    # Remote-safe writes are bounded: capture candidate ledger only; place uploads quarantine only
    # (size/ext/random id; never project-tree). Capture promote / place confirm/correct need local authority.
    # Profile check-in is bearer-scoped (X-Metra-Profile-Sync), not local-session alone.
    # Local-authority gates: refresh, watch, preferences PUT, ask/engine POST, attention mutations,
    # place confirm/correct, settings, updates, open, profile issue-sync-token.

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
            $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/refresh') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            $full = $false
            if ($body) {
                try {
                    $parsed = $body | ConvertFrom-Json
                    $full = [bool](Get-MetraProp -Object $parsed -Name 'full' -Default $false)
                }
                catch { }
            }
            $payload = Get-MetraDeskPayload -Refresh -Full:$full -MetraRoot $MetraRoot -Request $Request
            Write-MetraOpsJsonResponse -Response $Response -Object $payload
            return
        }

        # M3: Preview local recommend-draft or Confirm Affirm A TT recommend (Mine-only).
        if ($method -eq 'POST' -and $path -eq '/api/watch/recommend') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            $ticketId = ''
            $doPreview = $true
            $doConfirm = $false
            $doForce = $false
            $minutes = 15
            if ($body) {
                try {
                    $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
                    $ticketId = [string](Get-MetraProp -Object $parsed -Name 'id' -Default '')
                    if (-not $ticketId) {
                        $ticketId = [string](Get-MetraProp -Object $parsed -Name 'ticketId' -Default '')
                    }
                    $doConfirm = [bool](Get-MetraProp -Object $parsed -Name 'confirm' -Default $false)
                    $doPreview = [bool](Get-MetraProp -Object $parsed -Name 'preview' -Default (-not $doConfirm))
                    $doForce = [bool](Get-MetraProp -Object $parsed -Name 'force' -Default $false)
                    $minutesRaw = Get-MetraProp -Object $parsed -Name 'minutes' -Default 15
                    if ($null -ne $minutesRaw) { $minutes = [int]$minutesRaw }
                }
                catch {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = $_.Exception.Message
                            ok    = $false
                        })
                    return
                }
            }
            if (-not $ticketId) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                        error = 'id (ticket id) is required.'
                        ok    = $false
                    })
                return
            }
            if ($doConfirm) { $doPreview = $false }
            try {
                $store = Invoke-MetraTicketWatchStoreRecommend `
                    -Id $ticketId `
                    -Preview:$doPreview `
                    -Confirm:$doConfirm `
                    -Force:$doForce `
                    -Minutes $minutes `
                    -Quiet `
                    -MetraRoot $MetraRoot
                $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        ok     = [bool]$store.ok
                        store  = $store
                        desk   = $payload
                        error  = $(if (-not $store.ok -and $store.warning) { [string]$store.warning } else { $null })
                    }) -Depth 12
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        # TicketWatch mine-scope scan -> Attention. No iSupport writes. Desk-only intake.
        if ($method -eq 'POST' -and $path -eq '/api/watch/tickets') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $prefs = Get-MetraDeskPreferences -MetraRoot $MetraRoot
            $enabled = [bool](Get-MetraProp -Object $prefs -Name 'ticketWatchEnabled' -Default $true)
            if (-not $enabled) {
                $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 409 -Object ([PSCustomObject]@{
                        error = 'Ticket watch is turned off in desk preferences.'
                        ok    = $false
                        watch = [PSCustomObject]@{
                            ok             = $false
                            available      = $false
                            scope          = 'mine'
                            synced         = $false
                            warning        = 'ticketWatchEnabled is off'
                            scanned        = 0
                            added          = 0
                            refreshed      = 0
                            unchanged      = 0
                            draftsWritten  = 0
                            draftAvailable = $false
                            evidenceSuggestions = 0
                            nextEvidenceAvailable = $false
                            readyForRecommendation = $false
                            iSupportWrites = $false
                        }
                        desk  = $payload
                    }) -Depth 12
                return
            }
            $draft = $false
            $body = Read-MetraOpsRequestBody -Request $Request
            if ($body) {
                try {
                    $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
                    $draft = [bool](Get-MetraProp -Object $parsed -Name 'draft' -Default $false)
                }
                catch {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = $_.Exception.Message
                            ok    = $false
                        })
                    return
                }
            }
            try {
                if (-not (Enter-MetraTicketWatchScanLease)) {
                    $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
                    Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                            ok      = $true
                            skipped = $true
                            watch   = [PSCustomObject]@{
                                ok             = $true
                                available      = $true
                                scope          = 'mine'
                                synced         = $false
                                warning        = 'Ticket scan already in progress on this host.'
                                scanned        = 0
                                added          = 0
                                refreshed      = 0
                                unchanged      = 0
                                draftsWritten  = 0
                                draftAvailable = $false
                                evidenceSuggestions = 0
                                nextEvidenceAvailable = $false
                                readyForRecommendation = $false
                                iSupportWrites = $false
                            }
                            desk    = $payload
                        }) -Depth 12
                    return
                }
                try {
                    $scan = Invoke-MetraTicketWatchScan -Quiet -MetraRoot $MetraRoot -Draft:$draft
                }
                finally {
                    Exit-MetraTicketWatchScanLease
                }
                $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        ok    = [bool]$scan.ok
                        watch = [PSCustomObject]@{
                            ok             = [bool]$scan.ok
                            available      = [bool]$scan.available
                            scope          = [string](Get-MetraProp -Object $scan -Name 'scope' -Default 'mine')
                            synced         = [bool]$scan.synced
                            syncError      = [string]$scan.syncError
                            warning        = [string]$scan.warning
                            scanned        = [int]$scan.scanned
                            added          = [int]$scan.added
                            refreshed      = [int]$scan.refreshed
                            unchanged      = [int]$scan.unchanged
                            draftsWritten  = [int]$scan.draftsWritten
                            draftAvailable = [bool](Get-MetraProp -Object $scan -Name 'draftAvailable' -Default ($scan.draftsWritten -gt 0))
                            evidenceSuggestions = [int](Get-MetraProp -Object $scan -Name 'evidenceSuggestions' -Default 0)
                            nextEvidenceAvailable = [bool](Get-MetraProp -Object $scan -Name 'nextEvidenceAvailable' -Default $false)
                            readyForRecommendation = [bool](Get-MetraProp -Object $scan -Name 'readyForRecommendation' -Default $false)
                            iSupportWrites = [bool]$scan.iSupportWrites
                        }
                        desk  = $payload
                    }) -Depth 12
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
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

        if ($method -eq 'GET' -and $path -eq '/api/profile/status') {
            if (-not (Test-MetraOpsProfileSyncAuthorized -Request $Request)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Profile status requires operator machine, local session, or X-Metra-Profile-Sync bearer.'
                        reasonCode = 'profileSyncUnauthorized'
                    })
                return
            }
            try {
                $status = Get-MetraProfileStatus -MetraRoot $MetraRoot
                $status | Add-Member -NotePropertyName hasSyncToken -NotePropertyValue ([bool](Test-MetraProfileSyncTokenConfigured)) -Force
                if (Test-MetraOpsRequestHasLocalAuthority -Request $Request) {
                    $roster = Get-MetraProfileSatelliteRoster -PublisherHash ([string]$status.contentHash)
                    $status | Add-Member -NotePropertyName satellites -NotePropertyValue @($roster.Satellites) -Force
                }
                Write-MetraOpsJsonResponse -Response $Response -Object $status -Depth 8
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/profile/satellites') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response `
                    -ErrorMessage 'Satellite roster requires the operator machine or a Host-issued local session.' `
                    -ReasonCode 'profileSatellitesLocalOnly')) { return }
            try {
                $status = Get-MetraProfileStatus -MetraRoot $MetraRoot
                $roster = Get-MetraProfileSatelliteRoster -PublisherHash ([string]$status.contentHash)
                Write-MetraOpsJsonResponse -Response $Response -Object $roster -Depth 8
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/profile/check-in') {
            # Satellite check-in is bearer-scoped so a local browser session cannot invent machine rows.
            if (-not (Test-MetraOpsProfileSyncBearer -Request $Request)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Profile check-in requires X-Metra-Profile-Sync bearer.'
                        reasonCode = 'profileSyncUnauthorized'
                    })
                return
            }
            try {
                $body = Read-MetraOpsRequestBody -Request $Request
                $parsed = $null
                if ($body) { $parsed = $body | ConvertFrom-Json }
                $machineName = [string](Get-MetraProp -Object $parsed -Name 'machineName' -Default '')
                $lastApplied = [string](Get-MetraProp -Object $parsed -Name 'lastAppliedHash' -Default '')
                $metraVer = [string](Get-MetraProp -Object $parsed -Name 'metraVersion' -Default '')
                $role = [string](Get-MetraProp -Object $parsed -Name 'role' -Default 'Satellite')
                $saved = Save-MetraProfileSatelliteCheckIn `
                    -MachineName $machineName `
                    -LastAppliedHash $lastApplied `
                    -MetraVersion $metraVer `
                    -Role $role
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                        ok          = $true
                        machineName = $saved.MachineName
                        lastSeenUtc = $saved.LastSeenUtc
                    })
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/profile/export') {
            # Bearer is profile-sync scoped (or local authority). Export must not include secrets
            # or the local session token - Export-MetraProfile owns that exclusion list.
            if (-not (Test-MetraOpsProfileSyncAuthorized -Request $Request)) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Profile export requires operator machine, local session, or X-Metra-Profile-Sync bearer.'
                        reasonCode = 'profileSyncUnauthorized'
                    })
                return
            }
            $zipPath = $null
            try {
                $status = Get-MetraProfileStatus -MetraRoot $MetraRoot
                $cacheDir = Join-Path $env:LOCALAPPDATA 'Metra\profile-export-cache'
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
                    [void][System.IO.Directory]::CreateDirectory($cacheDir)
                }
                $hashKey = ($status.contentHash -replace '[^a-fA-F0-9]', '')
                if ([string]::IsNullOrWhiteSpace($hashKey)) { $hashKey = 'empty' }
                $cached = Join-Path $cacheDir ("metra-profile-$hashKey.zip")
                # Older builds wrote "$cached.tmp", which Export-MetraProfile treats as a folder
                # (path must end in .zip). Drop leftover folders/files and any directory named *.zip.
                $legacyTmp = "$cached.tmp"
                if (Test-Path -LiteralPath $legacyTmp) {
                    Remove-Item -LiteralPath $legacyTmp -Recurse -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath $cached) {
                    $cachedItem = Get-Item -LiteralPath $cached -Force -ErrorAction SilentlyContinue
                    if ($null -ne $cachedItem -and $cachedItem.PSIsContainer) {
                        Remove-Item -LiteralPath $cached -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                if (-not (Test-Path -LiteralPath $cached)) {
                    $tmp = Join-Path $cacheDir ("metra-profile-$hashKey.partial.zip")
                    try {
                        $null = Export-MetraProfile -Path $tmp -Force -Quiet
                        Move-Item -LiteralPath $tmp -Destination $cached -Force
                    }
                    finally {
                        if (Test-Path -LiteralPath $tmp) {
                            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                $zipPath = $cached
                Write-MetraOpsFileResponse -Response $Response -FilePath $zipPath -ContentType 'application/zip' -DownloadFileName 'metra-profile.zip'
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                        error = $_.Exception.Message
                    })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/profile/issue-sync-token') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response `
                    -ErrorMessage 'Issuing a profile sync token requires the operator machine (loopback or local session).' `
                    -ReasonCode 'profileSyncTokenLocalOnly')) { return }
            $rotate = $false
            try {
                $body = Read-MetraOpsRequestBody -Request $Request
                if ($body) {
                    $parsed = $body | ConvertFrom-Json
                    $rotate = [bool](Get-MetraProp -Object $parsed -Name 'rotate' -Default $false)
                }
            }
            catch { }
            $issued = Initialize-MetraProfileSyncToken -Rotate:$rotate
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    ok        = $true
                    created   = [bool]$issued.Created
                    hasToken  = [bool]$issued.HasToken
                    token     = $issued.Token
                    header    = 'X-Metra-Profile-Sync'
                    message   = [string]$issued.Message
                }) -Depth 6
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/updates') {
            $forceRaw = Get-MetraOpsQueryValue -Request $Request -Name 'force'
            $force = $forceRaw -match '^(?i)(1|true|yes)$'
            Write-MetraOpsJsonResponse -Response $Response -Object (Get-MetraOpsUpdatesApiPayload -MetraRoot $MetraRoot -Force:$force) -Depth 8
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/updates') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response `
                    -ErrorMessage 'Updates run on the operator machine only.' `
                    -ReasonCode 'updatesLocalOnly')) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body -AllowEmpty
                $target = [string](Get-MetraProp -Object $parsed -Name 'target' -Default '').Trim().ToLowerInvariant()
                if ($target -notin @('metra', 'ollama')) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = 'target must be metra or ollama'
                        })
                    return
                }
                $started = Start-MetraProductUpdateApplyJob -Target $target -MetraRoot $MetraRoot
                $statusCode = [int](Get-MetraProp -Object $started -Name 'StatusCode' -Default 500)
                $payload = [PSCustomObject]@{
                    accepted = [bool](Get-MetraProp -Object $started -Name 'Accepted' -Default $false)
                    error    = Get-MetraProp -Object $started -Name 'Error' -Default $null
                    message  = Get-MetraProp -Object $started -Name 'Message' -Default $null
                    job      = Get-MetraProp -Object $started -Name 'Job' -Default $null
                }
                Write-MetraOpsJsonResponse -Response $Response -StatusCode $statusCode -Object $payload -Depth 8
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
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response `
                    -ErrorMessage 'Settings changes run on the operator machine only.' `
                    -ReasonCode 'settingsLocalOnly')) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body -AllowEmpty
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
                $machineRole = Get-MetraProp -Object $parsed -Name 'machineRole' -Default $null
                if ($null -ne $machineRole -and -not [string]::IsNullOrWhiteSpace([string]$machineRole)) {
                    $roleNorm = ConvertTo-MetraMachineRole -Role ([string]$machineRole)
                    if (-not $roleNorm) {
                        Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                                error = 'machineRole must be Hq, Satellite, or Standalone'
                            })
                        return
                    }
                    $setArgs['MachineRole'] = $roleNorm
                }
                if ([bool](Get-MetraProp -Object $parsed -Name 'clearOpsBaseUrl' -Default $false)) {
                    $setArgs['ClearOpsBaseUrl'] = $true
                }
                elseif ($null -ne (Get-MetraProp -Object $parsed -Name 'opsBaseUrl' -Default $null)) {
                    $setArgs['OpsBaseUrl'] = [string](Get-MetraProp -Object $parsed -Name 'opsBaseUrl' -Default '')
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

        if ($method -eq 'GET' -and $path -eq '/api/local-authority') {
            # Lightweight probe for Ops UI Settings gating. Always 200; transport is not authority.
            $authorized = Test-MetraOpsRequestHasLocalAuthority -Request $Request
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    authorized = [bool]$authorized
                })
            return
        }

        if ($method -eq 'GET' -and $path -eq '/api/local-session') {
            # Loopback-only: browser / webview on the operator machine may fetch the Host session marker.
            if (Test-MetraOpsRequestLooksProxiedThroughServe -Request $Request) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 403 -Object ([PSCustomObject]@{
                        error      = 'Local session token is not available through Tailscale Serve.'
                        reasonCode = 'localSessionServeDenied'
                    })
                return
            }
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
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                return
            }
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
            if ($null -ne (Get-MetraProp -Object $parsed -Name 'ticketWatchEnabled' -Default $null)) {
                $setArgs['TicketWatchEnabled'] = [bool](Get-MetraProp -Object $parsed -Name 'ticketWatchEnabled' -Default $true)
            }
            if ($setArgs.Keys.Count -le 1) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'deskMode, attentionVisibleCount, editorCommand, or ticketWatchEnabled required' })
                return
            }
            $prefs = Set-MetraDeskPreferences @setArgs
            Write-MetraOpsJsonResponse -Response $Response -Object $prefs
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/open') {
            # Desk process launches the editor; the browser cannot. Reach is split from authority:
            # loopback, or a Host-issued local session marker for non-loopback surfaces.
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response `
                    -ErrorMessage 'Open in editor runs on the operator machine only. Use the desk on that machine, or open the folder there manually.' `
                    -ReasonCode 'openLocalOnly')) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            $openPath = ''
            if ($body) {
                try {
                    $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
                    $openPath = [string](Get-MetraProp -Object $parsed -Name 'path' -Default '')
                }
                catch {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{
                            error = $_.Exception.Message
                        })
                    return
                }
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
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
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
                $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request
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
            $rawImageIds = Get-MetraProp -Object $parsed -Name 'imageIds' -Default @()
            $imageIds = @($rawImageIds | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)
            if ([string]::IsNullOrWhiteSpace($prompt) -and $imageIds.Count -eq 0) {
                Write-MetraOpsBadRequest -Response $Response -Message 'prompt required'
                return
            }
            if ($prompt.Length -gt 20000) {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 413 -Object ([PSCustomObject]@{
                        error = 'prompt too large'
                    })
                return
            }
            $resolvedImages = @()
            $journalImages = @()
            if ($imageIds.Count -gt 0) {
                $resolved = Resolve-MetraAskImages -ImageIds $imageIds
                if (-not $resolved.ok) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = [string]$resolved.error })
                    return
                }
                $resolvedImages = @($resolved.images)
                $journalImages = @($resolved.journal)
            }
            if ([string]::IsNullOrWhiteSpace($prompt) -and $resolvedImages.Count -gt 0) {
                $prompt = Get-MetraAskImageDefaultPrompt
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

            try {
                $ask = Get-MetraDeskAskResult -Prompt $prompt -SessionId $sessionId -RecallSessionId $recallSessionId `
                    -Images $resolvedImages -MetraRoot $MetraRoot
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                return
            }
            $journalSession = [string]$ask.sessionId
            if ([string]::IsNullOrWhiteSpace($journalSession)) { $journalSession = $sessionId }
            $journalPrompt = [string](Get-MetraProp -Object $ask -Name 'scrubbedPrompt' -Default $prompt)
            if ([string]::IsNullOrWhiteSpace($journalPrompt)) { $journalPrompt = $prompt }
            $askJournalImages = @(Get-MetraProp -Object $ask -Name 'images' -Default $journalImages)
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
                -Images $askJournalImages `
                -MetraRoot $MetraRoot
            $showWhere = Test-MetraAskShowWhere -Handoff $ask.handoff
            Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                    entry            = $entry
                    handoff          = $ask.handoff
                    message          = [string]$ask.message
                    sessionId        = [string]$entry.sessionId
                    capability       = $ask.capability
                    engine           = $ask.engine
                    model            = $ask.model
                    answered         = [bool]$ask.answered
                    answerType       = [string](Get-MetraProp -Object $ask -Name 'answerType' -Default '')
                    evidenceQuality  = [string](Get-MetraProp -Object $ask -Name 'evidenceQuality' -Default '')
                    nextStep         = [string](Get-MetraProp -Object $ask -Name 'nextStep' -Default '')
                    showWhere        = [bool]$showWhere
                    suggestCapture   = [bool](Get-MetraProp -Object $ask -Name 'suggestCapture' -Default $false)
                    continuity       = $ask.continuity
                    secretsScrubbed  = [bool](Get-MetraProp -Object $ask -Name 'secretsScrubbed' -Default $false)
                    secretsNotice    = $(Get-MetraProp -Object $ask -Name 'secretsNotice' -Default $null)
                    secretsKinds     = @(Get-MetraProp -Object $ask -Name 'secretsKinds' -Default @())
                    secretsReason    = $(Get-MetraProp -Object $ask -Name 'secretsReason' -Default $null)
                    images           = @(Get-MetraProp -Object $entry -Name 'images' -Default @())
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
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = if ($body) { $body | ConvertFrom-Json } else { [PSCustomObject]@{} }
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'invalid JSON body' })
                return
            }
            $action = [string](Get-MetraProp -Object $parsed -Name 'action' -Default 'set').Trim().ToLowerInvariant()
            if ($action -eq 'accept') {
                $result = Invoke-MetraAskAcceptRecommended -MetraRoot $MetraRoot
                Write-MetraOpsJsonResponse -Response $Response -Object $result -Depth 10
                return
            }
            if ($action -eq 'set') {
                $engine = [string](Get-MetraProp -Object $parsed -Name 'engine' -Default '').Trim().ToLowerInvariant()
                if ([string]::IsNullOrWhiteSpace($engine)) {
                    Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = 'engine required' })
                    return
                }
                $model = Get-MetraProp -Object $parsed -Name 'model' -Default $null
                $band = Get-MetraProp -Object $parsed -Name 'sizeBand' -Default $null
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
            $limitRaw = Get-MetraOpsQueryValue -Request $Request -Name 'limit'
            if ($limitRaw -match '^\d+$') {
                $limit = [Math]::Min(100, [int]$limitRaw)
            }
            $sessionIdFilter = [string](Get-MetraOpsQueryValue -Request $Request -Name 'sessionId')
            if ($null -eq $sessionIdFilter) { $sessionIdFilter = '' }
            $searchQuery = [string](Get-MetraOpsQueryValue -Request $Request -Name 'q')
            if ($null -eq $searchQuery) { $searchQuery = '' }

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
            $statusRaw = Get-MetraOpsQueryValue -Request $Request -Name 'status'
            if ($statusRaw -match '^(candidate|promoted|dismissed|all)$') {
                $status = $statusRaw.ToLowerInvariant()
            }
            Write-MetraOpsJsonResponse -Response $Response -Object (@(Get-MetraCaptureLedger -MetraRoot $MetraRoot -Limit 40 -Status $status)) -Depth 10
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/capture/propose') {
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            if ($body) {
                try { $parsed = $body | ConvertFrom-Json } catch { $parsed = $null }
            }
            try {
                $turnId = [string](Get-MetraProp -Object $parsed -Name 'turnId' -Default '')
                $sessionId = [string](Get-MetraProp -Object $parsed -Name 'sessionId' -Default '')
                $proposals = @(Propose-MetraCaptureSplit -TurnId $turnId -SessionId $sessionId -MetraRoot $MetraRoot)
                Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{ proposals = $proposals }) -Depth 10
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/capture') {
            # Remote-safe candidate ledger write only. Promotion into project tree checks local authority.
            $body = Read-MetraOpsRequestBody -Request $Request
            $parsed = $null
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                return
            }
            try {
                $turnId = [string](Get-MetraProp -Object $parsed -Name 'turnId' -Default '')
                $sessionId = [string](Get-MetraProp -Object $parsed -Name 'sessionId' -Default '')
                $summary = Limit-MetraOpsText -Text (Get-MetraProp -Object $parsed -Name 'summary' -Default '') -MaxLength 500
                $capBody = Limit-MetraOpsText -Text (Get-MetraProp -Object $parsed -Name 'body' -Default '') -MaxLength 8000
                $source = [string](Get-MetraProp -Object $parsed -Name 'source' -Default '')
                $placeId = [string](Get-MetraProp -Object $parsed -Name 'placeId' -Default '')
                $homeId = [string](Get-MetraProp -Object $parsed -Name 'homeId' -Default '')
                $text = Limit-MetraOpsText -Text (Get-MetraProp -Object $parsed -Name 'text' -Default '') -MaxLength 8000
                $attachmentIds = @()
                try {
                    $rawAtt = Get-MetraProp -Object $parsed -Name 'attachmentIds' -Default @()
                    $attachmentIds = @($rawAtt | ForEach-Object { [string]$_ } | Where-Object { $_ })
                }
                catch { }

                $acceptedRaw = Get-MetraProp -Object $parsed -Name 'acceptedProposals' -Default $null
                if ($null -ne $acceptedRaw) {
                    $created = @(Add-MetraCaptureFromAskSplit -Proposals @($acceptedRaw) -MetraRoot $MetraRoot)
                    Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
                            items = $created
                            count = $created.Count
                        }) -Depth 10
                    return
                }

                $item = $null
                if (-not [string]::IsNullOrWhiteSpace($turnId) -or $source -eq 'ask') {
                    if ([string]::IsNullOrWhiteSpace($turnId)) {
                        Write-MetraOpsBadRequest -Response $Response -Message 'turnId required for ask capture'
                        return
                    }
                    $item = Add-MetraCaptureFromAskTurn -TurnId $turnId -SessionId $sessionId -Summary $summary -Body $capBody -MetraRoot $MetraRoot
                }
                elseif ($source -eq 'place' -or (-not [string]::IsNullOrWhiteSpace($homeId) -and -not [string]::IsNullOrWhiteSpace($text))) {
                    $item = Add-MetraCaptureFromPlace -Text $(if ($text) { $text } else { $summary }) -HomeId $homeId -PlaceId $placeId -AttachmentIds $attachmentIds -MetraRoot $MetraRoot
                }
                else {
                    if ([string]::IsNullOrWhiteSpace($summary)) {
                        Write-MetraOpsBadRequest -Response $Response -Message 'summary required for manual capture'
                        return
                    }
                    $derived = New-MetraCaptureDerivedFrom -Type manual
                    $item = Add-MetraCaptureItem -Summary $summary -Body $capBody -Source manual -DerivedFrom $derived -MetraRoot $MetraRoot
                }
                Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
            }
            catch {
                Write-MetraOpsBadRequest -Response $Response -Message $_.Exception.Message
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
                    $project = [string](Get-MetraProp -Object $parsed -Name 'project' -Default '')
                    $cross = [bool](Get-MetraProp -Object $parsed -Name 'crossRootConfirm' -Default $false)
                    $hasLocal = Test-MetraOpsRequestHasLocalAuthority -Request $Request
                    $item = Invoke-MetraCapturePromote -Id $capId -Home $home -Project $project `
                        -CrossRootConfirm:$cross -HasLocalAuthority:$hasLocal -MetraRoot $MetraRoot
                    Write-MetraOpsJsonResponse -Response $Response -Object $item -Depth 10
                    return
                }
                if (Test-MetraPropExists -Object $parsed -Name 'derivedFrom') {
                    Write-MetraOpsBadRequest -Response $Response -Message 'derivedFrom is immutable after capture creation'
                    return
                }
                $updParams = @{ Id = $capId; MetraRoot = $MetraRoot }
                $sum = Limit-MetraOpsText -Text (Get-MetraProp -Object $parsed -Name 'summary' -Default '') -MaxLength 500
                if (-not [string]::IsNullOrWhiteSpace($sum)) { $updParams.Summary = $sum }
                if (Test-MetraPropExists -Object $parsed -Name 'body') {
                    $updParams.Body = Limit-MetraOpsText -Text (Get-MetraProp -Object $parsed -Name 'body' -Default '') -MaxLength 8000
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
            $text = Limit-MetraOpsText -Text $text -MaxLength 8000
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
            # Remote-safe temporary quarantine upload only. Save-MetraPlaceUpload randomizes storage
            # names, bounds size, allowlists extensions, and never trusts original filenames for path.
            try {
                $contentType = [string]$Request.ContentType
                $meta = $null
                if ($contentType -match '^\s*multipart/form-data\s*;') {
                    $bytes = Read-MetraOpsRequestBytes -Request $Request -MaxBytes 10485760
                    $part = ConvertFrom-MetraOpsMultipartUpload -Bytes $bytes -ContentType $contentType
                    $meta = Save-MetraPlaceUpload -FileName $part.FileName -Bytes $part.Bytes -ContentType $part.ContentType
                }
                else {
                    $body = Read-MetraOpsRequestBody -Request $Request
                    $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
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
                # Do not return absolute quarantine path to remote clients.
                Write-MetraOpsJsonResponse -Response $Response -Object (ConvertTo-MetraPlaceUploadPublicMeta -Meta $meta)
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
            }
            return
        }

        if ($method -eq 'POST' -and $path -eq '/api/place/confirm') {
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                return
            }
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
                if ($result.attentionKey -or $result.captureId) { $payload = Get-MetraDeskPayload -MetraRoot $MetraRoot -Request $Request }
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
            if (-not (Assert-MetraOpsLocalAuthority -Request $Request -Response $Response)) { return }
            $body = Read-MetraOpsRequestBody -Request $Request
            try {
                $parsed = ConvertFrom-MetraOpsJsonBody -Body $body
            }
            catch {
                Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
                return
            }
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
        $ex = $_.Exception
        $msg = [string]$ex.Message
        $code = 500
        if ($msg -match '(?i)Request body too large|too large') {
            $code = 413
        }
        elseif ($ex -is [System.ArgumentException] -or $msg -match '(?i)not valid UTF-8|invalid UTF-8') {
            $code = 400
        }
        Write-MetraOpsJsonResponse -Response $Response -StatusCode $code -Object ([PSCustomObject]@{
                error = $msg
            })
    }
}

function Invoke-MetraOpsStatic {
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(Mandatory)]$Response,
        [Parameter(Mandatory)][string]$DistPath
    )

    $candidate = Resolve-MetraOpsStaticPath -DistPath $DistPath -UrlPath $Request.Url.AbsolutePath
    if (-not $candidate) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 400 -Text 'Bad path'
        return
    }
    if (-not (Test-Path -LiteralPath $candidate) -or (Get-Item -LiteralPath $candidate) -isnot [System.IO.FileInfo]) {
        # SPA fallback
        $candidate = Resolve-MetraOpsStaticPath -DistPath $DistPath -UrlPath '/index.html'
    }
    if (-not $candidate -or -not (Test-MetraPathWithinRoot -Path $candidate -Root $DistPath)) {
        Write-MetraOpsTextResponse -Response $Response -StatusCode 400 -Text 'Bad path'
        return
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
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
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
    .DESCRIPTION
        Does not call Stop-MetraAskEngine. The desk process finally block stops Ask for that session;
        killing an orphaned listener must not tear down Ask belonging to another Ops process.
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
        [switch]$ForceLocal,
        [string]$OpsBaseUrl,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    Assert-MetraOpsMayStartLocally -ForceLocal:$ForceLocal -OpsBaseUrl $OpsBaseUrl -MetraRoot $MetraRoot

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

    $shareUrl = [string](Get-MetraProp -Object $binding -Name 'ShareUrl' -Default ([string]$binding.BrowserUrl))
    if ([string]::IsNullOrWhiteSpace($shareUrl)) { $shareUrl = [string]$binding.BrowserUrl }
    $operatorUrl = Get-MetraOpsOperatorOpenUrl -Binding $binding
    $deskDisplay = if ($shareUrl -and (Test-MetraOpsMemorableDeskBaseUrl -Url $shareUrl -OperatorUrl $operatorUrl)) {
        $shareUrl
    }
    else { $operatorUrl }
    if (Test-MetraOpsDeskResponding -Port $Port) {
        Write-Host ("Metra Ops desk already serving: {0}" -f $deskDisplay) -ForegroundColor Green
        if ($shareUrl -and $shareUrl -ne $operatorUrl -and $shareUrl -ne $deskDisplay) {
            Write-Host ("Share URL: {0}" -f $shareUrl) -ForegroundColor Cyan
        }
        Write-Host ("Restart it with: .\metra.ps1 ops -Stop -Port {0}" -f $Port) -ForegroundColor DarkGray
        if (-not $NoBrowser) {
            try {
                $authorizedOpenUrl = Get-MetraOpsDeskOpenUrl -Binding $binding
                Start-Process $authorizedOpenUrl | Out-Null
            }
            catch {
                Write-Warning "Could not open browser: $($_.Exception.Message)"
            }
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

    Write-Host ("Metra Ops desk: {0}" -f $deskDisplay) -ForegroundColor Green
    $isTailscale = $false
    try { $isTailscale = [bool](Get-MetraProp -Object $binding -Name 'Tailscale' -Default $false) } catch { }
    if ($isTailscale) {
        $serveOn = $false
        try { $serveOn = [bool](Get-MetraProp -Object $binding -Name 'Serve' -Default $false) } catch { }
        if ($serveOn) {
            Write-Host 'Tailscale Serve HTTPS enabled. Host Open uses the memorable Share URL with a local-session bootstrap; peers without Host open stay Ask-class.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host 'Tailscale reach enabled without Serve HTTPS (view/ask for peers). Clipboard APIs need a secure context - fix Serve or use Host Open on the share desk.' -ForegroundColor DarkYellow
            $serveErr = [string](Get-MetraProp -Object $binding -Name 'ServeError' -Default '')
            if ($serveErr) { Write-Warning $serveErr }
        }
        if ($shareUrl) {
            Write-Host ("Share URL: {0}" -f $shareUrl) -ForegroundColor Cyan
        }
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
            # Do not Write-Host the open URL - it includes #metraLocalSession bootstrap.
            $authorizedOpenUrl = Get-MetraOpsDeskOpenUrl -Binding $binding
            Start-Process $authorizedOpenUrl | Out-Null
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

            try {
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

                if ($req.HttpMethod -eq 'OPTIONS') {
                    # No CORS grant - just avoid treating preflight as a missing app route.
                    $res.StatusCode = 204
                    $res.Headers['Cache-Control'] = 'no-store'
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
            finally {
                if ($async -and $async.AsyncWaitHandle) {
                    try { $async.AsyncWaitHandle.Dispose() } catch { }
                }
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
