# Generated from the original Metra.psm1 domain split. Edit this file directly.

# VerifyVersion bumps when the check set changes (automation can detect suite growth).
# v1-v2: routing-centric smoke. v3: + snapshot, desk payload, selfdoc routes, updates, Ask.
$script:MetraVerifyVersion = 3

function Invoke-MetraVerify {
    <#
    .SYNOPSIS
        Runs Metra installation smoke checks; returns PASS/WARN/FAIL rows.
    .DESCRIPTION
        Behavior verification for core promises: foundation files, routing, profiles, ctx,
        quick snapshot / desk payload, self-doc route examples, product updates (fail-soft),
        and Ask capability shape. Required checks FAIL when missing. Soft sibling paths WARN
        when absent. Network-dependent update checks WARN when unavailable.
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
            [string]$Detail = '',
            [string]$Category = 'general'
        )
        [void]$results.Add([PSCustomObject]@{
                Name     = $Name
                Status   = $Status
                Detail   = $Detail
                Category = $Category
            })
    }

    function Test-SoftSiblingPath {
        param(
            [string]$Name,
            [string]$RelativeUnderProjectsRoot
        )
        $full = Join-Path $projectsRoot $RelativeUnderProjectsRoot
        if (Test-Path -LiteralPath $full) {
            Add-VerifyResult -Name $Name -Status 'PASS' -Detail $full -Category 'foundation'
            return $full
        }
        Add-VerifyResult -Name $Name -Status 'WARN' -Detail "absent (optional stub): $full" -Category 'foundation'
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
            Add-VerifyResult -Name $item.Name -Status 'PASS' -Detail $item.Path -Category 'foundation'
        }
        else {
            Add-VerifyResult -Name $item.Name -Status 'FAIL' -Detail "missing: $($item.Path)" -Category 'foundation'
        }
    }

    # Mark-of-the-web on checkout scripts (WARN only - recoverable via unblock)
    try {
        $blockedScripts = @(
            Get-MetraCheckoutScriptFiles -Path $metraRoot |
                Where-Object { Test-MetraBlockedFile -Path $_.FullName }
        )
        if ($blockedScripts.Count -eq 0) {
            Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'PASS' -Detail 'no Zone.Identifier on checkout scripts' -Category 'foundation'
        }
        else {
            $sample = @($blockedScripts | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
            $more = if ($blockedScripts.Count -gt 3) { '...' } else { '' }
            Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'WARN' -Detail (
                ("{0} blocked; run .\metra.ps1 unblock ({1}{2})" -f $blockedScripts.Count, $sample, $more)
            ) -Category 'foundation'
        }
    }
    catch {
        Add-VerifyResult -Name 'mark-of-the-web scripts' -Status 'WARN' -Detail $_.Exception.Message -Category 'foundation'
    }

    # Soft sibling paths from Routing-Scenarios fixtures
    $null = Test-SoftSiblingPath -Name 'TicketTracker/AGENTS.md' -RelativeUnderProjectsRoot 'TicketTracker\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Trivia/AGENTS.md' -RelativeUnderProjectsRoot 'Trivia\AGENTS.md'
    $null = Test-SoftSiblingPath -Name 'Solarwinds/docs/Ticket-Triage.md' -RelativeUnderProjectsRoot 'Solarwinds\docs\Ticket-Triage.md'

    $ttPs1 = Join-Path $projectsRoot 'TicketTracker\TicketTracker.ps1'
    if (Test-Path -LiteralPath $ttPs1) {
        foreach ($pat in @("'brief'", "'chats'")) {
            $hit = Select-String -LiteralPath $ttPs1 -Pattern $pat -SimpleMatch -ErrorAction SilentlyContinue
            if ($hit) {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'PASS' -Detail $ttPs1 -Category 'foundation'
            }
            else {
                Add-VerifyResult -Name ("TicketTracker.ps1 $pat") -Status 'FAIL' -Detail "pattern not found: $pat" -Category 'foundation'
            }
        }
    }
    else {
        Add-VerifyResult -Name 'TicketTracker.ps1 patterns' -Status 'WARN' -Detail 'TicketTracker.ps1 absent (optional stub)' -Category 'foundation'
    }

    # Live CLI: roots
    try {
        $roots = @(Get-MetraRoots -IncludeMissing)
        if ($roots.Count -gt 0) {
            Add-VerifyResult -Name 'metra.ps1 roots' -Status 'PASS' -Detail ("{0} root(s)" -f $roots.Count) -Category 'foundation'
        }
        else {
            Add-VerifyResult -Name 'metra.ps1 roots' -Status 'FAIL' -Detail 'no roots returned' -Category 'foundation'
        }
    }
    catch {
        Add-VerifyResult -Name 'metra.ps1 roots' -Status 'FAIL' -Detail $_.Exception.Message -Category 'foundation'
    }

    # Live CLI: routing for fixture names
    try {
        $routing = @(Get-MetraRoutingTable -Name @('TicketTracker', 'Solarwinds', 'Trivia'))
        if ($routing.Count -eq 0) {
            Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail 'no routing rows' -Category 'routing'
        }
        else {
            foreach ($row in $routing) {
                $label = "routing $($row.Name)"
                if ($row.Present) {
                    Add-VerifyResult -Name $label -Status 'PASS' -Detail $row.Path -Category 'routing'
                }
                elseif ($row.Optional) {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present (optional)' -Category 'routing'
                }
                else {
                    Add-VerifyResult -Name $label -Status 'WARN' -Detail 'not Present on disk' -Category 'routing'
                }
            }
        }
    }
    catch {
        Add-VerifyResult -Name 'routing TicketTracker,Solarwinds,Trivia' -Status 'FAIL' -Detail $_.Exception.Message -Category 'routing'
    }

    # Live CLI: ticket-shaped id and solutions-backed product routing
    try {
        $ttRow = @(Get-MetraRoutingTable -Name @('TicketTracker') | Select-Object -First 1)
        if ($ttRow -and $ttRow.Present) {
            $idAmb = Get-MetraRoutingAmbiguity -Query '1035299'
            if ($idAmb.Primary.Name -eq 'TicketTracker') {
                Add-VerifyResult -Name 'routing query 1035299' -Status 'PASS' -Detail 'Primary TicketTracker' -Category 'routing'
            }
            else {
                Add-VerifyResult -Name 'routing query 1035299' -Status 'FAIL' -Detail ("Primary={0}" -f $idAmb.Primary.Name) -Category 'routing'
            }

            $thriveAmb = Get-MetraRoutingAmbiguity -Query 'Thrive 360 access denied'
            if ($thriveAmb.Primary.Name -eq 'TicketTracker') {
                Add-VerifyResult -Name 'routing query Thrive 360 access denied' -Status 'PASS' -Detail 'Primary TicketTracker (solutions keywords)' -Category 'routing'
            }
            else {
                Add-VerifyResult -Name 'routing query Thrive 360 access denied' -Status 'FAIL' -Detail ("Primary={0}" -f $thriveAmb.Primary.Name) -Category 'routing'
            }

            $related = @(Get-MetraRelatedProjects -Name 'TicketTracker' | ForEach-Object { $_.Name })
            if ($related -contains 'Datamart') {
                Add-VerifyResult -Name 'TicketTracker related set' -Status 'FAIL' -Detail (
                    "expected Datamart absent; related=($($related -join ', '))"
                ) -Category 'routing'
            }
            else {
                Add-VerifyResult -Name 'TicketTracker related set' -Status 'PASS' -Detail (
                    "Datamart not related; related=($($related -join ', '))"
                ) -Category 'routing'
            }
        }
        else {
            Add-VerifyResult -Name 'routing query ticket-shaped / Thrive' -Status 'WARN' -Detail 'TicketTracker not Present' -Category 'routing'
        }
    }
    catch {
        Add-VerifyResult -Name 'routing query ticket-shaped / Thrive' -Status 'FAIL' -Detail $_.Exception.Message -Category 'routing'
    }

    # Live CLI: ctx (no docs write during smoke)
    try {
        $ctx = Export-MetraContextPack -Query 'ticket' -Format markdown -Path '-' -Quiet |
            Select-Object -Last 1
        if ($ctx -and [string]$ctx.Path -eq '-') {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'PASS' -Detail 'stdout-only (no file write)' -Category 'context'
        }
        else {
            Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail 'expected Path=- for quiet ctx' -Category 'context'
        }
    }
    catch {
        Add-VerifyResult -Name 'ctx -Query ticket' -Status 'FAIL' -Detail $_.Exception.Message -Category 'context'
    }

    # Live CLI: import-profile Preview (quiet)
    try {
        $sample = Join-Path $metraRoot 'profiles\sample'
        $preview = Import-MetraProfile -Path $sample -Preview -Quiet
        if ($preview.Preview -and @($preview.Files).Count -gt 0) {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'PASS' -Detail $sample -Category 'profiles'
        }
        else {
            Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail 'preview returned no files' -Category 'profiles'
        }
    }
    catch {
        Add-VerifyResult -Name 'import-profile sample -Preview' -Status 'FAIL' -Detail $_.Exception.Message -Category 'profiles'
    }

    # Soft: chats (Cursor-specific; may be empty)
    try {
        $chats = @(Get-MetraProjectChats -Name 'Solarwinds' -Query 'alert' -Limit 3 -ErrorAction Stop)
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'PASS' -Detail ("{0} row(s)" -f $chats.Count) -Category 'context'
    }
    catch {
        Add-VerifyResult -Name 'chats Solarwinds alert' -Status 'WARN' -Detail $_.Exception.Message -Category 'context'
    }

    # Soft: audit DriftOnly on fixture trio when present
    try {
        $presentNames = @(
            Get-MetraRoutingTable -Name @('Solarwinds', 'TicketTracker', 'Trivia') |
                Where-Object { $_.Present } |
                ForEach-Object { $_.Name }
        )
        if ($presentNames.Count -eq 0) {
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'WARN' -Detail 'no fixture projects Present' -Category 'context'
        }
        else {
            $audit = Invoke-MetraProjectContextAudit -Name $presentNames -DriftOnly -Quiet | Select-Object -Last 1
            Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'PASS' -Detail ("driftSignals={0}" -f $audit.DriftCount) -Category 'context'
        }
    }
    catch {
        Add-VerifyResult -Name 'audit -DriftOnly fixtures' -Status 'FAIL' -Detail $_.Exception.Message -Category 'context'
    }

    # Snapshot (Quick): Ops board brain without git/verify recursion
    try {
        $snap = Export-MetraCanvasSnapshot -Quick
        if ($snap -and [int]$snap.ProjectCount -gt 0) {
            Add-VerifyResult -Name 'snapshot -Quick' -Status 'PASS' -Detail (
                "projectCount={0}" -f $snap.ProjectCount
            ) -Category 'snapshot'
        }
        else {
            Add-VerifyResult -Name 'snapshot -Quick' -Status 'FAIL' -Detail 'ProjectCount not greater than 0' -Category 'snapshot'
        }
    }
    catch {
        Add-VerifyResult -Name 'snapshot -Quick' -Status 'FAIL' -Detail $_.Exception.Message -Category 'snapshot'
    }

    # Desk payload shaping (uses snapshot file just written when present)
    try {
        $desk = Get-MetraDeskPayload
        if ($desk -and $desk.meta -and $desk.health -and [int]$desk.health.projectCount -gt 0) {
            Add-VerifyResult -Name 'desk payload' -Status 'PASS' -Detail (
                "mode={0}; projectCount={1}; homeLabel={2}" -f $desk.mode, $desk.health.projectCount, $desk.meta.homeLabel
            ) -Category 'snapshot'
        }
        else {
            Add-VerifyResult -Name 'desk payload' -Status 'FAIL' -Detail 'missing meta/health or empty projectCount' -Category 'snapshot'
        }
    }
    catch {
        Add-VerifyResult -Name 'desk payload' -Status 'FAIL' -Detail $_.Exception.Message -Category 'snapshot'
    }

    # Self-documentation: live route examples (read-only; does not rewrite Overview/canvas)
    try {
        $overview = Join-Path $metraRoot 'docs\Overview.md'
        if (Test-Path -LiteralPath $overview) {
            Add-VerifyResult -Name 'docs/Overview.md' -Status 'PASS' -Detail $overview -Category 'documentation'
        }
        else {
            Add-VerifyResult -Name 'docs/Overview.md' -Status 'FAIL' -Detail "missing: $overview" -Category 'documentation'
        }

        $selfRoutes = Get-MetraSelfDocRouteExamples -DiagramLimit 3 -TableLimit 8
        $routeCount = @($selfRoutes.routes).Count
        if ($routeCount -gt 0 -and [string]$selfRoutes.source -eq 'routing-engine') {
            Add-VerifyResult -Name 'selfdoc route examples' -Status 'PASS' -Detail (
                "routes={0}; chosenId={1}" -f $routeCount, $selfRoutes.chosenId
            ) -Category 'documentation'
        }
        else {
            Add-VerifyResult -Name 'selfdoc route examples' -Status 'FAIL' -Detail 'no routing-engine routes returned' -Category 'documentation'
        }

        $behavior = Get-MetraSelfDocBehaviorExamples -RoutePayload $selfRoutes
        $exampleCount = @($behavior.examples).Count
        if ($exampleCount -gt 0 -and [int]$behavior.failCount -eq 0) {
            Add-VerifyResult -Name 'selfdoc behavior probes' -Status 'PASS' -Detail (
                "examples={0}" -f $exampleCount
            ) -Category 'documentation'
        }
        elseif ($exampleCount -gt 0) {
            Add-VerifyResult -Name 'selfdoc behavior probes' -Status 'FAIL' -Detail (
                "failCount={0}; examples={1}" -f $behavior.failCount, $exampleCount
            ) -Category 'documentation'
        }
        else {
            Add-VerifyResult -Name 'selfdoc behavior probes' -Status 'FAIL' -Detail 'no behavior examples returned' -Category 'documentation'
        }
    }
    catch {
        Add-VerifyResult -Name 'selfdoc routes / behavior' -Status 'FAIL' -Detail $_.Exception.Message -Category 'documentation'
    }

    # Product updates: fail-soft (GitHub/winget outages should not fail the suite)
    try {
        $updates = Get-MetraProductUpdates
        if (-not $updates -or -not $updates.metra) {
            Add-VerifyResult -Name 'product updates' -Status 'WARN' -Detail 'updates payload incomplete' -Category 'updates'
        }
        elseif ([string]$updates.metra.status -eq 'check_failed') {
            Add-VerifyResult -Name 'product updates' -Status 'WARN' -Detail (
                [string]$updates.metra.message
            ) -Category 'updates'
        }
        else {
            Add-VerifyResult -Name 'product updates' -Status 'PASS' -Detail (
                "metra={0}; ollama={1}" -f $updates.metra.status, $updates.ollama.status
            ) -Category 'updates'
        }
    }
    catch {
        Add-VerifyResult -Name 'product updates' -Status 'WARN' -Detail $_.Exception.Message -Category 'updates'
    }

    # Ask capability shape (availability may be WARN-level via reason; shape must exist)
    try {
        $ask = Get-MetraAskCapability -MetraRoot $metraRoot
        if ($ask -and $ask.PSObject.Properties['engine'] -and $ask.PSObject.Properties['reason']) {
            Add-VerifyResult -Name 'ask capability' -Status 'PASS' -Detail (
                "engine={0}; available={1}; reason={2}" -f $ask.engine, $ask.available, $ask.reason
            ) -Category 'ask'
        }
        else {
            Add-VerifyResult -Name 'ask capability' -Status 'FAIL' -Detail 'missing engine/reason shape' -Category 'ask'
        }
    }
    catch {
        Add-VerifyResult -Name 'ask capability' -Status 'FAIL' -Detail $_.Exception.Message -Category 'ask'
    }

    $pass = @($results | Where-Object Status -eq 'PASS').Count
    $warn = @($results | Where-Object Status -eq 'WARN').Count
    $fail = @($results | Where-Object Status -eq 'FAIL').Count

    return [PSCustomObject]@{
        VerifyVersion = [int]$script:MetraVerifyVersion
        Results       = @($results)
        PassCount     = $pass
        WarnCount     = $warn
        FailCount     = $fail
        Ok            = ($fail -eq 0)
    }
}
