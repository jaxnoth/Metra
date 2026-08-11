# Operator Communication Contract - private helpers (CLI via metra.ps1 profile).

$script:MetraOperatorContractMaxConfirmed = 20
$script:MetraOperatorContractStaleDays = 30

function Get-MetraOperatorContractPaths {
    <#
    .SYNOPSIS
        Resolves ledger and learned-rule paths under a Metra root.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    [PSCustomObject]@{
        MetraRoot   = $MetraRoot
        LedgerPath  = Join-Path $MetraRoot 'docs\operator-contract.json'
        LearnedPath = Join-Path $MetraRoot '.cursor\rules\metra-learned.local.mdc'
    }
}

function New-MetraOperatorContractId {
    ('g' + [guid]::NewGuid().ToString('N').Substring(0, 10))
}

function New-MetraOperatorContractEmpty {
    [PSCustomObject]@{
        version              = 1
        candidateStaleDays   = $script:MetraOperatorContractStaleDays
        maxConfirmed         = $script:MetraOperatorContractMaxConfirmed
        candidates           = @()
        confirmedGuidelines  = @()
    }
}

function Get-MetraOperatorContract {
    <#
    .SYNOPSIS
        Loads the operator contract ledger or returns an empty contract.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraOperatorContractPaths -MetraRoot $MetraRoot
    if (-not (Test-Path -LiteralPath $paths.LedgerPath)) {
        return New-MetraOperatorContractEmpty
    }

    $raw = Get-Content -LiteralPath $paths.LedgerPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return New-MetraOperatorContractEmpty
    }

    try {
        $obj = $raw | ConvertFrom-Json
    }
    catch {
        throw (
            "Failed to parse operator contract ledger '{0}': {1}" -f
            $paths.LedgerPath,
            $_.Exception.Message
        )
    }
    $candidates = @()
    if ($null -ne $obj.candidates) {
        $candidates = @($obj.candidates)
    }
    $confirmed = @()
    if ($null -ne $obj.confirmedGuidelines) {
        $confirmed = @($obj.confirmedGuidelines)
    }

    $staleDays = $script:MetraOperatorContractStaleDays
    if ($null -ne $obj.candidateStaleDays) {
        $staleDays = [int]$obj.candidateStaleDays
    }
    $maxConfirmed = $script:MetraOperatorContractMaxConfirmed
    if ($null -ne $obj.maxConfirmed) {
        $maxConfirmed = [int]$obj.maxConfirmed
    }

    [PSCustomObject]@{
        version             = if ($null -ne $obj.version) { [int]$obj.version } else { 1 }
        candidateStaleDays  = $staleDays
        maxConfirmed        = $maxConfirmed
        candidates          = $candidates
        confirmedGuidelines = $confirmed
    }
}

function Save-MetraOperatorContract {
    <#
    .SYNOPSIS
        Writes the operator contract ledger as UTF-8 JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Contract,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraOperatorContractPaths -MetraRoot $MetraRoot
    $docsDir = Split-Path -Parent $paths.LedgerPath
    if (-not (Test-Path -LiteralPath $docsDir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($docsDir)
    }

    $payload = [ordered]@{
        version             = [int]$Contract.version
        candidateStaleDays  = [int]$Contract.candidateStaleDays
        maxConfirmed        = [int]$Contract.maxConfirmed
        candidates          = @($Contract.candidates)
        confirmedGuidelines = @($Contract.confirmedGuidelines)
    }
    $json = $payload | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $paths.LedgerPath -Value $json -Encoding UTF8
}

function Test-MetraOperatorContractPortfolioWide {
    <#
    .SYNOPSIS
        Returns true when a claim looks like portfolio-wide product policy, not a personal habit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text
    )

    $t = $Text.ToLowerInvariant()
    $patterns = @(
        'portfolio-wide',
        'every clone',
        'all clones',
        'base persona',
        'metra-persona.mdc',
        'professional sink',
        'root isolation',
        'evidence hierarchy',
        'routing picks',
        'routing first',
        'route first for all',
        'decisions.md',
        'public readme',
        'product triangle',
        'communication discipline for all',
        'always apply for everyone'
    )
    foreach ($p in $patterns) {
        if ($t.Contains($p)) {
            return $true
        }
    }
    return $false
}

function Get-MetraOperatorContractPortfolioRefuseMessage {
    'Portfolio-wide preference refused for the personal contract. Record it in docs/Decisions.md, README.md / docs/Customizing-Metra.md, or base .cursor/rules/metra-persona.mdc instead.'
}

function Normalize-MetraOperatorContractClaim {
    param([Parameter(Mandatory)][string]$Text)
    ($Text -replace '\s+', ' ').Trim()
}

