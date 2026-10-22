# Future portfolio store: local YAML is the unshipped-intent graph.
# Validate fails closed. Reconcile prints warnings and writes nothing.
#
# docs/future.local.yaml is only the subset this file emits. It is not a general YAML parser.
# Scalars are one physical line, double-quoted, and the only escapes are \\ and \".
# Newlines, folded blocks, and other escapes are outside the subset and fail closed.

$script:MetraFutureItemStatuses = @('now', 'next', 'parked', 'cold', 'skip')
$script:MetraFutureProgramStatuses = @('active', 'parked', 'expired', 'completed')
$script:MetraFutureAudiences = @('human', 'agent', 'both')
$script:MetraFuturePlanRoles = @('parent', 'supporting', 'related')
$script:MetraFuturePlanSources = @('repo', 'cursor', 'missing')
$script:MetraFutureNowLimit = 3
$script:MetraFutureDuplicatePairs = @(
    @('human-procedure-skills', 'agent-a4-skills'),
    @('agent-a1-prove', 'sprint-s7')
)

function Get-MetraFutureStorePath {
    param([string]$MetraRoot = (Get-MetraRoot))
    return (Join-Path $MetraRoot 'docs\future.local.yaml')
}

function ConvertTo-MetraFutureYamlScalar {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value -match '[\r\n]') {
        throw 'Future YAML scalars are one physical line. Newlines are outside the emitted subset.'
    }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function ConvertFrom-MetraFutureYamlScalar {
    param([string]$Value)
    $text = $Value.Trim()
    if ($text.Length -lt 2 -or -not $text.StartsWith('"') -or -not $text.EndsWith('"')) {
        return $text
    }
    $inner = $text.Substring(1, $text.Length - 2)
    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $inner.Length; $i++) {
        $ch = $inner[$i]
        if ($ch -ne '\') {
            [void]$builder.Append($ch)
            continue
        }
        if ($i + 1 -ge $inner.Length) {
            throw 'Future YAML scalar has a trailing backslash. Only \\ and \" are escapes.'
        }
        $next = $inner[$i + 1]
        if ($next -ne '\' -and $next -ne '"') {
            throw "Future YAML scalar has an unsupported escape: \$next"
        }
        [void]$builder.Append($next)
        $i++
    }
    return $builder.ToString()
}

function ConvertTo-MetraFutureYaml {
    param($Portfolio)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('# Local Future portfolio. Operator-edited. Markdown and the canvas are projections.')
    [void]$lines.Add('schemaVersion: 1')
    [void]$lines.Add('programs:')
    foreach ($program in @($Portfolio.Programs)) {
        [void]$lines.Add('  - id: ' + (ConvertTo-MetraFutureYamlScalar $program.Id))
        [void]$lines.Add('    title: ' + (ConvertTo-MetraFutureYamlScalar $program.Title))
        [void]$lines.Add('    product: ' + (ConvertTo-MetraFutureYamlScalar $program.Product))
        [void]$lines.Add('    status: ' + $program.Status)
        [void]$lines.Add('    plan: ' + (ConvertTo-MetraFutureYamlScalar $program.Plan))
        [void]$lines.Add('    children:')
        foreach ($child in @($program.Children)) {
            [void]$lines.Add('      - ' + $child)
        }
    }
    [void]$lines.Add('items:')
    foreach ($item in @($Portfolio.Items)) {
        [void]$lines.Add('  - id: ' + (ConvertTo-MetraFutureYamlScalar $item.Id))
        [void]$lines.Add('    title: ' + (ConvertTo-MetraFutureYamlScalar $item.Title))
        [void]$lines.Add('    summary: ' + (ConvertTo-MetraFutureYamlScalar ([string]$item.Summary)))
        [void]$lines.Add('    status: ' + $item.Status)
        [void]$lines.Add('    audience: ' + $item.Audience)
        [void]$lines.Add('    product: ' + (ConvertTo-MetraFutureYamlScalar $item.Product))
        if (@($item.Tags).Count -eq 0) {
            [void]$lines.Add('    tags: []')
        }
        else {
            [void]$lines.Add('    tags:')
            foreach ($tag in @($item.Tags)) {
                [void]$lines.Add('      - ' + $tag)
            }
        }
        if ($item.Program) {
            [void]$lines.Add('    program: ' + $item.Program)
        }
        [void]$lines.Add('    next: ' + (ConvertTo-MetraFutureYamlScalar $item.Next))
        [void]$lines.Add('    verify: ' + (ConvertTo-MetraFutureYamlScalar $item.Verify))
        if ($item.HardOffs) {
            [void]$lines.Add('    hardOffs: ' + (ConvertTo-MetraFutureYamlScalar $item.HardOffs))
        }
        if (@($item.Plans).Count -eq 0) {
            [void]$lines.Add('    plans: []')
        }
        else {
            [void]$lines.Add('    plans:')
            foreach ($plan in @($item.Plans)) {
                [void]$lines.Add('      - ref: ' + (ConvertTo-MetraFutureYamlScalar $plan.Ref))
                [void]$lines.Add('        role: ' + $plan.Role)
                [void]$lines.Add('        source: ' + $plan.Source)
            }
        }
    }
    return ($lines -join "`n") + "`n"
}

