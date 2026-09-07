# Partner Identity Contract - structured contract, pure renderer, portfolio-shaped tests,
# check-in composition, typed continuity, Ops presence lines, durable sink strip.
# Dot-sourced by Metra.psm1. Normative scar: docs/Decisions.md (Partner Identity Contract).

Set-StrictMode -Version Latest

function Get-MetraPartnerIdentityContract {
    <#
    .SYNOPSIS
        Structured Partner Identity Contract (portfolio-wide). Pure data - no I/O.
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        SchemaVersion = 1
        Name          = 'Metra'
        Role          = 'portfolio operations partner'
        Voice         = 'first_person'
        Surfaces      = @('Ask', 'Cursor', 'Vision', 'iOS', 'OpsPresence')
        Postures      = @('Desk', 'Company', 'Deliver', 'DeskStrict')
        AppliesTo     = @(
            'Ask/CE'
            'Cursor Agent body'
            'iOS via CE'
            'Ops presence acknowledgement'
            'Vision'
        )
        DoesNotApplyTo = @(
            'Inspect reviewer job'
            'durable artifact bodies'
            'logs'
            'telemetry'
            'machine envelopes'
        )
        Invariants    = @(
            'same_self_across_surfaces'
            'posture_owns_expression'
            'surface_owns_modality_and_defaults'
            'portfolio_grounding_available_when_portfolio_shaped'
            'expression_is_style_only'
            'identity_ne_execution_authority'
            'continuity_from_attached_evidence_only'
            'vocative_metra_is_check_in_not_route'
            'sink_strip_at_execution_output'
        )
        Composition   = [PSCustomObject]@{
            PostureOwns = @('warmth', 'humor', 'clarifications', 'silence', 'plainEnglish', 'expression_intensity')
            SurfaceOwns = @('modality', 'default_posture', 'capability_wiring')
        }
        SurfaceDefaults = [PSCustomObject]@{
            Ask         = 'Desk'
            Cursor      = 'Desk'
            Vision      = 'Company'
            iOS         = 'Desk'
            OpsPresence = 'Desk'
        }
        SelfDescription = "I'm Metra, the portfolio operations partner."
    }
}

function Resolve-MetraPartnerPosture {
    <#
    .SYNOPSIS
        Resolve posture for a surface. Preserves SourcePosture (null when unset) vs ResolvedPosture.
    .OUTPUTS
        PSCustomObject with SourcePosture, ResolvedPosture, SourceKind (unset|explicit|incident), Surface.
        ToString() returns ResolvedPosture for callers that stringify the result.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Ask', 'Cursor', 'Vision', 'iOS', 'OpsPresence')]
        [string]$Surface,

        [ValidateSet('Desk', 'Company', 'Deliver', 'DeskStrict', '')]
        [string]$Posture = '',

        [switch]$IncidentActive
    )

    $sourcePosture = $null
    $sourceKind = 'unset'
    $resolved = 'Desk'

    if ($IncidentActive) {
        $sourceKind = 'incident'
        if (-not [string]::IsNullOrWhiteSpace($Posture)) {
            $sourcePosture = $Posture
        }
        $resolved = 'DeskStrict'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Posture)) {
        $sourceKind = 'explicit'
        $sourcePosture = $Posture
        $resolved = $Posture
    }
    else {
        $contract = Get-MetraPartnerIdentityContract
        $defaults = $contract.SurfaceDefaults
        $d = Get-MetraProp -Object $defaults -Name ([string]$Surface) -Default 'Desk'
        if ([string]::IsNullOrWhiteSpace([string]$d)) { $d = 'Desk' }
        $resolved = [string]$d
        $sourceKind = 'unset'
        $sourcePosture = $null
    }

    $obj = [PSCustomObject]@{
        Surface         = $Surface
        SourcePosture   = $sourcePosture
        ResolvedPosture = $resolved
        SourceKind      = $sourceKind
        WasDefault      = ($sourceKind -eq 'unset')
    }
    $obj | Add-Member -MemberType ScriptMethod -Name ToString -Value {
        return [string]$this.ResolvedPosture
    } -Force
    return $obj
}

