# Metra proposal store: immutable body + mutable status (Propose-Confirm-Apply Slice 2).
# Does not write project roots. Jail validation is Slice 3; Host apply is Slice 5.

$script:MetraProposalSchemaVersion = 1
$script:MetraProposalDefaultTtlMinutes = 15
$script:MetraProposalTerminalStatuses = @('applied', 'rejected', 'expired')

function Get-MetraProposalSupportedSchemaVersion {
    return [int]$script:MetraProposalSchemaVersion
}

function Get-MetraProposalStoreRoot {
    param(
        [string]$StoreRoot
    )

    $root = if (-not [string]::IsNullOrWhiteSpace($StoreRoot)) {
        $StoreRoot.TrimEnd('\', '/')
    }
    else {
        Join-Path $env:LOCALAPPDATA 'Metra\proposals'
    }

    if (-not (Test-Path -LiteralPath $root)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($root)
    }

    return $root
}

function Get-MetraProposalBodyPath {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )
    return Join-Path (Get-MetraProposalStoreRoot -StoreRoot $StoreRoot) ($Id + '.body.json')
}

function Get-MetraProposalMetaPath {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )
    return Join-Path (Get-MetraProposalStoreRoot -StoreRoot $StoreRoot) ($Id + '.json')
}

function ConvertTo-MetraProposalSha256 {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
        return 'sha256:' + $hex
    }
    finally {
        $sha.Dispose()
    }
}

function New-MetraProposalId {
    $utc = [datetime]::UtcNow
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    return ('p_{0:yyyyMMdd}_{0:HHmmss}_{1}' -f $utc, $suffix)
}

function New-MetraProposalNonce {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function ConvertTo-MetraProposalCanonicalJson {
    param(
        [Parameter(Mandatory)]$Object
    )

    # Ordered hashtables keep key order under ConvertTo-Json on pwsh 7 (test host).
    return ($Object | ConvertTo-Json -Depth 30 -Compress)
}

function Get-MetraProposalEntryValue {
    param(
        $Entry,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Entry) {
        return $null
    }
    if ($Entry -is [System.Collections.IDictionary]) {
        if ($Entry.Contains($Name)) {
            return $Entry[$Name]
        }
        return $null
    }
    $prop = $Entry.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }
    return $prop.Value
}

function Test-MetraProposalEntryHasName {
    param(
        $Entry,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Entry) {
        return $false
    }
    if ($Entry -is [System.Collections.IDictionary]) {
        return [bool]$Entry.Contains($Name)
    }
    return ($null -ne $Entry.PSObject.Properties[$Name])
}

function Get-MetraProposalHashableObject {
    param(
        [Parameter(Mandatory)]$Fields
    )

    $fileRows = @($Fields.files | Sort-Object {
            [string](Get-MetraProposalEntryValue -Entry $_ -Name 'pathRelative')
        } | ForEach-Object {
            $pathRelative = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'pathRelative')
            $action = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'action')
            $contentUtf8 = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'contentUtf8')
            $row = [ordered]@{
                pathRelative = $pathRelative
                action       = $action
                contentUtf8  = $contentUtf8
            }
            $previousHash = Get-MetraProposalEntryValue -Entry $_ -Name 'previousHash'
            if ($action -eq 'replace') {
                $row['previousHash'] = [string]$previousHash
            }
            $row
        })

    return [ordered]@{
        schemaVersion = [int]$Fields.schemaVersion
        id            = [string]$Fields.id
        createdAt     = [string]$Fields.createdAt
        project       = [string]$Fields.project
        routeStop     = [string]$Fields.routeStop
        rootPath      = [string]$Fields.rootPath
        summary       = [string]$Fields.summary
        files         = @($fileRows)
        source        = [string]$Fields.source
    }
}

function Get-MetraProposalContentHash {
    param(
        [Parameter(Mandatory)]$Fields
    )

    $canonical = Get-MetraProposalHashableObject -Fields $Fields
    $json = ConvertTo-MetraProposalCanonicalJson -Object $canonical
    return ConvertTo-MetraProposalSha256 -Text $json
}

