# Metra capability dispatch - conductor between faces and capability cars.
# Active bind beats portfolio routing. Engines nominate leave hints; Metra decides.

function Invoke-MetraCapabilityDispatchTurn {
    <#
    .SYNOPSIS
        If this Ask turn belongs to a bound capability (or clear enter cue), handle it.
        Returns a desk Ask result object, or $null to continue normal Ask routing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [string]$SessionId,
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$FallbackNarrate
    )

    $q = if ($null -eq $Prompt) { '' } else { $Prompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($q)) { return $null }

    $sess = if ([string]::IsNullOrWhiteSpace($SessionId)) { '' } else { $SessionId.Trim() }
    if ([string]::IsNullOrWhiteSpace($sess)) {
        # Enter cues can mint a session so the car can stick on later turns.
        if (Test-MetraNarrativeEnterCue -Prompt $q) {
            $sess = [guid]::NewGuid().ToString('N')
        }
        else {
            return $null
        }
    }
    elseif (-not (Test-MetraCapabilityBindSessionId -SessionId $sess)) {
        return $null
    }

    $bind = Get-MetraCapabilityBind -SessionId $sess -MetraRoot $MetraRoot
    $cap = if ($null -eq $bind) { '' } else { [string](Get-MetraProp -Object $bind -Name 'capability' -Default '') }

    if ($cap -eq 'narrative' -or ($null -eq $bind -and (Test-MetraNarrativeEnterCue -Prompt $q))) {
        $turn = Invoke-MetraNarrativeCapabilityTurn -Prompt $q -SessionId $sess -Bind $bind `
            -MetraRoot $MetraRoot -FallbackNarrate:$FallbackNarrate
        if ($null -eq $turn) { return $null }

        # Affirm leave: clear already done; signal caller to resume portfolio Ask with prior prompt.
        if ([bool](Get-MetraProp -Object $turn -Name '__capabilityLeaveAffirmed' -Default $false)) {
            return $turn
        }

        if (-not $turn.PSObject.Properties['sessionId'] -or [string]::IsNullOrWhiteSpace([string]$turn.sessionId)) {
            $turn | Add-Member -NotePropertyName sessionId -NotePropertyValue $sess -Force
        }
        return $turn
    }

    # Future capabilities plug in here.
    return $null
}
