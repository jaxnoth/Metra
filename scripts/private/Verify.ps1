# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Invoke-MetraVerify {
    <#
    .SYNOPSIS
        Runs Routing-Scenarios fixture smoke checks; returns PASS/WARN/FAIL rows.
    .DESCRIPTION
        Required checks FAIL when missing. Soft sibling paths WARN when absent (optional stubs)
        and FAIL when present but expected patterns are missing. Live CLI checks FAIL on
        exception; WARN when a named project is not Present on disk.
        Exit code semantics for callers: 0 when FailCount is 0; otherwise 1.
    #>
    [CmdletBinding()]
    param()

    $metraRoot = Get-MetraRoot
    $projectsRoot = Get-ProjectsRoot
    $results = New-Object System.Collections.ArrayList

    function Add-VerifyResult {
        param(
            [string]$Name,
            [ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
            [string]$Detail = ''
        )
        [void]$results.Add([PSCustomObject]@{
            Name   = $Name
            Status = $Status
            Detail = $Detail
        })
    }

    function Test-SoftSiblingPath {
        param(
            [string]$Name,
            [string]$RelativeUnderProjectsRoot
        )
        $full = Join-Path $projectsRoot $RelativeUnderProjectsRoot
        if (Test-Path -LiteralPath $full) {
            Add-VerifyResult -Name $Name -Status 'PASS' -Detail $full
            return $full
        }
        Add-VerifyResult -Name $Name -Status 'WARN' -Detail "absent (optional stub): $full"
        return $null
    }

    # Required files
    $requiredPaths = @(
        @{ Name = 'projects.json'; Path = (Join-Path $metraRoot 'projects.json') },
        @{ Name = 'profiles/sample/metra-profile.json'; Path = (Join-Path $metraRoot 'profiles\sample\metra-profile.json') },
        @{ Name = 'profiles/addons/humor-desk/metra-profile.json'; Path = (Join-Path $metraRoot 'profiles\addons\humor-desk\metra-profile.json') },
        @{ Name = 'profiles/addons/teaching-gentle/metra-profile.json'; Path = (Join-Path $metraRoot 'profiles\addons\teaching-gentle\metra-profile.json') }
    )
    foreach ($item in $requiredPaths) {
        if (Test-Path -LiteralPath $item.Path) {
            Add-VerifyResult -Name $item.Name -Status 'PASS' -Detail $item.Path
        }
        else {
            Add-VerifyResult -Name $item.Name -Status 'FAIL' -Detail "missing: $($item.Path)"
        }
    }

    # Mark-of-the-web on checkout scripts (WARN only - recoverable via unblock)
    try {
        $blockedScripts = @(
            Get-MetraCheckoutScriptFiles -Path $metraRoot |
                Where-Object { Test-MetraBlockedFile -Path $_.FullName }
        )
        if ($blockedScripts.Count -eq 0) {
            Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'PASS' -Detail 'no Zone.Identifier on checkout scripts'
        }
        else {
            $sample = @($blockedScripts | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
            $more = if ($blockedScripts.Count -gt 3) { '...' } else { '' }
            Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'WARN' -Detail (
                ("{0} blocked; run .\metra.ps1 unblock ({1}{2})" -f $blockedScripts.Count, $sample, $more)
            )
        }
    }
    catch {
        Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'WARN' -Detail $_.Exception.Message
    }

    # Soft sibling paths from Routing-Scenarios fixtures
    $null = Test-SoftSiblingPath -Name 'TicketTracker/AGENTS.md' -RelativeUnderProjectsRoot 'TicketTracker\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Trivia/AGENTS.md' -RelativeUnderProjectsRoot 'Trivia\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Solarwinds/docs/Ticket-Triage.md' -RelativeUnderProjectsRoot 'Solarwinds\docs\Ticket-Triage.md'

    $ttPs1 = Join-Path $projectsRoot 'TicketTracker\TicketTracker.ps1'
    if (Test-Path -LiteralPath $ttPs1) {
        foreach ($pat in @("'brief'", "'chats'")) {
            $hit = Select-String -Path $ttPs1 -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue
            if ($hit) {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'PASS' -Detail $ttPs1
            }
            else {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'FAIL' -Detail "pattern not found: $pat"
            }
        }
    }
    else {
        Add-VerifyResult -Name 'TicketTracker.ps1 patterns' -Status 'WARN' -Detail 'TicketTracker.ps1 absent (optional stub)'
    }

    # Live CLI: roots
    try {
        $roots = @(Get-MetraRoots -IncludeMissing)
        if ($roots.Count -gt 0) {
            Add-VerifyResult -Name 'metra.ps1 roots' -Status 'PASS' -Detail ("{0} root(s)" -f $roots.Count)
        }
        else {
            Add-VerifyResult -Name 'metra.ps1 roots' -Status 'FAIL' -Detail 'no roots returned'
        }
    }
    catch {
        Add-VerifyResult -Name 'metra.ps1 roots' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: routing for fixture names
    try {
        $routing = @(Get-MetraRoutingTable -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
        if ($routing.Count -eq 0) {
            Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail 'no routing rows'
        }
        else {
            foreach ($row in $routing) {
                $label = "routing $($row.Name)"
                if ($row.Present) {
                    Add-VerifyResult -Name $label -Status 'PASS' -Detail $row.Path
                }
                elseif ($row.Optional) {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present (optional)'
                }
                else {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present on disk'
                }
            }
        }
    }
    catch {
        Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: ctx (no docs write during smoke)
    try {
        $ctx = Export-MetraContextPack -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1
        if ($ctx -and [string]$ctx.Path -eq '-') {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'PASS' -Detail 'stdout-only (no file write)'
        }
        else {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail 'expected Path=- for quiet ctx'
        }
    }
    catch {
        Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Live CLI: import-profile Preview (quiet)
    try {
        $sample = Join-Path $metraRoot 'profiles\sample'
        $preview = Import-MetraProfile -Path $sample -Preview -Quiet
        if ($preview.Preview -and @($preview.Files).Count -gt 0) {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'PASS' -Detail $sample
        }
        else {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail 'preview returned no files'
        }
    }
    catch {
        Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail $_.Exception.Message
    }

    # Soft: chats (Cursor-specific; may be empty)
    try {
        $chats = @(Get-MetraProjectChats -Name 'Solarwinds' -Query 'alert' -Limit 3 -ErrorAction Stop)
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'PASS' -Detail ("{0} row(s)" -f $chats.Count)
    }
    catch {
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'WARN' -Detail $_.Exception.Message
    }

    # Soft: audit DriftOnly on fixture trio when present
    try {
        $presentNames = @(
            Get-MetraRoutingTable -Name @('Solarwinds', 'TicketTracker', 'Trivia') |
                Where-Object { $_.Present } |
                ForEach-Object { $_.Name }
        )
        if ($presentNames.Count -eq 0) {
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'WARN' -Detail 'no fixture projects Present'
        }
        else {
            $audit = Invoke-MetraProjectContextAudit -Name $presentNames -DriftOnly -Quiet | Select-Object -Last 1
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'PASS' -Detail ("driftSignals={0}" -f $audit.DriftCount)
        }
    }
    catch {
        Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'FAIL' -Detail $_.Exception.Message
    }

    $pass = @($results | Where-Object Status -eq 'PASS').Count
    $warn = @($results | Where-Object Status -eq 'WARN').Count
    $fail = @($results | Where-Object Status -eq 'FAIL').Count

    return [PSCustomObject]@{
        Results   = @($results)
        PassCount = $pass
        WarnCount = $warn
        FailCount = $fail
        Ok        = ($fail -eq 0)
    }
}

