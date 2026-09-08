# Metra Narrative Engine v0 - state is truth; AI is narrator only.

function Get-MetraNarrativeSchemaVersion {
    return 1
}

function Get-MetraNarrativePacksRoot {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return (Join-Path $MetraRoot 'narrative\packs')
}

function Get-MetraNarrativeSessionsRoot {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $data = Get-MetraMachineDataRoot -MetraRoot $MetraRoot
    $path = Join-Path $data 'narrative\sessions'
    [void][System.IO.Directory]::CreateDirectory($path)
    return $path
}

function Get-MetraNarrativeIndexPath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $data = Get-MetraMachineDataRoot -MetraRoot $MetraRoot
    $dir = Join-Path $data 'narrative'
    [void][System.IO.Directory]::CreateDirectory($dir)
    return (Join-Path $dir 'index.json')
}

function Get-MetraNarrativeContentHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-MetraNarrativeYaml {
    <#
    .SYNOPSIS
        Load a narrative scenario document. v0 accepts JSON (YAML 1.2 JSON subset) for reliable parsing without a YAML dependency.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'scenario document is empty'
    }
    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        try {
            return ($trimmed | ConvertFrom-Json -Depth 40)
        }
        catch {
            throw "scenario JSON/YAML parse failed: $($_.Exception.Message)"
        }
    }
    throw 'v0 narrative packs must use JSON-syntax scenario.yaml (YAML 1.2 JSON subset). Block-style YAML is deferred.'
}

function Get-MetraNarrativePackPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if ([string]::IsNullOrWhiteSpace($PackId) -or $PackId -eq '.' -or $PackId -eq '..' -or $PackId -match '[\\/]|(\.\.)') {
        throw "Invalid pack id: $PackId"
    }
    return (Join-Path (Get-MetraNarrativePacksRoot -MetraRoot $MetraRoot) "$PackId\scenario.yaml")
}

function Import-MetraNarrativePack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $path = Get-MetraNarrativePackPath -PackId $PackId -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Narrative pack not found: $PackId ($path)"
    }
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $doc = ConvertFrom-MetraNarrativeYaml -Text $raw
    $id = [string](Get-MetraProp -Object $doc -Name 'id' -Default '')
    if ([string]::IsNullOrWhiteSpace($id)) { throw "Pack $PackId missing id" }
    if (-not [string]::Equals($id, $PackId, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Pack folder '$PackId' does not match scenario id '$id'"
    }
    $mode = [string](Get-MetraProp -Object $doc -Name 'mode' -Default '')
    if ($mode -notin @('adventure', 'lesson', 'simulation')) {
        throw "Pack $PackId has invalid mode '$mode' (adventure|lesson|simulation)"
    }
    $version = 1
    $verObj = Get-MetraProp -Object $doc -Name 'version' -Default 1
    if ($null -ne $verObj) { $version = [int]$verObj }
    $fingerprint = Get-MetraNarrativeContentHash -Path $path
    return [PSCustomObject]@{
        PackId      = $PackId
        Path        = $path
        Version     = $version
        Fingerprint = $fingerprint
        Document    = $doc
        Mode        = $mode
    }
}

function Get-MetraNarrativePacks {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $root = Get-MetraNarrativePacksRoot -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $scenario = Join-Path $dir.FullName 'scenario.yaml'
        if (-not (Test-Path -LiteralPath $scenario)) { continue }
        try {
            $pack = Import-MetraNarrativePack -PackId $dir.Name -MetraRoot $MetraRoot
            $title = [string](Get-MetraProp -Object $pack.Document -Name 'title' -Default $pack.PackId)
            [void]$list.Add([PSCustomObject]@{
                    PackId  = $pack.PackId
                    Title   = $title
                    Mode    = $pack.Mode
                    Version = $pack.Version
                })
        }
        catch {
            [void]$list.Add([PSCustomObject]@{
                    PackId  = $dir.Name
                    Title   = '(invalid)'
                    Mode    = ''
                    Version = 0
                    Error   = $_.Exception.Message
                })
        }
    }
    return [object[]]$list.ToArray()
}

function ConvertTo-MetraNarrativeHashtable {
    [CmdletBinding()]
    param($InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ht = @{}
        foreach ($k in @($InputObject.Keys)) {
            $ht[[string]$k] = $InputObject[$k]
        }
        return $ht
    }
    $ht = @{}
    foreach ($p in @($InputObject.PSObject.Properties)) {
        $ht[$p.Name] = $p.Value
    }
    return $ht
}

