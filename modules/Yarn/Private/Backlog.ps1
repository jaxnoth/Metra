# Yarn backlog load/save/upsert.

function New-YarnBacklogId {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
    $suffix = [guid]::NewGuid().ToString('n').Substring(0, 6).ToUpperInvariant()
    return "YARN-$stamp-$suffix"
}

function Get-MetraYarnBacklog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )
    Initialize-MetraYarnLayout -Root $Root
    $path = Get-YarnBacklogPath -Root $Root
    $doc = Read-YarnJsonFile -Path $path
    [void](Assert-YarnBacklogDocument -Document $doc -Path $path)
    $items = @()
    if ($doc.PSObject.Properties.Name -contains 'items') {
        $items = @($doc.items)
    }
    $normalized = foreach ($item in $items) {
        if ($null -eq $item) { continue }
        $map = @{}
        foreach ($p in $item.PSObject.Properties) { $map[$p.Name] = $p.Value }
        if ($map.ContainsKey('firstSeenAt')) { $map['firstSeenAt'] = ConvertTo-YarnIsoTimestamp -Value $map['firstSeenAt'] }
        if ($map.ContainsKey('lastSeenAt')) { $map['lastSeenAt'] = ConvertTo-YarnIsoTimestamp -Value $map['lastSeenAt'] }
        if (-not $map.ContainsKey('health') -or [string]::IsNullOrWhiteSpace([string]$map['health'])) {
            $map['health'] = 'ok'
        }
        (New-YarnPsObject -Map $map)
    }
    return Sort-YarnBacklogItems -Items @($normalized)
}

function Save-MetraYarnBacklogItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        # [object] avoids PSCustomObject property-enumeration when a single item is passed.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$Items
    )
    $list = @(
        if ($null -eq $Items) { }
        elseif ($Items -is [System.Array]) { $Items }
        else { , $Items }
    )
    $doc = [ordered]@{
        schemaVersion = Get-YarnSchemaVersion
        items         = @($list)
    }
    [void](Assert-YarnBacklogDocument -Document $doc -Path (Get-YarnBacklogPath -Root $Root))
    Save-YarnBacklogDocument -Root $Root -Document $doc
}

function ConvertTo-YarnPropertyMap {
    param($Object)
    $map = @{}
    if ($null -eq $Object) { return $map }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            $map[[string]$key] = $Object[$key]
        }
        return $map
    }
    foreach ($p in $Object.PSObject.Properties) {
        $map[$p.Name] = $p.Value
    }
    return $map
}

function New-YarnPsObject {
    param($Map)
    $ordered = [ordered]@{}
    if ($null -ne $Map) {
        if ($Map -is [System.Collections.IDictionary]) {
            foreach ($key in $Map.Keys) {
                $ordered[[string]$key] = $Map[$key]
            }
        }
        else {
            foreach ($p in $Map.PSObject.Properties) {
                $ordered[$p.Name] = $p.Value
            }
        }
    }
    return [pscustomobject]$ordered
}

