# Lightweight Yarn document validation (schemaVersion + required fields). Fail closed.

function Get-YarnAllowedLifecycleStatuses {
    return @('idea', 'ready', 'pending-bing', 'stale-pack', 'approved', 'parked', 'rejected')
}

function Get-YarnAllowedHealthValues {
    return @('ok', 'blocked', 'inconsistent')
}

function Test-YarnDocumentHasProperty {
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }
    if ($null -ne $Object.PSObject.Properties[$Name]) { return $true }
    foreach ($p in $Object.PSObject.Properties) {
        if ([string]::Equals($p.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Assert-YarnBacklogDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [string]$Path = 'backlog.json'
    )

    if ($null -eq $Document) {
        throw "Yarn backlog invalid ($Path): document is null"
    }
    $version = Get-YarnProp -Object $Document -Name 'schemaVersion' -Default $null
    if ($null -eq $version) {
        throw "Yarn backlog invalid ($Path): schemaVersion required"
    }
    $expected = Get-YarnSchemaVersion
    if ([int]$version -ne [int]$expected) {
        throw "Yarn backlog invalid ($Path): schemaVersion $version (expected $expected)"
    }
    if (-not (Test-YarnDocumentHasProperty -Object $Document -Name 'items')) {
        throw "Yarn backlog invalid ($Path): items array required"
    }
    $items = @(Get-YarnProp -Object $Document -Name 'items' -Default @())
    $allowedStatus = Get-YarnAllowedLifecycleStatuses
    $allowedHealth = Get-YarnAllowedHealthValues
    $i = 0
    foreach ($item in $items) {
        if ($null -eq $item) {
            throw "Yarn backlog invalid ($Path): items[$i] is null"
        }
        foreach ($req in @('id', 'title', 'status', 'health', 'primarySourceKey', 'projectKey')) {
            $val = Get-YarnProp -Object $item -Name $req -Default $null
            if ($null -eq $val -or [string]::IsNullOrWhiteSpace([string]$val)) {
                throw "Yarn backlog invalid ($Path): items[$i].$req required"
            }
        }
        $id = [string](Get-YarnProp -Object $item -Name 'id' -Default '')
        if ($id -notmatch '^YARN-') {
            throw "Yarn backlog invalid ($Path): items[$i].id must start with YARN-"
        }
        $status = [string](Get-YarnProp -Object $item -Name 'status' -Default '')
        if ($allowedStatus -notcontains $status) {
            throw "Yarn backlog invalid ($Path): items[$i].status '$status' not allowed"
        }
        $health = [string](Get-YarnProp -Object $item -Name 'health' -Default '')
        if ($allowedHealth -notcontains $health) {
            throw "Yarn backlog invalid ($Path): items[$i].health '$health' not allowed"
        }
        $i++
    }
}

function Assert-YarnPlanLinksDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [string]$Path = 'plan-links.json'
    )

    if ($null -eq $Document) {
        throw "Yarn plan-links invalid ($Path): document is null"
    }
    $version = Get-YarnProp -Object $Document -Name 'schemaVersion' -Default $null
    if ($null -eq $version) {
        throw "Yarn plan-links invalid ($Path): schemaVersion required"
    }
    $expected = Get-YarnSchemaVersion
    if ([int]$version -ne [int]$expected) {
        throw "Yarn plan-links invalid ($Path): schemaVersion $version (expected $expected)"
    }
    if (-not (Test-YarnDocumentHasProperty -Object $Document -Name 'links')) {
        throw "Yarn plan-links invalid ($Path): links array required"
    }
    $i = 0
    foreach ($link in @(Get-YarnProp -Object $Document -Name 'links' -Default @())) {
        if ($null -eq $link) {
            throw "Yarn plan-links invalid ($Path): links[$i] is null"
        }
        foreach ($req in @('backlogId', 'formalPlanPath', 'planStatus')) {
            $val = Get-YarnProp -Object $link -Name $req -Default $null
            if ($null -eq $val -or [string]::IsNullOrWhiteSpace([string]$val)) {
                throw "Yarn plan-links invalid ($Path): links[$i].$req required"
            }
        }
        $handoff = Get-YarnProp -Object $link -Name 'handoffContractVersion' -Default $null
        if ($null -eq $handoff) {
            throw "Yarn plan-links invalid ($Path): links[$i].handoffContractVersion required"
        }
        if ([int]$handoff -ne [int](Get-YarnHandoffContractVersion)) {
            throw "Yarn plan-links invalid ($Path): links[$i].handoffContractVersion $handoff (expected $(Get-YarnHandoffContractVersion))"
        }
        $i++
    }
}