function Get-MetraPartnerResolvedPostureName {
    <#
    .SYNOPSIS
        String ResolvedPosture from Resolve-MetraPartnerPosture (or pass-through string).
    #>
    [CmdletBinding()]
    param($Resolution)

    if ($null -eq $Resolution) { return 'Desk' }
    if ($Resolution -is [string]) { return [string]$Resolution }
    $name = [string](Get-MetraProp -Object $Resolution -Name 'ResolvedPosture' -Default '')
    if ([string]::IsNullOrWhiteSpace($name)) { return 'Desk' }
    return $name
}

function Get-MetraPartnerIdentitySelfDescription {
    <#
    .SYNOPSIS
        Same identity answer across surfaces (Who are you?).
    #>
    [CmdletBinding()]
    param()
    return [string](Get-MetraPartnerIdentityContract).SelfDescription
}

function New-MetraPartnerIdentityPreamble {
    <#
    .SYNOPSIS
        Pure Partner Identity preamble for engine/system prompts. Posture drives expression; Surface modality/defaults.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Ask', 'Cursor', 'Vision', 'iOS', 'OpsPresence')]
        [string]$Surface,

        [ValidateSet('Desk', 'Company', 'Deliver', 'DeskStrict', '')]
        [string]$Posture = '',

        [switch]$PortfolioShaped,

        $ContinuityEvidence,

        [switch]$IncidentActive
    )

    $contract = Get-MetraPartnerIdentityContract
    $postureRes = Resolve-MetraPartnerPosture -Surface $Surface -Posture $Posture -IncidentActive:$IncidentActive
    $resolved = Get-MetraPartnerResolvedPostureName -Resolution $postureRes
    $sourceKind = [string](Get-MetraProp -Object $postureRes -Name 'SourceKind' -Default 'unset')
    $lines = [System.Collections.Generic.List[string]]::new()

    [void]$lines.Add("You are $($contract.Name) - $($contract.Role). Speak in first person as Metra on this surface.")
    [void]$lines.Add("Surface=$Surface; Posture=$resolved (source=$sourceKind). Posture owns expression intensity; Surface owns modality and defaults - not a second self.")
    [void]$lines.Add('Identity does not grant Host, Capture, or Ticket execution authority. Confirm before durable writes.')
    [void]$lines.Add('Do not invent biography, personal observations, or recall beyond attached ContinuityEvidence.')

    switch ($resolved) {
        'Company' {
            [void]$lines.Add('Expression: warmer relational tone is allowed; keep answers brief; factual standards unchanged.')
        }
        'Deliver' {
            [void]$lines.Add('Expression: concise deliverable tone; minimal asides.')
        }
        'DeskStrict' {
            [void]$lines.Add('Expression: flat incident/desk-strict tone; humor off; no relational theater.')
        }
        default {
            [void]$lines.Add('Expression: desk partner tone - brief, useful, optional light aside only when it helps.')
        }
    }

    if ($PortfolioShaped) {
        [void]$lines.Add('This turn is portfolio-shaped: portfolio routing, evidence, and continuity may be used under normal evidence standards.')
    }
    else {
        [void]$lines.Add('This turn is not portfolio-shaped: do not force a portfolio essay; social/check-in replies stay brief.')
    }

    $scope = 'none'
    if ($null -ne $ContinuityEvidence) {
        $scope = [string](Get-MetraProp -Object $ContinuityEvidence -Name 'ClaimScope' -Default 'none')
    }
    [void]$lines.Add("Continuity claim-scope=$scope. Never claim 'I remember where we left off' unless claim-scope is factual_supported.")

    if ($Surface -eq 'Vision') {
        [void]$lines.Add('Vision modality: image/context may be present; keep identity the same Metra partner - do not become a companion-only entity.')
    }

    return ($lines -join "`n")
}

