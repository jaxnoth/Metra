# Canonical frontmatter parse/mutate for content-bound Yarn desk marks.
# Hash exclusions + mutate must stay aligned with Get-YarnPlanContentForHash.

function Get-YarnPlanWorkflowFrontmatterKeys {
    <#
    .SYNOPSIS
        Frontmatter keys excluded from canonical plan content hash (frozen desk contract).
    #>
    return @(
        'externalReviewed'
        'externalReviewHash'
        'approveForLoom'
        'approveForLoomHash'
        'status'
        'loomHandoffId'
        'loomAcceptedAt'
        'packedAt'
        'packPlanPath'
        'packInputHash'
        'bingReviewed'
        'approvedAt'
        'approvedBy'
        'approvalId'
        'approvalRevision'
    )
}

function Split-YarnPlanDocument {
    <#
    .SYNOPSIS
        Split a plan markdown file into YAML frontmatter + body. Refuse malformed docs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $hadBom = $false
    if ($Text.Length -gt 0 -and [int][char]$Text[0] -eq 0xFEFF) {
        $hadBom = $true
        $Text = $Text.Substring(1)
    }

    if ($Text -notmatch '(?ms)\A---\r?\n(.*?)\r?\n---(\r?\n|$)') {
        throw 'Formal plan missing YAML frontmatter (expected opening --- block).'
    }

    $m = [regex]::Match($Text, '(?ms)\A---\r?\n(.*?)\r?\n---(\r?\n|$)')
    $fmInner = $m.Groups[1].Value
    $after = $Text.Substring($m.Length)
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }

    return [PSCustomObject]@{
        FrontmatterInner = $fmInner
        Body             = $after
        Newline          = $nl
        HadBom           = $hadBom
        FullMatchLength  = $m.Length
    }
}

function Get-YarnPlanFrontmatterMap {
    <#
    .SYNOPSIS
        Parse flat YAML frontmatter key/value pairs. Refuse duplicate keys.
        Nested blocks (todos/patterns lists) are preserved as raw line groups under the parent key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$FrontmatterInner
    )

    $map = [ordered]@{}
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $lines = $FrontmatterInner -split "`r?`n"
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            $i++
            continue
        }
        if ($line -match '^\s') {
            throw ("Malformed YAML frontmatter: unexpected indented line without a parent key: '{0}'" -f $line.Trim())
        }
        if ($line -notmatch '^([A-Za-z0-9_]+)\s*:\s*(.*)$') {
            throw ("Malformed YAML frontmatter line (expected key: value): '{0}'" -f $line)
        }
        $key = $Matches[1]
        $rest = $Matches[2]
        if (-not $seen.Add($key)) {
            throw ("Duplicate frontmatter key refused: '{0}'" -f $key)
        }

        # Collect continued indented lines for list/object values.
        $block = New-Object System.Collections.Generic.List[string]
        [void]$block.Add($line)
        $i++
        while ($i -lt $lines.Count -and ($lines[$i] -match '^\s' -or [string]::IsNullOrWhiteSpace($lines[$i]))) {
            if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
                [void]$block.Add($lines[$i])
            }
            elseif ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^\s') {
                [void]$block.Add($lines[$i])
            }
            $i++
        }

        if ($block.Count -eq 1) {
            $map[$key] = $rest.Trim()
        }
        else {
            # Preserve multi-line value as raw block (including the key line) for round-trip.
            $map[$key] = [PSCustomObject]@{
                __yarnRawBlock = $true
                Lines          = @($block.ToArray())
            }
        }
    }
    return $map
}

function ConvertTo-YarnFrontmatterYamlValue {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) {
        if ($Value) { return 'true' } else { return 'false' }
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) {
        return [string]$Value
    }
    $s = [string]$Value
    if ($s -eq 'true' -or $s -eq 'false' -or $s -eq 'null') { return $s }
    if ($s -match '^-?\d+(\.\d+)?$') { return $s }
    if ($s -match '[:#\[\]{},&*?|!<>=%@`"''\r\n]' -or $s -match '^\s|\s$') {
        $escaped = $s.Replace('\', '\\').Replace('"', '\"')
        return ('"{0}"' -f $escaped)
    }
    return $s
}

function ConvertFrom-YarnFrontmatterScalar {
    param([AllowEmptyString()][string]$Raw)
    if ($null -eq $Raw) { return $null }
    $t = $Raw.Trim()
    if ($t -eq '' -or $t -eq 'null' -or $t -eq '~') { return $null }
    if ($t -eq 'true' -or $t -eq 'yes') { return $true }
    if ($t -eq 'false' -or $t -eq 'no') { return $false }
    if (($t.StartsWith('"') -and $t.EndsWith('"')) -or ($t.StartsWith("'") -and $t.EndsWith("'"))) {
        return $t.Substring(1, $t.Length - 2)
    }
    return $t
}