function ConvertFrom-MetraFutureYaml {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Future store not found: $Path"
    }
    $portfolio = @{
        SchemaVersion = 0
        Programs      = New-Object System.Collections.ArrayList
        Items         = New-Object System.Collections.ArrayList
    }
    $section = 'root'
    $current = $null
    $mode = ''
    $plan = $null
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line = $raw.TrimEnd()
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^schemaVersion:\s*(\d+)\s*$') {
            $portfolio.SchemaVersion = [int]$Matches[1]
            continue
        }
        if ($line -eq 'programs:') { $section = 'programs'; $current = $null; $mode = ''; continue }
        if ($line -eq 'items:') { $section = 'items'; $current = $null; $mode = ''; $plan = $null; continue }

        if ($section -eq 'programs' -and $line -match '^  - id:\s*(.+)$') {
            $current = @{
                Id       = ConvertFrom-MetraFutureYamlScalar $Matches[1]
                Title    = ''
                Product  = ''
                Status   = ''
                Plan     = ''
                Children = New-Object System.Collections.ArrayList
            }
            [void]$portfolio.Programs.Add($current)
            $mode = 'program'
            continue
        }
        if ($section -eq 'items' -and $line -match '^  - id:\s*(.+)$') {
            $current = @{
                Id       = ConvertFrom-MetraFutureYamlScalar $Matches[1]
                Title    = ''
                Summary  = ''
                Status   = ''
                Audience = ''
                Product  = ''
                Tags     = New-Object System.Collections.ArrayList
                Program  = ''
                Next     = ''
                Verify   = ''
                HardOffs = ''
                Plans    = New-Object System.Collections.ArrayList
            }
            [void]$portfolio.Items.Add($current)
            $mode = 'item'
            $plan = $null
            continue
        }
        if ($null -eq $current) { continue }

        if ($section -eq 'programs' -and $mode -eq 'children' -and $line -match '^      - (.+)$') {
            [void]$current.Children.Add((ConvertFrom-MetraFutureYamlScalar $Matches[1]))
            continue
        }
        if ($section -eq 'items' -and $mode -eq 'tags' -and $line -match '^      - (.+)$') {
            [void]$current.Tags.Add((ConvertFrom-MetraFutureYamlScalar $Matches[1]))
            continue
        }
        if ($section -eq 'items' -and $line -match '^      - ref:\s*(.+)$') {
            $plan = @{
                Ref    = ConvertFrom-MetraFutureYamlScalar $Matches[1]
                Role   = ''
                Source = ''
            }
            [void]$current.Plans.Add($plan)
            $mode = 'plan'
            continue
        }
        if ($mode -eq 'plan' -and $plan -and $line -match '^        role:\s*(\S+)$') {
            $plan.Role = $Matches[1]
            continue
        }
        if ($mode -eq 'plan' -and $plan -and $line -match '^        source:\s*(\S+)$') {
            $plan.Source = $Matches[1]
            continue
        }

        if ($line -match '^    ([A-Za-z]+):\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2]
            if ($section -eq 'programs' -and $key -eq 'children' -and [string]::IsNullOrWhiteSpace($value)) {
                $mode = 'children'
                continue
            }
            if ($section -eq 'items' -and $key -eq 'tags') {
                $mode = 'tags'
                if ($value.Trim() -eq '[]') { $mode = 'item' }
                continue
            }
            if ($section -eq 'items' -and $key -eq 'plans') {
                $mode = 'plan'
                $plan = $null
                if ($value.Trim() -eq '[]') { $mode = 'item' }
                continue
            }
            $scalar = ConvertFrom-MetraFutureYamlScalar $value
            if ($section -eq 'programs') {
                switch ($key) {
                    'title' { $current.Title = $scalar }
                    'product' { $current.Product = $scalar }
                    'status' { $current.Status = $scalar }
                    'plan' { $current.Plan = $scalar }
                }
            }
            else {
                switch ($key) {
                    'title' { $current.Title = $scalar; $mode = 'item' }
                    'summary' { $current.Summary = $scalar; $mode = 'item' }
                    'status' { $current.Status = $scalar; $mode = 'item' }
                    'audience' { $current.Audience = $scalar; $mode = 'item' }
                    'product' { $current.Product = $scalar; $mode = 'item' }
                    'program' { $current.Program = $scalar; $mode = 'item' }
                    'next' { $current.Next = $scalar; $mode = 'item' }
                    'verify' { $current.Verify = $scalar; $mode = 'item' }
                    'hardOffs' { $current.HardOffs = $scalar; $mode = 'item' }
                }
            }
        }
    }
    return $portfolio
}

function Export-MetraFuturePortfolioYaml {
    param(
        [Parameter(Mandatory)]$Portfolio,
        [Parameter(Mandatory)][string]$Path
    )
    $text = ConvertTo-MetraFutureYaml -Portfolio $Portfolio
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [IO.File]::WriteAllText($Path, $text, $utf8)
}

function Test-MetraFuturePlanStem {
    param([string]$Ref)
    return $Ref -match '^[A-Za-z0-9_-]+$'
}

