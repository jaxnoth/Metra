# Conversation Identity Stack - frozen allowlisted manifest for Vision (and shared loaders).
# Manifest order is authoritative; never discover packs via Get-ChildItem / wildcard globs.
# Loader is the sole authority for TeachingActive / HumorActive.

Set-StrictMode -Version Latest

$script:MetraConversationIdentityManifestVersion = 1
$script:MetraConversationIdentityDefaultBudgetBytes = 48KB

function Get-MetraConversationIdentityNarrativeFace {
    <#
    .SYNOPSIS
        Fixed Narrative face ceilings for the identity stack (not Narrative Engine state).
    #>
    [CmdletBinding()]
    param()

    return @'
## Narrative face (not Narrative Engine)
- You do not own narrative state, scoring, or Ink story truth.
- Narration on Vision is transient; bound sessions use narrative APIs.
- Casual Vision turns are not auto-scenario play.
- Do not invent scenario progress or story JSON.
'@
}

function Get-MetraConversationIdentityManifest {
    <#
    .SYNOPSIS
        Frozen ordered allowlist for Conversation Identity sources. Pure data - no I/O.
    #>
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'partner'; Kind = 'runtime'; RelativePath = $null; BudgetTier = 0; AllowlistedAddon = $false }
        [pscustomobject]@{ Id = 'persona'; Kind = 'file'; RelativePath = '.cursor/rules/metra-persona.mdc'; BudgetTier = 1; AllowlistedAddon = $false }
        [pscustomobject]@{ Id = 'overlay'; Kind = 'file'; RelativePath = '.cursor/rules/metra-persona.local.mdc'; BudgetTier = 2; AllowlistedAddon = $false }
        [pscustomobject]@{ Id = 'occ'; Kind = 'file'; RelativePath = '.cursor/rules/metra-learned.local.mdc'; BudgetTier = 2; AllowlistedAddon = $false }
        [pscustomobject]@{ Id = 'humor'; Kind = 'add-on'; RelativePath = '.cursor/rules/metra-humor.local.mdc'; BudgetTier = 3; AllowlistedAddon = $true }
        [pscustomobject]@{ Id = 'teaching'; Kind = 'add-on'; RelativePath = '.cursor/rules/metra-teaching-gentle.local.mdc'; BudgetTier = 3; AllowlistedAddon = $true }
        [pscustomobject]@{ Id = 'vision'; Kind = 'file'; RelativePath = 'engines/vision-ask/system.md'; BudgetTier = 0; AllowlistedAddon = $false }
        [pscustomobject]@{ Id = 'narrative'; Kind = 'runtime'; RelativePath = $null; BudgetTier = 0; AllowlistedAddon = $false }
    )
}

function ConvertFrom-MetraConversationIdentityFrontmatter {
    <#
    .SYNOPSIS
        Strip leading YAML frontmatter (--- ... ---) from a Cursor rule / markdown file body.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized -notmatch '(?s)\A---\n.*?\n---\n?(.*)\z') {
        return $Text.Trim()
    }
    return $Matches[1].Trim()
}

function Get-MetraConversationIdentitySources {
    <#
    .SYNOPSIS
        Walk the frozen manifest and report existence. Never enumerates directories for discovery.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $root = [System.IO.Path]::GetFullPath($MetraRoot)
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-MetraConversationIdentityManifest)) {
        $exists = $false
        $fullPath = $null
        if ($entry.Kind -eq 'file' -or $entry.Kind -eq 'add-on') {
            $rel = ([string]$entry.RelativePath).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $rel))
            $exists = Test-Path -LiteralPath $fullPath
        }
        elseif ($entry.Kind -eq 'runtime') {
            $exists = $true
        }
        $out.Add([pscustomobject]@{
                Id               = [string]$entry.Id
                Kind             = [string]$entry.Kind
                RelativePath     = $entry.RelativePath
                FullPath         = $fullPath
                Exists           = [bool]$exists
                BudgetTier      = [int]$entry.BudgetTier
                AllowlistedAddon = [bool]$entry.AllowlistedAddon
            }) | Out-Null
    }
    return @($out)
}

