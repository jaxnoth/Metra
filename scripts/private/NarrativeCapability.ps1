# Narrative capability adapter - NL intent to Narrative runtime APIs.
# Allowed moves -> intent mapping -> move id. Never invent moves.

function Test-MetraNarrativeEnterCue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    $p = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ($p -match '(?i)\b(play|start|begin)\b.{0,40}\b(narrative|adventure|lesson|scenario|derelict|station)\b') { return $true }
    if ($p -match '(?i)\bnarrative\s+start\b') { return $true }
    if ($p -match '(?i)\b(derelict[_\s-]?station|pbi[_\s-]?gateway[_\s-]?ha[_\s-]?prep)\b') { return $true }
    if ($p -match '(?i)\bstart\s+(lesson|adventure|scenario)\b') { return $true }
    return $false
}

function Resolve-MetraNarrativePackIdFromPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    $p = $Prompt.ToLowerInvariant()
    if ($p -match 'derelict') { return 'derelict_station' }
    if ($p -match 'pbi' -or $p -match 'gateway' -or $p -match 'ha[_\s-]?prep' -or $p -match 'lesson') {
        return 'pbi_gateway_ha_prep'
    }
    $packs = @(Get-MetraNarrativePacks -MetraRoot $MetraRoot)
    foreach ($pack in $packs) {
        $id = [string]$pack.PackId
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $pattern = (($id -split '_') | ForEach-Object { [regex]::Escape($_) }) -join '[_\s-]*'
        if ($p -match $pattern) { return $id }
    }
    return 'derelict_station'
}

function Test-MetraNarrativeExplicitLeaveCue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    $p = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ($p -match '(?i)^(end|stop|quit|exit)(\s+(the\s+)?(adventure|narrative|scenario|lesson|session))?\.?$') { return $true }
    if ($p -match '(?i)\b(end|stop|quit|leave)\s+(the\s+)?(adventure|narrative|scenario|lesson)\b') { return $true }
    if ($p -match '(?i)\bnarrative\s+end\b') { return $true }
    return $false
}

function Test-MetraNarrativeCrossCarCue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    $p = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if (Test-MetraNarrativeExplicitLeaveCue -Prompt $p) { return $false }
    if (Test-MetraNarrativeEnterCue -Prompt $p) { return $false }
    # Ticket id
    if ($p -match '(?<![A-Za-z0-9])\d{6,8}(?![A-Za-z0-9])') { return $true }
    if ($p -match '(?i)\bR8[A-Z0-9]{6,}\b') { return $true }
    # Live / investigate vocabulary
    if ($p -match '(?i)\b(check|investigate|look\s+at|debug|troubleshoot)\b.{0,60}\b(sql|replication|orion|solarwinds|alert|outage|colleague|stuck\s+session|jitterbit|datamanager)\b') {
        return $true
    }
    if ($p -match '(?i)\b(live\s+investigate|open\s+ticket|ticket\s+\d{6,8})\b') { return $true }
    if ($p -match '(?i)\b(sql\s+replication|check\s+replication)\b') { return $true }
    return $false
}

