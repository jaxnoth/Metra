function Get-MetraTicketTrackerProject {
    <#
    .SYNOPSIS
        Resolves the TicketTracker companion path from the Metra registry (present on disk).
    #>
    [CmdletBinding()]
    param()

    $proj = @(Get-MetraProject -Name TicketTracker | Select-Object -First 1)
    if ($proj.Count -eq 0) { return $null }
    $path = [string]$proj[0].Path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    $module = Join-Path $path 'src\TicketTracker.psm1'
    if (-not (Test-Path -LiteralPath $module)) { return $null }
    return [PSCustomObject]@{
        Name       = 'TicketTracker'
        Path       = $path
        ModulePath = $module
    }
}

function Get-MetraTicketWatchConfig {
    <#
    .SYNOPSIS
        Local ticket-watch preferences (default: no local draft notes).
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $defaults = [PSCustomObject]@{
        writeLocalDraft = $false
        top             = 10
        syncOnScan      = $true
    }
    $cfgPath = Join-Path $MetraRoot 'docs\ticket-watch.local.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $defaults }
    try {
        $raw = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -ne (Get-MetraProp -Object $raw -Name 'writeLocalDraft' -Default $null)) {
            $defaults.writeLocalDraft = [bool]$raw.writeLocalDraft
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'top' -Default $null)) {
            $t = [int]$raw.top
            if ($t -gt 0) { $defaults.top = $t }
        }
        if ($null -ne (Get-MetraProp -Object $raw -Name 'syncOnScan' -Default $null)) {
            $defaults.syncOnScan = [bool]$raw.syncOnScan
        }
    }
    catch { }
    return $defaults
}

function New-MetraTicketAttentionEvidenceSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [string]$Updated = '',
        [string]$Status = ''
    )

    return ('ticket:{0}|updated:{1}|status:{2}' -f $TicketId.Trim(), ([string]$Updated).Trim(), ([string]$Status).Trim())
}

function ConvertTo-MetraTicketAttentionQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Ticket,
        [string]$TicketTrackerPath = ''
    )

    $id = [string](Get-MetraProp -Object $Ticket -Name 'Id' -Default '')
    if (-not $id) { $id = [string](Get-MetraProp -Object $Ticket -Name 'Number' -Default '') }
    if (-not $id) { return $null }

    $status = [string](Get-MetraProp -Object $Ticket -Name 'Status' -Default '')
    $updated = [string](Get-MetraProp -Object $Ticket -Name 'Updated' -Default '')
    $priority = [string](Get-MetraProp -Object $Ticket -Name 'Priority' -Default '')
    $summary = "Ticket $id needs triage"
    if ($priority) { $summary = "$summary - $priority priority" }

    $briefCmd = if ($TicketTrackerPath) {
        ".\TicketTracker.ps1 brief $id"
    }
    else {
        ".\TicketTracker.ps1 brief $id"
    }

    return [PSCustomObject]@{
        id                = "ticket:$id"
        project           = 'TicketTracker'
        kind              = 'ticket'
        content           = $summary
        command           = $briefCmd
        source            = 'TicketTracker'
        evidenceSignature = (New-MetraTicketAttentionEvidenceSignature -TicketId $id -Updated $updated -Status $status)
    }
}

function Get-MetraTicketWatchCandidates {
    <#
    .SYNOPSIS
        Reads open and watched tickets from TicketTracker module (objects, not Format-Table).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ModulePath,
        [int]$Top = 10,
        [bool]$DoSync = $false
    )

    Import-Module $ModulePath -Force
    $synced = $false
    $syncError = ''
    if ($DoSync) {
        try {
            $null = Sync-TrackedTickets
            $synced = $true
        }
        catch {
            $syncError = $_.Exception.Message
        }
    }

    $byId = @{}
    $openTickets = @(Get-TrackedTickets -Status 'Open*')
    foreach ($t in $openTickets) {
        $id = [string](Get-MetraProp -Object $t -Name 'Id' -Default '')
        if ($id) { $byId[$id] = $t }
    }
    # Avoid TicketTracker Get-TrackedTickets -Watched: local $watched overwrites [switch]$Watched (case-insensitive).
    $ttModule = Get-Module TicketTracker
    if ($ttModule) {
        $watchedIds = @(& $ttModule { @((Get-StateStore).Data.watched) })
        foreach ($wid in $watchedIds) {
            if (-not $wid) { continue }
            $widText = [string]$wid
            if ($byId.ContainsKey($widText)) { continue }
            $t = @(Get-TrackedTickets -Id $widText | Select-Object -First 1)
            if ($t.Count -gt 0) { $byId[$widText] = $t[0] }
        }
    }

    $sorted = @(
        $byId.Values | Sort-Object -Property @{
            Expression = {
                $u = Get-MetraProp -Object $_ -Name 'Updated' -Default $null
                if ($u) {
                    try { return [datetime]$u } catch { return [datetime]::MinValue }
                }
                return [datetime]::MinValue
            }
            Descending = $true
        }, @{
            Expression = { [string](Get-MetraProp -Object $_ -Name 'Priority' -Default '') }
            Descending = $true
        }
    )
    if ($Top -gt 0 -and $sorted.Count -gt $Top) {
        $sorted = @($sorted | Select-Object -First $Top)
    }

    return [PSCustomObject]@{
        Tickets   = $sorted
        Synced    = $synced
        SyncError = $syncError
        Scanned   = $sorted.Count
    }
}