function ConvertTo-MetraNarrativeBool {
    [CmdletBinding()]
    param($Value)
    if ($Value -is [bool]) { return [bool]$Value }
    if ($null -eq $Value) { return $false }
    $s = [string]$Value
    if ($s -eq '1' -or $s -eq 'true' -or $s -eq 'True' -or $s -eq 'TRUE') { return $true }
    if ($s -eq '0' -or $s -eq 'false' -or $s -eq 'False' -or $s -eq 'FALSE' -or $s -eq '') { return $false }
    try { return [bool]::Parse($s) } catch { throw "Cannot coerce '$Value' to bool" }
}

function Test-MetraNarrativeStatePredicate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        $When
    )

    if ($null -eq $When) { return $true }
    $pred = ConvertTo-MetraNarrativeHashtable -InputObject $When
    foreach ($key in @($pred.Keys)) {
        if (-not $State.ContainsKey($key)) { return $false }
        $expected = $pred[$key]
        $actual = $State[$key]
        if ($expected -is [bool] -or $actual -is [bool] -or
            ([string]$expected -in @('true', 'false', 'True', 'False', 'TRUE', 'FALSE'))) {
            try {
                if ((ConvertTo-MetraNarrativeBool -Value $expected) -ne (ConvertTo-MetraNarrativeBool -Value $actual)) {
                    return $false
                }
            }
            catch {
                return $false
            }
            continue
        }
        if ($expected -is [int] -or $expected -is [long] -or $expected -is [double] -or
            $actual -is [int] -or $actual -is [long] -or $actual -is [double]) {
            try {
                if ([double]$expected -ne [double]$actual) { return $false }
            }
            catch {
                return $false
            }
            continue
        }
        if (-not [string]::Equals([string]$expected, [string]$actual, [StringComparison]::Ordinal)) {
            return $false
        }
    }
    return $true
}

function Get-MetraNarrativeAllowedMoves {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][hashtable]$State,
        [string]$Terminal = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Terminal)) { return @() }
    $moves = @(Get-MetraProp -Object $Document -Name 'moves' -Default @())
    $allowed = New-Object System.Collections.Generic.List[object]
    foreach ($m in $moves) {
        $when = Get-MetraProp -Object $m -Name 'when' -Default $null
        if (-not (Test-MetraNarrativeStatePredicate -State $State -When $when)) { continue }
        $mid = [string](Get-MetraProp -Object $m -Name 'id' -Default '')
        if ([string]::IsNullOrWhiteSpace($mid)) { continue }
        [void]$allowed.Add([PSCustomObject]@{
                id          = $mid
                label       = [string](Get-MetraProp -Object $m -Name 'label' -Default $mid)
                description = [string](Get-MetraProp -Object $m -Name 'description' -Default '')
                outcome     = [string](Get-MetraProp -Object $m -Name 'outcome' -Default 'continue')
            })
    }
    return [object[]]$allowed.ToArray()
}

function Invoke-MetraNarrativeApplyEffects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        $Effects,
        $StateSchema
    )

    $next = @{}
    foreach ($k in @($State.Keys)) { $next[$k] = $State[$k] }
    if ($null -eq $Effects) { return $next }
    $patch = ConvertTo-MetraNarrativeHashtable -InputObject $Effects
    $schema = $null
    if ($null -ne $StateSchema) {
        $schema = ConvertTo-MetraNarrativeHashtable -InputObject $StateSchema
    }
    foreach ($key in @($patch.Keys)) {
        if ($null -ne $schema -and $schema.Count -gt 0 -and -not $schema.ContainsKey($key)) {
            throw "Effect path '$key' is not declared in stateSchema"
        }
        $value = $patch[$key]
        if ($null -ne $schema -and $schema.ContainsKey($key)) {
            $typeName = [string]$schema[$key]
            switch ($typeName.ToLowerInvariant()) {
                'bool' { $value = ConvertTo-MetraNarrativeBool -Value $value }
                'boolean' { $value = ConvertTo-MetraNarrativeBool -Value $value }
                'int' { $value = [int]$value }
                'integer' { $value = [int]$value }
                'number' { $value = [double]$value }
                'string' { $value = [string]$value }
                default { }
            }
        }
        $next[$key] = $value
    }
    return $next
}

function New-MetraNarrativeSessionId {
    return ('n' + [guid]::NewGuid().ToString('n').Substring(0, 12))
}