function Sync-YarnBacklogItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Incoming,
        [switch]$SkipPlanBoard
    )
    $items = @(Get-MetraYarnBacklog -Root $Root)
    $sourceKey = [string](Get-YarnProp -Object $Incoming -Name 'primarySourceKey' -Default '')
    $existing = $null
    if ($sourceKey) {
        $existing = $items | Where-Object {
            $sources = @(Get-YarnProp -Object $_ -Name 'sources' -Default @())
            $primary = [string](Get-YarnProp -Object $_ -Name 'primarySourceKey' -Default '')
            ($primary -eq $sourceKey) -or ($sources -contains $sourceKey)
        } | Select-Object -First 1
    }
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $incomingMap = ConvertTo-YarnPropertyMap -Object $Incoming
    if ($existing) {
        $map = ConvertTo-YarnPropertyMap -Object $existing
        foreach ($key in $incomingMap.Keys) {
            if ($key -in @('id', 'firstSeenAt', 'health', 'blockReason', 'lastError')) { continue }
            $map[$key] = $incomingMap[$key]
        }
        $map['lastSeenAt'] = $now
        $map['firstSeenAt'] = ConvertTo-YarnIsoTimestamp -Value (Get-YarnProp -Object $existing -Name 'firstSeenAt' -Default $now)
        if (-not $map.ContainsKey('health') -or [string]::IsNullOrWhiteSpace([string]$map['health'])) {
            $map['health'] = 'ok'
        }
        $rank = Measure-YarnRank -Item ((New-YarnPsObject -Map $map))
        foreach ($rp in $rank.PSObject.Properties) { $map[$rp.Name] = $rp.Value }
        if ([bool]$rank.readyEnough -and [string]$map['status'] -in @('idea', '')) {
            $map['status'] = 'ready'
        }
        $updated = (New-YarnPsObject -Map $map)
        $items = @($items | Where-Object { [string]$_.id -ne [string]$updated.id }) + @($updated)
        Save-MetraYarnBacklogItems -Root $Root -Items $items
        $st = [string](Get-YarnProp -Object $updated -Name 'status' -Default '')
        if (-not $SkipPlanBoard -and $st -in @('idea', 'ready', 'pending-bing', 'stale-pack', 'approved', 'parked', 'rejected')) {
            $fp = [string](Get-YarnProp -Object $updated -Name 'formalPlanPath' -Default '')
            Invoke-YarnPlanBoardNotifyFailOpen -Root $Root -BacklogId ([string]$updated.id) -CursorPlan $fp -Reason "yarn-status:$st"
        }
        return $updated
    }

    $id = New-YarnBacklogId
    $map = @{}
    foreach ($key in $incomingMap.Keys) { $map[$key] = $incomingMap[$key] }
    $map['id'] = $id
    $map['firstSeenAt'] = ConvertTo-YarnIsoTimestamp -Value $now
    $map['lastSeenAt'] = ConvertTo-YarnIsoTimestamp -Value $now
    if (-not $map.ContainsKey('status') -or [string]::IsNullOrWhiteSpace([string]$map['status'])) {
        $map['status'] = 'idea'
    }
    # Explicit health default on every new intake item (contract: ok|blocked|inconsistent).
    $map['health'] = 'ok'
    $rank = Measure-YarnRank -Item ((New-YarnPsObject -Map $map))
    foreach ($rp in $rank.PSObject.Properties) { $map[$rp.Name] = $rp.Value }
    if ([bool]$rank.readyEnough) { $map['status'] = 'ready' }
    $created = (New-YarnPsObject -Map $map)
    $items = @($items) + @($created)
    Save-MetraYarnBacklogItems -Root $Root -Items $items
    $stNew = [string](Get-YarnProp -Object $created -Name 'status' -Default '')
    if (-not $SkipPlanBoard -and $stNew -in @('idea', 'ready', 'pending-bing', 'stale-pack', 'approved', 'parked', 'rejected')) {
        $fpNew = [string](Get-YarnProp -Object $created -Name 'formalPlanPath' -Default '')
        Invoke-YarnPlanBoardNotifyFailOpen -Root $Root -BacklogId ([string]$created.id) -CursorPlan $fpNew -Reason "yarn-status:$stNew"
    }
    return $created
}

function Get-YarnPlanLinks {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    Initialize-MetraYarnLayout -Root $Root
    $path = Get-YarnPlanLinksPath -Root $Root
    $doc = Read-YarnJsonFile -Path $path
    [void](Assert-YarnPlanLinksDocument -Document $doc -Path $path)
    if (Test-YarnDocumentHasProperty -Object $doc -Name 'links') {
        return @(Get-YarnProp -Object $doc -Name 'links' -Default @())
    }
    return @()
}

function Sync-YarnPlanLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Link
    )
    $map = ConvertTo-YarnPropertyMap -Object $Link
    if (-not $map.ContainsKey('handoffContractVersion') -or $null -eq $map['handoffContractVersion']) {
        $map['handoffContractVersion'] = Get-YarnHandoffContractVersion
    }
    $normalized = (New-YarnPsObject -Map $map)
    $links = @(Get-YarnPlanLinks -Root $Root)
    $backlogId = [string](Get-YarnProp -Object $normalized -Name 'backlogId' -Default '')
    $links = @($links | Where-Object { [string](Get-YarnProp -Object $_ -Name 'backlogId' -Default '') -ne $backlogId })
    $links += $normalized
    $doc = [ordered]@{
        schemaVersion = Get-YarnSchemaVersion
        links         = @($links)
    }
    [void](Assert-YarnPlanLinksDocument -Document $doc -Path (Get-YarnPlanLinksPath -Root $Root))
    Save-YarnPlanLinksDocument -Root $Root -Document $doc
}
