# Yarn hash / pack-freshness helpers.

function Get-YarnCanonicalText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $t = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $t -split "`n" | ForEach-Object { $_.TrimEnd() }
    return ($lines -join "`n")
}

function Get-YarnSha256Hex {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Get-YarnSourceHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$NormalizedSourceText)
    return Get-YarnSha256Hex -Text (Get-YarnCanonicalText -Text $NormalizedSourceText)
}

function Get-YarnPlanContentForHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$PlanText)
    # Frozen desk contract: UTF-8 + LF (via Get-YarnCanonicalText) then exclude
    # workflow keys from YAML frontmatter only (opening --- through closing ---).
    # Keys must stay aligned with Get-YarnPlanWorkflowFrontmatterKeys / Surveyor planContentHash.
    $exclude = @(
        'externalReviewed', 'externalReviewHash',
        'approveForLoom', 'approveForLoomHash',
        'status', 'loomHandoffId', 'loomAcceptedAt',
        'packedAt', 'packPlanPath', 'packInputHash', 'bingReviewed',
        'approvedAt', 'approvedBy', 'approvalId', 'approvalRevision'
    )
    $excludeAlt = ($exclude -join '|')
    $canonical = Get-YarnCanonicalText -Text $PlanText
    $lines = @($canonical -split "`n")
    $filtered = New-Object System.Collections.Generic.List[string]
    if ($lines.Count -eq 0 -or $lines[0] -ne '---') {
        return ($lines -join "`n")
    }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) {
        return ($lines -join "`n")
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($i -gt 0 -and $i -lt $end -and ($line -match ("^\s*($excludeAlt)\s*:"))) {
            continue
        }
        [void]$filtered.Add($line)
    }
    return ($filtered -join "`n")
}

function Get-YarnPlanContentHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$PlanText)
    return Get-YarnSha256Hex -Text (Get-YarnPlanContentForHash -PlanText $PlanText)
}

function Get-YarnPackInputHash {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PlanText,
        [string]$PackContractVersion = (Get-YarnPackContractVersion)
    )
    $body = (Get-YarnPlanContentForHash -PlanText $PlanText) + "`npackContractVersion=$PackContractVersion"
    return Get-YarnSha256Hex -Text $body
}

function Test-YarnPackFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PlanText,
        [string]$RecordedPlanContentHash,
        [string]$RecordedPackInputHash,
        [string]$RecordedPackContractVersion,
        [bool]$LastPackSucceeded = $false
    )
    if (-not $LastPackSucceeded) {
        return [PSCustomObject]@{ fresh = $false; reason = 'pack-not-successful' }
    }
    $currentPlan = Get-YarnPlanContentHash -PlanText $PlanText
    $currentPack = Get-YarnPackInputHash -PlanText $PlanText
    $contract = Get-YarnPackContractVersion
    if ([string]$RecordedPackContractVersion -ne [string]$contract) {
        return [PSCustomObject]@{ fresh = $false; reason = 'pack-contract-mismatch'; currentPlanContentHash = $currentPlan }
    }
    if ([string]$RecordedPlanContentHash -ne [string]$currentPlan) {
        return [PSCustomObject]@{ fresh = $false; reason = 'plan-content-changed'; currentPlanContentHash = $currentPlan }
    }
    if ([string]$RecordedPackInputHash -ne [string]$currentPack) {
        return [PSCustomObject]@{ fresh = $false; reason = 'pack-input-changed'; currentPlanContentHash = $currentPlan }
    }
    return [PSCustomObject]@{
        fresh                 = $true
        reason                = 'ok'
        currentPlanContentHash = $currentPlan
        currentPackInputHash   = $currentPack
    }
}