function Test-MetraCapabilityLeaveAffirm {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    $p = if ($null -eq $Prompt) { '' } else { $Prompt.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ($p -match '^(yes|y|yeah|yep|affirm|confirm|ok|okay|sure|leave|switch|go ahead|do it)(\s|$)') { return $true }
    if ($p -match '\b(yes[,.]?\s+)?(leave|switch|exit)\b') { return $true }
    if ($p -match '\bleave\s+(narrative|the\s+car|adventure)\b') { return $true }
    return $false
}

function Test-MetraCapabilityLeaveDecline {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Prompt)
    $p = if ($null -eq $Prompt) { '' } else { $Prompt.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if ($p -match '^(no|n|nope|nah|stay|cancel|never\s*mind|nevermind)(\s|$)') { return $true }
    if ($p -match '\b(stay|keep\s+playing|don''t\s+leave|do\s+not\s+leave)\b') { return $true }
    return $false
}

function Resolve-MetraNarrativeMoveIdFromPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllowedMoves
    )
    $moves = @($AllowedMoves)
    if ($moves.Count -eq 0) { return $null }
    $p = $Prompt.Trim().ToLowerInvariant()
    # Numbered choice (Clues-style / training face): "1", "2.", "option 3"
    if ($p -match '^(?:option\s+|choice\s+|#)?(\d+)\.?$') {
        $n = [int]$Matches[1]
        if ($n -ge 1 -and $n -le $moves.Count) {
            $id = [string](Get-MetraProp -Object $moves[$n - 1] -Name 'id' -Default '')
            if ($id) {
                return [PSCustomObject]@{ kind = 'move'; moveId = $id; ambiguous = $false }
            }
        }
    }
    # Exact id
    foreach ($m in $moves) {
        $id = [string](Get-MetraProp -Object $m -Name 'id' -Default '')
        if ($id -and ($p -eq $id -or $p -eq "move $id" -or $p -match ("(?i)\b" + [regex]::Escape($id) + "\b"))) {
            return [PSCustomObject]@{ kind = 'move'; moveId = $id; ambiguous = $false }
        }
    }
    # Label / description token overlap
    $hits = New-Object System.Collections.Generic.List[object]
    foreach ($m in $moves) {
        $id = [string](Get-MetraProp -Object $m -Name 'id' -Default '')
        $label = [string](Get-MetraProp -Object $m -Name 'label' -Default '')
        $desc = [string](Get-MetraProp -Object $m -Name 'description' -Default '')
        $hay = (@($id, $label, $desc) -join ' ').ToLowerInvariant()
        $tokens = @($hay -split '[^a-z0-9]+' | Where-Object { $_.Length -ge 4 } | Select-Object -Unique)
        $score = 0
        foreach ($t in $tokens) {
            if ($p -match ("\b" + [regex]::Escape($t) + "\b")) { $score++ }
        }
        # underscore parts of id
        foreach ($part in @($id -split '_')) {
            if ($part.Length -ge 3 -and $p -match ("\b" + [regex]::Escape($part) + "\b")) { $score++ }
        }
        if ($score -gt 0) {
            [void]$hits.Add([PSCustomObject]@{ moveId = $id; score = $score; label = $label })
        }
    }
    if ($hits.Count -eq 0) { return $null }
    $ranked = @($hits | Sort-Object score -Descending)
    $best = $ranked[0]
    $tied = @($ranked | Where-Object { $_.score -eq $best.score })
    if ($tied.Count -gt 1) {
        return [PSCustomObject]@{
            kind       = 'clarify'
            moveId     = $null
            ambiguous  = $true
            candidates = @($tied | ForEach-Object { $_.moveId })
        }
    }
    return [PSCustomObject]@{ kind = 'move'; moveId = [string]$best.moveId; ambiguous = $false }
}

function New-MetraNarrativeCapabilityResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$SessionId,
        [object]$Status = $null,
        [object]$LeaveConfirm = $null,
        [string[]]$LeaveHints = @(),
        [string]$AnswerType = 'narrative',
        [string]$NextStep = '',
        [bool]$Answered = $true,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $allowed = @()
    $sessionState = $null
    $packId = $null
    $runtimeSessionId = $null
    if ($null -ne $Status) {
        $allowed = @($Status.allowedMoves)
        $runtimeSessionId = [string]$Status.sessionId
        $packId = [string]$Status.packId
        $sessionState = [PSCustomObject]@{
            lifecycle = [string]$Status.lifecycle
            terminal  = [string]$Status.terminal
            packId    = $packId
            title     = [string]$Status.title
            state     = $Status.state
        }
    }

    $handoff = [PSCustomObject]@{
        query     = $Prompt
        kind      = 'capability'
        preview   = $false
        where     = 'Narrative'
        what      = 'Narrative capability car (Ask face).'
        why       = @('Active capability bind beats portfolio stem scoring.')
        forWhom   = @()
        next      = $(if ($NextStep) { $NextStep } else { 'Choose an allowed move, ask for status/narrate, or end the adventure.' })
        ambiguous = $false
        runnerUp  = $null
        score     = 99
        note      = 'capability_bind'
    }

    return [PSCustomObject]@{
        handoff                      = $handoff
        message                      = $Message
        sessionId                    = $SessionId
        capability                   = $null
        engine                       = $null
        model                        = $null
        answered                     = $Answered
        answerType                   = $AnswerType
        evidenceQuality              = 'adequate'
        nextStep                     = [string]$handoff.next
        continuity                   = $null
        secretsScrubbed              = $false
        secretsNotice                = $null
        secretsKinds                 = @()
        secretsReason                = $null
        scrubbedPrompt               = $Prompt
        suggestCapture               = $false
        allowedMoves                 = $allowed
        sessionState                 = $sessionState
        leaveConfirm                 = $LeaveConfirm
        leaveHints                   = @($LeaveHints)
        capabilityBind               = [PSCustomObject]@{
            capability      = 'narrative'
            runtimeSessionId = $runtimeSessionId
            packId          = $packId
        }
        responseObjective            = $(if ($LeaveConfirm) { 'OperatorConfirm' } else { 'NarrativeTurn' })
        conversationExecutionEnabled = $false
        reasonCode                   = 'capability_narrative'
    }
}

