# Operator working-notes ledger (Stated / Observed / Moments).
# Machine-local under Get-MetraMachineDataRoot; packageable via profile machine-data/ map.
# Notes may tune pace, depth, verdict format, and callbacks - never lower Honesty / Conviction.

Set-StrictMode -Version Latest

$script:MetraWorkingNotesRelativePath = 'operator-working-notes.local.json'
$script:MetraWorkingNotesPackRelativePath = 'machine-data/operator-working-notes.local.json'
$script:MetraWorkingNotesObservedDecayDays = 30
$script:MetraWorkingNotesContextCapBytes = 2048
$script:MetraWorkingNotesSchemaVersion = 1
# Per-list row cap (prompt is still byte-capped separately). Stated/Observed refuse past cap; Moments drop oldest.
$script:MetraWorkingNotesMaxRowsPerList = 50

function Get-MetraOperatorWorkingNotesPath {
    <#
    .SYNOPSIS
        Absolute path to the operator working-notes ledger under machine data.
    .NOTES
        Migrates a legacy docs\ copy into machine data when present. Prefer
        Resolve-MetraOperatorWorkingNotesExistingPath for read-only probes.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    return Resolve-MetraMachineLedgerPath -MetraRoot $MetraRoot `
        -RelativeUnderMachineData $script:MetraWorkingNotesRelativePath `
        -LegacyRelativeUnderDocs $script:MetraWorkingNotesRelativePath
}

function Resolve-MetraOperatorWorkingNotesExistingPath {
    <#
    .SYNOPSIS
        Read-only probe for a live working-notes ledger (machine-data preferred, else docs legacy).
    .NOTES
        No docs→machine migrate and no notes-file / notes-parent CreateDirectory.
        Get-MetraMachineDataRoot (via the machine-path resolve) may still ensure the
        machine/sandbox root exists. Returns $null when neither notes path exists.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $machine = Resolve-MetraProfileMappedLivePath `
        -RelativePath $script:MetraWorkingNotesPackRelativePath `
        -MetraRoot $MetraRoot
    if (Test-Path -LiteralPath $machine) {
        return $machine
    }
    $legacy = Join-Path $MetraRoot (Join-Path 'docs' $script:MetraWorkingNotesRelativePath)
    if (Test-Path -LiteralPath $legacy) {
        return $legacy
    }
    return $null
}

function Get-MetraOperatorWorkingNotesPackRelativePath {
    [CmdletBinding()]
    param()
    return $script:MetraWorkingNotesPackRelativePath
}

function Get-MetraOperatorWorkingNotesDecayDays {
    [CmdletBinding()]
    param()
    return [int]$script:MetraWorkingNotesObservedDecayDays
}

function Get-MetraOperatorWorkingNotesContextCapBytes {
    [CmdletBinding()]
    param()
    return [int]$script:MetraWorkingNotesContextCapBytes
}

function Get-MetraOperatorWorkingNotesMaxRowsPerList {
    [CmdletBinding()]
    param()
    return [int]$script:MetraWorkingNotesMaxRowsPerList
}

function Test-MetraOperatorWorkingNotesIdFormat {
    <#
    .SYNOPSIS
        True when Id is a 32-hex GUID (N format) or a dashed GUID string.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    $s = $Id.Trim()
    if ($s -match '^[0-9a-fA-F]{32}$') { return $true }
    $g = [guid]::Empty
    return [guid]::TryParse($s, [ref]$g)
}

function Test-MetraOperatorWorkingNotesUtcStampFormat {
    <#
    .SYNOPSIS
        True when Stamp is empty (if AllowEmpty) or parses as a round-trip / ISO DateTime.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Stamp,
        [switch]$AllowEmpty
    )

    if ([string]::IsNullOrWhiteSpace($Stamp)) { return [bool]$AllowEmpty }
    try {
        $null = [DateTime]::Parse(
            $Stamp.Trim(),
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        )
        return $true
    }
    catch {
        return $false
    }
}

function Assert-MetraOperatorWorkingNotesIdAndUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [AllowEmptyString()][string]$Stamp,
        [Parameter(Mandatory)][string]$Field,
        [switch]$RequireStamp
    )

    if (-not (Test-MetraOperatorWorkingNotesIdFormat -Id $Id)) {
        throw ("Working-notes {0} id rejected (expected 32-hex or dashed GUID): '{1}'" -f $Field, $Id)
    }
    $allowEmpty = -not $RequireStamp
    if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $Stamp -AllowEmpty:$allowEmpty)) {
        throw ("Working-notes {0} timestamp rejected (expected ISO/round-trip UTC): '{1}'" -f $Field, $Stamp)
    }
}

function New-MetraOperatorWorkingNotesDefault {
    [CmdletBinding()]
    param()
    return [ordered]@{
        version    = [int]$script:MetraWorkingNotesSchemaVersion
        updatedUtc = [DateTime]::UtcNow.ToString('o')
        stated     = @()
        observed   = @()
        moments    = @()
    }
}

function ConvertTo-MetraOperatorWorkingNotesObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Raw
    )

    $dropped = 0
    $stated = @()
    foreach ($row in @((Get-MetraProp -Object $Raw -Name 'stated' -Default @()))) {
        if ($null -eq $row) { $dropped++; continue }
        $text = [string](Get-MetraProp -Object $row -Name 'text' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) { $dropped++; continue }
        $rawId = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
        # Blank/missing ids are dropped (not minted) so pack/status hashes stay stable.
        if (-not (Test-MetraOperatorWorkingNotesIdFormat -Id $rawId)) {
            $dropped++; continue
        }
        $notedUtc = [string](Get-MetraProp -Object $row -Name 'notedUtc' -Default '')
        if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $notedUtc -AllowEmpty:$false)) {
            $dropped++; continue
        }
        $stated += [pscustomobject]@{
            id       = $rawId.Trim()
            text     = $text.Trim()
            source   = [string](Get-MetraProp -Object $row -Name 'source' -Default 'operator')
            notedUtc = $notedUtc.Trim()
        }
    }

    $observed = @()
    foreach ($row in @((Get-MetraProp -Object $Raw -Name 'observed' -Default @()))) {
        if ($null -eq $row) { $dropped++; continue }
        $pattern = [string](Get-MetraProp -Object $row -Name 'pattern' -Default '')
        if ([string]::IsNullOrWhiteSpace($pattern)) { $dropped++; continue }
        $count = 0
        try { $count = [int](Get-MetraProp -Object $row -Name 'instanceCount' -Default 1) } catch { $count = 1 }
        if ($count -lt 1) { $count = 1 }
        $rawId = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
        if (-not (Test-MetraOperatorWorkingNotesIdFormat -Id $rawId)) {
            $dropped++; continue
        }
        $lastUtc = [string](Get-MetraProp -Object $row -Name 'lastObservedUtc' -Default '')
        $firstUtc = [string](Get-MetraProp -Object $row -Name 'firstObservedUtc' -Default '')
        if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $lastUtc -AllowEmpty:$false)) {
            $dropped++; continue
        }
        if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $firstUtc -AllowEmpty:$false)) {
            $dropped++; continue
        }
        $observed += [pscustomobject]@{
            id               = $rawId.Trim()
            pattern          = $pattern.Trim()
            evidence         = [string](Get-MetraProp -Object $row -Name 'evidence' -Default '')
            instanceCount    = $count
            lastObservedUtc  = $lastUtc.Trim()
            firstObservedUtc = $firstUtc.Trim()
        }
    }

    $moments = @()
    foreach ($row in @((Get-MetraProp -Object $Raw -Name 'moments' -Default @()))) {
        if ($null -eq $row) { $dropped++; continue }
        $text = [string](Get-MetraProp -Object $row -Name 'text' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) { $dropped++; continue }
        $rawId = [string](Get-MetraProp -Object $row -Name 'id' -Default '')
        if (-not (Test-MetraOperatorWorkingNotesIdFormat -Id $rawId)) {
            $dropped++; continue
        }
        $notedUtc = [string](Get-MetraProp -Object $row -Name 'notedUtc' -Default '')
        if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $notedUtc -AllowEmpty:$false)) {
            $dropped++; continue
        }
        $moments += [pscustomobject]@{
            id       = $rawId.Trim()
            text     = $text.Trim()
            notedUtc = $notedUtc.Trim()
        }
    }

    $versionRaw = Get-MetraProp -Object $Raw -Name 'version' -Default $null
    $version = -1
    $versionOk = $false
    if ($null -ne $versionRaw -and -not [string]::IsNullOrWhiteSpace([string]$versionRaw)) {
        try {
            $version = [int]$versionRaw
            $versionOk = ($version -eq $script:MetraWorkingNotesSchemaVersion)
        }
        catch {
            $versionOk = $false
            $version = -1
        }
    }
    $updatedUtc = [string](Get-MetraProp -Object $Raw -Name 'updatedUtc' -Default '')
    $updatedOk = Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $updatedUtc -AllowEmpty:$false

    return [pscustomobject]@{
        version           = [int]$version
        updatedUtc        = $updatedUtc.Trim()
        stated            = $stated
        observed          = $observed
        moments           = $moments
        DroppedRowCount   = [int]$dropped
        SchemaVersionOk   = [bool]$versionOk
        UpdatedUtcOk      = [bool]$updatedOk
    }
}

function Read-MetraOperatorWorkingNotes {
    <#
    .SYNOPSIS
        Read working-notes JSON from disk (or empty default). Does not filter decay.
    .OUTPUTS
        Object with stated/observed/moments plus LedgerPath / LedgerExists / LedgerCorrupt.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $path)) {
        $empty = [pscustomobject](New-MetraOperatorWorkingNotesDefault)
        $empty | Add-Member -NotePropertyName LedgerPath -NotePropertyValue $path -Force
        $empty | Add-Member -NotePropertyName LedgerExists -NotePropertyValue $false -Force
        $empty | Add-Member -NotePropertyName LedgerCorrupt -NotePropertyValue $false -Force
        $empty | Add-Member -NotePropertyName DroppedRowCount -NotePropertyValue 0 -Force
        return $empty
    }
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $notes = ConvertTo-MetraOperatorWorkingNotesObject -Raw $raw
        $dropped = 0
        try { $dropped = [int]$notes.DroppedRowCount } catch { $dropped = 0 }
        $schemaOk = $false
        $updatedOk = $false
        try { $schemaOk = [bool]$notes.SchemaVersionOk } catch { $schemaOk = $false }
        try { $updatedOk = [bool]$notes.UpdatedUtcOk } catch { $updatedOk = $false }
        $corrupt = ($dropped -gt 0) -or (-not $schemaOk) -or (-not $updatedOk)
        $notes | Add-Member -NotePropertyName LedgerPath -NotePropertyValue $path -Force
        $notes | Add-Member -NotePropertyName LedgerExists -NotePropertyValue $true -Force
        # Blank/null rows, bad schema version, or bad root updatedUtc must not pass as healthy.
        $notes | Add-Member -NotePropertyName LedgerCorrupt -NotePropertyValue $corrupt -Force
        $notes | Add-Member -NotePropertyName DroppedRowCount -NotePropertyValue $dropped -Force
        if ($dropped -gt 0) {
            Write-Warning ("Read-MetraOperatorWorkingNotes: {0} blank/unusable row(s) in '{1}' - ledger flagged corrupt; fix or reset -Force before writes." -f $dropped, $path)
        }
        if (-not $schemaOk) {
            Write-Warning ("Read-MetraOperatorWorkingNotes: unsupported schema version in '{0}' (expected {1})." -f $path, $script:MetraWorkingNotesSchemaVersion)
        }
        if (-not $updatedOk) {
            Write-Warning ("Read-MetraOperatorWorkingNotes: blank/invalid updatedUtc in '{0}' - ledger flagged corrupt." -f $path)
        }
        return $notes
    }
    catch {
        Write-Warning ("Read-MetraOperatorWorkingNotes: corrupt ledger at '{0}': {1}" -f $path, $_.Exception.Message)
        $empty = [pscustomobject](New-MetraOperatorWorkingNotesDefault)
        $empty | Add-Member -NotePropertyName LedgerPath -NotePropertyValue $path -Force
        $empty | Add-Member -NotePropertyName LedgerExists -NotePropertyValue $true -Force
        $empty | Add-Member -NotePropertyName LedgerCorrupt -NotePropertyValue $true -Force
        $empty | Add-Member -NotePropertyName DroppedRowCount -NotePropertyValue 0 -Force
        return $empty
    }
}

