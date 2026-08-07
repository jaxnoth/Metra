# Ask secrets scrub - defense in depth for Ops Ask prompts, context, responses, and journal.

function Get-MetraAskSecretsPatternSet {
    <#
    .SYNOPSIS
        High-signal secret patterns. Prefer labeled prefixes; avoid ticket ids and short hex.
    #>
    [CmdletBinding()]
    param()

    # Order matters: refuse patterns first so PEM is detected before generic scrapes.
    @(
        [PSCustomObject]@{
            Kind   = 'pem'
            Refuse = $true
            Reason = 'pem_private_key'
            # Multiline private key blocks (RSA / EC / OPENSSH / generic PRIVATE KEY).
            Regex  = [regex]::new('-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', 'IgnoreCase, Multiline')
        }
        [PSCustomObject]@{
            Kind   = 'github'
            Refuse = $false
            Reason = $null
            Regex  = [regex]::new('\b(?:ghp_|gho_|ghu_|ghs_|ghr_|github_pat_)[A-Za-z0-9_]{20,}\b', 'IgnoreCase')
        }
        [PSCustomObject]@{
            Kind   = 'aws'
            Refuse = $false
            Reason = $null
            Regex  = [regex]::new('\bAKIA[0-9A-Z]{16}\b')
        }
        [PSCustomObject]@{
            Kind   = 'slack'
            Refuse = $false
            Reason = $null
            Regex  = [regex]::new('\bxox[baprs]-[A-Za-z0-9-]{10,}\b', 'IgnoreCase')
        }
        [PSCustomObject]@{
            Kind   = 'api_key'
            Refuse = $false
            Reason = $null
            # OpenAI-style sk- keys (length-gated to reduce false positives).
            Regex  = [regex]::new('\bsk-[A-Za-z0-9]{20,}\b')
        }
        [PSCustomObject]@{
            Kind   = 'bearer'
            Refuse = $false
            Reason = $null
            Regex  = [regex]::new('\bBearer\s+[A-Za-z0-9\-._~+/]+=*', 'IgnoreCase')
        }
        [PSCustomObject]@{
            Kind   = 'connection'
            Refuse = $false
            Reason = $null
            # Connection-string password shapes (Password= / Pwd=).
            Regex  = [regex]::new('(?i)(?:Password|Pwd)\s*=\s*([^;"''\s][^;"'']*)')
        }
    )
}

function Merge-MetraAskSecretsKindCounts {
    [CmdletBinding()]
    param(
        [hashtable]$Counts,
        [string]$Kind,
        [int]$Add = 1
    )

    if ([string]::IsNullOrWhiteSpace($Kind) -or $Add -le 0) { return }
    if ($Counts.ContainsKey($Kind)) {
        $Counts[$Kind] = [int]$Counts[$Kind] + $Add
    }
    else {
        $Counts[$Kind] = $Add
    }
}

function Format-MetraAskSecretsNotice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Refuse,
        [string]$Reason,
        [object[]]$Kinds,
        [double]$RedactedCharsRatio
    )

    if ($Refuse) {
        return 'Private-key material was blocked and not sent to the Ask engine. Rephrase without the key block.'
    }

    if (-not $Kinds -or @($Kinds).Count -eq 0) {
        if ($RedactedCharsRatio -gt 0.75) {
            return 'Large amount of sensitive content removed.'
        }
        return $null
    }

    $parts = @(
        $Kinds | ForEach-Object {
            $k = [string](Get-MetraProp -Object $_ -Name 'Kind' -Default '')
            $c = [int](Get-MetraProp -Object $_ -Name 'Count' -Default 0)
            if ($k -and $c -gt 0) { "$k($c)" }
        } | Where-Object { $_ }
    )
    $notice = if ($parts.Count -gt 0) {
        "Secrets scrubbed: $($parts -join ', ')."
    }
    else {
        $null
    }

    if ($RedactedCharsRatio -gt 0.75) {
        if ($notice) {
            return "$notice Large amount of sensitive content removed."
        }
        return 'Large amount of sensitive content removed.'
    }

    return $notice
}

function Invoke-MetraAskSecretsScrubText {
    <#
    .SYNOPSIS
        Scrub high-signal secrets from a string. Same function for prompts and engine responses.
    .DESCRIPTION
        Replaces matches with [REDACTED:<kind>]. PEM / private-key blocks set Refuse + Reason
        and still return scrubbed text (never the raw match). Never logs raw matched substrings.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    $original = if ($null -eq $Text) { '' } else { [string]$Text }
    $originalLen = $original.Length
    $work = $original
    $counts = @{}
    $refuse = $false
    $reason = $null
    $redactedChars = 0

    foreach ($pat in @(Get-MetraAskSecretsPatternSet)) {
        $matches = $pat.Regex.Matches($work)
        if ($matches.Count -eq 0) { continue }

        $placeholder = "[REDACTED:$($pat.Kind)]"
        # Replace from the end so offsets stay valid.
        for ($i = $matches.Count - 1; $i -ge 0; $i--) {
            $m = $matches[$i]
            $redactedChars += $m.Length
            $work = $work.Remove($m.Index, $m.Length).Insert($m.Index, $placeholder)
        }
        Merge-MetraAskSecretsKindCounts -Counts $counts -Kind $pat.Kind -Add $matches.Count

        if ($pat.Refuse) {
            $refuse = $true
            if (-not $reason) { $reason = [string]$pat.Reason }
        }
    }

    $kinds = @(
        $counts.Keys | Sort-Object | ForEach-Object {
            [PSCustomObject]@{ Kind = [string]$_; Count = [int]$counts[$_] }
        }
    )

    $ratio = if ($originalLen -le 0) { 0.0 } else {
        [Math]::Min(1.0, [double]$redactedChars / [double]$originalLen)
    }

    $matched = $kinds.Count -gt 0
    $notice = Format-MetraAskSecretsNotice -Refuse $refuse -Reason $reason -Kinds $kinds -RedactedCharsRatio $ratio

    return [PSCustomObject]@{
        Text               = $work
        Matched            = [bool]$matched
        Refuse             = [bool]$refuse
        Reason             = $reason
        Kinds              = @($kinds)
        RedactedCharsRatio = [double]$ratio
        Notice             = $notice
    }
}