function ConvertTo-MetraNarrativeStateObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$State)
    $ordered = [ordered]@{}
    foreach ($k in @($State.Keys | Sort-Object)) {
        $ordered[$k] = $State[$k]
    }
    return [PSCustomObject]$ordered
}

function Save-MetraNarrativeJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Object
    )
    $dir = Split-Path -Parent $Path
    [void][System.IO.Directory]::CreateDirectory($dir)
    $json = ($Object | ConvertTo-Json -Depth 40)
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-MetraNarrativeIndex {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraNarrativeIndexPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ schemaVersion = (Get-MetraNarrativeSchemaVersion); sessions = @() }
    }
    try {
        $doc = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        if ($null -eq $doc.sessions) { $doc | Add-Member -NotePropertyName sessions -NotePropertyValue @() -Force }
        return $doc
    }
    catch {
        return [PSCustomObject]@{ schemaVersion = (Get-MetraNarrativeSchemaVersion); sessions = @() }
    }
}

function Save-MetraNarrativeIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Index,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $path = Get-MetraNarrativeIndexPath -MetraRoot $MetraRoot
    Save-MetraNarrativeJson -Path $path -Object $Index
}

function Update-MetraNarrativeIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][hashtable]$Fields,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $index = Get-MetraNarrativeIndex -MetraRoot $MetraRoot
    $sessions = @($index.sessions)
    $found = $false
    $updated = New-Object System.Collections.Generic.List[object]
    foreach ($s in $sessions) {
        if ([string]$s.sessionId -eq $SessionId) {
            $ht = ConvertTo-MetraNarrativeHashtable -InputObject $s
            foreach ($k in @($Fields.Keys)) { $ht[$k] = $Fields[$k] }
            [void]$updated.Add([PSCustomObject]$ht)
            $found = $true
        }
        else {
            [void]$updated.Add($s)
        }
    }
    if (-not $found) {
        $ht = @{ sessionId = $SessionId }
        foreach ($k in @($Fields.Keys)) { $ht[$k] = $Fields[$k] }
        [void]$updated.Add([PSCustomObject]$ht)
    }
    $index = [PSCustomObject]@{
        schemaVersion = (Get-MetraNarrativeSchemaVersion)
        sessions      = @($updated.ToArray())
    }
    Save-MetraNarrativeIndex -Index $index -MetraRoot $MetraRoot
}

function Test-MetraNarrativeSessionId {
    [CmdletBinding()]
    param([string]$SessionId)
    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $false }
    return ($SessionId -match '^n[0-9a-fA-F]{12}$')
}

function Get-MetraNarrativeSessionDir {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    if (-not (Test-MetraNarrativeSessionId -SessionId $SessionId)) {
        throw "Invalid session id: $SessionId"
    }
    return (Join-Path (Get-MetraNarrativeSessionsRoot -MetraRoot $MetraRoot) $SessionId)
}

function Read-MetraNarrativeSessionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $dir = Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot
    $path = Join-Path $dir 'state.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Narrative session not found: $SessionId"
    }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 40)
}

function Write-MetraNarrativeSessionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)]$StateDoc,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $dir = Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot
    Save-MetraNarrativeJson -Path (Join-Path $dir 'state.json') -Object $StateDoc
}

function Add-MetraNarrativeEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)]$Event,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $dir = Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot
    [void][System.IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir 'events.jsonl'
    $line = ($Event | ConvertTo-Json -Depth 20 -Compress)
    [System.IO.File]::AppendAllText($path, $line + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Get-MetraNarrativeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $path = Join-Path (Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot) 'events.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        [void]$list.Add(($line | ConvertFrom-Json -Depth 20))
    }
    return [object[]]$list.ToArray()
}