function Get-MetraNarrativeLeaveHints {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Status)
    $hints = New-Object System.Collections.Generic.List[string]
    $term = [string](Get-MetraProp -Object $Status -Name 'terminal' -Default '')
    $life = [string](Get-MetraProp -Object $Status -Name 'lifecycle' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($term)) { [void]$hints.Add('terminal') }
    if ($life -eq 'forgotten') { [void]$hints.Add('forgotten') }
    if ($life -eq 'archived' -or $life -eq 'ended') { [void]$hints.Add('ended') }
    return @($hints)
}

function Invoke-MetraNarrativeCapabilityTurn {
    <#
    .SYNOPSIS
        One Ask turn against the Narrative capability car (start/status/move/narrate/end).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$SessionId,
        [object]$Bind = $null,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$FallbackNarrate
    )

    $q = $Prompt.Trim()

    # Unbound enter
    if ($null -eq $Bind) {
        if (-not (Test-MetraNarrativeEnterCue -Prompt $q)) { return $null }
        $packId = Resolve-MetraNarrativePackIdFromPrompt -Prompt $q -MetraRoot $MetraRoot
        $status = Start-MetraNarrativeSession -PackId $packId -MetraRoot $MetraRoot
        [void](Set-MetraCapabilityBind -SessionId $SessionId -Capability 'narrative' `
                -RuntimeSessionId ([string]$status.sessionId) -PackId ([string]$status.packId) -MetraRoot $MetraRoot)
        $narr = Invoke-MetraNarrativeNarrate -SessionId $status.sessionId -MetraRoot $MetraRoot -FallbackOnly:$FallbackNarrate
        $msg = [string]$narr.text
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId `
            -Status $status -LeaveHints @(Get-MetraNarrativeLeaveHints -Status $status) -MetraRoot $MetraRoot `
            -NextStep 'Reply with a choice number, move id, or plain wording.'
    }

    $runtimeSessionId = [string](Get-MetraProp -Object $Bind -Name 'runtimeSessionId' -Default '')
    $status = $null
    try {
        $status = Get-MetraNarrativeSessionStatus -SessionId $runtimeSessionId -MetraRoot $MetraRoot
    }
    catch {
        Clear-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot | Out-Null
        return New-MetraNarrativeCapabilityResult -Message "Narrative session is unavailable ($($_.Exception.Message)). Bind cleared." `
            -Prompt $q -SessionId $SessionId -AnswerType 'narrative_cleared' -Answered $true `
            -NextStep 'Start again with play derelict station or narrative start.' -MetraRoot $MetraRoot
    }

    $hints = @(Get-MetraNarrativeLeaveHints -Status $status)
    $isTerminal = $hints -contains 'terminal' -or $hints -contains 'forgotten' -or $hints -contains 'ended'

    # Metra accepts terminal leave hints - reply with scene epilogue, not bind machinery
    if ($isTerminal) {
        Clear-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot | Out-Null
        $msg = New-MetraNarrativeFallbackText -Status $status -MetraRoot $MetraRoot
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -AnswerType 'narrative_terminal' -NextStep 'Ask normally, or start another scenario.' `
            -MetraRoot $MetraRoot
    }

    # Pending leave confirm resolution
    $pending = Get-MetraProp -Object $Bind -Name 'pendingLeaveConfirm' -Default $null
    if ($null -ne $pending) {
        if (Test-MetraCapabilityLeaveAffirm -Prompt $q) {
            $prior = [string](Get-MetraProp -Object $pending -Name 'prompt' -Default '')
            Clear-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot | Out-Null
            return [PSCustomObject]@{
                __capabilityLeaveAffirmed = $true
                priorPrompt               = $prior
                sessionId                 = $SessionId
            }
        }
        if (Test-MetraCapabilityLeaveDecline -Prompt $q) {
            [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -ClearPendingLeave -MetraRoot $MetraRoot)
            $msg = "Staying in $($status.title). Choose an allowed move, or say status / narrate / end."
            return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
                -LeaveHints $hints -MetraRoot $MetraRoot
        }
        # Still pending - restate confirm unless they issued a narrative action
    }

    if (Test-MetraNarrativeExplicitLeaveCue -Prompt $q) {
        try { [void](Stop-MetraNarrativeSession -SessionId $runtimeSessionId -MetraRoot $MetraRoot -Summary 'ended via Ask face') } catch { }
        Clear-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot | Out-Null
        return New-MetraNarrativeCapabilityResult -Message "Left Narrative car ($($status.title)). Bind cleared." `
            -Prompt $q -SessionId $SessionId -AnswerType 'narrative_left' -NextStep 'Ask normally, or start another scenario.' `
            -MetraRoot $MetraRoot
    }

    if (Test-MetraNarrativeCrossCarCue -Prompt $q) {
        $confirm = [PSCustomObject]@{
            required = $true
            prompt   = $q
            packId   = [string]$status.packId
            title    = [string]$status.title
            message  = "You're currently in $($status.title). Leave narrative and investigate that instead?"
        }
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -PendingLeaveConfirm $confirm -MetraRoot $MetraRoot)
        $msg = "$([string]$confirm.message)`nSay yes to leave, or no to stay."
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveConfirm $confirm -LeaveHints $hints -AnswerType 'leave_confirm' -Answered $true `
            -NextStep 'Confirm leave, or stay and pick an allowed move.' -MetraRoot $MetraRoot
    }

    # Status / narrate / moves list
    if ($q -match '(?i)^(status|where\s+am\s+i|what.?s\s+my\s+state)\.?$') {
        $msg = New-MetraNarrativeFallbackText -Status $status -MetraRoot $MetraRoot
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -MetraRoot $MetraRoot)
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -MetraRoot $MetraRoot
    }
    if ($q -match '(?i)^(narrate|describe|look\s+around|what\s+do\s+i\s+see)\.?$') {
        $narr = Invoke-MetraNarrativeNarrate -SessionId $runtimeSessionId -MetraRoot $MetraRoot -FallbackOnly:$FallbackNarrate
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -MetraRoot $MetraRoot)
        return New-MetraNarrativeCapabilityResult -Message ([string]$narr.text) -Prompt $q -SessionId $SessionId `
            -Status $status -LeaveHints $hints -MetraRoot $MetraRoot
    }
    if ($q -match '(?i)^(moves|options|what\s+can\s+i\s+do)\.?$') {
        $msg = Format-MetraNarrativeChoiceBlock -AllowedMoves @($status.allowedMoves)
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = 'No moves available.' }
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -MetraRoot $MetraRoot)
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -MetraRoot $MetraRoot
    }

    $mapped = Resolve-MetraNarrativeMoveIdFromPrompt -Prompt $q -AllowedMoves @($status.allowedMoves)
    if ($null -eq $mapped) {
        # Pending confirm restatement if still open and no move matched
        if ($null -ne $pending) {
            $msg = [string](Get-MetraProp -Object $pending -Name 'message' -Default 'Leave narrative?')
            return New-MetraNarrativeCapabilityResult -Message "$msg`nSay yes to leave, or no to stay." `
                -Prompt $q -SessionId $SessionId -Status $status -LeaveConfirm $pending -LeaveHints $hints `
                -AnswerType 'leave_confirm' -MetraRoot $MetraRoot
        }
        $choice = Format-MetraNarrativeChoiceBlock -AllowedMoves @($status.allowedMoves)
        $msg = "That did not match a choice.`n$choice"
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -MetraRoot $MetraRoot)
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -MetraRoot $MetraRoot
    }
    if ($mapped.kind -eq 'clarify') {
        $msg = "Which move? " + (($mapped.candidates) -join ', ')
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -AnswerType 'clarify' -MetraRoot $MetraRoot
    }

    try {
        $status = Invoke-MetraNarrativeMove -MoveId ([string]$mapped.moveId) -SessionId $runtimeSessionId -MetraRoot $MetraRoot
    }
    catch {
        $choice = Format-MetraNarrativeChoiceBlock -AllowedMoves @($status.allowedMoves)
        $msg = "Move failed: $($_.Exception.Message)`n$choice"
        return New-MetraNarrativeCapabilityResult -Message $msg -Prompt $q -SessionId $SessionId -Status $status `
            -LeaveHints $hints -Answered $true -MetraRoot $MetraRoot
    }

    $hints = @(Get-MetraNarrativeLeaveHints -Status $status)
    if ($hints -contains 'terminal') {
        Clear-MetraCapabilityBind -SessionId $SessionId -MetraRoot $MetraRoot | Out-Null
    }
    else {
        [void](Update-MetraCapabilityBindTouch -SessionId $SessionId -ClearPendingLeave -MetraRoot $MetraRoot)
    }
    $narr = Invoke-MetraNarrativeNarrate -SessionId $runtimeSessionId -MetraRoot $MetraRoot -FallbackOnly:$FallbackNarrate
    return New-MetraNarrativeCapabilityResult -Message ([string]$narr.text) -Prompt $q -SessionId $SessionId -Status $status `
        -LeaveHints $hints -MetraRoot $MetraRoot
}