function Get-MetraOperatorContractUtcDateTime {
    <#
    .SYNOPSIS
        Normalizes a DateTime to UTC so Kind-safe comparisons succeed under StrictMode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Value
    )

    if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
    if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
        return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    return $Value.ToUniversalTime()
}

function Get-MetraOperatorContractCandidateTimestamp {
    <#
    .SYNOPSIS
        Parses candidate updatedAt (else createdAt) as UTC DateTime, or $null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Candidate
    )

    $updated = [string](Get-MetraProp -Object $Candidate -Name 'updatedAt' -Default '')
    $created = [string](Get-MetraProp -Object $Candidate -Name 'createdAt' -Default '')
    $stampText = if ($updated) { $updated } else { $created }
    if ([string]::IsNullOrWhiteSpace($stampText)) { return $null }
    try {
        $parsed = [datetime]::Parse($stampText, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return (Get-MetraOperatorContractUtcDateTime -Value $parsed)
    }
    catch {
        return $null
    }
}

function Find-MetraOperatorContractSimilarCandidate {
    param(
        $Contract,
        [Parameter(Mandatory)][string]$Text
    )

    $norm = (Normalize-MetraOperatorContractClaim $Text).ToLowerInvariant()
    foreach ($c in @($Contract.candidates)) {
        $ct = [string](Get-MetraProp -Object $c -Name 'text' -Default '')
        $ctNorm = (Normalize-MetraOperatorContractClaim $ct).ToLowerInvariant()
        if ($ctNorm -eq $norm) {
            return $c
        }
    }
    return $null
}

function Resolve-MetraOperatorContractEntry {
    param(
        $Contract,
        [Parameter(Mandatory)][string]$IdOrText
    )

    $key = $IdOrText.Trim()
    foreach ($c in @($Contract.candidates)) {
        if ([string](Get-MetraProp -Object $c -Name 'id' -Default '') -eq $key) {
            return [PSCustomObject]@{ Bucket = 'candidates'; Entry = $c }
        }
    }
    foreach ($c in @($Contract.confirmedGuidelines)) {
        if ([string](Get-MetraProp -Object $c -Name 'id' -Default '') -eq $key) {
            return [PSCustomObject]@{ Bucket = 'confirmedGuidelines'; Entry = $c }
        }
    }

    $norm = (Normalize-MetraOperatorContractClaim $key).ToLowerInvariant()
    foreach ($c in @($Contract.candidates)) {
        $ct = [string](Get-MetraProp -Object $c -Name 'text' -Default '')
        $ctNorm = (Normalize-MetraOperatorContractClaim $ct).ToLowerInvariant()
        if ($ctNorm -eq $norm) {
            return [PSCustomObject]@{ Bucket = 'candidates'; Entry = $c }
        }
    }
    foreach ($c in @($Contract.confirmedGuidelines)) {
        $ct = [string](Get-MetraProp -Object $c -Name 'text' -Default '')
        $ctNorm = (Normalize-MetraOperatorContractClaim $ct).ToLowerInvariant()
        if ($ctNorm -eq $norm) {
            return [PSCustomObject]@{ Bucket = 'confirmedGuidelines'; Entry = $c }
        }
    }
    return $null
}

