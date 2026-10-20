# Shared local defaults for iOS gate scripts (no operator identity in tracked defaults).
# Prefers repo-local scripts/ios-gate.local.json, then %LOCALAPPDATA%/Metra/ios-gate.local.json when present.
function Resolve-MetraIosGateLocalSettings {
    [CmdletBinding()]
    param(
        [string]$OpsBaseUrl = '',
        [string]$MacSsh = '',
        [string]$MacIosRoot = '',
        [string]$SshUserKnownHostsFile = ''
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    $repoLocal = Join-Path $PSScriptRoot 'ios-gate.local.json'
    [void]$candidates.Add($repoLocal)
    $appDataRoot = [string]$env:LOCALAPPDATA
    if (-not [string]::IsNullOrWhiteSpace($appDataRoot)) {
        [void]$candidates.Add((Join-Path $appDataRoot (Join-Path 'Metra' 'ios-gate.local.json')))
    }

    $localPath = $repoLocal
    $local = $null
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $localPath = $candidate
        try {
            $local = Get-Content -LiteralPath $candidate -Raw -Encoding utf8 | ConvertFrom-Json
        }
        catch {
            throw "Invalid ios-gate.local.json: $candidate - $($_.Exception.Message)"
        }
        break
    }

    $pick = {
        param([string]$Explicit, [string]$FromLocal, [string]$Fallback)
        if (-not [string]::IsNullOrWhiteSpace($Explicit)) { return $Explicit.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($FromLocal)) { return $FromLocal.Trim() }
        return $Fallback
    }

    $readLocal = {
        param($Obj, [string]$Name)
        if ($null -eq $Obj) { return '' }
        $prop = $Obj.PSObject.Properties[$Name]
        if (-not $prop) { return '' }
        return [string]$prop.Value
    }

    $ops = & $pick $OpsBaseUrl (& $readLocal $local 'opsBaseUrl') 'https://hq.example.ts.net'
    $ssh = & $pick $MacSsh (& $readLocal $local 'macSsh') ''
    $iosRoot = & $pick $MacIosRoot (& $readLocal $local 'macIosRoot') '~/Developer/Metra/clients/ios'
    $known = & $pick $SshUserKnownHostsFile (& $readLocal $local 'sshUserKnownHostsFile') ''

    return [PSCustomObject]@{
        OpsBaseUrl             = $ops
        MacSsh                 = $ssh
        MacIosRoot             = $iosRoot
        SshUserKnownHostsFile  = $known
        LocalConfigPath        = $localPath
        LocalConfigPresent     = ($null -ne $local)
    }
}