function Start-MetraNarrativeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackId,
        [int]$Seed = 0,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $pack = Import-MetraNarrativePack -PackId $PackId -MetraRoot $MetraRoot
    $doc = $pack.Document
    $initial = ConvertTo-MetraNarrativeHashtable -InputObject (Get-MetraProp -Object $doc -Name 'state' -Default @{})
    if ($Seed -le 0) {
        $Seed = Get-Random -Minimum 1 -Maximum 2147483647
    }
    $sessionId = New-MetraNarrativeSessionId
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $title = [string](Get-MetraProp -Object $doc -Name 'title' -Default $PackId)
    $stateDoc = [PSCustomObject]@{
        schemaVersion   = (Get-MetraNarrativeSchemaVersion)
        sessionId       = $sessionId
        packId          = $pack.PackId
        packVersion     = $pack.Version
        packFingerprint = $pack.Fingerprint
        mode            = $pack.Mode
        title           = $title
        seed            = $Seed
        lifecycle       = 'active'
        terminal        = ''
        createdAt       = $now
        updatedAt       = $now
        state           = ConvertTo-MetraNarrativeStateObject -State $initial
    }
    $dir = Get-MetraNarrativeSessionDir -SessionId $sessionId -MetraRoot $MetraRoot
    [void][System.IO.Directory]::CreateDirectory($dir)
    Write-MetraNarrativeSessionState -SessionId $sessionId -StateDoc $stateDoc -MetraRoot $MetraRoot
    Add-MetraNarrativeEvent -SessionId $sessionId -MetraRoot $MetraRoot -Event ([PSCustomObject]@{
            at     = $now
            type   = 'session_started'
            packId = $pack.PackId
            seed   = $Seed
        })
    Update-MetraNarrativeIndexEntry -SessionId $sessionId -MetraRoot $MetraRoot -Fields @{
        packId    = $pack.PackId
        title     = $title
        mode      = $pack.Mode
        lifecycle = 'active'
        terminal  = ''
        createdAt = $now
        updatedAt = $now
        seed      = $Seed
    }
    return Get-MetraNarrativeSessionStatus -SessionId $sessionId -MetraRoot $MetraRoot
}

function Assert-MetraNarrativePackBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$StateDoc,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $packId = [string]$StateDoc.packId
    $pack = Import-MetraNarrativePack -PackId $packId -MetraRoot $MetraRoot
    if ($pack.Fingerprint -ne [string]$StateDoc.packFingerprint) {
        throw "Pack '$packId' changed since session start (fingerprint mismatch). session=$($StateDoc.packFingerprint) current=$($pack.Fingerprint). Start a new session."
    }
    return $pack
}

function Get-MetraNarrativeSessionStatus {
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        $index = Get-MetraNarrativeIndex -MetraRoot $MetraRoot
        $active = @($index.sessions | Where-Object { [string]$_.lifecycle -eq 'active' } | Sort-Object updatedAt -Descending)
        if ($active.Count -eq 0) { throw 'No active narrative session. Use narrative start <packId>.' }
        $SessionId = [string]$active[0].sessionId
    }

    $stateDoc = Read-MetraNarrativeSessionState -SessionId $SessionId -MetraRoot $MetraRoot
    if ([string]$stateDoc.lifecycle -eq 'forgotten') {
        throw "Session $SessionId is forgotten"
    }
    $pack = $null
    $allowed = @()
    $doc = $null
    try {
        $pack = Assert-MetraNarrativePackBinding -StateDoc $stateDoc -MetraRoot $MetraRoot
        $doc = $pack.Document
        $stateHt = ConvertTo-MetraNarrativeHashtable -InputObject $stateDoc.state
        $allowed = @(Get-MetraNarrativeAllowedMoves -Document $doc -State $stateHt -Terminal ([string]$stateDoc.terminal))
    }
    catch {
        $allowed = @()
    }

    return [PSCustomObject]@{
        sessionId       = $stateDoc.sessionId
        packId          = $stateDoc.packId
        title           = $stateDoc.title
        mode            = $stateDoc.mode
        lifecycle       = $stateDoc.lifecycle
        terminal        = $stateDoc.terminal
        seed            = $stateDoc.seed
        packVersion     = $stateDoc.packVersion
        packFingerprint = $stateDoc.packFingerprint
        state           = $stateDoc.state
        allowedMoves    = $allowed
        objectives      = @(Get-MetraProp -Object $doc -Name 'objectives' -Default @())
        updatedAt       = $stateDoc.updatedAt
    }
}

