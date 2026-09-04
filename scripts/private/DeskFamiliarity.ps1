# Desk familiarity - durable working-together register (operator-private local ledger).
# Humor-desk companion; mechanical CLI - agent performs chat analysis.

$script:MetraDeskFamiliarityRelativePath = 'desk-familiarity.local.json'
$script:MetraDeskFamiliarityBands = @('Cold', 'Warming', 'Familiar')
$script:MetraDeskFamiliarityScoreMin = 0
$script:MetraDeskFamiliarityScoreMax = 8
$script:MetraDeskFamiliarityDefaultScore = 3
$script:MetraDeskFamiliarityDefaultBand = 'Warming'
$script:MetraDeskFamiliarityEvidenceCap = 40

function Get-MetraDeskFamiliarityPaths {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $ledger = Get-MetraDeskFamiliarityLedgerPath -MetraRoot $MetraRoot
    $example = Join-Path $MetraRoot ('docs' + [IO.Path]::DirectorySeparatorChar + 'examples' + [IO.Path]::DirectorySeparatorChar + 'desk-familiarity.local.example.json')
    return [PSCustomObject]@{
        LedgerPath      = $ledger
        RelativePath    = $script:MetraDeskFamiliarityRelativePath
        ExamplePath     = $example
        MachineDataRoot = (Get-MetraMachineDataRoot -MetraRoot $MetraRoot)
    }
}

function ConvertTo-MetraDeskFamiliarityBand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Score)

    if ($Score -le 2) { return 'Cold' }
    if ($Score -le 5) { return 'Warming' }
    return 'Familiar'
}

function Resolve-MetraDeskFamiliarityBand {
    <#
    .SYNOPSIS
        Map a band name to the canonical Cold/Warming/Familiar label (case-insensitive).
    .NOTES
        v1 scale is intentionally fixed to these three bands and score 0-8 - not schema-extensible yet.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Band)

    foreach ($canonical in $script:MetraDeskFamiliarityBands) {
        if ([string]::Equals($canonical, $Band, [StringComparison]::OrdinalIgnoreCase)) {
            return $canonical
        }
    }
    throw "Invalid desk familiarity band '$Band'. Use: Cold, Warming, Familiar."
}

function Get-MetraDeskFamiliarityBandIndex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Band)

    $canonical = Resolve-MetraDeskFamiliarityBand -Band $Band
    return [array]::IndexOf($script:MetraDeskFamiliarityBands, $canonical)
}

function Test-MetraDeskFamiliarityBandName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Band)
    try {
        $null = Resolve-MetraDeskFamiliarityBand -Band $Band
        return $true
    }
    catch {
        return $false
    }
}

function New-MetraDeskFamiliarityDefault {
    [CmdletBinding()]
    param()

    $now = [datetime]::UtcNow.ToString('o')
    return [ordered]@{
        version      = 1
        durableBand  = $script:MetraDeskFamiliarityDefaultBand
        score        = $script:MetraDeskFamiliarityDefaultScore
        updatedUtc   = $now
        lastNudgeUtc = $null
        evidence     = @()
    }
}

function Get-MetraDeskFamiliarityEffective {
    <#
    .SYNOPSIS
        Read durable familiarity. Missing or corrupt ledger -> Warming without overwrite.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $paths = Get-MetraDeskFamiliarityPaths -MetraRoot $MetraRoot
    $result = [PSCustomObject]@{
        LedgerPath              = $paths.LedgerPath
        LedgerExists            = $false
        LedgerCorrupt           = $false
        WarmingDefaultActive    = $true
        DurableBand             = $script:MetraDeskFamiliarityDefaultBand
        Score                   = $script:MetraDeskFamiliarityDefaultScore
        UpdatedUtc              = $null
        LastNudgeUtc            = $null
        QualifyingEvidenceCount = 0
        Evidence                = @()
        Ledger                  = $null
    }

    if (-not (Test-Path -LiteralPath $paths.LedgerPath)) {
        return $result
    }

    $result.LedgerExists = $true
    try {
        $raw = [System.IO.File]::ReadAllText($paths.LedgerPath, [System.Text.Encoding]::UTF8)
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { throw 'null JSON' }
        $score = 0
        if ($null -ne $obj.score) { $score = [int]$obj.score }
        if ($score -lt $script:MetraDeskFamiliarityScoreMin -or $score -gt $script:MetraDeskFamiliarityScoreMax) {
            throw "score out of bounds: $score"
        }
        $band = ConvertTo-MetraDeskFamiliarityBand -Score $score
        $evidence = @()
        if ($obj.evidence) { $evidence = @($obj.evidence) }
        $qualCount = @($evidence | Where-Object { $_.qualifying -eq $true }).Count

        $result.WarmingDefaultActive = $false
        $result.DurableBand = $band
        $result.Score = $score
        $result.UpdatedUtc = $obj.updatedUtc
        $result.LastNudgeUtc = $obj.lastNudgeUtc
        $result.QualifyingEvidenceCount = $qualCount
        $result.Evidence = $evidence
        $result.Ledger = $obj
        return $result
    }
    catch {
        $result.LedgerCorrupt = $true
        $result.WarmingDefaultActive = $true
        $result.DurableBand = $script:MetraDeskFamiliarityDefaultBand
        $result.Score = $script:MetraDeskFamiliarityDefaultScore
        $result.Ledger = $null
        return $result
    }
}

function Save-MetraDeskFamiliarityLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ledger,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraDeskFamiliarityPaths -MetraRoot $MetraRoot
    $json = ($Ledger | ConvertTo-Json -Depth 8)
    Write-MetraProfileAtomicText -Path $paths.LedgerPath -Text ($json + "`n")
}

function Get-MetraDeskFamiliarityUtcDateString {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    $parsed = [datetime]::MinValue
    $ok = [datetime]::TryParse(
        [string]$Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
    if (-not $ok) {
        return $null
    }
    return $parsed.ToUniversalTime().ToString('yyyy-MM-dd')
}

function Show-MetraDeskFamiliarity {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $eff = Get-MetraDeskFamiliarityEffective -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action                  = 'show'
        DurableBand             = $eff.DurableBand
        Score                   = $eff.Score
        LastNudgeUtc            = $eff.LastNudgeUtc
        LastNudgeUtcDate        = (Get-MetraDeskFamiliarityUtcDateString -Value $eff.LastNudgeUtc)
        QualifyingEvidenceCount = $eff.QualifyingEvidenceCount
        LedgerPath              = $eff.LedgerPath
        LedgerExists            = $eff.LedgerExists
        LedgerCorrupt           = $eff.LedgerCorrupt
        WarmingDefaultActive    = $eff.WarmingDefaultActive
        UpdatedUtc              = $eff.UpdatedUtc
    }
}