function Test-MetraOperatorWorkingNotesObservedActive {
    <#
    .SYNOPSIS
        True when an Observed row is still within the decay window (or has no usable timestamp).
    .NOTES
        Missing/invalid lastObservedUtc is treated as expired (fail closed - do not keep forever).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Entry,
        [DateTime]$AsOfUtc = [DateTime]::UtcNow,
        [int]$DecayDays = 0
    )

    if ($DecayDays -le 0) { $DecayDays = [int]$script:MetraWorkingNotesObservedDecayDays }
    $stamp = [string](Get-MetraProp -Object $Entry -Name 'lastObservedUtc' -Default '')
    if ([string]::IsNullOrWhiteSpace($stamp)) { return $false }
    $parsed = [DateTime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [DateTime]::TryParse(
            $stamp,
            [System.Globalization.CultureInfo]::InvariantCulture,
            $styles,
            [ref]$parsed
        )) {
        return $false
    }
    if ($parsed.Kind -eq [DateTimeKind]::Unspecified) {
        $parsed = [DateTime]::SpecifyKind($parsed, [DateTimeKind]::Utc)
    }
    else {
        $parsed = $parsed.ToUniversalTime()
    }
    $age = $AsOfUtc.ToUniversalTime() - $parsed
    return ($age.TotalDays -le [double]$DecayDays)
}

function Select-MetraOperatorWorkingNotesActiveObserved {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Notes,
        [DateTime]$AsOfUtc = [DateTime]::UtcNow,
        [int]$DecayDays = 0
    )

    $out = @()
    foreach ($row in @($Notes.observed)) {
        if (Test-MetraOperatorWorkingNotesObservedActive -Entry $row -AsOfUtc $AsOfUtc -DecayDays $DecayDays) {
            $out += $row
        }
    }
    return @($out)
}

function Update-MetraOperatorWorkingNotesObservation {
    <#
    .SYNOPSIS
        Reset decay clock and increment instance count for a matching Observed pattern (or add one).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Notes,
        [Parameter(Mandatory)][string]$Pattern,
        [string]$Evidence = '',
        [DateTime]$AsOfUtc = [DateTime]::UtcNow
    )

    $needle = $Pattern.Trim()
    if ([string]::IsNullOrWhiteSpace($needle)) {
        throw 'Pattern is required.'
    }
    $stamp = $AsOfUtc.ToUniversalTime().ToString('o')
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($Notes.observed)) { $list.Add($row) | Out-Null }

    $hit = $null
    foreach ($row in $list) {
        if ([string]::Equals([string]$row.pattern, $needle, [StringComparison]::OrdinalIgnoreCase)) {
            $hit = $row
            break
        }
    }

    if ($null -eq $hit) {
        $list.Add([pscustomobject]@{
                id               = [guid]::NewGuid().ToString('N')
                pattern          = $needle
                evidence         = $Evidence
                instanceCount    = 1
                lastObservedUtc  = $stamp
                firstObservedUtc = $stamp
            }) | Out-Null
    }
    else {
        $hit.instanceCount = [int]$hit.instanceCount + 1
        $hit.lastObservedUtc = $stamp
        if (-not [string]::IsNullOrWhiteSpace($Evidence)) {
            $hit.evidence = $Evidence
        }
    }

    return [pscustomobject]@{
        version    = [int]$Notes.version
        updatedUtc = $stamp
        stated     = @($Notes.stated)
        observed   = @($list)
        moments    = @($Notes.moments)
    }
}

function Test-MetraOperatorWorkingNotesLedgerWritable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Notes)

    if (-not [bool]$Notes.LedgerCorrupt) { return }
    $dropped = 0
    try { $dropped = [int]$Notes.DroppedRowCount } catch { $dropped = 0 }
    if ($dropped -gt 0) {
        throw ("Working-notes ledger has {0} blank/unusable row(s); fix the JSON or run: .\metra.ps1 profile notes reset -Force  (ledger: {1})" -f $dropped, $Notes.LedgerPath)
    }
    throw ("Working-notes ledger is corrupt; run: .\metra.ps1 profile notes reset -Force  (ledger: {0})" -f $Notes.LedgerPath)
}