function Invoke-MetraNarrativeMove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MoveId,
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $status = Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
    $SessionId = [string]$status.sessionId
    $stateDoc = Read-MetraNarrativeSessionState -SessionId $SessionId -MetraRoot $MetraRoot
    if ([string]$stateDoc.lifecycle -ne 'active') {
        throw "Session $SessionId is not active (lifecycle=$($stateDoc.lifecycle))"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$stateDoc.terminal)) {
        throw "Session $SessionId already ended with terminal='$($stateDoc.terminal)'"
    }

    $pack = Assert-MetraNarrativePackBinding -StateDoc $stateDoc -MetraRoot $MetraRoot
    $doc = $pack.Document
    $stateHt = ConvertTo-MetraNarrativeHashtable -InputObject $stateDoc.state
    $now = (Get-Date).ToUniversalTime().ToString('o')

    $moves = @(Get-MetraProp -Object $doc -Name 'moves' -Default @())
    $move = $moves | Where-Object { [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -eq $MoveId } | Select-Object -First 1
    if ($null -eq $move) {
        Add-MetraNarrativeEvent -SessionId $SessionId -MetraRoot $MetraRoot -Event ([PSCustomObject]@{
                at     = $now
                type   = 'move_rejected'
                moveId = $MoveId
                reason = 'unknown_move'
            })
        throw "Unknown move: $MoveId"
    }

    $when = Get-MetraProp -Object $move -Name 'when' -Default $null
    if (-not (Test-MetraNarrativeStatePredicate -State $stateHt -When $when)) {
        Add-MetraNarrativeEvent -SessionId $SessionId -MetraRoot $MetraRoot -Event ([PSCustomObject]@{
                at     = $now
                type   = 'move_rejected'
                moveId = $MoveId
                reason = 'predicate_failed'
            })
        throw "Move '$MoveId' is not available in the current state"
    }

    $effects = Get-MetraProp -Object $move -Name 'effects' -Default $null
    $schema = Get-MetraProp -Object $doc -Name 'stateSchema' -Default $null
    $newState = Invoke-MetraNarrativeApplyEffects -State $stateHt -Effects $effects -StateSchema $schema
    $outcome = [string](Get-MetraProp -Object $move -Name 'outcome' -Default 'continue')
    if ($outcome -notin @('success', 'fail', 'continue')) {
        throw "Move '$MoveId' has invalid outcome '$outcome'"
    }

    $terminal = ''
    if ($outcome -eq 'success' -or $outcome -eq 'fail') {
        $terminal = $outcome
    }

    $stateDoc.state = ConvertTo-MetraNarrativeStateObject -State $newState
    $stateDoc.terminal = $terminal
    $stateDoc.updatedAt = $now
    if ($terminal) {
        $stateDoc.lifecycle = 'active'
    }
    Write-MetraNarrativeSessionState -SessionId $SessionId -StateDoc $stateDoc -MetraRoot $MetraRoot
    Add-MetraNarrativeEvent -SessionId $SessionId -MetraRoot $MetraRoot -Event ([PSCustomObject]@{
            at       = $now
            type     = 'move_accepted'
            moveId   = $MoveId
            outcome  = $outcome
            terminal = $terminal
            state    = ConvertTo-MetraNarrativeStateObject -State $newState
        })
    Update-MetraNarrativeIndexEntry -SessionId $SessionId -MetraRoot $MetraRoot -Fields @{
        lifecycle = [string]$stateDoc.lifecycle
        terminal  = $terminal
        updatedAt = $now
        packId    = [string]$stateDoc.packId
        title     = [string]$stateDoc.title
        mode      = [string]$stateDoc.mode
    }

    return Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
}

function New-MetraNarrativeFallbackText {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Status)

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("Scenario: $($Status.title) [$($Status.packId)]")
    [void]$lines.Add("Lifecycle: $($Status.lifecycle); terminal: $(if ($Status.terminal) { $Status.terminal } else { 'none' })")
    $stateHt = ConvertTo-MetraNarrativeHashtable -InputObject $Status.state
    $pairs = @($stateHt.Keys | Sort-Object | ForEach-Object { "$_=$($stateHt[$_])" })
    [void]$lines.Add('State: ' + ($pairs -join ', '))
    if (@($Status.allowedMoves).Count -gt 0) {
        $moveLabels = @($Status.allowedMoves | ForEach-Object { $_.id })
        [void]$lines.Add('Allowed moves: ' + ($moveLabels -join ', '))
    }
    elseif ($Status.terminal) {
        [void]$lines.Add("Scenario ended with '$($Status.terminal)'.")
    }
    else {
        [void]$lines.Add('No moves available.')
    }
    return ($lines -join [Environment]::NewLine)
}

function Invoke-MetraNarrativeNarrate {
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$FallbackOnly
    )

    $status = Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
    $fallback = New-MetraNarrativeFallbackText -Status $status
    if ($FallbackOnly) {
        return [PSCustomObject]@{
            sessionId = $status.sessionId
            source    = 'fallback'
            text      = $fallback
            ok        = $true
        }
    }

    $moveLines = @($status.allowedMoves | ForEach-Object {
            $desc = if ($_.description) { " - $($_.description)" } else { '' }
            "- $($_.id): $($_.label)$desc"
        })
    $stateJson = ($status.state | ConvertTo-Json -Depth 10 -Compress)
    $prompt = @"