function Test-YarnFrontmatterRawBlock {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
    try {
        return [bool]($Value.__yarnRawBlock)
    }
    catch {
        return $false
    }
}

function Format-YarnFrontmatterMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Map,
        [string]$Newline = "`n"
    )

    $sb = New-Object System.Text.StringBuilder
    foreach ($key in @($Map.Keys)) {
        $val = $Map[$key]
        if (Test-YarnFrontmatterRawBlock -Value $val) {
            foreach ($line in @($val.Lines)) {
                [void]$sb.Append($line)
                [void]$sb.Append($Newline)
            }
        }
        else {
            [void]$sb.Append($key)
            [void]$sb.Append(': ')
            [void]$sb.Append((ConvertTo-YarnFrontmatterYamlValue -Value $val))
            [void]$sb.Append($Newline)
        }
    }
    return $sb.ToString().TrimEnd("`r", "`n")
}

function Set-YarnPlanFrontmatterFields {
    <#
    .SYNOPSIS
        Atomically set/merge flat frontmatter scalar fields via surgical line edit.
        Preserves untouched keys and list blocks so content hash stays stable for mark writes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Fields,
        [switch]$DryRun,
        [switch]$ResetWorkflowMarksOnBodyEdit
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Plan file not found: $Path"
    }

    $enc = Get-YarnUtf8NoBomEncoding
    $text = [System.IO.File]::ReadAllText($Path, $enc)
    $split = Split-YarnPlanDocument -Text $text

    # Validate parse (duplicate keys / malformed) before mutating.
    $map = Get-YarnPlanFrontmatterMap -FrontmatterInner $split.FrontmatterInner

    if ($ResetWorkflowMarksOnBodyEdit) {
        $Fields = @{
            externalReviewed   = $false
            externalReviewHash = $null
            approveForLoom     = $false
            approveForLoomHash = $null
        }
    }

    $nl = $split.Newline
    $fmLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($split.FrontmatterInner -split "`r?`n")) {
        [void]$fmLines.Add($line)
    }

    foreach ($k in @($Fields.Keys)) {
        $val = ConvertTo-YarnFrontmatterYamlValue -Value $Fields[$k]
        $replacement = "${k}: ${val}"
        $found = $false
        for ($i = 0; $i -lt $fmLines.Count; $i++) {
            if ($fmLines[$i] -match ("^\s*{0}\s*:" -f [regex]::Escape($k))) {
                # Only replace scalar key lines (not nested under a list - those are indented).
                if ($fmLines[$i] -notmatch '^\s') {
                    $fmLines[$i] = $replacement
                    $found = $true
                    break
                }
            }
        }
        if (-not $found) {
            # Insert before closing of FM (end of list).
            [void]$fmLines.Add($replacement)
            $map[$k] = $Fields[$k]
        }
        else {
            $map[$k] = $Fields[$k]
        }
    }

    $fmOut = ($fmLines -join $nl).TrimEnd("`r", "`n")
    # Preserve body bytes exactly as split (do not strip leading blank lines).
    $updated = '---' + $nl + $fmOut + $nl + '---' + $nl + $split.Body

    $compareOld = if ($split.HadBom) { $text.TrimStart([char]0xFEFF) } else { $text }
    $changed = ($updated -ne $compareOld)

    if ($DryRun) {
        return [PSCustomObject]@{
            changed = $changed
            text    = $updated
            path    = $Path
            map     = $map
        }
    }

    if ($changed) {
        Write-YarnAtomicUtf8Text -Path $Path -Text $updated
    }
    return [PSCustomObject]@{
        changed = $changed
        path    = $Path
        map     = $map
    }
}

function Get-YarnPlanFrontmatterScalars {
    <#
    .SYNOPSIS
        Read common desk scalar fields from plan text (or path).
    #>
    [CmdletBinding()]
    param(
        [string]$PlanText,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($PlanText)) {
        if ([string]::IsNullOrWhiteSpace($Path)) { throw 'PlanText or Path required.' }
        $PlanText = [System.IO.File]::ReadAllText($Path, (Get-YarnUtf8NoBomEncoding))
    }

    $split = Split-YarnPlanDocument -Text $PlanText
    $map = Get-YarnPlanFrontmatterMap -FrontmatterInner $split.FrontmatterInner

    $readScalar = {
        param([string]$Key)
        if (-not $map.Contains($Key)) { return $null }
        $v = $map[$Key]
        if (Test-YarnFrontmatterRawBlock -Value $v) {
            return $null
        }
        return (ConvertFrom-YarnFrontmatterScalar -Raw ([string]$v))
    }

    return [PSCustomObject]@{
        externalReviewed   = [bool](& $readScalar 'externalReviewed')
        externalReviewHash = [string](& $readScalar 'externalReviewHash')
        approveForLoom     = [bool](& $readScalar 'approveForLoom')
        approveForLoomHash = [string](& $readScalar 'approveForLoomHash')
        status             = [string](& $readScalar 'status')
        loomHandoffId      = [string](& $readScalar 'loomHandoffId')
        loomAcceptedAt     = [string](& $readScalar 'loomAcceptedAt')
        bingReviewed       = [bool](& $readScalar 'bingReviewed')
        map                = $map
        planText           = $PlanText
    }
}