function Add-MetraOperatorWorkingNoteStated {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Source = 'operator',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $notes = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
    Test-MetraOperatorWorkingNotesLedgerWritable -Notes $notes
    $scrub = Invoke-MetraAskSecretsScrubText -Text $Text.Trim()
    if ([bool]$scrub.Refuse) {
        throw ("Stated note refused by secrets scrub: {0}" -f $scrub.Reason)
    }
    if ([string]::IsNullOrWhiteSpace([string]$scrub.Text)) {
        throw 'Stated note text is required (blank/whitespace refused).'
    }
    $max = Get-MetraOperatorWorkingNotesMaxRowsPerList
    $existing = @($notes.stated)
    if ($existing.Count -ge $max) {
        throw ("Stated notes at cap ({0}); remove rows or run profile notes reset -Force before adding." -f $max)
    }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $existing) { $list.Add($row) | Out-Null }
    $list.Add([pscustomobject]@{
            id       = [guid]::NewGuid().ToString('N')
            text     = [string]$scrub.Text
            source   = $Source
            notedUtc = [DateTime]::UtcNow.ToString('o')
        }) | Out-Null
    $updated = [pscustomobject]@{
        version    = [int]$notes.version
        updatedUtc = [DateTime]::UtcNow.ToString('o')
        stated     = @($list)
        observed   = @($notes.observed)
        moments    = @($notes.moments)
    }
    $whatIfBound = [bool]$WhatIfPreference
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $whatIfBound = [bool]$PSBoundParameters['WhatIf']
    }
    if ($whatIfBound) {
        return [pscustomobject]@{
            Path     = $notes.LedgerPath
            Kind     = 'stated'
            Text     = [string]$scrub.Text
            WhatIf   = $true
            Declined = $false
            Wrote    = $false
        }
    }
    if (-not $PSCmdlet.ShouldProcess($notes.LedgerPath, 'Add stated working note')) {
        return [pscustomobject]@{
            Path     = $notes.LedgerPath
            Kind     = 'stated'
            Text     = [string]$scrub.Text
            WhatIf   = $false
            Declined = $true
            Wrote    = $false
        }
    }
    $path = Save-MetraOperatorWorkingNotes -Notes $updated -MetraRoot $MetraRoot
    return [pscustomobject]@{ Path = $path; Kind = 'stated'; Text = [string]$scrub.Text; WhatIf = $false; Declined = $false; Wrote = $true }
}

function Add-MetraOperatorWorkingNoteMoment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $notes = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
    Test-MetraOperatorWorkingNotesLedgerWritable -Notes $notes
    $scrub = Invoke-MetraAskSecretsScrubText -Text $Text.Trim()
    if ([bool]$scrub.Refuse) {
        throw ("Moment note refused by secrets scrub: {0}" -f $scrub.Reason)
    }
    if ([string]::IsNullOrWhiteSpace([string]$scrub.Text)) {
        throw 'Moment note text is required (blank/whitespace refused).'
    }
    $max = Get-MetraOperatorWorkingNotesMaxRowsPerList
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($notes.moments)) { $list.Add($row) | Out-Null }
    $list.Add([pscustomobject]@{
            id       = [guid]::NewGuid().ToString('N')
            text     = [string]$scrub.Text
            notedUtc = [DateTime]::UtcNow.ToString('o')
        }) | Out-Null
    # Moments: drop oldest (by notedUtc) when over cap.
    while ($list.Count -gt $max) {
        $oldestIdx = 0
        $oldestStamp = [string]$list[0].notedUtc
        for ($i = 1; $i -lt $list.Count; $i++) {
            $stamp = [string]$list[$i].notedUtc
            if ([string]::IsNullOrWhiteSpace($oldestStamp) -or (
                    -not [string]::IsNullOrWhiteSpace($stamp) -and
                    [string]::CompareOrdinal($stamp, $oldestStamp) -lt 0
                )) {
                $oldestIdx = $i
                $oldestStamp = $stamp
            }
        }
        $list.RemoveAt($oldestIdx) | Out-Null
    }
    $updated = [pscustomobject]@{
        version    = [int]$notes.version
        updatedUtc = [DateTime]::UtcNow.ToString('o')
        stated     = @($notes.stated)
        observed   = @($notes.observed)
        moments    = @($list)
    }
    $whatIfBound = [bool]$WhatIfPreference
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $whatIfBound = [bool]$PSBoundParameters['WhatIf']
    }
    if ($whatIfBound) {
        return [pscustomobject]@{
            Path     = $notes.LedgerPath
            Kind     = 'moment'
            Text     = [string]$scrub.Text
            WhatIf   = $true
            Declined = $false
            Wrote    = $false
        }
    }
    if (-not $PSCmdlet.ShouldProcess($notes.LedgerPath, 'Add moment working note')) {
        return [pscustomobject]@{
            Path     = $notes.LedgerPath
            Kind     = 'moment'
            Text     = [string]$scrub.Text
            WhatIf   = $false
            Declined = $true
            Wrote    = $false
        }
    }
    $path = Save-MetraOperatorWorkingNotes -Notes $updated -MetraRoot $MetraRoot
    return [pscustomobject]@{ Path = $path; Kind = 'moment'; Text = [string]$scrub.Text; WhatIf = $false; Declined = $false; Wrote = $true }
}

