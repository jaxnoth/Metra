# Company spark-or-quiet helpers (shared contract; iOS owns emit). Caps restrict, never authorize.

function Test-MetraCompanySparkEligibility {
    <#
    .SYNOPSIS
        Default-deny spark eligibility (quiet episode, 1/episode, 5m cooldown, <=3/hour).
    #>
    [CmdletBinding()]
    param(
        [bool]$IsCompany = $false,
        [bool]$SilenceOk = $false,
        [bool]$OpenEnergy = $false,
        [bool]$QuietEpisodeActive = $false,
        [bool]$SparkAlreadyThisEpisode = $false,
        [datetime]$LastSparkAt,
        [datetime[]]$SparkTimestampsHour = @(),
        [datetime]$NowUtc = [datetime]::UtcNow,
        [int]$CooldownSeconds = 300,
        [int]$MaxPerHour = 3
    )

    if (-not $IsCompany -or -not $SilenceOk) {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'not_company_silence' }
    }
    if (-not $OpenEnergy) {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'closed_energy' }
    }
    if (-not $QuietEpisodeActive) {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'no_quiet_episode' }
    }
    if ($SparkAlreadyThisEpisode) {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'already_sparked_this_episode' }
    }
    if ($PSBoundParameters.ContainsKey('LastSparkAt')) {
        $last = [datetime]$LastSparkAt
        if ($last.Kind -ne [DateTimeKind]::Utc) { $last = $last.ToUniversalTime() }
        if (($NowUtc.ToUniversalTime() - $last).TotalSeconds -lt $CooldownSeconds) {
            return [PSCustomObject]@{ Eligible = $false; Reason = 'cooldown_5m' }
        }
    }
    $hourAgo = $NowUtc.ToUniversalTime().AddHours(-1)
    $inHour = @($SparkTimestampsHour | Where-Object {
            $t = [datetime]$_
            if ($t.Kind -ne [DateTimeKind]::Utc) { $t = $t.ToUniversalTime() }
            $t -ge $hourAgo
        }).Count
    if ($inHour -ge $MaxPerHour) {
        return [PSCustomObject]@{ Eligible = $false; Reason = 'hourly_cap' }
    }
    return [PSCustomObject]@{ Eligible = $true; Reason = 'eligible' }
}

function Test-MetraSeamAuthorization {
    <#
    .SYNOPSIS
        Anti-flatness seam gate - Company + open energy; skip closed/DeskStrict.
    #>
    [CmdletBinding()]
    param(
        [bool]$IsCompany = $false,
        [bool]$OpenEnergy = $false,
        [bool]$DeskStrict = $false,
        [bool]$ClosedCommandTurn = $false
    )

    if ($DeskStrict) { return [PSCustomObject]@{ Allow = $false; Reason = 'desk_strict' } }
    if (-not $IsCompany) { return [PSCustomObject]@{ Allow = $false; Reason = 'not_company' } }
    if ($ClosedCommandTurn) { return [PSCustomObject]@{ Allow = $false; Reason = 'closed_command' } }
    if (-not $OpenEnergy) { return [PSCustomObject]@{ Allow = $false; Reason = 'closed_energy' } }
    return [PSCustomObject]@{ Allow = $true; Reason = 'park_or_continue' }
}

function Test-MetraResumeCallbackAuthorized {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$ParkedThreadId = '')

    return -not [string]::IsNullOrWhiteSpace($ParkedThreadId)
}