function Test-MetraProposalSchemaVersion {
    param(
        $SchemaVersion
    )

    if ($null -eq $SchemaVersion) {
        return $false
    }
    try {
        $v = [int]$SchemaVersion
    }
    catch {
        return $false
    }
    return ($v -eq (Get-MetraProposalSupportedSchemaVersion))
}

function Get-MetraProposalAllowedNextStatuses {
    param(
        [Parameter(Mandatory)][string]$Status
    )

    switch ($Status) {
        'draft' { return @('pendingApply', 'rejected', 'expired') }
        'pendingApply' { return @('applied', 'rejected', 'expired') }
        default { return @() }
    }
}

function Test-MetraProposalStatusTransition {
    param(
        [Parameter(Mandatory)][string]$From,
        [Parameter(Mandatory)][string]$To
    )

    $allowed = @(Get-MetraProposalAllowedNextStatuses -Status $From)
    return ($allowed -contains $To)
}

function Assert-MetraProposalPathRelative {
    <#
    .SYNOPSIS
        Rejects rooted, UNC, or parent-segment pathRelative values before jail/apply.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathRelative
    )

    $norm = $PathRelative.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($norm)) {
        throw 'Each proposal file requires pathRelative.'
    }
    if ($norm.Contains([char]0)) {
        throw "Invalid pathRelative (null byte): $PathRelative"
    }
    if ($norm.StartsWith('/') -or $norm.StartsWith('\\') -or $norm -match '^[A-Za-z]:') {
        throw "Invalid pathRelative (must be relative): $PathRelative"
    }
    if ([System.IO.Path]::IsPathRooted(($norm -replace '/', '\'))) {
        throw "Invalid pathRelative (must be relative): $PathRelative"
    }
    if ($norm -match '(^|/)\.\.(/|$)') {
        throw "Invalid pathRelative (parent segment not allowed): $PathRelative"
    }
    return $norm
}

function Assert-MetraProposalFileEntries {
    param(
        [Parameter(Mandatory)][object[]]$Files
    )

    if ($null -eq $Files -or $Files.Count -lt 1) {
        throw 'Proposal files must contain at least one entry.'
    }

    $seen = @{}
    foreach ($file in $Files) {
        $pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
        $action = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
        $hasContent = Test-MetraProposalEntryHasName -Entry $file -Name 'contentUtf8'

        $normPath = Assert-MetraProposalPathRelative -PathRelative $pathRelative
        $key = $normPath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            throw "Duplicate proposal path: $normPath"
        }
        $seen[$key] = $true

        if ($action -notin @('create', 'replace')) {
            throw "Proposal file action must be create or replace (got '$action')."
        }
        if (-not $hasContent) {
            throw "Proposal file '$normPath' requires contentUtf8."
        }

        $previousHash = Get-MetraProposalEntryValue -Entry $file -Name 'previousHash'
        if ($action -eq 'replace' -and [string]::IsNullOrWhiteSpace([string]$previousHash)) {
            throw "Replace action for '$normPath' requires previousHash."
        }
        if ($action -eq 'create' -and -not [string]::IsNullOrWhiteSpace([string]$previousHash)) {
            throw "Create action for '$normPath' must not include previousHash."
        }
    }
}

function ConvertTo-MetraProposalNormalizedFiles {
    param(
        [Parameter(Mandatory)][object[]]$Files
    )

    Assert-MetraProposalFileEntries -Files $Files

    return @($Files | ForEach-Object {
            $pathRelative = Assert-MetraProposalPathRelative -PathRelative ([string](Get-MetraProposalEntryValue -Entry $_ -Name 'pathRelative'))
            $action = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'action')
            $contentUtf8 = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'contentUtf8')
            $row = [ordered]@{
                pathRelative = $pathRelative
                action       = $action
                contentUtf8  = $contentUtf8
            }
            if ($action -eq 'replace') {
                $row['previousHash'] = [string](Get-MetraProposalEntryValue -Entry $_ -Name 'previousHash')
            }
            $row
        })
}