function Add-MetraOperatorWorkingNoteObservation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [string]$Evidence = '',
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $notes = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
    Test-MetraOperatorWorkingNotesLedgerWritable -Notes $notes
    $scrubPattern = Invoke-MetraAskSecretsScrubText -Text $Pattern.Trim()
    if ([bool]$scrubPattern.Refuse) {
        throw ("Observed pattern refused by secrets scrub: {0}" -f $scrubPattern.Reason)
    }
    if ([string]::IsNullOrWhiteSpace([string]$scrubPattern.Text)) {
        throw 'Observed pattern is required (blank/whitespace refused).'
    }
    $scrubEvidence = Invoke-MetraAskSecretsScrubText -Text $Evidence
    if ([bool]$scrubEvidence.Refuse) {
        throw ("Observed evidence refused by secrets scrub: {0}" -f $scrubEvidence.Reason)
    }
    $max = Get-MetraOperatorWorkingNotesMaxRowsPerList
    $needle = [string]$scrubPattern.Text
    $existingHit = $false
    foreach ($row in @($notes.observed)) {
        if ([string]::Equals([string]$row.pattern, $needle, [StringComparison]::OrdinalIgnoreCase)) {
            $existingHit = $true
            break
        }
    }
    if (-not $existingHit -and @($notes.observed).Count -ge $max) {
        throw ("Observed notes at cap ({0}); remove rows or run profile notes reset -Force before adding a new pattern." -f $max)
    }
    $updated = Update-MetraOperatorWorkingNotesObservation `
        -Notes $notes `
        -Pattern $needle `
        -Evidence ([string]$scrubEvidence.Text)
    $hit = @($updated.observed) | Where-Object {
        [string]::Equals([string]$_.pattern, $needle, [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    $instanceCount = if ($hit) { [int]$hit.instanceCount } else { 1 }
    $whatIfBound = [bool]$WhatIfPreference
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $whatIfBound = [bool]$PSBoundParameters['WhatIf']
    }
    if ($whatIfBound) {
        return [pscustomobject]@{
            Path          = $notes.LedgerPath
            Kind          = 'observed'
            Pattern       = $needle
            InstanceCount = $instanceCount
            WhatIf        = $true
            Declined      = $false
            Wrote         = $false
        }
    }
    if (-not $PSCmdlet.ShouldProcess($notes.LedgerPath, 'Add/update observed working note')) {
        return [pscustomobject]@{
            Path          = $notes.LedgerPath
            Kind          = 'observed'
            Pattern       = $needle
            InstanceCount = $instanceCount
            WhatIf        = $false
            Declined      = $true
            Wrote         = $false
        }
    }
    $path = Save-MetraOperatorWorkingNotes -Notes $updated -MetraRoot $MetraRoot
    return [pscustomobject]@{
        Path          = $path
        Kind          = 'observed'
        Pattern       = $needle
        InstanceCount = $instanceCount
        WhatIf        = $false
        Declined      = $false
        Wrote         = $true
    }
}

function Invoke-MetraOperatorWorkingNotesCommand {
    <#
    .SYNOPSIS
        Dispatches metra.ps1 profile notes show|add|observe|moment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string[]]$ArgsRest = @(),
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $sub = $Subcommand.ToLowerInvariant()
    switch ($sub) {
        'show' {
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
            $active = @(Select-MetraOperatorWorkingNotesActiveObserved -Notes $notes)
            $dropped = 0
            try { $dropped = [int]$notes.DroppedRowCount } catch { $dropped = 0 }
            return [pscustomobject]@{
                LedgerPath         = $notes.LedgerPath
                LedgerExists       = [bool]$notes.LedgerExists
                LedgerCorrupt      = [bool]$notes.LedgerCorrupt
                DroppedRowCount    = $dropped
                StatedCount        = @($notes.stated).Count
                ObservedActive     = $active.Count
                ObservedTotal      = @($notes.observed).Count
                MomentsCount       = @($notes.moments).Count
                DecayDays          = Get-MetraOperatorWorkingNotesDecayDays
                ContextCapBytes    = Get-MetraOperatorWorkingNotesContextCapBytes
                MaxRowsPerList     = Get-MetraOperatorWorkingNotesMaxRowsPerList
                Stated             = @($notes.stated)
                ObservedActiveRows = $active
                Moments            = @($notes.moments)
            }
        }
        'add' {
            # profile notes add stated|moment <text...> [-WhatIf] [-Confirm]
            $whatIf = $false
            $confirm = $false
            $tokens = [System.Collections.Generic.List[string]]::new()
            foreach ($a in @($ArgsRest)) {
                if ($a -ieq '-WhatIf') { $whatIf = $true; continue }
                if ($a -ieq '-Confirm') { $confirm = $true; continue }
                if ($a -like '-*') {
                    throw "Unknown add argument '$a'. Use -WhatIf and/or -Confirm only."
                }
                [void]$tokens.Add([string]$a)
            }
            if ($tokens.Count -lt 2) {
                throw "profile notes add requires stated|moment and text. Example: .\metra.ps1 profile notes add stated 'Prefer terse verdicts'"
            }
            $kind = [string]$tokens[0]
            $text = ($tokens[1..($tokens.Count - 1)] -join ' ').Trim().Trim("'").Trim('"')
            $addParams = @{ Text = $text; MetraRoot = $MetraRoot }
            if ($whatIf) { $addParams.WhatIf = $true }
            if ($confirm) { $addParams.Confirm = $true }
            if ($kind -ieq 'stated') {
                return Add-MetraOperatorWorkingNoteStated @addParams
            }
            if ($kind -ieq 'moment') {
                return Add-MetraOperatorWorkingNoteMoment @addParams
            }
            throw "profile notes add kind must be stated or moment (got '$kind')."
        }
        'observe' {
            if ($ArgsRest.Count -lt 1) {
                throw "profile notes observe requires a pattern. Example: .\metra.ps1 profile notes observe 'parks threads' -Evidence 'resumed after gap'"
            }
            $pattern = $null
            $evidence = ''
            $whatIf = $false
            $confirm = $false
            $i = 0
            while ($i -lt $ArgsRest.Count) {
                $a = [string]$ArgsRest[$i]
                if ($a -ieq '-WhatIf') {
                    $whatIf = $true
                }
                elseif ($a -ieq '-Confirm') {
                    $confirm = $true
                }
                elseif ($a -ieq '-Evidence' -or $a -ieq '-Note') {
                    if (($i + 1) -ge $ArgsRest.Count) { throw "Missing value for $a." }
                    $next = [string]$ArgsRest[$i + 1]
                    if ($next -like '-*') {
                        throw "Missing value for $a."
                    }
                    $i++; $evidence = $next
                }
                elseif ($a -like '-*') {
                    throw "Unknown observe argument '$a'. Use optional -Evidence, -WhatIf, and/or -Confirm."
                }
                elseif ($null -eq $pattern) {
                    $pattern = $a.Trim().Trim("'").Trim('"')
                }
                else {
                    $pattern = ($pattern + ' ' + $a).Trim()
                }
                $i++
            }
            if ([string]::IsNullOrWhiteSpace($pattern)) {
                throw 'profile notes observe requires a pattern string.'
            }
            $obsParams = @{ Pattern = $pattern; Evidence = $evidence; MetraRoot = $MetraRoot }
            if ($whatIf) { $obsParams.WhatIf = $true }
            if ($confirm) { $obsParams.Confirm = $true }
            return Add-MetraOperatorWorkingNoteObservation @obsParams
        }
        'moment' {
            $whatIf = $false
            $confirm = $false
            $tokens = [System.Collections.Generic.List[string]]::new()
            foreach ($a in @($ArgsRest)) {
                if ($a -ieq '-WhatIf') { $whatIf = $true; continue }
                if ($a -ieq '-Confirm') { $confirm = $true; continue }
                if ($a -like '-*') {
                    throw "Unknown moment argument '$a'. Use -WhatIf and/or -Confirm only."
                }
                [void]$tokens.Add([string]$a)
            }
            if ($tokens.Count -lt 1) {
                throw "profile notes moment requires text. Example: .\metra.ps1 profile notes moment 'Called the dial a costume'"
            }
            $text = ($tokens -join ' ').Trim().Trim("'").Trim('"')
            $momentParams = @{ Text = $text; MetraRoot = $MetraRoot }
            if ($whatIf) { $momentParams.WhatIf = $true }
            if ($confirm) { $momentParams.Confirm = $true }
            return Add-MetraOperatorWorkingNoteMoment @momentParams
        }
        'reset' {
            $force = $false
            $whatIf = $false
            $confirm = $false
            foreach ($a in @($ArgsRest)) {
                if ($a -ieq '-Force') { $force = $true }
                elseif ($a -ieq '-WhatIf') { $whatIf = $true }
                elseif ($a -ieq '-Confirm') { $confirm = $true }
                elseif ($a -like '-*') {
                    throw "Unknown reset argument '$a'. Use -Force, -WhatIf, and/or -Confirm."
                }
            }
            $resetParams = @{ MetraRoot = $MetraRoot }
            if ($force) { $resetParams.Force = $true }
            if ($whatIf) { $resetParams.WhatIf = $true }
            if ($confirm) { $resetParams.Confirm = $true }
            return Reset-MetraOperatorWorkingNotes @resetParams
        }
        default {
            throw "profile notes requires show|add|observe|moment|reset. Example: .\metra.ps1 profile notes show"
        }
    }
}

function Get-MetraOperatorWorkingNotesScrubbedText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Raw)
    if (-not (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue)) {
        # Fail closed: never inject unscrubbed ledger text into identity context.
        return '[REDACTED:scrub-unavailable]'
    }
    $scrub = Invoke-MetraAskSecretsScrubText -Text $Raw
    if ([bool]$scrub.Refuse) {
        return '[REDACTED:refused]'
    }
    return [string]$scrub.Text
}

function ConvertFrom-MetraOperatorWorkingNotesRawForPack {
    <#
    .SYNOPSIS
        Canonical scrubbed pack text for export/import/status hashing (same Serialize shape everywhere).
    .NOTES
        Fail-closed by default (blank rows / schema / updatedUtc). Pass -AllowDroppedRows only for
        repair/tests that intentionally pack surviving rows after a heal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Raw,
        [switch]$AllowDroppedRows,
        # Compat alias: same as default refuse (ignored when -AllowDroppedRows is set).
        [switch]$RefuseDroppedRows
    )

    $converted = ConvertTo-MetraOperatorWorkingNotesObject -Raw $Raw
    $dropped = 0
    try { $dropped = [int]$converted.DroppedRowCount } catch { $dropped = 0 }
    $schemaOk = $false
    $updatedOk = $false
    try { $schemaOk = [bool]$converted.SchemaVersionOk } catch { $schemaOk = $false }
    try { $updatedOk = [bool]$converted.UpdatedUtcOk } catch { $updatedOk = $false }
    $refuse = -not [bool]$AllowDroppedRows
    if ($refuse) {
        if ($dropped -gt 0) {
            throw ("Working-notes pack refused: {0} blank/unusable row(s). Fix the JSON or run: .\metra.ps1 profile notes reset -Force" -f $dropped)
        }
        if (-not $schemaOk) {
            throw ("Working-notes pack refused: unsupported schema version (expected {0})." -f $script:MetraWorkingNotesSchemaVersion)
        }
        if (-not $updatedOk) {
            throw 'Working-notes pack refused: blank/invalid updatedUtc.'
        }
    }
    $notes = Protect-MetraOperatorWorkingNotesSecrets -Notes $converted
    $payload = [ordered]@{
        version    = [int]$notes.version
        updatedUtc = [string]$notes.updatedUtc
        stated     = @($notes.stated)
        observed   = @($notes.observed)
        moments    = @($notes.moments)
    }
    $text = ($payload | ConvertTo-Json -Depth 6) + "`n"
    return [pscustomobject]@{
        Notes           = $notes
        Text            = $text
        DroppedRowCount = $dropped
    }
}