function Write-MetraOperatorContractLearnedRule {
    <#
    .SYNOPSIS
        Renders confirmed guidelines into the alwaysApply learned overlay.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Contract,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraOperatorContractPaths -MetraRoot $MetraRoot
    $rulesDir = Split-Path -Parent $paths.LearnedPath
    if (-not (Test-Path -LiteralPath $rulesDir)) {
        [void][System.IO.Directory]::CreateDirectory($rulesDir)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('---')
    [void]$lines.Add('description: Metra Operator Communication Contract (learned) - gitignored; soft preferences only')
    [void]$lines.Add('alwaysApply: true')
    [void]$lines.Add('---')
    [void]$lines.Add('')
    [void]$lines.Add('# Learned operator overlay')
    [void]$lines.Add('')
    [void]$lines.Add('## Confirmed guidelines')
    [void]$lines.Add('')

    $confirmed = @($Contract.confirmedGuidelines)
    if ($confirmed.Count -eq 0) {
        [void]$lines.Add('- (none yet - use `.\metra.ps1 profile promote` after confirming a candidate)')
    }
    else {
        foreach ($g in $confirmed) {
            $text = [string](Get-MetraProp -Object $g -Name 'text' -Default '').Trim()
            if ($text) {
                [void]$lines.Add(('- {0}' -f $text))
            }
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Interpretation')
    [void]$lines.Add('')
    [void]$lines.Add('Treat the guidelines above as soft preferences.')
    [void]$lines.Add('Routing, evidence hierarchy, professional sink,')
    [void]$lines.Add('and root isolation always take precedence.')
    [void]$lines.Add('Do not invent beyond this list. Overlay owns name/greeting.')
    [void]$lines.Add('')

    Set-Content -LiteralPath $paths.LearnedPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
    return $paths.LearnedPath
}

function Add-MetraOperatorContractCandidate {
    <#
    .SYNOPSIS
        Adds or bumps a candidate preference in the contract ledger.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $claim = Normalize-MetraOperatorContractClaim $Text
    if (-not $claim) {
        throw 'profile note requires non-empty text.'
    }

    $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $existing = Find-MetraOperatorContractSimilarCandidate -Contract $contract -Text $claim
    if ($existing) {
        $count = [int](Get-MetraProp -Object $existing -Name 'count' -Default 1)
        $existing.count = $count + 1
        $existing.updatedAt = $now
        Save-MetraOperatorContract -Contract $contract -MetraRoot $MetraRoot
        return [PSCustomObject]@{
            Action = 'bumped'
            Id     = [string]$existing.id
            Text   = [string]$existing.text
            Count  = [int]$existing.count
        }
    }

    $entry = [PSCustomObject]@{
        id        = New-MetraOperatorContractId
        text      = $claim
        count     = 1
        createdAt = $now
        updatedAt = $now
    }
    $contract.candidates = @($contract.candidates) + @($entry)
    Save-MetraOperatorContract -Contract $contract -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action = 'added'
        Id     = [string]$entry.id
        Text   = [string]$entry.text
        Count  = 1
    }
}

function Promote-MetraOperatorContractGuideline {
    <#
    .SYNOPSIS
        Promotes a candidate (or text) to confirmedGuidelines and re-renders the learned rule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdOrText,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $claimProbe = Normalize-MetraOperatorContractClaim $IdOrText
    $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
    $resolved = Resolve-MetraOperatorContractEntry -Contract $contract -IdOrText $IdOrText

    $text = $null
    $id = $null
    if ($resolved -and $resolved.Bucket -eq 'confirmedGuidelines') {
        throw ("Already confirmed: {0}" -f $resolved.Entry.id)
    }
    if ($resolved -and $resolved.Bucket -eq 'candidates') {
        $text = [string]$resolved.Entry.text
        $id = [string]$resolved.Entry.id
    }
    else {
        $text = $claimProbe
        $id = $null
    }

    if (-not $text) {
        throw "No candidate matched '$IdOrText'. Use profile note first, or pass the guideline text."
    }

    if (Test-MetraOperatorContractPortfolioWide -Text $text) {
        throw (Get-MetraOperatorContractPortfolioRefuseMessage)
    }

    $max = [int]$contract.maxConfirmed
    if ($max -le 0) { $max = $script:MetraOperatorContractMaxConfirmed }
    $confirmed = @($contract.confirmedGuidelines)
    if ($confirmed.Count -ge $max) {
        throw ("Confirmed guideline budget is full ({0}). Run profile forget <id> before promoting another." -f $max)
    }

    $textNorm = (Normalize-MetraOperatorContractClaim $text).ToLowerInvariant()
    foreach ($g in $confirmed) {
        $gt = [string](Get-MetraProp -Object $g -Name 'text' -Default '')
        $gtNorm = (Normalize-MetraOperatorContractClaim $gt).ToLowerInvariant()
        if ($gtNorm -eq $textNorm) {
            throw ("Already confirmed as {0}" -f $g.id)
        }
    }

    $now = (Get-Date).ToUniversalTime().ToString('o')
    $newId = if ($id) { $id } else { New-MetraOperatorContractId }
    $entry = [PSCustomObject]@{
        id          = $newId
        text        = $text
        confirmedAt = $now
    }

    if ($id) {
        $contract.candidates = @($contract.candidates | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $id
            })
    }

    $contract.confirmedGuidelines = @($confirmed) + @($entry)
    Save-MetraOperatorContract -Contract $contract -MetraRoot $MetraRoot
    $learned = Write-MetraOperatorContractLearnedRule -Contract $contract -MetraRoot $MetraRoot

    return [PSCustomObject]@{
        Action      = 'promoted'
        Id          = $newId
        Text        = $text
        Confirmed   = @($contract.confirmedGuidelines).Count
        LearnedPath = $learned
    }
}

function Remove-MetraOperatorContractEntry {
    <#
    .SYNOPSIS
        Forgets a candidate or confirmed guideline and re-renders when needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IdOrText,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
    $resolved = Resolve-MetraOperatorContractEntry -Contract $contract -IdOrText $IdOrText
    if (-not $resolved) {
        throw "Nothing to forget matching '$IdOrText'."
    }

    $dropId = [string]$resolved.Entry.id
    $bucket = $resolved.Bucket
    if ($bucket -eq 'candidates') {
        $contract.candidates = @($contract.candidates | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $dropId
            })
    }
    else {
        $contract.confirmedGuidelines = @($contract.confirmedGuidelines | Where-Object {
                [string](Get-MetraProp -Object $_ -Name 'id' -Default '') -ne $dropId
            })
    }

    Save-MetraOperatorContract -Contract $contract -MetraRoot $MetraRoot
    $learned = $null
    if ($bucket -eq 'confirmedGuidelines') {
        $learned = Write-MetraOperatorContractLearnedRule -Contract $contract -MetraRoot $MetraRoot
    }

    return [PSCustomObject]@{
        Action      = 'forgot'
        Id          = $dropId
        Bucket      = $bucket
        LearnedPath = $learned
    }
}