function Convert-MetraJsonElementToObject {
    param(
        [System.Text.Json.JsonElement]$Element
    )

    switch ($Element.ValueKind.ToString()) {
        'String' { return $Element.GetString() }
        'Number' {
            $asLong = 0L
            if ($Element.TryGetInt64([ref]$asLong)) {
                return $asLong
            }
            return $Element.GetDouble()
        }
        'True' { return $true }
        'False' { return $false }
        'Null' { return $null }
        'Array' {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((Convert-MetraJsonElementToObject -Element $item))
            }
            return @($items.ToArray())
        }
        'Object' {
            $ordered = [ordered]@{}
            foreach ($prop in $Element.EnumerateObject()) {
                $ordered[$prop.Name] = Convert-MetraJsonElementToObject -Element $prop.Value
            }
            return [pscustomobject]$ordered
        }
        default { return $Element.GetRawText() }
    }
}

function Read-MetraProposalJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Proposal file not found: $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    # System.Text.Json keeps ISO timestamps as strings (ConvertFrom-Json promotes them to DateTime and breaks contentHash).
    $doc = [System.Text.Json.JsonDocument]::Parse($raw)
    try {
        return (Convert-MetraJsonElementToObject -Element $doc.RootElement)
    }
    finally {
        $doc.Dispose()
    }
}

function Write-MetraProposalJsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $json = ($Object | ConvertTo-Json -Depth 30) + "`r`n"
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json, (Get-MetraUtf8NoBomEncoding))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function New-MetraProposal {
    <#
    .SYNOPSIS
        Creates an immutable proposal body and mutable status metadata under the proposal store.
    .DESCRIPTION
        Slice 2 only: no project-root writes and no jail checks. Returns the stored proposal plus the one-time nonce (also kept in meta for Host v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$RouteStop,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$Summary,
        [Parameter(Mandatory)][object[]]$Files,
        [string]$Source = 'ask',
        [int]$SchemaVersion = 1,
        [int]$TtlMinutes = 0,
        [string]$StoreRoot,
        [datetime]$CreatedAtUtc
    )

    if (-not (Test-MetraProposalSchemaVersion -SchemaVersion $SchemaVersion)) {
        throw "Unknown schemaVersion. Supported: $(Get-MetraProposalSupportedSchemaVersion)."
    }

    if ([string]::IsNullOrWhiteSpace($Project)) {
        throw 'Project (route stop) is required.'
    }
    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        throw 'RootPath is required.'
    }
    if ([string]::IsNullOrWhiteSpace($Summary)) {
        throw 'Summary is required.'
    }
    if ([string]::IsNullOrWhiteSpace($Source)) {
        $Source = 'ask'
    }
    if ([string]::IsNullOrWhiteSpace($RouteStop)) {
        $RouteStop = $Project
    }
    if ($TtlMinutes -le 0) {
        $TtlMinutes = [int]$script:MetraProposalDefaultTtlMinutes
    }

    $created = if ($PSBoundParameters.ContainsKey('CreatedAtUtc')) {
        $CreatedAtUtc.ToUniversalTime()
    }
    else {
        [datetime]::UtcNow
    }
    $createdAt = $created.ToString('o')
    $expiresAt = $created.AddMinutes($TtlMinutes).ToString('o')

    $normalizedFiles = ConvertTo-MetraProposalNormalizedFiles -Files $Files
    $id = New-MetraProposalId
    $nonce = New-MetraProposalNonce
    $nonceHash = ConvertTo-MetraProposalSha256 -Text $nonce

    $hashFields = [ordered]@{
        schemaVersion = $SchemaVersion
        id            = $id
        createdAt     = $createdAt
        project       = $Project
        routeStop     = $RouteStop
        rootPath      = $RootPath
        summary       = $Summary
        files         = $normalizedFiles
        source        = $Source
    }
    $contentHash = Get-MetraProposalContentHash -Fields $hashFields

    $body = [ordered]@{
        schemaVersion = $SchemaVersion
        id            = $id
        createdAt     = $createdAt
        project       = $Project
        routeStop     = $RouteStop
        rootPath      = $RootPath
        summary       = $Summary
        files         = $normalizedFiles
        contentHash   = $contentHash
        nonceHash     = $nonceHash
        source        = $Source
    }

    $meta = [ordered]@{
        id            = $id
        status        = 'draft'
        createdAt     = $createdAt
        updatedAt     = $createdAt
        expiresAt     = $expiresAt
        contentHash   = $contentHash
        nonce         = $nonce
        resultMessage = $null
        schemaVersion = $SchemaVersion
        project       = $Project
        routeStop     = $RouteStop
    }

    $store = Get-MetraProposalStoreRoot -StoreRoot $StoreRoot
    $bodyPath = Get-MetraProposalBodyPath -Id $id -StoreRoot $store
    $metaPath = Get-MetraProposalMetaPath -Id $id -StoreRoot $store
    if ((Test-Path -LiteralPath $bodyPath) -or (Test-Path -LiteralPath $metaPath)) {
        throw "Proposal id collision: $id"
    }

    Write-MetraProposalJsonFile -Path $bodyPath -Object $body
    Write-MetraProposalJsonFile -Path $metaPath -Object $meta

    return [pscustomobject]@{
        Id          = $id
        Status      = 'draft'
        Body        = Read-MetraProposalJsonFile -Path $bodyPath
        Meta        = Read-MetraProposalJsonFile -Path $metaPath
        BodyPath    = $bodyPath
        MetaPath    = $metaPath
        StoreRoot   = $store
        Nonce       = $nonce
        ContentHash = $contentHash
        ExpiresAt   = $expiresAt
    }
}