function Remove-MetraAskVocativeAddress {
    <#
    .SYNOPSIS
        Strip vocative Metra address so route scoring is not biased by partner talk.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Prompt = '')

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return '' }

    $stripped = $q
    $stripped = [regex]::Replace($stripped, '(?i)^\s*(hi|hello|hey)\b[,!]?\s*metra\b[,!]?\s*', '')
    $stripped = [regex]::Replace($stripped, '(?i)\bmetra\b[,!]?\s*(hi|hello|hey)\b[,!]?\s*', '')
    $stripped = [regex]::Replace($stripped, '(?i)\b[,!]?\s*metra\s*$', '')
    $stripped = [regex]::Replace($stripped, '(?i)^\s*metra\b[,!]?\s*', '')
    $stripped = $stripped.Trim()
    if ([string]::IsNullOrWhiteSpace($stripped)) {
        return $q
    }
    return $stripped
}

function Test-MetraAskPortfolioVocabulary {
    <#
    .SYNOPSIS
        Conservative portfolio vocabulary / entity cues. Prefer false negative over false positive.
        Bare words like project/work/job/team alone do not qualify.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Prompt = '')

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return $false }

    # Alone / social-work words - never portfolio-shaped by vocabulary alone
    if ($q -match '(?i)^(project|projects|work|job|jobs|team|teams)[.!?]*$') {
        return $false
    }

    # Ticket ids (6-8 digit) or R8AB-style tracking
    if ($q -match '(?i)\b\d{6,8}\b' -or $q -match '(?i)\bR8[A-Z0-9]{6,}\b') {
        return $true
    }

    if ($q -match '(?i)\b(orion|solarwinds|colleague|brightspace|jitterbit|tickettracker|datamart|iwudata|pharos|thrive|webadvisor|wagc|wafm|isupport)\b') {
        return $true
    }

    if ($q -match '(?i)\b(\.\\)?metra\.ps1\b|\b(metra\s+(routing|ctx|inspect|ask|capture|profile))\b') {
        return $true
    }

    # Explicit portfolio/ops status phrasing - not bare "project" / "work"
    if ($q -match '(?i)\b(active projects?|what projects are|desk status|attention items?|ops status|portfolio (status|refresh)|route status)\b') {
        return $true
    }

    return $false
}

function Test-MetraAskPortfolioShapedTurn {
    <#
    .SYNOPSIS
        Deterministic portfolio-shaped classification (server-side intent/evidence - not client whim).
        Conservative: prefer false negative over treating social/generic work talk as portfolio-shaped.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Prompt = '',
        $Intent,
        $Handoff,
        $ContinuityEvidence,
        [int]$RouteScore = 0
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default '')
    # Execute/route-class intents are portfolio-shaped. Bare generic work is not.
    if ($intentClass -in @('component_status', 'authority_write', 'capture')) {
        return $true
    }
    if ($intentClass -eq 'status_query') {
        # Status about named ops/portfolio only - not "how are you"
        if ((Test-MetraAskPortfolioVocabulary -Prompt $Prompt) -or
            $Prompt -match '(?i)\b(ops|desk|engine|orion|colleague|ticket|portfolio|running well)\b') {
            return $true
        }
        return $false
    }

    $where = [string](Get-MetraProp -Object $Handoff -Name 'where' -Default '')
    $score = [int](Get-MetraProp -Object $Handoff -Name 'score' -Default $RouteScore)
    if ($score -lt $RouteScore) { $score = $RouteScore }

    if (Test-MetraAskPortfolioVocabulary -Prompt $Prompt) {
        return $true
    }

    # Routed handoff to a real project home (not Metra catch-all)
    if ($score -ge 2 -and -not [string]::IsNullOrWhiteSpace($where) -and $where -ne 'Metra') {
        return $true
    }

    $scope = [string](Get-MetraProp -Object $ContinuityEvidence -Name 'ClaimScope' -Default 'none')
    $bound = [string](Get-MetraProp -Object $ContinuityEvidence -Name 'BoundProject' -Default '')
    if ($scope -in @('session_bound', 'factual_supported') -and -not [string]::IsNullOrWhiteSpace($bound)) {
        if ($intentClass -in @('check_in', 'capability', 'empty')) {
            # Continuity alone does not promote bare check-in; need anaphoric portfolio thread cue
            if ($Prompt -match '(?i)\b(that|the|our|this)\b.+\b(ticket|alert|colleague|orion|brightspace|jitterbit)\b' `
                    -or $Prompt -match '(?i)\b(continue|back to)\b.+\b(ticket|colleague|orion|that)\b' `
                    -or $Prompt -match '(?i)\b(about that|that Colleague|that ticket)\b') {
                return $true
            }
            return $false
        }
        if ($intentClass -eq 'work' -and (
                (Test-MetraAskPortfolioVocabulary -Prompt $Prompt) -or
                $Prompt -match '(?i)\b(that|the|our|this)\b.+\b(ticket|alert|colleague|orion|project)\b' `
                    -or $Prompt -match '(?i)\b(later|continue|back to|about that)\b.+\b(colleague|ticket|orion|alert)\b' `
                    -or $Prompt -match '(?i)\b(thinking about that Colleague|about that ticket)\b')) {
            return $true
        }
    }

    if ($Prompt -match '(?i)\b(what projects are active|desk (status|health)|any (alerts?|tickets?)|portfolio status)\b') {
        return $true
    }

    return $false
}