function Test-YarnContentBoundLoomEligibility {
    <#
    .SYNOPSIS
        Both content-bound mark/hash pairs must match current canonical plan hash.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PlanText
    )

    $currentHash = Get-YarnPlanContentHash -PlanText $PlanText
    try {
        $fm = Get-YarnPlanFrontmatterScalars -PlanText $PlanText
    }
    catch {
        return [PSCustomObject]@{
            eligible           = $false
            reason             = ('frontmatter-parse:' + [string]$_.Exception.Message)
            currentContentHash = $currentHash
        }
    }

    if (-not $fm.externalReviewed) {
        return [PSCustomObject]@{
            eligible           = $false
            reason             = 'external-review-missing'
            currentContentHash = $currentHash
            frontmatter        = $fm
        }
    }
    if ([string]::IsNullOrWhiteSpace($fm.externalReviewHash) -or $fm.externalReviewHash -ne $currentHash) {
        return [PSCustomObject]@{
            eligible           = $false
            reason             = 'external-review-hash-stale'
            currentContentHash = $currentHash
            frontmatter        = $fm
        }
    }
    if (-not $fm.approveForLoom) {
        return [PSCustomObject]@{
            eligible           = $false
            reason             = 'approve-for-loom-missing'
            currentContentHash = $currentHash
            frontmatter        = $fm
        }
    }
    if ([string]::IsNullOrWhiteSpace($fm.approveForLoomHash) -or $fm.approveForLoomHash -ne $currentHash) {
        return [PSCustomObject]@{
            eligible           = $false
            reason             = 'approve-for-loom-hash-stale'
            currentContentHash = $currentHash
            frontmatter        = $fm
        }
    }

    return [PSCustomObject]@{
        eligible           = $true
        reason             = 'ok'
        currentContentHash = $currentHash
        frontmatter        = $fm
    }
}

function Get-YarnDeterministicLoomHandoffId {
    <#
    .SYNOPSIS
        Stable handoff id from plan identity + approved content hash (idempotent retries).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlanIdentity,
        [Parameter(Mandatory)][string]$ContentHash
    )
    $material = ('{0}|{1}' -f $PlanIdentity.Trim().ToLowerInvariant(), $ContentHash.Trim().ToLowerInvariant())
    $hex = Get-YarnSha256Hex -Text $material
    return ('yh-' + $hex.Substring(0, 32))
}

function Set-YarnPlanContentBoundMarks {
    <#
    .SYNOPSIS
        Set review and/or approve marks with hashes bound to current content.
        Surgical frontmatter edit keeps canonical hash stable across the write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$ExternalReviewed,
        [switch]$ApproveForLoom,
        [switch]$DryRun
    )

    if (-not $ExternalReviewed -and -not $ApproveForLoom) {
        throw 'Set-YarnPlanContentBoundMarks requires -ExternalReviewed and/or -ApproveForLoom'
    }

    $text = [System.IO.File]::ReadAllText($Path, (Get-YarnUtf8NoBomEncoding))
    $hash = Get-YarnPlanContentHash -PlanText $text
    $fields = @{}
    if ($ExternalReviewed) {
        $fields['externalReviewed'] = $true
        $fields['externalReviewHash'] = $hash
    }
    if ($ApproveForLoom) {
        $fields['approveForLoom'] = $true
        $fields['approveForLoomHash'] = $hash
    }

    $write = Set-YarnPlanFrontmatterFields -Path $Path -Fields $fields -DryRun:$DryRun
    $afterText = if ($DryRun) { [string]$write.text } else {
        [System.IO.File]::ReadAllText($Path, (Get-YarnUtf8NoBomEncoding))
    }
    $afterHash = Get-YarnPlanContentHash -PlanText $afterText
    if ($afterHash -ne $hash) {
        throw ("Content hash changed during mark write (before=$hash after=$afterHash). Refusing unstable frontmatter mutate.")
    }

    return [PSCustomObject]@{
        changed     = [bool]$write.changed
        contentHash = $hash
        text        = $(if ($DryRun) { $write.text } else { $null })
        path        = $Path
    }
}