function Resolve-MetraFuturePlanFile {
    param(
        [string]$Ref,
        [string]$Source,
        [string]$MetraRoot,
        [string]$CursorPlansDir
    )
    if ($Source -eq 'missing') { return $null }
    if (-not (Test-MetraFuturePlanStem $Ref)) { return $null }
    if ($Source -eq 'repo') {
        return (Join-Path $MetraRoot ("plans\" + $Ref + '.plan.md'))
    }
    if ($Source -eq 'cursor') {
        return (Join-Path $CursorPlansDir ($Ref + '.plan.md'))
    }
    return $null
}

function Test-MetraFutureModel {
    param(
        [Parameter(Mandatory)]$Portfolio,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$CursorPlansDir = (Join-Path $env:USERPROFILE '.cursor\plans')
    )
    $errors = New-Object System.Collections.ArrayList
    if ($Portfolio.SchemaVersion -ne 1) {
        [void]$errors.Add('BAD_SCHEMA schemaVersion must be 1')
    }

    $seen = @{}
    foreach ($item in @($Portfolio.Items)) {
        if ($seen.ContainsKey($item.Id)) {
            [void]$errors.Add("DUPLICATE_ID $($item.Id)")
        }
        else { $seen[$item.Id] = $true }
        if ($script:MetraFutureItemStatuses -notcontains $item.Status) {
            [void]$errors.Add("BAD_ITEM_STATUS $($item.Id) $($item.Status)")
        }
        if ($script:MetraFutureAudiences -notcontains $item.Audience) {
            [void]$errors.Add("BAD_AUDIENCE $($item.Id) $($item.Audience)")
        }
        if ([string]::IsNullOrWhiteSpace($item.Title)) {
            [void]$errors.Add("MISSING_FIELD $($item.Id) title")
        }
        foreach ($plan in @($item.Plans)) {
            if ($script:MetraFuturePlanRoles -notcontains $plan.Role) {
                [void]$errors.Add("BAD_PLAN_ROLE $($item.Id) $($plan.Ref)")
            }
            if ($script:MetraFuturePlanSources -notcontains $plan.Source) {
                [void]$errors.Add("BAD_PLAN_SOURCE $($item.Id) $($plan.Source)")
                continue
            }
            if ($plan.Source -eq 'missing') { continue }
            if ([string]::IsNullOrWhiteSpace($plan.Ref)) {
                [void]$errors.Add("UNRESOLVED_PLAN_REF $($item.Id)")
                continue
            }
            $file = Resolve-MetraFuturePlanFile -Ref $plan.Ref -Source $plan.Source -MetraRoot $MetraRoot -CursorPlansDir $CursorPlansDir
            if (-not $file -or -not (Test-Path -LiteralPath $file)) {
                [void]$errors.Add("UNRESOLVED_PLAN_REF $($item.Id) $($plan.Source):$($plan.Ref)")
            }
        }
    }

    $nowCount = @($Portfolio.Items | Where-Object { $_.Status -eq 'now' }).Count
    if ($nowCount -gt $script:MetraFutureNowLimit) {
        [void]$errors.Add("NOW_LIMIT $nowCount exceeds $($script:MetraFutureNowLimit)")
    }

    $childOwner = @{}
    foreach ($program in @($Portfolio.Programs)) {
        if ($script:MetraFutureProgramStatuses -notcontains $program.Status) {
            [void]$errors.Add("BAD_PROGRAM_STATUS $($program.Id) $($program.Status)")
        }
        if ([string]::IsNullOrWhiteSpace($program.Plan)) {
            [void]$errors.Add("MISSING_FIELD $($program.Id) plan")
        }
        else {
            if (-not (Test-MetraFuturePlanStem $program.Plan)) {
                [void]$errors.Add("UNRESOLVED_PLAN_REF program $($program.Id) repo:$($program.Plan)")
            }
            else {
                $programFile = Join-Path $MetraRoot ("plans\" + $program.Plan + '.plan.md')
                if (-not (Test-Path -LiteralPath $programFile)) {
                    [void]$errors.Add("UNRESOLVED_PLAN_REF program $($program.Id) repo:$($program.Plan)")
                }
            }
        }
        foreach ($child in @($program.Children)) {
            if (-not $seen.ContainsKey($child)) {
                [void]$errors.Add("MISSING_PROGRAM_CHILD $($program.Id) $child")
                continue
            }
            if ($childOwner.ContainsKey($child)) {
                [void]$errors.Add("MULTI_PROGRAM $child $($childOwner[$child]) $($program.Id)")
            }
            else { $childOwner[$child] = $program.Id }
        }
    }
    foreach ($item in @($Portfolio.Items)) {
        if ([string]::IsNullOrWhiteSpace($item.Program)) { continue }
        if (-not $childOwner.ContainsKey($item.Id) -or $childOwner[$item.Id] -ne $item.Program) {
            [void]$errors.Add("MULTI_PROGRAM $($item.Id) claims $($item.Program)")
        }
    }

    return @{
        Errors       = $errors
        ItemCount    = @($Portfolio.Items).Count
        ProgramCount = @($Portfolio.Programs).Count
        Portfolio    = $Portfolio
    }
}

function Get-MetraFuturePlanFrontmatter {
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    $front = ''
    if ($text -match '(?s)^---\r?\n(.*?)\r?\n---') { $front = $Matches[1] }
    $status = ''
    $product = ''
    $disposition = ''
    if ($front -match '(?m)^status:\s*(\S+)') { $status = $Matches[1].Trim() }
    if ($front -match '(?m)^product:\s*(.+)$') { $product = $Matches[1].Trim().Trim('"').Trim("'") }
    if ($front -match '(?m)^portfolio\.disposition:\s*(\S+)') { $disposition = $Matches[1].Trim() }
    $todoStatuses = New-Object System.Collections.ArrayList
    $inTodos = $false
    foreach ($line in ($front -split '\r?\n')) {
        if ($line -match '^todos:') { $inTodos = $true; continue }
        if ($inTodos -and $line -match '^[A-Za-z]') { $inTodos = $false }
        if ($inTodos -and $line -match 'status:\s*(\S+)') { [void]$todoStatuses.Add($Matches[1].Trim()) }
    }
    $openTodos = @($todoStatuses | Where-Object { $_ -notin @('completed', 'cancelled', 'canceled') })
    $nextBiteNone = $text -match '(?i)\*\*Next bite:\*\*\s*none'
    $implementationComplete = $status -in @('completed', 'cancelled', 'canceled') -or ($todoStatuses.Count -gt 0 -and $openTodos.Count -eq 0 -and $nextBiteNone)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($stem.EndsWith('.plan')) { $stem = [IO.Path]::GetFileNameWithoutExtension($stem) }
    return @{
        Path                     = $Path
        Stem                     = $stem
        Status                   = $status
        Product                  = $product
        Disposition              = $disposition
        ImplementationComplete   = [bool]$implementationComplete
    }
}

function Get-MetraFutureReconcileWarnings {
    param(
        [Parameter(Mandatory)]$Portfolio,
        [string]$MetraRoot = (Get-MetraRoot),
        [string]$CursorPlansDir = (Join-Path $env:USERPROFILE '.cursor\plans')
    )
    $warnings = New-Object System.Collections.ArrayList
    $referenced = @{}
    foreach ($item in @($Portfolio.Items)) {
        if (@($item.Plans).Count -eq 0) {
            [void]$warnings.Add(@{
                Code    = 'FUTURE_PLAN_MISSING'
                Message = "$($item.Id) has no structured plan link. Prose Home cannot satisfy one."
            })
        }
        foreach ($plan in @($item.Plans)) {
            $referenced[$plan.Ref] = $true
            if ($plan.Source -eq 'missing') {
                [void]$warnings.Add(@{
                    Code    = 'PLAN_SOURCE_MISSING'
                    Message = "$($item.Id) marks $($plan.Ref) source missing."
                })
                continue
            }
            $file = Resolve-MetraFuturePlanFile -Ref $plan.Ref -Source $plan.Source -MetraRoot $MetraRoot -CursorPlansDir $CursorPlansDir
            if (-not $file -or -not (Test-Path -LiteralPath $file)) { continue }
            $facts = Get-MetraFuturePlanFrontmatter -Path $file
            if ($facts.ImplementationComplete -and $item.Status -notin @('skip')) {
                [void]$warnings.Add(@{
                    Code    = 'FUTURE_PLAN_COMPLETED'
                    Message = "$($item.Id) is still live and links $($plan.Source):$($plan.Ref), which is implementation-complete ($($facts.Status))."
                })
            }
        }
    }

    $ids = @{}
    foreach ($item in @($Portfolio.Items)) { $ids[$item.Id] = $true }
    foreach ($pair in $script:MetraFutureDuplicatePairs) {
        if ($ids.ContainsKey($pair[0]) -and $ids.ContainsKey($pair[1])) {
            [void]$warnings.Add(@{
                Code    = 'DUPLICATE_WORK_RELATIONSHIP'
                Message = "$($pair[0]) and $($pair[1]) describe the same work."
            })
        }
    }

    $planFiles = New-Object System.Collections.ArrayList
    $repoDir = Join-Path $MetraRoot 'plans'
    if (Test-Path -LiteralPath $repoDir) {
        foreach ($file in [IO.Directory]::GetFiles($repoDir, '*.plan.md')) { [void]$planFiles.Add($file) }
    }
    if (Test-Path -LiteralPath $CursorPlansDir) {
        foreach ($file in [IO.Directory]::GetFiles($CursorPlansDir, '*.plan.md')) { [void]$planFiles.Add($file) }
    }
    foreach ($file in $planFiles) {
        $facts = Get-MetraFuturePlanFrontmatter -Path $file
        # product: was added to existing Metra plans so this filter can skip other products.
        # That normalization did not change plan status, todos, or body text.
        $isRepo = $file.StartsWith($repoDir, [StringComparison]::OrdinalIgnoreCase)
        if (-not $isRepo -and $facts.Product -ne 'Metra') { continue }
        if ($isRepo -and $facts.Product -and $facts.Product -ne 'Metra') { continue }
        if ($facts.Disposition) { continue }
        if ($facts.Status -in @('completed', 'cancelled', 'canceled')) { continue }
        if ($facts.ImplementationComplete) { continue }
        if ($referenced.ContainsKey($facts.Stem)) { continue }
        $where = $(if ($isRepo) { 'repo' } else { 'cursor' })
        [void]$warnings.Add(@{
            Code    = 'PLAN_WITHOUT_DISPOSITION'
            Message = "Open Metra plan ${where}:$($facts.Stem) has no portfolio disposition and no Future card."
        })
    }
    return @($warnings.ToArray())
}

function Get-MetraFutureCanvasPath {
    $metraRoot = Get-MetraRoot
    $slug = ConvertTo-MetraCursorProjectSlug -Path $metraRoot
    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'c-Projects-meta'
    }
    return Join-Path $env:USERPROFILE (Join-Path '.cursor\projects' (Join-Path $slug 'canvases\metra-future-development.canvas.tsx'))
}

function Get-MetraFutureIndexStems {
    param([string]$MetraRoot)
    $stems = @{}
    $indexPath = Join-Path $MetraRoot 'plans\index.yaml'
    if (-not (Test-Path -LiteralPath $indexPath)) { return $stems }
    foreach ($line in [IO.File]::ReadAllLines($indexPath)) {
        if ($line -match '^\s*-?\s*stem:\s*(\S+)\s*$') {
            $stems[$Matches[1].Trim()] = $true
        }
    }
    return $stems
}

function Get-MetraFutureDerivedSurveyor {
    param($Item, $IndexStems)
    $parent = $null
    $hasRepo = $false
    $hasCursor = $false
    $planCount = 0
    foreach ($plan in @($Item.Plans)) {
        if ($null -eq $plan) { continue }
        $planCount++
        if ($plan.Source -eq 'repo') { $hasRepo = $true }
        if ($plan.Source -eq 'cursor') { $hasCursor = $true }
        if ($plan.Role -eq 'parent' -and $null -eq $parent) { $parent = $plan }
    }
    if ($parent -and $parent.Source -eq 'repo' -and $IndexStems.ContainsKey([string]$parent.Ref)) {
        return "yes ($($parent.Ref))"
    }
    if (-not $hasRepo -and $hasCursor) { return 'cursor-only' }
    if ($planCount -eq 0) { return 'no' }
    return 'no'
}

function Format-MetraFutureJsString {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function Format-MetraFuturePlanCell {
    param($Plans)
    $parts = New-Object System.Collections.ArrayList
    foreach ($plan in @($Plans)) {
        if ($null -eq $plan -or [string]::IsNullOrWhiteSpace([string]$plan.Ref)) { continue }
        [void]$parts.Add("$($plan.Source):$($plan.Ref) ($($plan.Role))")
    }
    if ($parts.Count -eq 0) { return 'none' }
    return ($parts -join '; ')
}

function Format-MetraFutureTagCell {
    param($Tags)
    $names = New-Object System.Collections.ArrayList
    foreach ($tag in @($Tags)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tag)) { [void]$names.Add([string]$tag) }
    }
    if ($names.Count -eq 0) { return 'none' }
    return ($names -join ', ')
}

function Get-MetraFutureItemsForStatus {
    param($Portfolio, [string]$Status)
    $matched = New-Object System.Collections.ArrayList
    foreach ($item in $Portfolio.Items) {
        if ($item.Status -eq $Status) { [void]$matched.Add($item) }
    }
    return @($matched.ToArray() | Sort-Object { $_.Id })
}

function New-MetraFutureParkedMarkdown {
    param($Portfolio, $IndexStems)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('# Metra future parked')
    [void]$lines.Add('')
    [void]$lines.Add('Generated from docs/future.local.yaml. Edit that file, then run .\metra.ps1 future render. Do not hand-edit this file.')
    [void]$lines.Add('')
    foreach ($status in $script:MetraFutureItemStatuses) {
        $items = @(Get-MetraFutureItemsForStatus -Portfolio $Portfolio -Status $status)
        if ($items.Count -eq 0) { continue }
        [void]$lines.Add("## $status")
        [void]$lines.Add('')
        foreach ($item in $items) {
            [void]$lines.Add('### ' + $item.Title)
            [void]$lines.Add('')
            [void]$lines.Add([string]$item.Summary)
            [void]$lines.Add('')
            [void]$lines.Add('| Field | Value |')
            [void]$lines.Add('| ----- | ----- |')
            [void]$lines.Add('| Id | ' + $item.Id + ' |')
            [void]$lines.Add('| Status | ' + $item.Status + ' |')
            [void]$lines.Add('| Audience | ' + $item.Audience + ' |')
            [void]$lines.Add('| Product | ' + $item.Product + ' |')
            [void]$lines.Add('| Tags | ' + (Format-MetraFutureTagCell $item.Tags) + ' |')
            if ($item.Program) {
                [void]$lines.Add('| Program | ' + $item.Program + ' |')
            }
            [void]$lines.Add('| Plans | ' + (Format-MetraFuturePlanCell $item.Plans) + ' |')
            $surveyor = Get-MetraFutureDerivedSurveyor -Item $item -IndexStems $IndexStems
            [void]$lines.Add('| Surveyor | ' + $surveyor + ' |')
            [void]$lines.Add('| Verify | ' + $item.Verify + ' |')
            [void]$lines.Add('| Next | ' + $item.Next + ' |')
            if ($item.HardOffs) {
                [void]$lines.Add('| Hard offs | ' + $item.HardOffs + ' |')
            }
            [void]$lines.Add('')
        }
    }
    return (($lines -join "`n") + "`n")
}

function New-MetraFutureIndexMarkdown {
    param($Portfolio, $IndexStems)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('# Metra future development (operator index)')
    [void]$lines.Add('')
    [void]$lines.Add('Generated from docs/future.local.yaml. Edit that file, then run .\metra.ps1 future render. Do not hand-edit this file.')
    [void]$lines.Add('')
    [void]$lines.Add('## Now')
    [void]$lines.Add('')
    [void]$lines.Add('| Id | Title | Summary | Surveyor | Verify |')
    [void]$lines.Add('| -- | ----- | ------- | -------- | ------ |')
    foreach ($item in @(Get-MetraFutureItemsForStatus -Portfolio $Portfolio -Status 'now')) {
        $surveyor = Get-MetraFutureDerivedSurveyor -Item $item -IndexStems $IndexStems
        [void]$lines.Add('| ' + $item.Id + ' | ' + $item.Title + ' | ' + $item.Summary + ' | ' + $surveyor + ' | ' + $item.Verify + ' |')
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Programs')
    [void]$lines.Add('')
    $claimed = @{}
    foreach ($program in @($Portfolio.Programs)) {
        [void]$lines.Add('### ' + $program.Id)
        [void]$lines.Add('')
        [void]$lines.Add($program.Title + '. Status ' + $program.Status + '. Plan ' + $program.Plan + '.')
        [void]$lines.Add('')
        foreach ($childId in @($program.Children)) {
            $claimed[$childId] = $true
            $child = $null
            foreach ($item in $Portfolio.Items) {
                if ($item.Id -eq $childId) { $child = $item; break }
            }
            if ($null -eq $child) { continue }
            [void]$lines.Add('- ' + $child.Id + ' (' + $child.Status + '): ' + (Format-MetraFuturePlanCell $child.Plans))
        }
        [void]$lines.Add('')
    }
    [void]$lines.Add('## Unprogrammed')
    [void]$lines.Add('')
    $loose = New-Object System.Collections.ArrayList
    foreach ($item in $Portfolio.Items) {
        if (-not $claimed.ContainsKey($item.Id)) { [void]$loose.Add($item) }
    }
    foreach ($item in @($loose.ToArray() | Sort-Object { $_.Id })) {
        [void]$lines.Add('- ' + $item.Id + ' (' + $item.Status + '): ' + (Format-MetraFuturePlanCell $item.Plans))
    }
    [void]$lines.Add('')
    return (($lines -join "`n") + "`n")
}

function New-MetraFutureCanvasRegion {
    param($Portfolio, $IndexStems, $Warnings)
    $itemBlocks = New-Object System.Collections.ArrayList
    foreach ($item in $Portfolio.Items) {
        $surveyor = Get-MetraFutureDerivedSurveyor -Item $item -IndexStems $IndexStems
        $tagBits = New-Object System.Collections.ArrayList
        foreach ($tag in @($item.Tags)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$tag)) { [void]$tagBits.Add((Format-MetraFutureJsString $tag)) }
        }
        $planBits = New-Object System.Collections.ArrayList
        foreach ($plan in @($item.Plans)) {
            if ($null -eq $plan) { continue }
            $planText = '{{ "ref": {0}, "role": {1}, "source": {2} }}' -f (Format-MetraFutureJsString $plan.Ref), (Format-MetraFutureJsString $plan.Role), (Format-MetraFutureJsString $plan.Source)
            [void]$planBits.Add($planText)
        }
        $blockLines = New-Object System.Collections.ArrayList
        [void]$blockLines.Add('    {')
        [void]$blockLines.Add(('      "id": {0},' -f (Format-MetraFutureJsString $item.Id)))
        [void]$blockLines.Add(('      "title": {0},' -f (Format-MetraFutureJsString $item.Title)))
        [void]$blockLines.Add(('      "summary": {0},' -f (Format-MetraFutureJsString $item.Summary)))
        [void]$blockLines.Add(('      "status": {0},' -f (Format-MetraFutureJsString $item.Status)))
        [void]$blockLines.Add(('      "audience": {0},' -f (Format-MetraFutureJsString $item.Audience)))
        [void]$blockLines.Add(('      "product": {0},' -f (Format-MetraFutureJsString $item.Product)))
        [void]$blockLines.Add(('      "tags": [{0}],' -f ($tagBits -join ', ')))
        [void]$blockLines.Add(('      "program": {0},' -f (Format-MetraFutureJsString $item.Program)))
        [void]$blockLines.Add(('      "plans": [{0}],' -f ($planBits -join ', ')))
        [void]$blockLines.Add(('      "surveyor": {0},' -f (Format-MetraFutureJsString $surveyor)))
        [void]$blockLines.Add(('      "next": {0},' -f (Format-MetraFutureJsString $item.Next)))
        [void]$blockLines.Add(('      "verify": {0},' -f (Format-MetraFutureJsString $item.Verify)))
        [void]$blockLines.Add(('      "hardOffs": {0}' -f (Format-MetraFutureJsString $item.HardOffs)))
        [void]$blockLines.Add('    }')
        [void]$itemBlocks.Add(($blockLines -join "`n"))
    }
    $programBlocks = New-Object System.Collections.ArrayList
    foreach ($program in @($Portfolio.Programs)) {
        $childBits = New-Object System.Collections.ArrayList
        foreach ($child in @($program.Children)) { [void]$childBits.Add((Format-MetraFutureJsString $child)) }
        $blockLines = New-Object System.Collections.ArrayList
        [void]$blockLines.Add('    {')
        [void]$blockLines.Add(('      "id": {0},' -f (Format-MetraFutureJsString $program.Id)))
        [void]$blockLines.Add(('      "title": {0},' -f (Format-MetraFutureJsString $program.Title)))
        [void]$blockLines.Add(('      "product": {0},' -f (Format-MetraFutureJsString $program.Product)))
        [void]$blockLines.Add(('      "status": {0},' -f (Format-MetraFutureJsString $program.Status)))
        [void]$blockLines.Add(('      "plan": {0},' -f (Format-MetraFutureJsString $program.Plan)))
        [void]$blockLines.Add(('      "children": [{0}]' -f ($childBits -join ', ')))
        [void]$blockLines.Add('    }')
        [void]$programBlocks.Add(($blockLines -join "`n"))
    }
    $warningList = New-Object System.Collections.ArrayList
    foreach ($warning in @($Warnings)) {
        if ($null -eq $warning) { continue }
        if (-not $warning.Code) { continue }
        [void]$warningList.Add($warning)
    }
    $warningBlocks = New-Object System.Collections.ArrayList
    foreach ($warning in $warningList) {
        $blockLines = New-Object System.Collections.ArrayList
        [void]$blockLines.Add('    {')
        [void]$blockLines.Add(('      "code": {0},' -f (Format-MetraFutureJsString $warning.Code)))
        [void]$blockLines.Add(('      "message": {0}' -f (Format-MetraFutureJsString $warning.Message)))
        [void]$blockLines.Add('    }')
        [void]$warningBlocks.Add(($blockLines -join "`n"))
    }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('// metra-future-data:start')
    [void]$lines.Add('const FUTURE_MODEL = {')
    [void]$lines.Add('  "items": [')
    [void]$lines.Add(($itemBlocks -join ",`n"))
    [void]$lines.Add('  ],')
    [void]$lines.Add('  "programs": [')
    [void]$lines.Add(($programBlocks -join ",`n"))
    [void]$lines.Add('  ],')
    if ($warningBlocks.Count -eq 0) {
        [void]$lines.Add('  "warnings": []')
    }
    else {
        [void]$lines.Add('  "warnings": [')
        [void]$lines.Add(($warningBlocks -join ",`n"))
        [void]$lines.Add('  ]')
    }
    [void]$lines.Add('} as const')
    [void]$lines.Add('void FUTURE_MODEL')
    [void]$lines.Add('// metra-future-data:end')
    return ($lines -join "`n")
}