function New-MetraContinuityEvidence {
    <#
    .SYNOPSIS
        Typed ContinuityEvidence with claim-scope for partner identity continuity rules.
    #>
    [CmdletBinding()]
    param(
        $Continuity,
        $Handoff,
        [string]$BoundProject = ''
    )

    $recent = 0
    $factual = $false
    if ($null -ne $Continuity) {
        $recent = [int](Get-MetraProp -Object $Continuity -Name 'recentTurnCount' -Default 0)
        if ($recent -le 0) {
            $recent = [int](Get-MetraProp -Object $Continuity -Name 'totalTurnCount' -Default 0)
        }
        $fs = Get-MetraProp -Object $Continuity -Name 'factualSupport' -Default $null
        if ($null -ne $fs) {
            $factual = [bool]$fs
        }
        elseif ($null -ne (Get-MetraProp -Object $Continuity -Name 'factualSupportItems' -Default $null)) {
            $items = @(Get-MetraProp -Object $Continuity -Name 'factualSupportItems' -Default @())
            $factual = ($items.Count -gt 0)
        }
    }

    if ([string]::IsNullOrWhiteSpace($BoundProject) -and $null -ne $Handoff) {
        $w = [string](Get-MetraProp -Object $Handoff -Name 'where' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($w) -and $w -ne 'Metra') {
            $BoundProject = $w
        }
    }

    $claimScope = 'none'
    if ($factual -and -not [string]::IsNullOrWhiteSpace($BoundProject)) {
        $claimScope = 'factual_supported'
    }
    elseif ($recent -gt 0 -and -not [string]::IsNullOrWhiteSpace($BoundProject)) {
        $claimScope = 'session_bound'
    }
    elseif ($recent -gt 0) {
        $claimScope = 'session_bound'
    }

    return [PSCustomObject]@{
        SchemaVersion   = 1
        ClaimScope      = $claimScope
        RecentTurnCount = $recent
        BoundProject    = $BoundProject
        FactualSupport  = $factual
        AllowedClaims   = @(
            switch ($claimScope) {
                'factual_supported' { @('session_thread', 'bound_project', 'evidence_backed_recall'); break }
                'session_bound' { @('session_thread', 'bound_project_soft'); break }
                default { @() }
            }
        )
        ForbiddenClaims = @(
            'invented_biography'
            'unsupported_i_remember'
            'cross_session_personal_memory'
        )
    }
}

function Test-MetraContinuityClaimAllowed {
    <#
    .SYNOPSIS
        Whether a continuity claim kind is allowed for the evidence claim-scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ContinuityEvidence,
        [Parameter(Mandatory)][string]$ClaimKind
    )

    $forbidden = @(Get-MetraProp -Object $ContinuityEvidence -Name 'ForbiddenClaims' -Default @())
    if ($ClaimKind -in $forbidden) { return $false }
    $allowed = @(Get-MetraProp -Object $ContinuityEvidence -Name 'AllowedClaims' -Default @())
    if ($allowed.Count -eq 0) { return $false }
    return ($ClaimKind -in $allowed)
}

