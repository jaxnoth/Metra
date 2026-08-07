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

    # top = 0 means all active/watched tickets. A cap would silently drop tickets
    # from a full scan, and anything missing from a full scan gets auto-closed.
    $defaults = [PSCustomObject]@{
        writeLocalDraft = $false
        top             = 0
        syncOnScan      = $true
        syncOnSnapshot  = $false
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
        if ($null -ne (Get-MetraProp -Object $raw -Name 'syncOnSnapshot' -Default $null)) {
            $defaults.syncOnSnapshot = [bool]$raw.syncOnSnapshot
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

function Format-MetraTicketPriorityLabel {
    [CmdletBinding()]
    param([string]$Priority = '')

    $p = ([string]$Priority).Trim()
    if (-not $p) { return '' }
    if ($p -match '^(?i)(critical|high|medium|low)$') {
        return (Get-Culture).TextInfo.ToTitleCase($p.ToLowerInvariant()) + ' priority'
    }
    if ($p -match '^\d+$') { return "Priority $p" }
    return $p
}

function Test-MetraTicketStatusIsActive {
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return $true }
    return ($s -notmatch '(?i)^(closed|resolved|cancelled|canceled)\b')
}

function Get-MetraTicketAttentionStatusRank {
    <#
    .SYNOPSIS
        Lower number = higher Attention priority. Waiting on Customer sorts below Open work.
    #>
    [CmdletBinding()]
    param([string]$Status = '')

    $s = ([string]$Status).Trim()
    if (-not $s) { return 1 }
    # Ball in operator court - surface first.
    if ($s -match '(?i)^open\b') { return 0 }
    if ($s -match '(?i)^update from\b') { return 0 }
    if ($s -match '(?i)^(in\s*progress|assigned|new|active)\b') { return 5 }
    # Ball with customer / parked - keep in queue but below Open work.
    if ($s -match '(?i)^waiting\b') { return 40 }
    if ($s -match '(?i)^(pending|on\s*hold)\b') { return 30 }
    return 20
}

function Get-MetraAttentionItemStatusRank {
    [CmdletBinding()]
    param($Item)

    if ([string]$Item.kind -ne 'ticket') { return 0 }
    $explicit = Get-MetraProp -Object $Item -Name 'statusRank' -Default $null
    if ($null -ne $explicit -and "$explicit" -ne '') {
        try { return [int]$explicit } catch { }
    }
    $status = [string](Get-MetraProp -Object $Item -Name 'ticketStatus' -Default '')
    if (-not $status) {
        $detail = [string](Get-MetraProp -Object $Item -Name 'detail' -Default '')
        if ($detail -match '(?i)^(Waiting on Customer|Open|In Progress|Pending|On Hold)') {
            $status = $Matches[1]
        }
        elseif ([string]$Item.evidenceSignature -match '(?i)\|status:([^|]+)') {
            $status = $Matches[1].Trim()
        }
    }
    return (Get-MetraTicketAttentionStatusRank -Status $status)
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
    $subject = ([string](Get-MetraProp -Object $Ticket -Name 'Subject' -Default '')).Trim()
    $customer = ([string](Get-MetraProp -Object $Ticket -Name 'Customer' -Default '')).Trim()
    $assignee = ([string](Get-MetraProp -Object $Ticket -Name 'Assignee' -Default '')).Trim()

    $priorityLabel = Format-MetraTicketPriorityLabel -Priority $priority
    $content = if ($subject) { "Ticket $id`: $subject" } else { "Ticket $id needs triage" }
    if (-not $subject -and $priorityLabel) { $content = "$content - $priorityLabel" }

    $detailParts = @()
    if ($status) { $detailParts += $status }
    if ($priorityLabel) { $detailParts += $priorityLabel }
    if ($customer) { $detailParts += "for $customer" }
    if ($assignee) { $detailParts += "assigned to $assignee" }
    if ($updated) {
        $updatedText = $updated
        try {
            $u = [datetime]::Parse($updated, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $updatedText = $u.ToLocalTime().ToString('MMM d, h:mm tt')
        }
        catch {
            try {
                $u = [datetime]$updated
                $updatedText = $u.ToString('MMM d, h:mm tt')
            }
            catch { }
        }
        $detailParts += "updated $updatedText"
    }

    return [PSCustomObject]@{
        id                = "ticket:$id"
        project           = 'TicketTracker'
        kind              = 'ticket'
        content           = $content
        detail            = ($detailParts -join ' - ')
        ticketStatus      = $status
        statusRank        = (Get-MetraTicketAttentionStatusRank -Status $status)
        command           = ".\TicketTracker.ps1 brief $id"
        source            = 'TicketTracker'
        evidenceSignature = (New-MetraTicketAttentionEvidenceSignature -TicketId $id -Updated $updated -Status $status)
    }
}

function Update-MetraTicketAttentionDisplayFields {
    <#
    .SYNOPSIS
        Fills subject/status/priority/customer on a ticket Attention item from TicketTracker.
        Used at desk-view time so Ops is not stuck on thin pre-subject memory rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$MemItem
    )

    if ([string]$MemItem.kind -ne 'ticket') { return $MemItem }

    $id = ''
    $key = [string]$MemItem.key
    $content = [string]$MemItem.content
    if ($key -match '(?i)^ticket:(\d+)') { $id = $Matches[1] }
    elseif ($content -match '(?i)\b(\d{6,8})\b') { $id = $Matches[1] }
    if (-not $id) { return $MemItem }

    $detail = [string](Get-MetraProp -Object $MemItem -Name 'detail' -Default '')
    $hasSubject = $content -match '(?i)^Ticket\s+\d+\s*:'
    if ($hasSubject -and $detail) { return $MemItem }

    $tt = Get-MetraTicketTrackerProject
    if (-not $tt) { return $MemItem }

    try {
        Import-Module $tt.ModulePath -Force
        $getTickets = Get-Command Get-TrackedTickets -ErrorAction Stop
        $ticket = @(& $getTickets -Id $id | Select-Object -First 1)
        if ($ticket.Count -eq 0) { return $MemItem }
        $qi = ConvertTo-MetraTicketAttentionQueueItem -Ticket $ticket[0] -TicketTrackerPath $tt.Path
        if (-not $qi) { return $MemItem }
        $MemItem.content = [string]$qi.content
        if ($MemItem.PSObject.Properties['detail']) { $MemItem.detail = [string]$qi.detail }
        else { $MemItem | Add-Member -NotePropertyName detail -NotePropertyValue ([string]$qi.detail) -Force }
        $ticketStatus = [string](Get-MetraProp -Object $qi -Name 'ticketStatus' -Default '')
        $statusRank = Get-MetraProp -Object $qi -Name 'statusRank' -Default $null
        if ($MemItem.PSObject.Properties['ticketStatus']) { $MemItem.ticketStatus = $ticketStatus }
        else { $MemItem | Add-Member -NotePropertyName ticketStatus -NotePropertyValue $ticketStatus -Force }
        if ($MemItem.PSObject.Properties['statusRank']) { $MemItem.statusRank = $statusRank }
        else { $MemItem | Add-Member -NotePropertyName statusRank -NotePropertyValue $statusRank -Force }
        if ($qi.command) { $MemItem.command = [string]$qi.command }
        if ($qi.evidenceSignature) { $MemItem.evidenceSignature = [string]$qi.evidenceSignature }
    }
    catch { }

    return $MemItem
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
    # Include Waiting on Customer and other non-closed statuses - Open* alone misses active work.
    $activeTickets = @(
        Get-TrackedTickets | Where-Object {
            Test-MetraTicketStatusIsActive -Status ([string](Get-MetraProp -Object $_ -Name 'Status' -Default ''))
        }
    )
    foreach ($t in $activeTickets) {
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
                Get-MetraTicketAttentionStatusRank -Status ([string](Get-MetraProp -Object $_ -Name 'Status' -Default ''))
            }
            Descending = $false
        }, @{
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
            Descending = $false
        }
    )
    $truncated = $false
    if ($Top -gt 0 -and $sorted.Count -gt $Top) {
        $truncated = $true
        $sorted = @($sorted | Select-Object -First $Top)
    }

    return [PSCustomObject]@{
        Tickets   = $sorted
        Synced    = $synced
        SyncError = $syncError
        Scanned   = $sorted.Count
        Truncated = $truncated
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
    # A truncated list is not full coverage - auto-close would kill live tickets past the cap.
    $truncated = [bool](Get-MetraProp -Object $candidates -Name 'Truncated' -Default $false)
    $coveredKinds = if ($truncated) { @() } else { @('ticket') }
    $memory = Update-MetraAttentionMemory `
        -Queue $queue `
        -CoveredKinds $coveredKinds `
        -ScanMode 'full' `
        -MetraRoot $MetraRoot
    $result.coveredTicket = -not $truncated
    $result.ok = $true
    if ($truncated -and -not $Quiet) {
        Write-Warning ("Ticket list capped at {0}; tickets past the cap stay in Attention untouched." -f $topN)
    }

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