function Invoke-MetraAskSecretsScrubObject {
    <#
    .SYNOPSIS
        Recursively scrub every string member of hashtables, PSCustomObjects, and arrays.
    .OUTPUTS
        PSCustomObject with Value (scrubbed clone), Matched, Refuse, Reason, Kinds, Notice, RedactedCharsRatio.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    $state = @{
        Counts   = @{}
        Refuse   = $false
        Reason   = $null
        MaxRatio = 0.0
        Matched  = $false
    }

    $value = Invoke-MetraAskSecretsScrubObjectWalk -Node $InputObject -State $state

    $kinds = @(
        $state.Counts.Keys | Sort-Object | ForEach-Object {
            [PSCustomObject]@{ Kind = [string]$_; Count = [int]$state.Counts[$_] }
        }
    )

    $combinedNotice = Format-MetraAskSecretsNotice `
        -Refuse ([bool]$state.Refuse) `
        -Reason ([string]$state.Reason) `
        -Kinds $kinds `
        -RedactedCharsRatio ([double]$state.MaxRatio)

    return [PSCustomObject]@{
        Value              = $value
        Matched            = [bool]$state.Matched
        Refuse             = [bool]$state.Refuse
        Reason             = $(if ($state.Reason) { [string]$state.Reason } else { $null })
        Kinds              = @($kinds)
        RedactedCharsRatio = [double]$state.MaxRatio
        Notice             = $combinedNotice
    }
}

function Invoke-MetraAskSecretsAbsorbTextResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)]$Result
    )

    if ($Result.Matched) { $State.Matched = $true }
    if ($Result.Refuse) {
        $State.Refuse = $true
        if (-not $State.Reason) { $State.Reason = [string]$Result.Reason }
    }
    if ($null -ne $Result.RedactedCharsRatio -and [double]$Result.RedactedCharsRatio -gt [double]$State.MaxRatio) {
        $State.MaxRatio = [double]$Result.RedactedCharsRatio
    }
    foreach ($row in @($Result.Kinds)) {
        $k = [string](Get-MetraProp -Object $row -Name 'Kind' -Default '')
        $c = [int](Get-MetraProp -Object $row -Name 'Count' -Default 0)
        if ($k -and $c -gt 0) {
            Merge-MetraAskSecretsKindCounts -Counts $State.Counts -Kind $k -Add $c
        }
    }
}

function Invoke-MetraAskSecretsScrubObjectWalk {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Node,
        [Parameter(Mandatory)][hashtable]$State
    )

    if ($null -eq $Node) { return $null }

    if ($Node -is [string]) {
        $r = Invoke-MetraAskSecretsScrubText -Text $Node
        Invoke-MetraAskSecretsAbsorbTextResult -State $State -Result $r
        return $r.Text
    }

    if ($Node -is [ValueType] -or $Node -is [datetime] -or $Node -is [guid]) {
        return $Node
    }

    if ($Node -is [hashtable] -or $Node -is [System.Collections.IDictionary]) {
        $out = @{}
        foreach ($key in @($Node.Keys)) {
            $child = Invoke-MetraAskSecretsScrubObjectWalk -Node $Node[$key] -State $State
            # List[object] survives single-element hashtable assignment; plain object[] does not.
            $out[$key] = $child
        }
        return $out
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($Node)) {
            [void]$list.Add((Invoke-MetraAskSecretsScrubObjectWalk -Node $item -State $State))
        }
        return $list
    }

    if ($Node -is [PSCustomObject]) {
        $props = [ordered]@{}
        foreach ($p in $Node.PSObject.Properties) {
            $props[$p.Name] = Invoke-MetraAskSecretsScrubObjectWalk -Node $p.Value -State $State
        }
        return [PSCustomObject]$props
    }

    return $Node
}

function Join-MetraAskSecretsNotices {
    <#
    .SYNOPSIS
        Merge distinct operator notices (prompt + response) into one line block.
    #>
    [CmdletBinding()]
    param([string[]]$Notices)

    $uniq = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @($Notices)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $t = $n.Trim()
        if (-not $uniq.Contains($t)) { $uniq.Add($t) }
    }
    if ($uniq.Count -eq 0) { return $null }
    return ($uniq -join ' ')
}

function Add-MetraAskSecretsNoticeToMessage {
    <#
    .SYNOPSIS
        Prepend operator secrets notice to an Ask reply message.
    #>
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Notice
    )

    if ([string]::IsNullOrWhiteSpace($Notice)) { return [string]$Message }
    $body = if ($null -eq $Message) { '' } else { [string]$Message }
    if ([string]::IsNullOrWhiteSpace($body)) { return $Notice.Trim() }
    return "$($Notice.Trim())`n`n$($body.TrimStart())"
}