function Get-MetraProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )

    $store = Get-MetraProposalStoreRoot -StoreRoot $StoreRoot
    $bodyPath = Get-MetraProposalBodyPath -Id $Id -StoreRoot $store
    $metaPath = Get-MetraProposalMetaPath -Id $Id -StoreRoot $store
    $body = Read-MetraProposalJsonFile -Path $bodyPath
    $meta = Read-MetraProposalJsonFile -Path $metaPath

    return [pscustomobject]@{
        Id          = $Id
        Status      = [string]$meta.status
        Body        = $body
        Meta        = $meta
        BodyPath    = $bodyPath
        MetaPath    = $metaPath
        StoreRoot   = $store
        ContentHash = [string]$body.contentHash
        ExpiresAt   = [string]$meta.expiresAt
    }
}

function Test-MetraProposalContentHashMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )

    $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
    $fields = [ordered]@{
        schemaVersion = [int]$proposal.Body.schemaVersion
        id            = [string]$proposal.Body.id
        createdAt     = [string]$proposal.Body.createdAt
        project       = [string]$proposal.Body.project
        routeStop     = [string]$proposal.Body.routeStop
        rootPath      = [string]$proposal.Body.rootPath
        summary       = [string]$proposal.Body.summary
        files         = @($proposal.Body.files)
        source        = [string]$proposal.Body.source
    }
    $recomputed = Get-MetraProposalContentHash -Fields $fields
    return ($recomputed -eq [string]$proposal.Body.contentHash)
}

function Test-MetraProposalNonce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Nonce,
        [string]$StoreRoot
    )

    $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
    $expected = ConvertTo-MetraProposalSha256 -Text $Nonce
    return ($expected -eq [string]$proposal.Body.nonceHash)
}

function Set-MetraProposalStatus {
    <#
    .SYNOPSIS
        Transitions proposal status metadata. Never rewrites the immutable body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('pendingApply', 'applied', 'rejected', 'expired')]
        [string]$Status,
        [string]$ResultMessage,
        [string]$StoreRoot
    )

    $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
    $from = [string]$proposal.Meta.status

    if ($from -eq $Status) {
        return $proposal
    }

    if ($Status -in @('pendingApply', 'applied')) {
        $expiresAt = [datetime]::Parse([string]$proposal.Meta.expiresAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ([datetime]::UtcNow -gt $expiresAt.ToUniversalTime()) {
            $Status = 'expired'
            if (-not $PSBoundParameters.ContainsKey('ResultMessage') -or [string]::IsNullOrWhiteSpace($ResultMessage)) {
                $ResultMessage = 'Expired'
            }
        }
    }

    if ($from -eq $Status) {
        return $proposal
    }

    if (-not (Test-MetraProposalStatusTransition -From $from -To $Status)) {
        throw "Illegal proposal status transition: $from -> $Status."
    }

    $meta = [ordered]@{
        id            = [string]$proposal.Meta.id
        status        = $Status
        createdAt     = [string]$proposal.Meta.createdAt
        updatedAt     = [datetime]::UtcNow.ToString('o')
        expiresAt     = [string]$proposal.Meta.expiresAt
        contentHash   = [string]$proposal.Meta.contentHash
        nonce         = [string]$proposal.Meta.nonce
        resultMessage = if ($PSBoundParameters.ContainsKey('ResultMessage')) { $ResultMessage } else { $proposal.Meta.resultMessage }
        schemaVersion = [int]$proposal.Meta.schemaVersion
        project       = [string]$proposal.Meta.project
        routeStop     = [string]$proposal.Meta.routeStop
    }

    Write-MetraProposalJsonFile -Path $proposal.MetaPath -Object $meta
    return Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
}