function Protect-MetraOperatorWorkingNotesSecrets {
    <#
    .SYNOPSIS
        Scrub all string fields on a working-notes object. Throws when scrub is unavailable or Refuse.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Notes)

    if (-not (Get-Command Invoke-MetraAskSecretsScrubText -ErrorAction SilentlyContinue)) {
        throw 'Working-notes secrets scrub unavailable (Invoke-MetraAskSecretsScrubText missing).'
    }

    $scrubOne = {
        param([string]$Text, [string]$Field)
        $scrub = Invoke-MetraAskSecretsScrubText -Text $Text
        if ([bool]$scrub.Refuse) {
            throw ("Working-notes ${Field} refused by secrets scrub: {0}" -f $scrub.Reason)
        }
        return [string]$scrub.Text
    }

    $stated = @()
    foreach ($row in @($Notes.stated)) {
        $id = [string]$row.id
        $notedUtc = [string]$row.notedUtc
        Assert-MetraOperatorWorkingNotesIdAndUtc -Id $id -Stamp $notedUtc -Field 'stated' -RequireStamp
        $text = & $scrubOne -Text ([string]$row.text) -Field 'stated'
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw 'Working-notes stated text blank after scrub (refused).'
        }
        $stated += [pscustomobject]@{
            id       = $id.Trim()
            text     = $text
            source   = & $scrubOne -Text ([string]$row.source) -Field 'stated.source'
            notedUtc = $notedUtc.Trim()
        }
    }
    $observed = @()
    foreach ($row in @($Notes.observed)) {
        $id = [string]$row.id
        $lastUtc = [string]$row.lastObservedUtc
        $firstUtc = [string]$row.firstObservedUtc
        Assert-MetraOperatorWorkingNotesIdAndUtc -Id $id -Stamp $lastUtc -Field 'observed.lastObservedUtc' -RequireStamp
        Assert-MetraOperatorWorkingNotesIdAndUtc -Id $id -Stamp $firstUtc -Field 'observed.firstObservedUtc' -RequireStamp
        $pattern = & $scrubOne -Text ([string]$row.pattern) -Field 'observed.pattern'
        if ([string]::IsNullOrWhiteSpace($pattern)) {
            throw 'Working-notes observed pattern blank after scrub (refused).'
        }
        $observed += [pscustomobject]@{
            id               = $id.Trim()
            pattern          = $pattern
            evidence         = & $scrubOne -Text ([string]$row.evidence) -Field 'observed.evidence'
            instanceCount    = [int]$row.instanceCount
            lastObservedUtc  = $lastUtc.Trim()
            firstObservedUtc = $firstUtc.Trim()
        }
    }
    $moments = @()
    foreach ($row in @($Notes.moments)) {
        $id = [string]$row.id
        $notedUtc = [string]$row.notedUtc
        Assert-MetraOperatorWorkingNotesIdAndUtc -Id $id -Stamp $notedUtc -Field 'moment' -RequireStamp
        $text = & $scrubOne -Text ([string]$row.text) -Field 'moment'
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw 'Working-notes moment text blank after scrub (refused).'
        }
        $moments += [pscustomobject]@{
            id       = $id.Trim()
            text     = $text
            notedUtc = $notedUtc.Trim()
        }
    }
    $rootUpdated = [string](Get-MetraProp -Object $Notes -Name 'updatedUtc' -Default '')
    if (-not (Test-MetraOperatorWorkingNotesUtcStampFormat -Stamp $rootUpdated -AllowEmpty:$false)) {
        throw ("Working-notes updatedUtc rejected (expected ISO/round-trip UTC): '{0}'" -f $rootUpdated)
    }
    return [pscustomobject]@{
        version    = [int](Get-MetraProp -Object $Notes -Name 'version' -Default $script:MetraWorkingNotesSchemaVersion)
        updatedUtc = $rootUpdated.Trim()
        stated     = $stated
        observed   = $observed
        moments    = $moments
    }
}

