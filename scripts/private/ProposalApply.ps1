# Metra Host proposal apply (Slice 5). Native confirm + jail revalidate + project writes + audit.
# Ops HTTP never calls these write paths.

$script:MetraProposalApplyBusy = $false

function Get-MetraProposalApplyAuditPath {
    param([string]$DataDir)

    if ([string]::IsNullOrWhiteSpace($DataDir)) {
        $DataDir = Get-MetraOpsHostDataDir
    }
    return Join-Path $DataDir 'apply-audit.log'
}

function Write-MetraProposalApplyAuditEvent {
    param(
        [Parameter(Mandatory)][string]$Event,
        [Parameter(Mandatory)][string]$ProposalId,
        [hashtable]$Fields,
        [string]$DataDir
    )

    $path = Get-MetraProposalApplyAuditPath -DataDir $DataDir
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        # Directory.CreateDirectory is literal-path safe; New-Item -LiteralPath is not on all hosts.
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    $payload = [ordered]@{
        timestamp = [datetime]::UtcNow.ToString('o')
        event     = $Event
        proposalId = $ProposalId
    }
    if ($Fields) {
        foreach ($key in $Fields.Keys) {
            $payload[$key] = $Fields[$key]
        }
    }

    $json = ($payload | ConvertTo-Json -Depth 20 -Compress)
    Add-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Get-MetraPendingProposalIds {
    param([string]$StoreRoot)

    $store = Get-MetraProposalStoreRoot -StoreRoot $StoreRoot
    $ids = @(Get-ChildItem -LiteralPath $store -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.body.json' } |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })

    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $ids) {
        try {
            $null = Sync-MetraProposalExpiration -Id $id -StoreRoot $store
            $proposal = Get-MetraProposal -Id $id -StoreRoot $store
            if ($proposal.Status -eq 'pendingApply') {
                $pending.Add($id)
            }
        }
        catch { }
    }
    return @($pending.ToArray())
}

function Confirm-MetraProposalApply {
    <#
    .SYNOPSIS
        Native confirm for Host apply. Returns apply | deny | skip.
    .PARAMETER ConfirmAction
        Test hook: scriptblock receiving the proposal, returning apply|deny|skip|diff.
    #>
    param(
        [Parameter(Mandatory)]$Proposal,
        [scriptblock]$ConfirmAction
    )

    if ($ConfirmAction) {
        $choice = & $ConfirmAction $Proposal
        return ([string]$choice).ToLowerInvariant()
    }

    Add-Type -AssemblyName System.Windows.Forms | Out-Null

    while ($true) {
        $fileCount = @($Proposal.Body.files).Count
        $hashShort = [string]$Proposal.Body.contentHash
        if ($hashShort.Length -gt 19) {
            $hashShort = $hashShort.Substring(0, 19) + '...'
        }

        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Metra wants to apply a proposed change'
        $form.Width = 520
        $form.Height = 320
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true

        $label = New-Object System.Windows.Forms.Label
        $label.Left = 16
        $label.Top = 16
        $label.Width = 470
        $label.Height = 180
        $label.Text = @(
            "Project: $($Proposal.Body.project)"
            "Files: $fileCount"
            "Summary: $($Proposal.Body.summary)"
            ''
            'Metra Ops requested this change from the browser/webview.'
            'The Metra Host will apply it only inside the project root after validation.'
            ''
            "Content hash: $hashShort"
            "Expires: $($Proposal.ExpiresAt)"
            "Source: $($Proposal.Body.source)"
        ) -join "`r`n"
        $form.Controls.Add($label)

        $btnApply = New-Object System.Windows.Forms.Button
        $btnApply.Text = 'Apply once'
        $btnApply.Width = 110
        $btnApply.Left = 16
        $btnApply.Top = 220
        $btnApply.DialogResult = [System.Windows.Forms.DialogResult]::Yes
        $form.Controls.Add($btnApply)
        $form.AcceptButton = $btnApply

        $btnDeny = New-Object System.Windows.Forms.Button
        $btnDeny.Text = 'Deny'
        $btnDeny.Width = 90
        $btnDeny.Left = 140
        $btnDeny.Top = 220
        $btnDeny.DialogResult = [System.Windows.Forms.DialogResult]::No
        $form.Controls.Add($btnDeny)

        $btnDiff = New-Object System.Windows.Forms.Button
        $btnDiff.Text = 'Open diff'
        $btnDiff.Width = 100
        $btnDiff.Left = 250
        $btnDiff.Top = 220
        $btnDiff.DialogResult = [System.Windows.Forms.DialogResult]::Retry
        $form.Controls.Add($btnDiff)

        $btnSkip = New-Object System.Windows.Forms.Button
        $btnSkip.Text = 'Later'
        $btnSkip.Width = 90
        $btnSkip.Left = 370
        $btnSkip.Top = 220
        $btnSkip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Controls.Add($btnSkip)
        $form.CancelButton = $btnSkip

        $dialogResult = $form.ShowDialog()
        $form.Dispose()

        switch ($dialogResult) {
            ([System.Windows.Forms.DialogResult]::Yes) { return 'apply' }
            ([System.Windows.Forms.DialogResult]::No) { return 'deny' }
            ([System.Windows.Forms.DialogResult]::Cancel) { return 'skip' }
            ([System.Windows.Forms.DialogResult]::Retry) {
                $diffPath = Join-Path $Proposal.StoreRoot ($Proposal.Id + '.diff.txt')
                if (-not (Test-Path -LiteralPath $diffPath)) {
                    $null = Save-MetraProposalDiffText -Proposal $Proposal
                }
                $diffText = Get-Content -LiteralPath $diffPath -Raw -Encoding UTF8
                if ($diffText.Length -gt 6000) {
                    $diffText = $diffText.Substring(0, 6000) + "`r`n... [truncated]"
                }
                [System.Windows.Forms.MessageBox]::Show(
                    $diffText,
                    "Proposal diff - $($Proposal.Id)",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                continue
            }
            default { return 'skip' }
        }
    }
}

function Write-MetraProposalFileContent {
    <#
    .SYNOPSIS
        Atomically write UTF-8 (no BOM) proposal content via temp file + Move-Item.
    #>
    param(
        [Parameter(Mandatory)][string]$FullPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ContentUtf8
    )

    $dir = Split-Path -Parent $FullPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $tmpName = '.metra-apply-' + [guid]::NewGuid().ToString('N') + '.tmp'
    $tmp = if ($dir) { Join-Path $dir $tmpName } else { $tmpName }
    try {
        [System.IO.File]::WriteAllText($tmp, $ContentUtf8, $encoding)
        Move-Item -LiteralPath $tmp -Destination $FullPath -Force
    }
    catch {
        try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch { }
        throw
    }

    return (ConvertTo-MetraProposalSha256 -Text $ContentUtf8)
}

function Test-MetraProposalSkipConfirmAllowed {
    <#
    .SYNOPSIS
        True when unattended apply (SkipConfirmForTest) is explicitly enabled for tests.
    #>
    param()
    return ($env:METRA_ALLOW_UNATTENDED_APPLY -match '^(?i)(1|true|yes)$')
}

function Complete-MetraProposalNonce {
    param(
        [Parameter(Mandatory)]$Proposal,
        [string]$StoreRoot
    )

    $meta = [ordered]@{
        id             = [string]$Proposal.Meta.id
        status         = [string]$Proposal.Meta.status
        createdAt      = [string]$Proposal.Meta.createdAt
        updatedAt      = [datetime]::UtcNow.ToString('o')
        expiresAt      = [string]$Proposal.Meta.expiresAt
        contentHash    = [string]$Proposal.Meta.contentHash
        nonce          = ''
        nonceConsumed  = $true
        resultMessage  = $Proposal.Meta.resultMessage
        schemaVersion  = [int]$Proposal.Meta.schemaVersion
        project        = [string]$Proposal.Meta.project
        routeStop      = [string]$Proposal.Meta.routeStop
    }
    Write-MetraProposalJsonFile -Path $Proposal.MetaPath -Object $meta
}

function Invoke-MetraProposalHostApply {
    <#
    .SYNOPSIS
        Host apply authority: confirm, revalidate, write project files, audit.
    .PARAMETER SkipConfirmForTest
        Test-only unattended apply. Requires METRA_ALLOW_UNATTENDED_APPLY=1|true|yes.
        Alias: -SkipConfirm (same gate).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$StoreRoot,
        [string]$Surface = 'browser',
        [string]$DataDir,
        [scriptblock]$ConfirmAction,
        [Alias('SkipConfirm')]
        [switch]$SkipConfirmForTest
    )

    if ($SkipConfirmForTest -and -not (Test-MetraProposalSkipConfirmAllowed)) {
        throw 'SkipConfirmForTest is disabled outside test mode. Set METRA_ALLOW_UNATTENDED_APPLY=1 for automated tests only.'
    }

    $null = Sync-MetraProposalExpiration -Id $Id -StoreRoot $StoreRoot
    $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot

    $auditBase = @{
        project     = [string]$proposal.Body.project
        routeStop   = [string]$proposal.Body.routeStop
        rootPath    = [string]$proposal.Body.rootPath
        contentHash = [string]$proposal.Body.contentHash
        source      = [string]$proposal.Body.source
        surface     = $Surface
        hostMachine = $env:COMPUTERNAME
        approvedBySessionUser = [Environment]::UserName
        schemaVersion = [int]$proposal.Body.schemaVersion
    }

    if ($proposal.Status -ne 'pendingApply') {
        $msg = "Proposal no longer valid (status=$($proposal.Status))."
        Write-MetraProposalApplyAuditEvent -Event 'proposal.policyDenied' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'denied'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'policyDenied'
            Proposal      = $proposal
        }
    }

    $nonceConsumed = $false
    if ($null -ne $proposal.Meta.PSObject.Properties['nonceConsumed']) {
        $nonceConsumed = [bool]$proposal.Meta.nonceConsumed
    }
    if ($nonceConsumed -or [string]::IsNullOrWhiteSpace([string]$proposal.Meta.nonce)) {
        $msg = 'Proposal nonce already used or missing.'
        Write-MetraProposalApplyAuditEvent -Event 'proposal.policyDenied' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'denied'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'policyDenied'
            Proposal      = $proposal
        }
    }

    if (-not (Test-MetraProposalNonce -Id $Id -Nonce ([string]$proposal.Meta.nonce) -StoreRoot $StoreRoot)) {
        $msg = 'Proposal nonce hash mismatch.'
        Write-MetraProposalApplyAuditEvent -Event 'proposal.policyDenied' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'denied'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'policyDenied'
            Proposal      = $proposal
        }
    }

    if (-not (Test-MetraProposalSchemaVersion -SchemaVersion $proposal.Body.schemaVersion)) {
        $msg = 'Unknown schemaVersion.'
        $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $msg -StoreRoot $StoreRoot
        $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
        Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
        Write-MetraProposalApplyAuditEvent -Event 'proposal.schemaRejected' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'schemaRejected'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'schemaRejected'
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    if (-not (Test-MetraProposalContentHashMatch -Id $Id -StoreRoot $StoreRoot)) {
        $msg = 'Hash mismatch'
        $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $msg -StoreRoot $StoreRoot
        $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
        Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
        Write-MetraProposalApplyAuditEvent -Event 'proposal.hashMismatch' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'hashMismatch'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'hashMismatch'
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    $expiresAt = [datetime]::Parse([string]$proposal.Meta.expiresAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    if ([datetime]::UtcNow -gt $expiresAt.ToUniversalTime()) {
        $msg = 'Expired'
        $null = Set-MetraProposalStatus -Id $Id -Status expired -ResultMessage $msg -StoreRoot $StoreRoot
        Write-MetraProposalApplyAuditEvent -Event 'proposal.expired' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = 'expired'
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'expired'
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    $files = ConvertTo-MetraProposalApiFileSpecs -Files @($proposal.Body.files)
    $jail = Test-MetraProposalJailApply `
        -Project ([string]$proposal.Body.project) `
        -RootPath ([string]$proposal.Body.rootPath) `
        -Files $files `
        -SchemaVersion ([int]$proposal.Body.schemaVersion)

    if (-not $jail.Ok) {
        $eventName = switch ($jail.ReasonCode) {
            'hashMismatch' { 'proposal.hashMismatch' }
            'fileChanged' { 'proposal.fileChanged' }
            'pathRejected' { 'proposal.pathRejected' }
            'schemaRejected' { 'proposal.schemaRejected' }
            default { 'proposal.policyDenied' }
        }
        $msg = $jail.Message
        if ($jail.ReasonCode -in @('hashMismatch', 'fileChanged', 'pathRejected', 'policyDenied', 'schemaRejected')) {
            $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $msg -StoreRoot $StoreRoot
            $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
            Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
        }
        Write-MetraProposalApplyAuditEvent -Event $eventName -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result       = $jail.ReasonCode
                message      = $msg
                pathRelative = $jail.PathRelative
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = $jail.ReasonCode
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    if (-not $SkipConfirmForTest) {
        Write-MetraProposalApplyAuditEvent -Event 'proposal.confirmShown' -ProposalId $Id -DataDir $DataDir -Fields $auditBase
        $choice = Confirm-MetraProposalApply -Proposal $proposal -ConfirmAction $ConfirmAction
        if ($choice -eq 'deny') {
            $msg = 'Rejected by user'
            $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $msg -StoreRoot $StoreRoot
            $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
            Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
            Write-MetraProposalApplyAuditEvent -Event 'proposal.rejected' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                    result  = 'rejected'
                    message = $msg
                })
            return [pscustomobject]@{
                Ok            = $false
                ResultMessage = $msg
                ReasonCode    = 'rejected'
                Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
            }
        }
        if ($choice -eq 'skip' -or $choice -ne 'apply') {
            # Later/skip keeps nonce and status - not a durable decision.
            return [pscustomobject]@{
                Ok            = $false
                ResultMessage = 'Skipped'
                ReasonCode    = 'skipped'
                Proposal      = $proposal
            }
        }
        Write-MetraProposalApplyAuditEvent -Event 'proposal.confirmAccepted' -ProposalId $Id -DataDir $DataDir -Fields $auditBase
    }

    # Re-validate after confirm (TOCTOU).
    $jail2 = Test-MetraProposalJailApply `
        -Project ([string]$proposal.Body.project) `
        -RootPath ([string]$proposal.Body.rootPath) `
        -Files $files `
        -SchemaVersion ([int]$proposal.Body.schemaVersion)
    if (-not $jail2.Ok) {
        $msg = $jail2.Message
        $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $msg -StoreRoot $StoreRoot
        $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
        Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
        Write-MetraProposalApplyAuditEvent -Event 'proposal.policyDenied' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result  = $jail2.ReasonCode
                message = $msg
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = $jail2.ReasonCode
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    Write-MetraProposalApplyAuditEvent -Event 'proposal.writeStarted' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
            fileCount = @($files).Count
        })

    $fileResults = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($file in $files) {
            $pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
            $action = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
            $content = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
            $target = Resolve-MetraProposalJailTargetPath -RootPath ([string]$proposal.Body.rootPath) -PathRelative $pathRelative
            if ([string]::IsNullOrWhiteSpace($target)) {
                throw "Path outside project root: $pathRelative"
            }
            $previousHash = $null
            $prevRaw = Get-MetraProposalEntryValue -Entry $file -Name 'previousHash'
            if ($null -ne $prevRaw -and -not [string]::IsNullOrWhiteSpace([string]$prevRaw)) {
                $previousHash = [string]$prevRaw
            }
            $newHash = Write-MetraProposalFileContent -FullPath $target -ContentUtf8 $content
            $fileResults.Add([pscustomobject]@{
                    pathRelative = $pathRelative
                    action       = $action
                    previousHash = $previousHash
                    newHash      = $newHash
                })
        }
    }
    catch {
        $msg = $_.Exception.Message
        $written = @($fileResults.ToArray())
        # Partial write consumes the proposal so retry cannot silently finish a half-applied set.
        if ($written.Count -gt 0) {
            $rejectMsg = "Partial write failure: $msg"
            $null = Set-MetraProposalStatus -Id $Id -Status rejected -ResultMessage $rejectMsg -StoreRoot $StoreRoot
            $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
            Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot
            $msg = $rejectMsg
        }
        Write-MetraProposalApplyAuditEvent -Event 'proposal.writeFailed' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
                result       = 'writeFailed'
                message      = $msg
                filesWritten = $written
                partialWrite = ($written.Count -gt 0)
            })
        return [pscustomobject]@{
            Ok            = $false
            ResultMessage = $msg
            ReasonCode    = 'writeFailed'
            Files         = $written
            Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
        }
    }

    $null = Set-MetraProposalStatus -Id $Id -Status applied -ResultMessage 'Applied' -StoreRoot $StoreRoot
    $proposal = Get-MetraProposal -Id $Id -StoreRoot $StoreRoot
    Complete-MetraProposalNonce -Proposal $proposal -StoreRoot $StoreRoot

    Write-MetraProposalApplyAuditEvent -Event 'proposal.applied' -ProposalId $Id -DataDir $DataDir -Fields ($auditBase + @{
            result = 'applied'
            files  = @($fileResults.ToArray())
        })

    return [pscustomobject]@{
        Ok            = $true
        ResultMessage = 'Applied'
        ReasonCode    = 'applied'
        Files         = @($fileResults.ToArray())
        Proposal      = (Get-MetraProposal -Id $Id -StoreRoot $StoreRoot)
    }
}

