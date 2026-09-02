# Yarn storage helpers (self-contained; no Metra imports).

function Get-YarnUtf8NoBomEncoding {
    return [System.Text.UTF8Encoding]::new($false)
}

function Write-YarnAtomicUtf8Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    $enc = Get-YarnUtf8NoBomEncoding
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, $enc)
    if (Test-Path -LiteralPath $Path) {
        $bak = "$Path.bak"
        Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
        [System.IO.File]::Replace($tmp, $Path, $bak)
        Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
    }
    else {
        [System.IO.File]::Move($tmp, $Path)
    }
}

function Invoke-YarnWithNamedMutex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Script,
        [int]$TimeoutMs = 15000
    )
    $mutexName = "Local\Metra_$Name"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne($TimeoutMs)
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw "Timed out waiting for mutex $Name (${TimeoutMs}ms)."
        }
        return (& $Script)
    }
    finally {
        if ($acquired) { [void]$mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-YarnProp {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            $val = $Object[$Name]
            if ($null -eq $val) { return $Default }
            return $val
        }
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $val = $Object[$key]
                if ($null -eq $val) { return $Default }
                return $val
            }
        }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        foreach ($p in $Object.PSObject.Properties) {
            if ([string]::Equals($p.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -eq $p.Value) { return $Default }
                return $p.Value
            }
        }
        return $Default
    }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function ConvertTo-YarnIsoTimestamp {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return (Get-Date).ToUniversalTime().ToString('o')
    }
    if ($Value -is [datetime]) {
        return ([datetime]$Value).ToUniversalTime().ToString('o')
    }
    $s = [string]$Value
    try {
        $dt = [datetime]::Parse($s, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dt.ToUniversalTime().ToString('o')
    }
    catch {
        return $s
    }
}

function Get-YarnSchemaVersion { return 1 }
function Get-YarnHandoffContractVersion { return 1 }
function Get-YarnPackContractVersion { return '1' }
function Get-YarnRubricVersion { return 'yarn-rank-v1' }

function Get-MetraYarnRoot {
    [CmdletBinding()]
    param(
        [string]$Override
    )
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return [System.IO.Path]::GetFullPath($Override)
    }
    if ($env:METRA_YARN_ROOT) {
        return [System.IO.Path]::GetFullPath($env:METRA_YARN_ROOT)
    }
    return Join-Path $env:LOCALAPPDATA 'Metra\yarn'
}

function Initialize-MetraYarnLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )
    foreach ($rel in @('', 'daily', 'journal', 'plans')) {
        $path = if ($rel) { Join-Path $Root $rel } else { $Root }
        [void][System.IO.Directory]::CreateDirectory($path)
    }
    $backlogPath = Join-Path $Root 'backlog.json'
    if (-not (Test-Path -LiteralPath $backlogPath)) {
        $empty = [ordered]@{
            schemaVersion = Get-YarnSchemaVersion
            items         = @()
        }
        Write-YarnAtomicUtf8Text -Path $backlogPath -Text (($empty | ConvertTo-Json -Depth 8) + "`n")
    }
    $linksPath = Join-Path $Root 'plan-links.json'
    if (-not (Test-Path -LiteralPath $linksPath)) {
        $emptyLinks = [ordered]@{
            schemaVersion = Get-YarnSchemaVersion
            links         = @()
        }
        Write-YarnAtomicUtf8Text -Path $linksPath -Text (($emptyLinks | ConvertTo-Json -Depth 8) + "`n")
    }
}

function Get-YarnBacklogPath {
    param([Parameter(Mandatory)][string]$Root)
    return Join-Path $Root 'backlog.json'
}

function Get-YarnPlanLinksPath {
    param([Parameter(Mandatory)][string]$Root)
    return Join-Path $Root 'plan-links.json'
}

function Read-YarnJsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Yarn JSON missing: $Path"
    }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, (Get-YarnUtf8NoBomEncoding))
        return ($raw | ConvertFrom-Json)
    }
    catch {
        throw "Yarn JSON invalid (fail closed): $Path - $($_.Exception.Message)"
    }
}

function Save-YarnBacklogDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Document
    )
    $path = Get-YarnBacklogPath -Root $Root
    Invoke-YarnWithNamedMutex -Name 'yarn-backlog' -Script {
        Write-YarnAtomicUtf8Text -Path $path -Text (($Document | ConvertTo-Json -Depth 12) + "`n")
    }
}

function Save-YarnPlanLinksDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Document
    )
    $path = Get-YarnPlanLinksPath -Root $Root
    Invoke-YarnWithNamedMutex -Name 'yarn-plan-links' -Script {
        Write-YarnAtomicUtf8Text -Path $path -Text (($Document | ConvertTo-Json -Depth 12) + "`n")
    }
}

function Add-MetraYarnJournalEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][hashtable]$Entry
    )
    $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $dir = Join-Path $Root 'journal'
    [void][System.IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir "$day.jsonl"
    if (-not $Entry.ContainsKey('at')) {
        $Entry['at'] = (Get-Date).ToUniversalTime().ToString('o')
    }
    $line = ($Entry | ConvertTo-Json -Compress -Depth 8)
    Invoke-YarnWithNamedMutex -Name 'yarn-journal' -Script {
        [System.IO.File]::AppendAllText($path, $line + "`n", (Get-YarnUtf8NoBomEncoding))
    }
}