function Invoke-MetraDeskFamiliarityAnalyzeNudge {
    <#
    .SYNOPSIS
        Apply bounded durable familiarity nudge from structured agent observation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Cold', 'Warming', 'Familiar')]
        [string]$SessionPeak,

        [Parameter(Mandatory)]
        [ValidateSet('Cold', 'Warming', 'Familiar')]
        [string]$SessionFloor,

        [Parameter(Mandatory)]
        [ValidateSet('Up', 'Down')]
        [string]$Direction,

        [switch]$Sustained,

        [string]$Note = '',

        [switch]$TicketOnly,

        [string]$MetraRoot = (Get-MetraRoot)
    )

    $now = [datetime]::UtcNow
    $nowIso = $now.ToString('o')
    $today = $now.ToString('yyyy-MM-dd')
    $noteText = ([string]$Note).Trim()
    if ([string]::IsNullOrWhiteSpace($noteText)) {
        $noteText = 'sustained collaborative session pattern'
    }

    if ($TicketOnly) {
        $effTicket = Get-MetraDeskFamiliarityEffective -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Action      = 'analyze-nudge'
            Outcome     = 'neutral'
            Reason      = 'ticket-only-excluded'
            DurableBand = $effTicket.DurableBand
            Score       = $effTicket.Score
            LedgerPath  = $effTicket.LedgerPath
            WroteLedger = $false
        }
    }

    if (-not $Sustained) {
        $eff = Get-MetraDeskFamiliarityEffective -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Action       = 'analyze-nudge'
            Outcome      = 'insufficient-pattern'
            Reason       = 'not-sustained'
            DurableBand  = $eff.DurableBand
            Score        = $eff.Score
            LedgerPath   = $eff.LedgerPath
            WroteLedger  = $false
        }
    }

    $eff = Get-MetraDeskFamiliarityEffective -MetraRoot $MetraRoot
    if ($eff.LedgerCorrupt) {
        return [PSCustomObject]@{
            Action       = 'analyze-nudge'
            Outcome      = 'neutral'
            Reason       = 'ledger-corrupt-fail-closed'
            DurableBand  = $eff.DurableBand
            Score        = $eff.Score
            LedgerPath   = $eff.LedgerPath
            WroteLedger  = $false
        }
    }

    # Working copy: create from defaults when absent and a write is needed.
    if ($eff.LedgerExists -and $eff.Ledger) {
        $ledger = [ordered]@{
            version      = 1
            durableBand  = $eff.DurableBand
            score        = $eff.Score
            updatedUtc   = $eff.UpdatedUtc
            lastNudgeUtc = $eff.LastNudgeUtc
            evidence     = @($eff.Evidence)
        }
    }
    else {
        $ledger = New-MetraDeskFamiliarityDefault
        $ledger.score = $script:MetraDeskFamiliarityDefaultScore
        $ledger.durableBand = $script:MetraDeskFamiliarityDefaultBand
    }

    $score = [int]$ledger.score
    $durableBand = ConvertTo-MetraDeskFamiliarityBand -Score $score
    $durableIdx = Get-MetraDeskFamiliarityBandIndex -Band $durableBand
    $peakIdx = Get-MetraDeskFamiliarityBandIndex -Band $SessionPeak
    $dir = $Direction.ToLowerInvariant()

    $lastNudgeDate = Get-MetraDeskFamiliarityUtcDateString -Value $ledger.lastNudgeUtc
    if ($lastNudgeDate -eq $today) {
        $ev = [ordered]@{
            utc          = $nowIso
            sessionPeak  = $SessionPeak
            sessionFloor = $SessionFloor
            direction    = $dir
            qualifying   = $false
            note         = $noteText
            outcome      = 'rate-limited'
        }
        $ledger.evidence = @(@($ledger.evidence) + @([pscustomobject]$ev) | Select-Object -Last $script:MetraDeskFamiliarityEvidenceCap)
        $ledger.updatedUtc = $nowIso
        Save-MetraDeskFamiliarityLedger -Ledger ([pscustomobject]$ledger) -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Action       = 'analyze-nudge'
            Outcome      = 'rate-limited'
            Reason       = 'already-nudged-utc-date'
            DurableBand  = $durableBand
            Score        = $score
            LedgerPath   = $eff.LedgerPath
            WroteLedger  = $true
        }
    }

    $twoBandOutlierUp = ($dir -eq 'up' -and ($peakIdx - $durableIdx) -ge 2)
    $outcome = $null
    $delta = 0
    $reason = $null

    if ($twoBandOutlierUp) {
        $priorOutlierEvidence = [System.Collections.Generic.List[object]]::new()
        foreach ($row in @($ledger.evidence)) {
            if ($row.qualifying -ne $true) { continue }
            if (([string]$row.direction).ToLowerInvariant() -ne 'up') { continue }
            $rowDay = Get-MetraDeskFamiliarityUtcDateString -Value $row.utc
            if ($rowDay -eq $today) { continue }
            $rowOutcome = [string]$row.outcome
            if ($rowOutcome -eq 'evidence-only') {
                [void]$priorOutlierEvidence.Add($row)
                continue
            }
            if (-not (Test-MetraDeskFamiliarityBandName -Band ([string]$row.sessionPeak))) { continue }
            $rowPeakIdx = Get-MetraDeskFamiliarityBandIndex -Band ([string]$row.sessionPeak)
            if (($rowPeakIdx - $durableIdx) -ge 2) {
                [void]$priorOutlierEvidence.Add($row)
            }
        }
        if ($priorOutlierEvidence.Count -eq 0) {
            $outcome = 'evidence-only'
            $delta = 0
            $reason = 'two-band-outlier-first-day'
        }
        else {
            $outcome = 'nudged-up'
            $delta = 1
            $reason = 'two-band-outlier-second-qualifying-day'
        }
    }
    elseif ($dir -eq 'up') {
        if ($peakIdx -lt $durableIdx) {
            return [PSCustomObject]@{
                Action      = 'analyze-nudge'
                Outcome     = 'insufficient-pattern'
                Reason      = 'peak-below-durable'
                DurableBand = $durableBand
                Score       = $score
                LedgerPath  = $eff.LedgerPath
                WroteLedger = $false
            }
        }
        $outcome = 'nudged-up'
        $delta = 1
        $reason = 'adjacent-or-equal-peak-up'
    }
    else {
        $outcome = 'nudged-down'
        $delta = -1
        $reason = 'sustained-cool-pattern'
    }

    $newScore = [Math]::Max($script:MetraDeskFamiliarityScoreMin, [Math]::Min($script:MetraDeskFamiliarityScoreMax, $score + $delta))
    $newBand = ConvertTo-MetraDeskFamiliarityBand -Score $newScore
    if ($null -eq $reason) { $reason = $outcome }

    $evOut = [ordered]@{
        utc          = $nowIso
        sessionPeak  = $SessionPeak
        sessionFloor = $SessionFloor
        direction    = $dir
        qualifying   = ($outcome -eq 'evidence-only' -or $outcome -like 'nudged-*')
        note         = $noteText
        outcome      = $outcome
    }

    $ledger.evidence = @(@($ledger.evidence) + @([pscustomobject]$evOut) | Select-Object -Last $script:MetraDeskFamiliarityEvidenceCap)
    $ledger.updatedUtc = $nowIso
    $ledger.score = $newScore
    $ledger.durableBand = $newBand
    # evidence-only must not set lastNudgeUtc (second qualifying day can still nudge)
    if ($outcome -like 'nudged-*') {
        $ledger.lastNudgeUtc = $nowIso
    }

    Save-MetraDeskFamiliarityLedger -Ledger ([pscustomobject]$ledger) -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        Action        = 'analyze-nudge'
        Outcome       = $outcome
        Reason        = $reason
        DurableBand   = $newBand
        Score         = $newScore
        PreviousScore = $score
        LedgerPath    = $eff.LedgerPath
        WroteLedger   = $true
    }
}