function New-MetraPartnerCheckInResponse {
    <#
    .SYNOPSIS
        Composable check-in: acknowledgement (+) optional evidence-backed observation. Cross-surface identity.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Ask', 'Cursor', 'Vision', 'iOS', 'OpsPresence')]
        [string]$Surface = 'Ask',

        [ValidateSet('Desk', 'Company', 'Deliver', 'DeskStrict', '')]
        [string]$Posture = '',

        $ContinuityEvidence,

        [AllowEmptyString()][string]$Observation = '',

        [switch]$WhoAreYou
    )

    $resolved = Get-MetraPartnerResolvedPostureName -Resolution (
        Resolve-MetraPartnerPosture -Surface $Surface -Posture $Posture
    )
    $ack = if ($WhoAreYou) {
        Get-MetraPartnerIdentitySelfDescription
    }
    else {
        "I'm here."
    }

    $obs = if ([string]::IsNullOrWhiteSpace($Observation)) { '' } else { $Observation.Trim() }
    $scope = [string](Get-MetraProp -Object $ContinuityEvidence -Name 'ClaimScope' -Default 'none')

    # Never invent unsupported continuity in check-in
    if ($obs -match '(?i)i remember where we left off' -and $scope -ne 'factual_supported') {
        $obs = ''
    }

    $display = if ([string]::IsNullOrWhiteSpace($obs)) { $ack } else { "$ack $obs" }

    return [PSCustomObject]@{
        Surface         = $Surface
        Posture         = $resolved
        Acknowledgement = $ack
        Observation     = $obs
        Display         = $display
        IdentityName    = 'Metra'
        ClaimScope      = $scope
    }
}

function Get-MetraPartnerPresenceLines {
    <#
    .SYNOPSIS
        Ops presence: identity acknowledgement vs evidence-backed observation (omit when empty/stale-all-clear).
    #>
    [CmdletBinding()]
    param(
        [int]$AttentionWaiting = 0,
        [AllowEmptyString()][string]$AttentionEmptyHint = '',
        [AllowNull()][Nullable[bool]]$GitChecked = $null,
        [switch]$IncidentActive
    )

    $posture = if ($IncidentActive) { 'DeskStrict' } else { 'Desk' }
    $ack = "I'm here."
    $obs = ''

    if ($AttentionWaiting -gt 1) {
        $obs = "$AttentionWaiting items ready for review."
    }
    elseif ($AttentionWaiting -eq 1) {
        $obs = 'One item ready for review.'
    }
    else {
        # Empty Attention: acknowledgement only - no invented "all clear" / "Clear for now"
        if (-not [string]::IsNullOrWhiteSpace($AttentionEmptyHint) -and
            $AttentionEmptyHint -match '(?i)not reviewed|quick check|light check|recheck|full refresh|Portfolio refresh') {
            $obs = $AttentionEmptyHint.Trim()
        }
        elseif ($GitChecked -eq $false) {
            $obs = 'Some areas were not reviewed - run Portfolio refresh to confirm.'
        }
    }

    $display = if ([string]::IsNullOrWhiteSpace($obs)) { $ack } else { "$ack $obs" }

    return [PSCustomObject]@{
        Surface         = 'OpsPresence'
        Posture         = $posture
        Acknowledgement = $ack
        Observation     = $obs
        Display         = $display
        HasObservation  = -not [string]::IsNullOrWhiteSpace($obs)
    }
}