function Reset-MetraOperatorWorkingNotes {
    <#
    .SYNOPSIS
        Replace a missing/corrupt working-notes ledger with an empty default (requires -Force when corrupt/exists).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Force
    )
    $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $MetraRoot
    $exists = Test-Path -LiteralPath $path
    # SupportsShouldProcess binds -WhatIf into $WhatIfPreference / $PSBoundParameters, not a local $WhatIf.
    $whatIfBound = [bool]$WhatIfPreference
    if ($PSBoundParameters.ContainsKey('WhatIf')) {
        $whatIfBound = [bool]$PSBoundParameters['WhatIf']
    }
    # WhatIf preview reaches here even without -Force so the operator sees the plan.
    if ($whatIfBound) {
        $wouldNeedForce = ($exists -and -not $Force)
        return [pscustomobject]@{
            Path           = $path
            Reset          = $false
            WhatIf         = $true
            Declined       = $false
            Exists         = $exists
            RequiresForce  = $wouldNeedForce
            WouldBackup    = $exists
            Message        = if ($wouldNeedForce) {
                "WhatIf: ledger exists; a real reset needs -Force (would backup then empty)."
            }
            else {
                "WhatIf: would backup (if exists) then write an empty working-notes ledger."
            }
            Backup         = $null
        }
    }
    if ($exists -and -not $Force) {
        throw ("Refusing to reset existing working-notes ledger without -Force: {0}" -f $path)
    }
    if (-not $PSCmdlet.ShouldProcess($path, 'Reset Metra operator working-notes ledger')) {
        return [pscustomobject]@{
            Path     = $path
            Reset    = $false
            WhatIf   = $false
            Declined = $true
            Backup   = $null
        }
    }
    $bak = $null
    if ($exists) {
        $bak = "$path.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $path -Destination $bak -Force
    }
    $empty = [pscustomobject](New-MetraOperatorWorkingNotesDefault)
    $saved = Save-MetraOperatorWorkingNotes -Notes $empty -MetraRoot $MetraRoot -Force
    return [pscustomobject]@{
        Path    = $saved
        Reset   = $true
        Backup  = $bak
        WhatIf  = $false
    }
}