function Get-MetraFutureCanvasMarkerSpan {
    param([Parameter(Mandatory)][string]$Text)
    $startToken = '// metra-future-data:start'
    $endToken = '// metra-future-data:end'
    $starts = New-Object System.Collections.ArrayList
    $ends = New-Object System.Collections.ArrayList
    $from = 0
    while (($at = $Text.IndexOf($startToken, $from)) -ge 0) {
        [void]$starts.Add($at)
        $from = $at + $startToken.Length
    }
    $from = 0
    while (($at = $Text.IndexOf($endToken, $from)) -ge 0) {
        [void]$ends.Add($at)
        $from = $at + $endToken.Length
    }
    if ($starts.Count -eq 0 -and $ends.Count -eq 0) {
        return @{ Mode = 'insert' }
    }
    if ($starts.Count -eq 1 -and $ends.Count -eq 1 -and [int]$starts[0] -lt [int]$ends[0]) {
        return @{ Mode = 'replace'; Start = [int]$starts[0]; End = [int]$ends[0] + $endToken.Length }
    }
    throw 'Future canvas markers are invalid. Render wrote nothing.'
}

function New-MetraFutureCanvasText {
    param(
        $Portfolio,
        $IndexStems,
        $Warnings,
        [Parameter(Mandatory)][string]$CanvasPath
    )
    if (-not (Test-Path -LiteralPath $CanvasPath)) {
        throw "Future canvas not found: $CanvasPath"
    }
    $text = [IO.File]::ReadAllText($CanvasPath)
    $span = Get-MetraFutureCanvasMarkerSpan -Text $text
    $region = New-MetraFutureCanvasRegion -Portfolio $Portfolio -IndexStems $IndexStems -Warnings $Warnings
    if ($span.Mode -eq 'insert') {
        $needle = "} from 'cursor/canvas';"
        $at = $text.IndexOf($needle)
        if ($at -lt 0) { throw 'Canvas import from cursor/canvas was not found. Render wrote nothing.' }
        $insertAt = $at + $needle.Length
        if ($insertAt -lt $text.Length -and $text[$insertAt] -eq "`r") { $insertAt++ }
        if ($insertAt -lt $text.Length -and $text[$insertAt] -eq "`n") { $insertAt++ }
        return $text.Substring(0, $insertAt) + $region + "`n" + $text.Substring($insertAt)
    }
    return $text.Substring(0, $span.Start) + $region + $text.Substring($span.End)
}