function Test-MetraConversationIdentityPackActive {
    <#
    .SYNOPSIS
        True when an allowlisted add-on file exists for the given id (humor|teaching).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('humor', 'teaching')]
        [string]$Id,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $entry = @(Get-MetraConversationIdentityManifest) | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $entry -or -not [bool]$entry.AllowlistedAddon) {
        return $false
    }
    $rel = ([string]$entry.RelativePath).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $full = Join-Path $MetraRoot $rel
    return (Test-Path -LiteralPath $full)
}

function Resolve-MetraConversationIdentityPackGates {
    <#
    .SYNOPSIS
        Sole authority for HumorActive / TeachingActive given posture and teachingWanted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Posture,
        [switch]$IncidentActive,
        [switch]$TeachingWanted,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $postureName = $Posture.Trim()
    if ($IncidentActive) { $postureName = 'DeskStrict' }

    $humorFile = Test-MetraConversationIdentityPackActive -Id humor -MetraRoot $MetraRoot
    $teachingFile = Test-MetraConversationIdentityPackActive -Id teaching -MetraRoot $MetraRoot

    $humorActive = $false
    if ($humorFile -and $postureName -ne 'DeskStrict') {
        $humorActive = $true
    }

    $teachingActive = $false
    if ($teachingFile -and $postureName -ne 'DeskStrict') {
        if ($postureName -eq 'Company' -or $postureName -eq 'Deliver') {
            $teachingActive = $true
        }
        elseif ($postureName -eq 'Desk' -and $TeachingWanted) {
            $teachingActive = $true
        }
    }

    return [pscustomobject]@{
        HumorActive    = [bool]$humorActive
        TeachingActive = [bool]$teachingActive
        HumorFile      = [bool]$humorFile
        TeachingFile   = [bool]$teachingFile
        Posture        = $postureName
    }
}

function Get-MetraConversationIdentityHash {
    <#
    .SYNOPSIS
        SHA-256 hex of UTF-8 text, truncated for telemetry (default 16 chars).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [int]$TruncateChars = 16
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    if ($TruncateChars -gt 0 -and $hex.Length -gt $TruncateChars) {
        return $hex.Substring(0, $TruncateChars)
    }
    return $hex
}