You are the narrator for a Metra Narrative session. State is authoritative. Do not invent new facts, items, locations, or outcomes. Do not decide success or failure. Describe the current situation briefly and list the allowed moves as options the player may take. Keep it under 180 words.

Pack: $($status.packId) ($($status.mode))
Title: $($status.title)
Terminal: $(if ($status.terminal) { $status.terminal } else { 'none' })
State JSON: $stateJson
Allowed moves:
$($moveLines -join [Environment]::NewLine)
"@

    try {
        $result = Invoke-MetraAskEngine -Prompt $prompt -Cwd $MetraRoot -Context @{ purpose = 'narrative' } -MetraRoot $MetraRoot -TimeoutSec 90
        $ok = $false
        $msg = ''
        if ($null -ne $result) {
            $okProp = Get-MetraProp -Object $result -Name 'ok' -Default $false
            $ok = [bool]$okProp
            $msg = [string](Get-MetraProp -Object $result -Name 'message' -Default '')
        }
        if ($ok -and -not [string]::IsNullOrWhiteSpace($msg)) {
            return [PSCustomObject]@{
                sessionId = $status.sessionId
                source    = 'ask'
                text      = $msg.Trim()
                ok        = $true
            }
        }
    }
    catch {
        # Narration failure never blocks; fall through to deterministic fallback.
    }

    return [PSCustomObject]@{
        sessionId = $status.sessionId
        source    = 'fallback'
        text      = $fallback
        ok        = $true
    }
}

function Stop-MetraNarrativeSession {
    [CmdletBinding()]
    param(
        [string]$SessionId,
        [string]$Summary = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $status = Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
    $SessionId = [string]$status.sessionId
    $stateDoc = Read-MetraNarrativeSessionState -SessionId $SessionId -MetraRoot $MetraRoot
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $stateDoc.lifecycle = 'dormant'
    $stateDoc.updatedAt = $now
    Write-MetraNarrativeSessionState -SessionId $SessionId -StateDoc $stateDoc -MetraRoot $MetraRoot

    $summaryObj = [PSCustomObject]@{
        sessionId = $SessionId
        packId    = $stateDoc.packId
        terminal  = $stateDoc.terminal
        seed      = $stateDoc.seed
        endedAt   = $now
        summary   = $Summary
        state     = $stateDoc.state
    }
    Save-MetraNarrativeJson -Path (Join-Path (Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot) 'summary.json') -Object $summaryObj
    Add-MetraNarrativeEvent -SessionId $SessionId -MetraRoot $MetraRoot -Event ([PSCustomObject]@{
            at   = $now
            type = 'session_ended'
        })
    Update-MetraNarrativeIndexEntry -SessionId $SessionId -MetraRoot $MetraRoot -Fields @{
        lifecycle = 'dormant'
        terminal  = [string]$stateDoc.terminal
        updatedAt = $now
        packId    = [string]$stateDoc.packId
        title     = [string]$stateDoc.title
        mode      = [string]$stateDoc.mode
    }
    return Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
}

function Set-MetraNarrativeLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][ValidateSet('draft', 'active', 'dormant', 'archived', 'forgotten')][string]$Lifecycle,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $dir = Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $dir)) { throw "Narrative session not found: $SessionId" }

    if ($Lifecycle -eq 'forgotten') {
        return Invoke-MetraNarrativeForget -SessionId $SessionId -MetraRoot $MetraRoot
    }

    $stateDoc = Read-MetraNarrativeSessionState -SessionId $SessionId -MetraRoot $MetraRoot
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $stateDoc.lifecycle = $Lifecycle
    $stateDoc.updatedAt = $now
    Write-MetraNarrativeSessionState -SessionId $SessionId -StateDoc $stateDoc -MetraRoot $MetraRoot
    Update-MetraNarrativeIndexEntry -SessionId $SessionId -MetraRoot $MetraRoot -Fields @{
        lifecycle = $Lifecycle
        updatedAt = $now
        packId    = [string]$stateDoc.packId
        title     = [string]$stateDoc.title
        mode      = [string]$stateDoc.mode
        terminal  = [string]$stateDoc.terminal
    }
    return Get-MetraNarrativeSessionStatus -SessionId $SessionId -MetraRoot $MetraRoot
}