function Invoke-MetraTicketWatchScan {
    <#
    .SYNOPSIS
        Ticket-first watch intake: TicketTracker read signals -> Attention observations.
        No iSupport recommend/post/resolve. Optional local draft notes with -Draft.
    #>
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot),
        [switch]$Draft,
        [switch]$SkipSync,
        [switch]$Quiet,
        [int]$Top = 0
    )

    $cfg = Get-MetraTicketWatchConfig -MetraRoot $MetraRoot
    $topN = if ($Top -gt 0) { $Top } else { [int]$cfg.top }
    $writeDraft = [bool]$Draft -or [bool]$cfg.writeLocalDraft
    $doSync = [bool]$cfg.syncOnScan -and -not $SkipSync

    $result = [PSCustomObject]@{
        ok              = $false
        available       = $false
        synced          = $false
        syncError       = ''
        warning         = ''
        scanned         = 0
        added           = 0
        refreshed       = 0
        unchanged       = 0
        draftsWritten   = 0
        coveredTicket   = $false
        queue           = @()
        iSupportWrites  = $false
    }

    $tt = Get-MetraTicketTrackerProject
    if (-not $tt) {
        $result.warning = 'TicketTracker project or module not present; ticket watch skipped.'
        if (-not $Quiet) {
            Write-Warning $result.warning
        }
        return $result
    }

    $result.available = $true
    try {
        $candidates = Get-MetraTicketWatchCandidates -ModulePath $tt.ModulePath -Top $topN -DoSync $doSync
    }
    catch {
        $result.warning = "Ticket watch scan skipped: $($_.Exception.Message)"
        if (-not $Quiet) { Write-Warning $result.warning }
        return $result
    }

    $result.synced = [bool]$candidates.Synced
    $result.syncError = [string]$candidates.SyncError
    $result.scanned = [int]$candidates.Scanned
    if ($result.syncError -and -not $Quiet) {
        Write-Warning ("TicketTracker sync failed; using local cache. {0}" -f $result.syncError)
    }

    $before = Get-MetraAttentionMemory -MetraRoot $MetraRoot
    $beforeByKey = @{}
    foreach ($item in @($before.items)) {
        if ($item.key) { $beforeByKey[[string]$item.key] = $item }
    }

    $queue = @(
        foreach ($t in @($candidates.Tickets)) {
            ConvertTo-MetraTicketAttentionQueueItem -Ticket $t -TicketTrackerPath $tt.Path
        }
    ) | Where-Object { $null -ne $_ }

    $result.queue = $queue
    $memory = Update-MetraAttentionMemory `
        -Queue $queue `
        -CoveredKinds @('ticket') `
        -ScanMode 'full' `
        -MetraRoot $MetraRoot
    $result.coveredTicket = $true
    $result.ok = $true

    foreach ($q in $queue) {
        $key = [string]$q.id
        $after = @($memory.items | Where-Object { [string]$_.key -eq $key } | Select-Object -First 1)
        $prev = $beforeByKey[$key]
        if (-not $prev) {
            $result.added++
            continue
        }
        $prevSig = [string]$prev.evidenceSignature
        $newSig = [string]$q.evidenceSignature
        if ($prevSig -eq $newSig -and [string]$prev.state -eq 'active') {
            $result.unchanged++
        }
        else {
            $result.refreshed++
        }
    }

    if ($writeDraft) {
        foreach ($t in @($candidates.Tickets)) {
            $id = [string](Get-MetraProp -Object $t -Name 'Id' -Default '')
            if (-not $id) { continue }
            $subject = [string](Get-MetraProp -Object $t -Name 'Subject' -Default '')
            $text = @"
[watch-draft]
This is a local draft generated from ticket watch intake.
No iSupport update has been posted.
Subject: $subject
Suggested next operator action: brief/recommend/review.
"@
            try {
                Add-TrackedTicketNote -Id $id -Text $text -Tags 'watch-draft' | Out-Null
                $result.draftsWritten++
            }
            catch {
                if (-not $Quiet) {
                    Write-Warning ("Local draft note failed for {0}: {1}" -f $id, $_.Exception.Message)
                }
            }
        }
    }

    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Metra ticket watch scan'
        Write-Host ''
        if ($result.synced) {
            Write-Host 'Synced TicketTracker.'
        }
        elseif ($doSync) {
            Write-Host 'TicketTracker sync skipped or failed; used local cache.'
        }
        else {
            Write-Host 'Skipped TicketTracker sync (-SkipSync or config).'
        }
        Write-Host ("Scanned {0} open/watched tickets." -f $result.scanned)
        Write-Host 'Attention updated:'
        Write-Host ("  Added: {0}" -f $result.added)
        Write-Host ("  Refreshed: {0}" -f $result.refreshed)
        Write-Host ("  Unchanged: {0}" -f $result.unchanged)
        if ($writeDraft) {
            Write-Host ("Local draft notes written: {0}" -f $result.draftsWritten)
        }
        Write-Host ''
        Write-Host 'No iSupport writes performed.'
        Write-Host 'Next: open Ops Next or run .\TicketTracker.ps1 brief <id>'
        Write-Host ''
    }

    return $result
}