function New-MetraFutureProjectionBundle {
    param(
        [Parameter(Mandatory)]$Portfolio,
        [string]$MetraRoot = (Get-MetraRoot),
        [Parameter(Mandatory)][string]$CanvasPath
    )
    $stems = Get-MetraFutureIndexStems -MetraRoot $MetraRoot
    $warningList = New-Object System.Collections.ArrayList
    foreach ($warning in @(Get-MetraFutureReconcileWarnings -Portfolio $Portfolio -MetraRoot $MetraRoot)) {
        [void]$warningList.Add($warning)
    }
    $parked = New-MetraFutureParkedMarkdown -Portfolio $Portfolio -IndexStems $stems
    $index = New-MetraFutureIndexMarkdown -Portfolio $Portfolio -IndexStems $stems
    $canvas = New-MetraFutureCanvasText -Portfolio $Portfolio -IndexStems $stems -Warnings $warningList -CanvasPath $CanvasPath
    if ([string]::IsNullOrWhiteSpace($parked) -or [string]::IsNullOrWhiteSpace($index) -or [string]::IsNullOrWhiteSpace($canvas)) {
        throw 'Future projection was not constructible. Render wrote nothing.'
    }
    return @{ Parked = $parked; Index = $index; Canvas = $canvas }
}

function Write-MetraFutureTextAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $tmp = $Path + '.metra-tmp'
    [IO.File]::WriteAllText($tmp, $Text, $utf8)
    try {
        if (Test-Path -LiteralPath $Path) {
            $bak = "$Path.bak"
            [IO.File]::Replace($tmp, $Path, $bak)
            Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::Move($tmp, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Publish-MetraFutureOutputs {
    param(
        [Parameter(Mandatory)]$Outputs,
        [scriptblock]$BeforeEach
    )
    $list = New-Object System.Collections.ArrayList
    foreach ($output in $Outputs) { [void]$list.Add($output) }
    $saved = New-Object System.Collections.ArrayList
    foreach ($output in $list) {
        $existed = Test-Path -LiteralPath $output.Path
        $prior = $null
        if ($existed) { $prior = [IO.File]::ReadAllText($output.Path) }
        [void]$saved.Add(@{ Path = $output.Path; Existed = $existed; Text = $prior })
    }
    $completed = 0
    try {
        for ($i = 0; $i -lt $list.Count; $i++) {
            if ($BeforeEach) { & $BeforeEach $i $list[$i].Path }
            Write-MetraFutureTextAtomic -Path $list[$i].Path -Text $list[$i].Text
            $completed++
        }
    }
    catch {
        for ($j = $completed - 1; $j -ge 0; $j--) {
            $snap = $saved[$j]
            if ($snap.Existed) {
                Write-MetraFutureTextAtomic -Path $snap.Path -Text $snap.Text
            }
            elseif (Test-Path -LiteralPath $snap.Path) {
                Remove-Item -LiteralPath $snap.Path -Force
            }
        }
        throw
    }
}

function Test-MetraFutureProjectionMatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $stream = New-Object System.IO.MemoryStream (,$utf8.GetBytes($Text))
    try {
        $expected = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
    }
    finally { $stream.Dispose() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "future render drift: $Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($expected -ne $actual) {
        throw "future render drift: $Path"
    }
}

function Invoke-MetraFutureCommand {
    param(
        [Parameter(Mandatory)][string]$Subcommand,
        [string]$Path,
        [switch]$Check,
        [switch]$WhatIf
    )
    $store = $Path
    if ([string]::IsNullOrWhiteSpace($store)) { $store = Get-MetraFutureStorePath }
    switch ($Subcommand) {
        'validate' {
            $portfolio = ConvertFrom-MetraFutureYaml -Path $store
            $result = Test-MetraFutureModel -Portfolio $portfolio
            if ($result.Errors.Count -gt 0) {
                foreach ($err in $result.Errors) { Write-Host $err }
                throw "future validate failed ($($result.Errors.Count))"
            }
            Write-Host "future validate ok ($($result.ItemCount) items, $($result.ProgramCount) programs)"
        }
        'reconcile' {
            $portfolio = ConvertFrom-MetraFutureYaml -Path $store
            $result = Test-MetraFutureModel -Portfolio $portfolio
            if ($result.Errors.Count -gt 0) {
                foreach ($err in $result.Errors) { Write-Host $err }
                throw "future reconcile refused: validate failed ($($result.Errors.Count))"
            }
            $before = (Get-Item -LiteralPath $store).LastWriteTimeUtc
            $warnings = @(Get-MetraFutureReconcileWarnings -Portfolio $portfolio)
            foreach ($warning in $warnings) {
                Write-Host ("{0}  {1}" -f $warning.Code, $warning.Message)
            }
            $after = (Get-Item -LiteralPath $store).LastWriteTimeUtc
            if ($after -ne $before) {
                throw 'future reconcile wrote the store'
            }
            Write-Host ("future reconcile warnings: {0}" -f $warnings.Count)
        }
        'render' {
            $portfolio = ConvertFrom-MetraFutureYaml -Path $store
            $result = Test-MetraFutureModel -Portfolio $portfolio
            if ($result.Errors.Count -gt 0) {
                foreach ($err in $result.Errors) { Write-Host $err }
                throw "future render refused: validate failed ($($result.Errors.Count))"
            }
            $root = Get-MetraRoot
            $parkedPath = Join-Path $root 'docs\Future-Parked.local.md'
            $indexPath = Join-Path $root 'docs\Future-Development.local.md'
            $canvasPath = Get-MetraFutureCanvasPath
            $bundle = New-MetraFutureProjectionBundle -Portfolio $portfolio -MetraRoot $root -CanvasPath $canvasPath
            if ($Check) {
                Test-MetraFutureProjectionMatch -Path $parkedPath -Text $bundle.Parked
                Test-MetraFutureProjectionMatch -Path $indexPath -Text $bundle.Index
                Test-MetraFutureProjectionMatch -Path $canvasPath -Text $bundle.Canvas
                Write-Host 'future render check ok'
            }
            else {
                if ($WhatIf) {
                    Write-Host "WhatIf: would write $parkedPath"
                    Write-Host "WhatIf: would write $indexPath"
                    Write-Host "WhatIf: would write $canvasPath"
                }
                else {
                    $outputs = New-Object System.Collections.ArrayList
                    [void]$outputs.Add(@{ Path = $parkedPath; Text = $bundle.Parked })
                    [void]$outputs.Add(@{ Path = $indexPath; Text = $bundle.Index })
                    [void]$outputs.Add(@{ Path = $canvasPath; Text = $bundle.Canvas })
                    Publish-MetraFutureOutputs -Outputs $outputs
                    Write-Host 'future render wrote 3 projections'
                }
            }
        }
        default { throw "Unknown future subcommand: $Subcommand" }
    }
}