function Clear-MetraOperatorContractStaleCandidates {
    <#
    .SYNOPSIS
        Drops candidates older than candidateStaleDays without promotion.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
    $days = [int]$contract.candidateStaleDays
    if ($days -le 0) { $days = $script:MetraOperatorContractStaleDays }
    $asOfUtc = Get-MetraOperatorContractUtcDateTime -Value (Get-Date).ToUniversalTime()
    $cutoff = $asOfUtc.AddDays(-1 * $days)
    $kept = New-Object System.Collections.Generic.List[object]
    $removed = 0
    foreach ($c in @($contract.candidates)) {
        $stamp = Get-MetraOperatorContractCandidateTimestamp -Candidate $c
        if ($stamp -and $stamp -lt $cutoff) {
            $removed++
        }
        else {
            [void]$kept.Add($c)
        }
    }
    $contract.candidates = @($kept)
    Save-MetraOperatorContract -Contract $contract -MetraRoot $MetraRoot
    return [PSCustomObject]@{
        Action  = 'gc'
        Removed = $removed
        Kept    = $kept.Count
        Days    = $days
    }
}

function Show-MetraOperatorContract {
    <#
    .SYNOPSIS
        Returns a display object for the operator contract.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $paths = Get-MetraOperatorContractPaths -MetraRoot $MetraRoot
    $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
    [PSCustomObject]@{
        LedgerPath          = $paths.LedgerPath
        LearnedPath         = $paths.LearnedPath
        LedgerExists        = [bool](Test-Path -LiteralPath $paths.LedgerPath)
        LearnedExists       = [bool](Test-Path -LiteralPath $paths.LearnedPath)
        MaxConfirmed        = [int]$contract.maxConfirmed
        ConfirmedCount      = @($contract.confirmedGuidelines).Count
        CandidateCount      = @($contract.candidates).Count
        ConfirmedGuidelines = @($contract.confirmedGuidelines)
        Candidates          = @($contract.candidates)
    }
}

function Invoke-MetraOperatorContractCommand {
    <#
    .SYNOPSIS
        Dispatches metra.ps1 profile subcommands.
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
            return Show-MetraOperatorContract -MetraRoot $MetraRoot
        }
        'note' {
            $text = ($ArgsRest -join ' ').Trim()
            if (-not $text) {
                throw 'profile note requires text. Example: .\metra.ps1 profile note "Prefer terse verdicts before detail."'
            }
            return Add-MetraOperatorContractCandidate -Text $text -MetraRoot $MetraRoot
        }
        'promote' {
            $key = ($ArgsRest -join ' ').Trim()
            if (-not $key) {
                throw 'profile promote requires an id or guideline text.'
            }
            return Promote-MetraOperatorContractGuideline -IdOrText $key -MetraRoot $MetraRoot
        }
        'forget' {
            $key = ($ArgsRest -join ' ').Trim()
            if (-not $key) {
                throw 'profile forget requires an id or text.'
            }
            return Remove-MetraOperatorContractEntry -IdOrText $key -MetraRoot $MetraRoot
        }
        'render' {
            $contract = Get-MetraOperatorContract -MetraRoot $MetraRoot
            $path = Write-MetraOperatorContractLearnedRule -Contract $contract -MetraRoot $MetraRoot
            return [PSCustomObject]@{
                Action      = 'render'
                LearnedPath = $path
                Confirmed   = @($contract.confirmedGuidelines).Count
            }
        }
        'gc' {
            return Clear-MetraOperatorContractStaleCandidates -MetraRoot $MetraRoot
        }
        default {
            throw "Unknown profile subcommand '$Subcommand'. Use: show, note, promote, forget, render, gc"
        }
    }
}