function Get-MetraConversationIdentityPrompt {
    <#
    .SYNOPSIS
        Assemble Conversation Identity Stack text + loader metadata (sole teaching/humor authority).
    .NOTES
        identityHash is computed after frontmatter strip and after budget truncation.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [ValidateSet('Desk', 'Company', 'Deliver', 'DeskStrict', '')]
        [string]$Posture = 'Company',
        [switch]$PortfolioShaped,
        [switch]$IncidentActive,
        [switch]$TeachingWanted,
        $ContinuityEvidence,
        [int]$BudgetBytes = 0
    )

    if ($BudgetBytes -le 0) {
        $BudgetBytes = [int]$script:MetraConversationIdentityDefaultBudgetBytes
    }

    $resolvedPosture = if ([string]::IsNullOrWhiteSpace($Posture)) { 'Company' } else { $Posture }
    if ($IncidentActive) { $resolvedPosture = 'DeskStrict' }

    $gates = Resolve-MetraConversationIdentityPackGates `
        -Posture $resolvedPosture `
        -IncidentActive:$IncidentActive `
        -TeachingWanted:$TeachingWanted `
        -MetraRoot $MetraRoot

    $packsIncluded = [System.Collections.Generic.List[string]]::new()
    $packsOmitted = [System.Collections.Generic.List[object]]::new()
    $sections = [System.Collections.Generic.List[object]]::new()

    $partnerText = if (Get-Command New-MetraPartnerIdentityPreamble -ErrorAction SilentlyContinue) {
        New-MetraPartnerIdentityPreamble `
            -Surface Vision `
            -Posture $resolvedPosture `
            -PortfolioShaped:$PortfolioShaped `
            -ContinuityEvidence $ContinuityEvidence
    }
    else {
        "I'm Metra, the portfolio operations partner. Surface=Vision."
    }

    foreach ($src in @(Get-MetraConversationIdentitySources -MetraRoot $MetraRoot)) {
        $id = [string]$src.Id
        $tier = [int]$src.BudgetTier
        $body = $null
        $omitReason = $null

        switch ($id) {
            'partner' {
                $body = $partnerText
            }
            'narrative' {
                $body = Get-MetraConversationIdentityNarrativeFace
            }
            'humor' {
                if (-not $src.Exists) {
                    $omitReason = 'missing_file'
                }
                elseif (-not $gates.HumorActive) {
                    $omitReason = 'posture_gate'
                }
                else {
                    $raw = [System.IO.File]::ReadAllText($src.FullPath)
                    $body = ConvertFrom-MetraConversationIdentityFrontmatter -Text $raw
                    if ([string]::IsNullOrWhiteSpace($body)) { $omitReason = 'missing_file'; $body = $null }
                }
            }
            'teaching' {
                if (-not $src.Exists) {
                    $omitReason = 'missing_file'
                }
                elseif (-not $gates.TeachingActive) {
                    $omitReason = 'posture_gate'
                }
                else {
                    $raw = [System.IO.File]::ReadAllText($src.FullPath)
                    $body = ConvertFrom-MetraConversationIdentityFrontmatter -Text $raw
                    if ([string]::IsNullOrWhiteSpace($body)) { $omitReason = 'missing_file'; $body = $null }
                }
            }
            default {
                if ($src.Kind -eq 'file' -or $src.Kind -eq 'add-on') {
                    if (-not $src.Exists) {
                        $omitReason = 'missing_file'
                    }
                    else {
                        $raw = [System.IO.File]::ReadAllText($src.FullPath)
                        $body = ConvertFrom-MetraConversationIdentityFrontmatter -Text $raw
                        if ([string]::IsNullOrWhiteSpace($body)) { $omitReason = 'missing_file'; $body = $null }
                    }
                }
            }
        }

        if ($null -ne $omitReason) {
            $packsOmitted.Add([pscustomobject]@{ Id = $id; Reason = $omitReason }) | Out-Null
            continue
        }
        if ([string]::IsNullOrWhiteSpace($body)) {
            continue
        }

        $sections.Add([pscustomobject]@{
                Id         = $id
                BudgetTier = $tier
                Text       = $body.Trim()
            }) | Out-Null
        if ($id -in @('humor', 'teaching', 'persona', 'overlay', 'occ', 'vision', 'partner', 'narrative')) {
            if ($id -in @('humor', 'teaching')) {
                $packsIncluded.Add($id) | Out-Null
            }
        }
    }

    # Assemble in manifest order (sections already ordered from manifest walk).
    $assemble = {
        param($secs)
        ($secs | ForEach-Object { $_.Text }) -join "`n`n"
    }

    $text = & $assemble $sections
    $truncated = $false
    $utf8 = [System.Text.Encoding]::UTF8
    $bytesLen = $utf8.GetByteCount($text)

    if ($bytesLen -gt $BudgetBytes) {
        $truncated = $true
        # Drop / shrink from highest BudgetTier first (P3 then P2 then P1; never drop all P0).
        for ($tierDrop = 3; $tierDrop -ge 1 -and $utf8.GetByteCount($text) -gt $BudgetBytes; $tierDrop--) {
            $keep = [System.Collections.Generic.List[object]]::new()
            foreach ($sec in $sections) {
                if ([int]$sec.BudgetTier -eq $tierDrop) {
                    $packsOmitted.Add([pscustomobject]@{ Id = [string]$sec.Id; Reason = 'budget' }) | Out-Null
                    if ([string]$sec.Id -in @('humor', 'teaching')) {
                        $null = $packsIncluded.Remove([string]$sec.Id)
                    }
                    continue
                }
                $keep.Add($sec) | Out-Null
            }
            $sections = $keep
            $text = & $assemble $sections
        }

        # If still over (large P0), shrink partner first, then narrative; keep vision when possible.
        while ($utf8.GetByteCount($text) -gt $BudgetBytes -and $sections.Count -gt 0) {
            $partnerIdx = -1
            $narrativeIdx = -1
            for ($i = 0; $i -lt $sections.Count; $i++) {
                if ([string]$sections[$i].Id -eq 'partner') { $partnerIdx = $i }
                if ([string]$sections[$i].Id -eq 'narrative') { $narrativeIdx = $i }
            }
            $shrinkIdx = if ($partnerIdx -ge 0) { $partnerIdx } elseif ($narrativeIdx -ge 0) { $narrativeIdx } else { $sections.Count - 1 }
            $sec = $sections[$shrinkIdx]
            $overflow = $utf8.GetByteCount($text) - $BudgetBytes
            $charTrim = [Math]::Max(64, $overflow + 64)
            if ($sec.Text.Length -gt $charTrim + 32) {
                $sec.Text = $sec.Text.Substring(0, $sec.Text.Length - $charTrim) + "`n`n[identity truncated]"
                $truncated = $true
                $text = & $assemble $sections
                continue
            }
            # Section too small to shrink further - drop it (prefer dropping narrative/partner over vision).
            if ([string]$sec.Id -eq 'vision' -and $sections.Count -gt 1) {
                # Drop a different section if vision would be removed.
                $alt = ($sections | Where-Object { $_.Id -ne 'vision' } | Select-Object -Last 1)
                if ($null -ne $alt) {
                    $packsOmitted.Add([pscustomobject]@{ Id = [string]$alt.Id; Reason = 'budget' }) | Out-Null
                    $sections = [System.Collections.Generic.List[object]]::new(
                        [object[]]@($sections | Where-Object { $_.Id -ne $alt.Id })
                    )
                    $text = & $assemble $sections
                    $truncated = $true
                    continue
                }
            }
            $packsOmitted.Add([pscustomobject]@{ Id = [string]$sec.Id; Reason = 'budget' }) | Out-Null
            if ([string]$sec.Id -in @('humor', 'teaching')) {
                $null = $packsIncluded.Remove([string]$sec.Id)
            }
            $sections.RemoveAt($shrinkIdx)
            $text = & $assemble $sections
            $truncated = $true
        }
    }

    # Reconcile HumorActive/TeachingActive with what actually survived budget.
    $humorActive = ($packsIncluded -contains 'humor')
    $teachingActive = ($packsIncluded -contains 'teaching')

    $packsActive = @($packsIncluded)
    $metaLine = "Posture=$resolvedPosture; PortfolioShaped=$([bool]$PortfolioShaped); PacksActive=$($packsActive -join ','); IdentityBudget=$BudgetBytes; IdentityTruncated=$truncated"
    $textWithMeta = if ([string]::IsNullOrWhiteSpace($text)) { $metaLine } else { "$text`n`n$metaLine" }

    # Hash after strip + budget (delivered identity before user message / portfolio evidence).
    $identityHash = Get-MetraConversationIdentityHash -Text $textWithMeta

    $finalText = "$textWithMeta; IdentityHash=$identityHash"

    return [pscustomobject]@{
        Text             = $finalText
        PacksIncluded     = @($packsIncluded)
        PacksOmitted      = @($packsOmitted)
        TeachingActive    = [bool]$teachingActive
        HumorActive       = [bool]$humorActive
        IdentityChars     = $finalText.Length
        IdentityTruncated = [bool]$truncated
        IdentityHash      = $identityHash
        ManifestVersion   = [int]$script:MetraConversationIdentityManifestVersion
        Posture           = $resolvedPosture
    }
}