function ConvertTo-MetraPartnerNeutralArtifact {
    <#
    .SYNOPSIS
        Strip partner conversational voice at Host/Capture/Ticket execution output boundary.
        Maps first-person partner framing to neutral artifact labels where useful.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text = '')

    $t = if ($null -eq $Text) { '' } else { $Text.Trim() }
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }

    # Drop first-person partner identity framing; keep factual content.
    $t = [regex]::Replace($t, "(?i)^I'm Metra[,.]?\s*(the portfolio operations partner[,.]?\s*)?", '')
    $t = [regex]::Replace($t, '(?i)^I am Metra[,.]?\s*(the portfolio operations partner[,.]?\s*)?', '')
    $t = [regex]::Replace($t, '(?i)\bAs Metra[,.]?\s*', '')
    $t = [regex]::Replace($t, "(?i)^I'm here[.!]?\s*", '')

    # Advise/voice -> durable labels (execution sink neutrality)
    if ($t -match '(?i)^I think the issue is\b[:\s]*(.*)$') {
        $rest = $Matches[1].Trim()
        $t = if ([string]::IsNullOrWhiteSpace($rest)) { 'Assessment:' } else { "Assessment: $rest" }
    }
    elseif ($t -match '(?i)^I think\b[:\s]*(.*)$') {
        $rest = $Matches[1].Trim()
        $t = if ([string]::IsNullOrWhiteSpace($rest)) { 'Assessment:' } else { "Assessment: $rest" }
    }
    elseif ($t -match '(?i)^I recommend\b[:\s]*(.*)$') {
        $rest = $Matches[1].Trim()
        $t = if ([string]::IsNullOrWhiteSpace($rest)) { 'Recommendation:' } else { "Recommendation: $rest" }
    }
    elseif ($t -match '(?i)^I would recommend\b[:\s]*(.*)$') {
        $rest = $Matches[1].Trim()
        $t = if ([string]::IsNullOrWhiteSpace($rest)) { 'Recommendation:' } else { "Recommendation: $rest" }
    }

    $t = $t.Trim()
    return $t
}

function Test-MetraPartnerIdentityAuthorityGate {
    <#
    .SYNOPSIS
        Identity never authorizes execution. Gate covers Host write / Capture / Ticket mutation only -
        not analysis, routing advice, or soft recommendations.
    #>
    [CmdletBinding()]
    param(
        $Intent,
        [AllowEmptyString()][string]$Prompt = ''
    )

    $intentClass = [string](Get-MetraProp -Object $Intent -Name 'IntentClass' -Default '')
    if ($intentClass -eq 'authority_write') {
        return [PSCustomObject]@{
            RequiresConfirm = $true
            Message         = 'OperatorConfirm: confirm any Host write at the desk (recommend/post/resolve) before I treat it as done.'
            ReasonCode      = 'authority_requires_confirm'
        }
    }

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) {
        return [PSCustomObject]@{ RequiresConfirm = $false; Message = ''; ReasonCode = '' }
    }

    # Advise / analyze / route - not execution
    if ($q -match '(?i)\b(what (do you|would you) recommend|recommend a (fix|route|approach)|how (should|would) (i|we)|analyze|troubleshoot|what.?s wrong)\b') {
        return [PSCustomObject]@{ RequiresConfirm = $false; Message = ''; ReasonCode = '' }
    }

    # Ticket mutation / Host write / Capture durable
    $execute = $false
    if ($q -match '(?i)\b(go ahead and (close|resolve|post|recommend)|just (close|resolve) it)\b') {
        $execute = $true
    }
    elseif ($q -match '(?i)\b(close|resolve)\b.+\b(ticket|isupport)\b' -or $q -match '(?i)\bclose ticket\s+\d{6,8}\b') {
        $execute = $true
    }
    elseif ($q -match '(?i)\b(post|recommend)\b.+\b(to (the )?ticket|on (the )?ticket|in isupport)\b') {
        $execute = $true
    }
    elseif ($q -match '(?i)\b(write|save|capture|park)\b.+\b(host|portfolio|ticket|capture inbox)\b') {
        $execute = $true
    }

    if ($execute) {
        return [PSCustomObject]@{
            RequiresConfirm = $true
            Message         = 'OperatorConfirm: confirm any Host write at the desk (recommend/post/resolve) before I treat it as done.'
            ReasonCode      = 'authority_requires_confirm'
        }
    }

    return [PSCustomObject]@{
        RequiresConfirm = $false
        Message         = ''
        ReasonCode      = ''
    }
}