function Sync-MetraProposalHostPending {
    <#
    .SYNOPSIS
        Poll pendingApply proposals and run Host confirm/apply for each (default one per call).
    #>
    [CmdletBinding()]
    param(
        [string]$StoreRoot,
        [string]$Surface = 'browser',
        [string]$DataDir,
        [int]$MaxCount = 1,
        [scriptblock]$ConfirmAction,
        [Alias('SkipConfirm')]
        [switch]$SkipConfirmForTest
    )

    if ($script:MetraProposalApplyBusy) {
        return @()
    }
    $script:MetraProposalApplyBusy = $true
    try {
        $ids = @(Get-MetraPendingProposalIds -StoreRoot $StoreRoot)
        if ($ids.Count -eq 0) {
            return @()
        }

        $results = [System.Collections.Generic.List[object]]::new()
        $count = 0
        foreach ($id in $ids) {
            if ($count -ge $MaxCount) { break }
            $results.Add((Invoke-MetraProposalHostApply `
                    -Id $id `
                    -StoreRoot $StoreRoot `
                    -Surface $Surface `
                    -DataDir $DataDir `
                    -ConfirmAction $ConfirmAction `
                    -SkipConfirmForTest:$SkipConfirmForTest))
            $count++
        }
        return @($results.ToArray())
    }
    finally {
        $script:MetraProposalApplyBusy = $false
    }
}