function Invoke-MetraNarrativeForget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $dir = Get-MetraNarrativeSessionDir -SessionId $SessionId -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $dir)) { throw "Narrative session not found: $SessionId" }

    $title = $SessionId
    $packId = ''
    $terminal = ''
    $summaryText = ''
    try {
        $stateDoc = Read-MetraNarrativeSessionState -SessionId $SessionId -MetraRoot $MetraRoot
        $title = [string]$stateDoc.title
        $packId = [string]$stateDoc.packId
        $terminal = [string]$stateDoc.terminal
    }
    catch { }
    $summaryPath = Join-Path $dir 'summary.json'
    if (Test-Path -LiteralPath $summaryPath) {
        try {
            $sum = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 10
            $summaryText = [string](Get-MetraProp -Object $sum -Name 'summary' -Default '')
            if (-not $terminal) { $terminal = [string](Get-MetraProp -Object $sum -Name 'terminal' -Default '') }
            if (-not $packId) { $packId = [string](Get-MetraProp -Object $sum -Name 'packId' -Default '') }
        }
        catch { }
    }

    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $notable = if ($summaryText) { $summaryText } elseif ($terminal) { "Ended with $terminal" } else { '' }
    Update-MetraNarrativeIndexEntry -SessionId $SessionId -MetraRoot $MetraRoot -Fields @{
        lifecycle      = 'forgotten'
        updatedAt      = $now
        packId         = $packId
        title          = $title
        terminal       = $terminal
        notableOutcome = $notable
    }
    return [PSCustomObject]@{
        sessionId      = $SessionId
        lifecycle      = 'forgotten'
        title          = $title
        packId         = $packId
        terminal       = $terminal
        notableOutcome = $notable
    }
}

function Clear-MetraNarrativeTempFiles {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $removed = 0
    $root = Split-Path -Parent (Get-MetraNarrativeIndexPath -MetraRoot $MetraRoot)
    if (-not (Test-Path -LiteralPath $root)) { return 0 }
    foreach ($tmp in @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.tmp' -File -ErrorAction SilentlyContinue)) {
        try {
            Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction Stop
            $removed++
        }
        catch { }
    }
    return $removed
}

function Invoke-MetraNarrativeExpire {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$DormantDays = 14,
        [int]$ArchivedDays = 60,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $whatIf = [bool]$WhatIfPreference
    $tmpCleared = 0
    if (-not $whatIf) {
        $tmpCleared = Clear-MetraNarrativeTempFiles -MetraRoot $MetraRoot
    }

    $index = Get-MetraNarrativeIndex -MetraRoot $MetraRoot
    $now = (Get-Date).ToUniversalTime()
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($index.sessions)) {
        $life = [string]$s.lifecycle
        if ($life -in @('forgotten', '')) { continue }
        $updated = $now
        try { $updated = [datetime]::Parse([string]$s.updatedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) } catch { }
        $age = ($now - $updated).TotalDays
        $target = $null
        if ($life -eq 'active' -and $age -ge $DormantDays) { $target = 'dormant' }
        elseif ($life -eq 'dormant' -and $age -ge $DormantDays) { $target = 'archived' }
        elseif ($life -eq 'archived' -and $age -ge $ArchivedDays) { $target = 'forgotten' }
        if (-not $target) { continue }
        [void]$actions.Add([PSCustomObject]@{
                sessionId = [string]$s.sessionId
                from      = $life
                to        = $target
                ageDays   = [math]::Round($age, 1)
            })
        $targetLabel = "session $([string]$s.sessionId) $($life)->$target"
        if ($PSCmdlet.ShouldProcess($targetLabel, 'Expire narrative session')) {
            if ($target -eq 'forgotten') {
                [void](Invoke-MetraNarrativeForget -SessionId ([string]$s.sessionId) -MetraRoot $MetraRoot)
            }
            else {
                [void](Set-MetraNarrativeLifecycle -SessionId ([string]$s.sessionId) -Lifecycle $target -MetraRoot $MetraRoot)
            }
        }
    }
    return [PSCustomObject]@{
        whatIf     = $whatIf
        actions    = @($actions.ToArray())
        count      = @($actions.ToArray()).Count
        tmpCleared = $tmpCleared
    }
}