function Request-MetraProposalApply {
    <#
    .SYNOPSIS
        Marks a draft proposal pendingApply. Does not write project files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )

    return Set-MetraProposalStatus -Id $Id -Status pendingApply -StoreRoot $StoreRoot
}

function Deny-MetraProposal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$ResultMessage = 'Rejected by user',
        [string]$StoreRoot
    )

    return Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $ResultMessage -StoreRoot $StoreRoot
}

function Sync-MetraProposalExpiration {
    <#
    .SYNOPSIS
        Flips overdue draft/pendingApply proposals to expired. Does not touch project disk.
    #>
    [CmdletBinding()]
    param(
        [string]$StoreRoot,
        [string]$Id
    )

    $store = Get-MetraProposalStoreRoot -StoreRoot $StoreRoot
    $ids = @()
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        $ids = @($Id)
    }
    else {
        $ids = @(Get-ChildItem -LiteralPath $store -Filter '*.json' -File |
            Where-Object { $_.Name -notlike '*.body.json' } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    }

    $changed = [System.Collections.Generic.List[object]]::new()
    foreach ($proposalId in $ids) {
        $proposal = Get-MetraProposal -Id $proposalId -StoreRoot $store
        if ($proposal.Status -in $script:MetraProposalTerminalStatuses) {
            continue
        }
        $expiresAt = [datetime]::Parse([string]$proposal.Meta.expiresAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        if ([datetime]::UtcNow -gt $expiresAt.ToUniversalTime()) {
            $changed.Add((Set-MetraProposalStatus -Id $proposalId -Status expired -ResultMessage 'Expired' -StoreRoot $store))
        }
    }
    return @($changed.ToArray())
}

function Get-MetraProposalBodyRaw {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot
    )
    $path = Get-MetraProposalBodyPath -Id $Id -StoreRoot $StoreRoot
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
}

function Find-MetraActiveProposalForProject {
    <#
    .SYNOPSIS
        Finds draft or pendingApply proposal for a project (Resolve UI safe capability).
    #>
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$StoreRoot
    )

    if ([string]::IsNullOrWhiteSpace($Project)) {
        return $null
    }

    $store = Get-MetraProposalStoreRoot -StoreRoot $StoreRoot
    # One store-wide expiration pass (not per-id) so N proposals do not mean N rescans.
    try { $null = Sync-MetraProposalExpiration -StoreRoot $store } catch { }

    $ids = @(Get-ChildItem -LiteralPath $store -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.body.json' } |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })

    $pending = $null
    $draft = $null
    foreach ($id in $ids) {
        try {
            $proposal = Get-MetraProposal -Id $id -StoreRoot $store
            if ([string]$proposal.Body.project -ne $Project) {
                continue
            }
            if ($proposal.Status -eq 'pendingApply') {
                $pending = $proposal
                break
            }
            if ($proposal.Status -eq 'draft' -and -not $draft) {
                $draft = $proposal
            }
        }
        catch { }
    }

    if ($pending) { return $pending }
    return $draft
}

function Get-MetraAttentionEditCapability {
    <#
    .SYNOPSIS
        Maps attention kind + optional proposal to Resolve editCapability (safe|unsafe|git).
    #>
    param(
        [string]$Kind,
        [string]$ProposalId
    )

    if (-not [string]::IsNullOrWhiteSpace($ProposalId)) {
        return 'safe'
    }
    if ([string]$Kind -eq 'git') {
        return 'git'
    }
    return 'unsafe'
}