function Invoke-MetraDeskFamiliarityCommand {
    <#
    .SYNOPSIS
        Dispatches metra.ps1 profile familiarity subcommands.
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
            return Show-MetraDeskFamiliarity -MetraRoot $MetraRoot
        }
        'analyze-nudge' {
            $peak = $null
            $floor = $null
            $direction = $null
            $note = ''
            $sustained = $false
            $ticketOnly = $false
            $i = 0
            while ($i -lt $ArgsRest.Count) {
                $a = [string]$ArgsRest[$i]
                $needsValue = $a -match '^-(SessionPeak|SessionFloor|Direction|Note)$'
                if ($needsValue) {
                    if (($i + 1) -ge $ArgsRest.Count) {
                        throw "Missing value for $a."
                    }
                    $next = [string]$ArgsRest[$i + 1]
                    if ($next.StartsWith('-')) {
                        throw "Missing value for $a."
                    }
                }
                switch -Regex ($a) {
                    '^-SessionPeak$' {
                        $i++; $peak = $ArgsRest[$i]
                    }
                    '^-SessionFloor$' {
                        $i++; $floor = $ArgsRest[$i]
                    }
                    '^-Direction$' {
                        $i++; $direction = $ArgsRest[$i]
                    }
                    '^-Note$' {
                        $i++; $note = [string]$ArgsRest[$i]
                    }
                    '^-Sustained$' { $sustained = $true }
                    '^-TicketOnly$' { $ticketOnly = $true }
                    default {
                        throw "Unknown analyze-nudge argument '$a'. Use -SessionPeak -SessionFloor -Direction [-Sustained] [-Note] [-TicketOnly]."
                    }
                }
                $i++
            }
            if (-not $peak -or -not $floor -or -not $direction) {
                throw 'profile familiarity analyze-nudge requires -SessionPeak, -SessionFloor, and -Direction.'
            }
            $peak = Resolve-MetraDeskFamiliarityBand -Band $peak
            $floor = Resolve-MetraDeskFamiliarityBand -Band $floor
            if ([string]::Equals($direction, 'Up', [StringComparison]::OrdinalIgnoreCase)) {
                $direction = 'Up'
            }
            elseif ([string]::Equals($direction, 'Down', [StringComparison]::OrdinalIgnoreCase)) {
                $direction = 'Down'
            }
            else {
                throw "Invalid -Direction '$direction'. Use: Up, Down."
            }
            return Invoke-MetraDeskFamiliarityAnalyzeNudge `
                -SessionPeak $peak `
                -SessionFloor $floor `
                -Direction $direction `
                -Note $note `
                -MetraRoot $MetraRoot `
                -Sustained:$sustained `
                -TicketOnly:$ticketOnly
        }
        default {
            throw "Unknown familiarity subcommand '$Subcommand'. Use: show, analyze-nudge"
        }
    }
}