function Get-MetraNarrativeSessions {
    [CmdletBinding()]
    param(
        [string]$Lifecycle = 'all',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $index = Get-MetraNarrativeIndex -MetraRoot $MetraRoot
    $items = @($index.sessions)
    if ($Lifecycle -and $Lifecycle -ne 'all') {
        $items = @($items | Where-Object { [string]$_.lifecycle -eq $Lifecycle })
    }
    return @($items | Sort-Object updatedAt -Descending)
}

function Invoke-MetraNarrativeCommand {
    <#
    .SYNOPSIS
        CLI: narrative packs|start|status|moves|move|narrate|end|list|expire|forget|lifecycle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    switch ($Subcommand.ToLowerInvariant()) {
        'packs' {
            return [object[]]@(Get-MetraNarrativePacks -MetraRoot $MetraRoot)
        }
        'list' {
            $life = 'all'
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Lifecycle' -and ($i + 1) -lt $ArgsRest.Count) {
                    $life = [string]$ArgsRest[$i + 1]
                }
            }
            return [object[]]@(Get-MetraNarrativeSessions -Lifecycle $life -MetraRoot $MetraRoot)
        }
        'start' {
            $packId = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            $seed = 0
            for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Seed' -and ($i + 1) -lt $ArgsRest.Count) {
                    $seed = [int]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($packId)) { throw 'narrative start <packId> [-Seed n]' }
            return Start-MetraNarrativeSession -PackId $packId -Seed $seed -MetraRoot $MetraRoot
        }
        'status' {
            $sid = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            return Get-MetraNarrativeSessionStatus -SessionId $sid -MetraRoot $MetraRoot
        }
        'moves' {
            $sid = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            $st = Get-MetraNarrativeSessionStatus -SessionId $sid -MetraRoot $MetraRoot
            return [object[]]@($st.allowedMoves)
        }
        'move' {
            $moveId = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            $sid = ''
            for ($i = 1; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Session' -and ($i + 1) -lt $ArgsRest.Count) {
                    $sid = [string]$ArgsRest[$i + 1]
                }
            }
            if ([string]::IsNullOrWhiteSpace($moveId)) { throw 'narrative move <moveId> [-Session <id>]' }
            return Invoke-MetraNarrativeMove -MoveId $moveId -SessionId $sid -MetraRoot $MetraRoot
        }
        'narrate' {
            $sid = ''
            $fallbackOnly = $false
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-FallbackOnly') { $fallbackOnly = $true; continue }
                if (-not $ArgsRest[$i].StartsWith('-') -and [string]::IsNullOrWhiteSpace($sid)) {
                    $sid = [string]$ArgsRest[$i]
                }
            }
            return Invoke-MetraNarrativeNarrate -SessionId $sid -MetraRoot $MetraRoot -FallbackOnly:$fallbackOnly
        }
        'end' {
            $sid = ''
            $summary = ''
            for ($i = 0; $i -lt $ArgsRest.Count; $i++) {
                if ($ArgsRest[$i] -eq '-Summary' -and ($i + 1) -lt $ArgsRest.Count) {
                    $summary = [string]$ArgsRest[$i + 1]
                    $i++
                    continue
                }
                if (-not $ArgsRest[$i].StartsWith('-') -and [string]::IsNullOrWhiteSpace($sid)) {
                    $sid = [string]$ArgsRest[$i]
                }
            }
            return Stop-MetraNarrativeSession -SessionId $sid -Summary $summary -MetraRoot $MetraRoot
        }
        'forget' {
            $sid = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            if ([string]::IsNullOrWhiteSpace($sid)) { throw 'narrative forget <sessionId>' }
            return Invoke-MetraNarrativeForget -SessionId $sid -MetraRoot $MetraRoot
        }
        'lifecycle' {
            $sid = if ($ArgsRest.Count -gt 0) { [string]$ArgsRest[0] } else { '' }
            $life = if ($ArgsRest.Count -gt 1) { [string]$ArgsRest[1] } else { '' }
            if ([string]::IsNullOrWhiteSpace($sid) -or [string]::IsNullOrWhiteSpace($life)) {
                throw 'narrative lifecycle <sessionId> <draft|active|dormant|archived|forgotten>'
            }
            return Set-MetraNarrativeLifecycle -SessionId $sid -Lifecycle $life -MetraRoot $MetraRoot
        }
        'expire' {
            $useWhatIf = $WhatIfPreference -or ($ArgsRest -contains '-WhatIf')
            if ($useWhatIf) {
                return Invoke-MetraNarrativeExpire -MetraRoot $MetraRoot -WhatIf
            }
            return Invoke-MetraNarrativeExpire -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown narrative subcommand: $Subcommand. Use packs|start|status|moves|move|narrate|end|list|expire|forget|lifecycle."
        }
    }
}