function Format-MetraOperatorWorkingNotesForPrompt {
    <#
    .SYNOPSIS
        Compact, capped context block for CE/Ask/Cursor. Skips expired Observed. Silent-use contract in header.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [int]$CapBytes = 0,
        [DateTime]$AsOfUtc = [DateTime]::UtcNow
    )

    if ($CapBytes -le 0) { $CapBytes = [int]$script:MetraWorkingNotesContextCapBytes }
    $notes = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
    if ([bool]$notes.LedgerCorrupt) {
        return ''
    }
    $activeObserved = @(Select-MetraOperatorWorkingNotesActiveObserved -Notes $notes -AsOfUtc $AsOfUtc)

    if (@($notes.stated).Count -eq 0 -and $activeObserved.Count -eq 0 -and @($notes.moments).Count -eq 0) {
        return ''
    }

    $utf8 = [System.Text.Encoding]::UTF8
    $header = @(
        '## Operator working notes'
        'Path: machine-data operator-working-notes.local.json (operator-owned).'
        'Use to tune pace, depth, verdict format, and callbacks. Do not announce these notes unprompted (no "I''ve learned that you..."). If the operator asks where a preference came from, say the working-notes file. Never lower Honesty or Conviction because of these notes.'
    )

    # Priority under cap: Observed (active) > Moments > Stated (long Stated must not starve observations).
    $chunks = [System.Collections.Generic.List[object]]::new()
    if ($activeObserved.Count -gt 0) {
        $obsLines = [System.Collections.Generic.List[string]]::new()
        [void]$obsLines.Add('### Observed (active; expired rows omitted)')
        foreach ($row in $activeObserved) {
            $pat = Get-MetraOperatorWorkingNotesScrubbedText -Raw ([string]$row.pattern)
            $ev = [string]$row.evidence
            if ([string]::IsNullOrWhiteSpace($ev)) {
                [void]$obsLines.Add(('- {0} (n={1})' -f $pat, [int]$row.instanceCount))
            }
            else {
                $evS = Get-MetraOperatorWorkingNotesScrubbedText -Raw $ev
                [void]$obsLines.Add(('- {0} (n={1}; {2})' -f $pat, [int]$row.instanceCount, $evS))
            }
        }
        [void]$chunks.Add([pscustomobject]@{ Priority = 1; Lines = @($obsLines) })
    }
    if (@($notes.moments).Count -gt 0) {
        $momLines = [System.Collections.Generic.List[string]]::new()
        [void]$momLines.Add('### Moments (callback material; do not announce unprompted)')
        foreach ($row in @($notes.moments)) {
            $t = Get-MetraOperatorWorkingNotesScrubbedText -Raw ([string]$row.text)
            [void]$momLines.Add(('- {0}' -f $t))
        }
        [void]$chunks.Add([pscustomobject]@{ Priority = 2; Lines = @($momLines) })
    }
    if (@($notes.stated).Count -gt 0) {
        $stLines = [System.Collections.Generic.List[string]]::new()
        [void]$stLines.Add('### Stated (operator-supplied; not Metra inference)')
        foreach ($row in @($notes.stated)) {
            $t = Get-MetraOperatorWorkingNotesScrubbedText -Raw ([string]$row.text)
            [void]$stLines.Add(('- {0}' -f $t))
        }
        [void]$chunks.Add([pscustomobject]@{ Priority = 3; Lines = @($stLines) })
    }

    $assembled = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $header) { [void]$assembled.Add($h) }
    $truncated = $false
    foreach ($chunk in @($chunks | Sort-Object Priority)) {
        $candidate = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in $assembled) { [void]$candidate.Add($existing) }
        foreach ($line in @($chunk.Lines)) { [void]$candidate.Add($line) }
        $probe = ($candidate -join "`n").Trim()
        if ($utf8.GetByteCount($probe) -le $CapBytes) {
            $assembled = $candidate
            continue
        }
        # Try adding heading + rows one at a time until over cap.
        $partial = [System.Collections.Generic.List[string]]::new()
        foreach ($existing in $assembled) { [void]$partial.Add($existing) }
        $addedAny = $false
        foreach ($line in @($chunk.Lines)) {
            $trial = [System.Collections.Generic.List[string]]::new()
            foreach ($existing in $partial) { [void]$trial.Add($existing) }
            [void]$trial.Add($line)
            if ($utf8.GetByteCount(($trial -join "`n").Trim()) -le $CapBytes) {
                $partial = $trial
                $addedAny = $true
            }
            else {
                $truncated = $true
                break
            }
        }
        if ($addedAny) { $assembled = $partial }
        else { $truncated = $true }
        if ($truncated) { break }
    }

    $marker = "`n[working-notes truncated to ${CapBytes} bytes]"
    $markerBytes = $utf8.GetByteCount($marker)
    $bodyBudget = [Math]::Max(0, $CapBytes - $markerBytes)
    $text = ($assembled -join "`n").Trim()
    if ($utf8.GetByteCount($text) -gt $bodyBudget) {
        $bytes = $utf8.GetBytes($text)
        $take = [Math]::Min($bytes.Length, $bodyBudget)
        # Walk back to a UTF-8 character boundary (continuation bytes are 10xxxxxx).
        while ($take -gt 0 -and (($bytes[$take - 1] -band 0xC0) -eq 0x80)) {
            $take--
        }
        if ($take -le 0) {
            $text = ''
        }
        else {
            $text = $utf8.GetString($bytes, 0, $take).TrimEnd()
        }
        $truncated = $true
    }
    if ($truncated) {
        $out = if ([string]::IsNullOrEmpty($text)) { $marker.TrimStart() } else { $text.TrimEnd() + $marker }
        if ($utf8.GetByteCount($out) -gt $CapBytes) {
            $ob = $utf8.GetBytes($out)
            $take = [Math]::Min($ob.Length, $CapBytes)
            while ($take -gt 0 -and (($ob[$take - 1] -band 0xC0) -eq 0x80)) { $take-- }
            if ($take -le 0) { return '' }
            return $utf8.GetString($ob, 0, $take)
        }
        return $out
    }
    return $text
}

function Save-MetraOperatorWorkingNotes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Notes,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Force
    )

    $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $MetraRoot
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        $probe = Read-MetraOperatorWorkingNotes -MetraRoot $MetraRoot
        if ([bool]$probe.LedgerCorrupt) {
            throw ("Refusing to overwrite corrupt working-notes ledger without -Force: {0}" -f $path)
        }
    }
    $toWrite = Protect-MetraOperatorWorkingNotesSecrets -Notes $Notes
    $dir = Split-Path -Parent $path
    if ($dir) { [void][System.IO.Directory]::CreateDirectory($dir) }
    $payload = [ordered]@{
        version    = [int](Get-MetraProp -Object $toWrite -Name 'version' -Default $script:MetraWorkingNotesSchemaVersion)
        updatedUtc = [DateTime]::UtcNow.ToString('o')
        stated     = @($toWrite.stated)
        observed   = @($toWrite.observed)
        moments    = @($toWrite.moments)
    }
    $json = ($payload | ConvertTo-Json -Depth 6)
    Write-MetraProfileAtomicText -Path $path -Text ($json + "`n")
    return $path
}
