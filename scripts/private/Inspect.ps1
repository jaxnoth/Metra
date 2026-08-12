# Metra Inspect Phase 1 - local plan/diff advisory via Ask engine (recommend-only).

function Get-MetraInspectStateRoot {
    <#
    .SYNOPSIS
        Machine-local Inspect persist root under LocalAppData (path only; writers create).
    #>
    [CmdletBinding()]
    param()
    return (Join-Path $env:LOCALAPPDATA 'Metra\inspect')
}

function Get-MetraInspectFileClass {
    <#
    .SYNOPSIS
        Simple scope-reducer classification for a relative path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    $p = ([string]$RelativePath).Replace('\', '/')

    while ($p.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $p = $p.Substring(2)
    }

    $p = $p.TrimStart('/')

    $leaf = [System.IO.Path]::GetFileName($p)
    $ext = [System.IO.Path]::GetExtension($p).ToLowerInvariant()

    if ($p -match '(^|/)(credentials|node_modules|\.venv|bin|obj|secrets)(/|$)' -or
        $leaf -match '\.local\.json$' -or
        $leaf -match '^\.env' -or
        $leaf -match '(secret|password|credential|apikey|api_key)' -or
        $ext -in @('.pem', '.pfx', '.p12', '.key') -or
        $leaf -in @('package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'Cargo.lock') -or
        $ext -in @('.dll', '.exe', '.png', '.jpg', '.jpeg', '.gif', '.zip', '.pdf', '.pbix', '.woff', '.woff2')) {
        return 'skip'
    }

    if ($ext -in @('.ps1', '.psm1', '.psd1', '.cs', '.py', '.ts', '.tsx', '.js', '.jsx', '.sql', '.go', '.rs', '.java', '.cpp', '.c', '.h')) {
        return 'code'
    }

    if ($ext -in @('.json', '.yaml', '.yml', '.xml', '.toml', '.ini', '.config') -and $leaf -notmatch 'lock') {
        return 'config'
    }

    if ($ext -eq '.md' -or $leaf -match '^(readme|agents|license)' ) {
        return 'docs'
    }

    if ($ext -in @('.txt', '.csv', '.html', '.css', '.scss')) {
        return 'docs'
    }

    return 'config'
}

function Get-MetraInspectInputHash {
    <#
    .SYNOPSIS
        Stable sha256 hex over ordered path/content pairs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Parts
    )

    $sb = New-Object System.Text.StringBuilder
    foreach ($part in @($Parts)) {
        $path = [string](Get-MetraProp -Object $part -Name 'path' -Default '')
        $content = [string](Get-MetraProp -Object $part -Name 'content' -Default '')
        [void]$sb.Append($path).Append("`n").Append($content).Append("`n---\n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $algo = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algo.ComputeHash($bytes)
    }
    finally {
        $algo.Dispose()
    }
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

function Resolve-MetraInspectGitBase {
    <#
    .SYNOPSIS
        Validates Inspect -Base as a safe, resolvable git revision in Root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Base
    )

    $trimmed = if ($null -eq $Base) { '' } else { $Base.Trim() }
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'Inspect -Base cannot be empty or whitespace.'
    }
    if ($trimmed.StartsWith('-')) {
        throw "Inspect -Base must not start with '-': $trimmed"
    }
    if ($trimmed -notmatch '^[A-Za-z0-9._/@~^+-]+$') {
        throw "Inspect -Base contains invalid characters: $trimmed"
    }
    if ($trimmed -match '(^|/)\.\.(/|$)') {
        throw "Inspect -Base must not contain path traversal segments: $trimmed"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
        throw "Not a git repository: $Root"
    }

    Push-Location -LiteralPath $Root
    try {
        $null = & git rev-parse --verify --quiet "${trimmed}^{commit}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $null = & git rev-parse --verify --quiet $trimmed 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Inspect -Base is not a valid git revision: $trimmed"
            }
        }
    }
    finally {
        Pop-Location
    }
    return $trimmed
}

function Get-MetraInspectUntrackedFiles {
    <#
    .SYNOPSIS
        Reads includable untracked text files for working-tree inspect (cwd must be repo root).
    #>
    [CmdletBinding()]
    param(
        [int]$MaxChars = 40000
    )

    $listed = & git ls-files --others --exclude-standard 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files --others failed: $($listed | Out-String)"
    }

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($rawPath in @($listed)) {
        $path = ([string]$rawPath).Trim()
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $path = $path.Replace('\', '/')
        if ((Get-MetraInspectFileClass -RelativePath $path) -eq 'skip') { continue }

        $full = Join-Path (Get-Location).Path ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $body = ''
        $truncated = $false
        try {
            $item = Get-Item -LiteralPath $full -ErrorAction Stop
            $byteCap = $MaxChars * 4
            if ($item.Length -gt $byteCap) {
                $truncated = $true
                $bytes = New-Object byte[] $byteCap
                $stream = [System.IO.File]::OpenRead($full)
                try {
                    $read = $stream.Read($bytes, 0, $byteCap)
                }
                finally {
                    $stream.Dispose()
                }
                $raw = if ($read -gt 0) {
                    [System.Text.Encoding]::UTF8.GetString($bytes, 0, $read)
                }
                else { '' }
            }
            else {
                $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8 -ErrorAction Stop
            }
            if ($null -eq $raw) { $raw = '' }
            if ($raw.Length -gt $MaxChars) {
                $body = $raw.Substring(0, $MaxChars) + "`n...[truncated]..."
                $truncated = $true
            }
            else {
                $body = $raw
            }
        }
        catch {
            # Binary / unreadable - skip rather than poison the inspect set.
            continue
        }

        $prefix = "UNTRACKED FILE: $path`nThis entire file is new in the working tree."
        if ($truncated) { $prefix = "$prefix (truncated)" }
        [void]$files.Add([PSCustomObject]@{
                path    = $path
                content = "$prefix`n$body"
            })
    }
    return @($files.ToArray())
}

function Test-MetraInspectWorkingTreeDirty {
    <#
    .SYNOPSIS
        True when porcelain status shows local changes (cwd must be repo root).
    #>
    [CmdletBinding()]
    param()

    $status = & git status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git status --porcelain failed: $($status | Out-String)"
    }
    $text = (@($status) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
    return -not [string]::IsNullOrWhiteSpace($text)
}

function Resolve-MetraInspectProjectContext {
    <#
    .SYNOPSIS
        Resolves project name/path for Inspect. Diff fails closed; plan may be context-limited.
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [ValidateSet('diff', 'plan')][string]$Mode = 'diff',
        [string]$Cwd = (Get-Location).Path
    )

    $result = [PSCustomObject]@{
        Ok             = $false
        Project        = $null
        Root           = $null
        ContextLimited = $false
        Warning        = $null
        Error          = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $n = $Name.Trim()
        if ($n -ieq 'Metra' -or $n -ieq '_meta' -or $n -ieq '_metra') {
            $orch = Get-MetraOrchestrationProject
            $result.Ok = $true
            $result.Project = [string]$orch.Name
            $result.Root = [string]$orch.Path
            return $result
        }
        $hit = @(Get-MetraProject -Name $n | Where-Object { -not $_.Shadowed }) | Select-Object -First 1
        if (-not $hit) {
            $result.Error = "Unknown project '$n'."
            return $result
        }
        $result.Ok = $true
        $result.Project = [string]$hit.Name
        $result.Root = [string]$hit.Path
        return $result
    }

    $cwdFull = try { [System.IO.Path]::GetFullPath($Cwd) } catch { $null }
    if ($cwdFull) {
        $metraRoot = [System.IO.Path]::GetFullPath((Get-MetraRoot))
        if ($cwdFull.Equals($metraRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $cwdFull.StartsWith($metraRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            $orch = Get-MetraOrchestrationProject
            $result.Ok = $true
            $result.Project = [string]$orch.Name
            $result.Root = [string]$orch.Path
            return $result
        }

        $projects = @(Get-MetraProjects | Where-Object { -not $_.Shadowed -and $_.Path })
        $matches = @(
            foreach ($p in $projects) {
                $pp = [System.IO.Path]::GetFullPath([string]$p.Path)
                if ($cwdFull.Equals($pp, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $cwdFull.StartsWith($pp + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $p
                }
            }
        )
        if ($matches.Count -eq 1) {
            $result.Ok = $true
            $result.Project = [string]$matches[0].Name
            $result.Root = [string]$matches[0].Path
            return $result
        }
        if ($matches.Count -gt 1) {
            $result.Error = 'Ambiguous project root for cwd. Pass -Name <Project>.'
            return $result
        }
    }

    if ($Mode -eq 'plan') {
        $result.Ok = $true
        $result.ContextLimited = $true
        $result.Warning = 'Project context not resolved; inspecting plan without AGENTS.md / Decisions context.'
        return $result
    }

    $result.Error = 'Could not resolve project root. Pass -Name <Project> or run from a project directory.'
    return $result
}

function Get-MetraInspectPlanRoots {
    [CmdletBinding()]
    param(
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $roots = New-Object System.Collections.Generic.List[string]
    $userPlans = Join-Path $env:USERPROFILE '.cursor\plans'
    if (Test-Path -LiteralPath $userPlans) { [void]$roots.Add($userPlans) }
    $checkoutPlans = Join-Path $MetraRoot '.cursor\plans'
    if (Test-Path -LiteralPath $checkoutPlans) { [void]$roots.Add($checkoutPlans) }
    return @($roots)
}

function Get-MetraInspectRecentPlans {
    <#
    .SYNOPSIS
        Recent *.plan.md under known plan roots (newest first).
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 10,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $files = @(
        foreach ($root in @(Get-MetraInspectPlanRoots -MetraRoot $MetraRoot)) {
            Get-ChildItem -LiteralPath $root -Filter '*.plan.md' -File -ErrorAction SilentlyContinue
        }
    )
    return @(
        $files |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First $Limit |
            ForEach-Object {
                [PSCustomObject]@{
                    Name             = $_.Name
                    Path             = $_.FullName
                    LastWriteTimeUtc = $_.LastWriteTimeUtc
                }
            }
    )
}

function Resolve-MetraInspectPlanPath {
    <#
    .SYNOPSIS
        Resolves plan path from -Latest, fragment, or -Path. Fail closed on conflicts.
    #>
    [CmdletBinding()]
    param(
        [switch]$Latest,
        [string]$Path,
        [string]$Fragment,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $selectorCount = 0
    if ($Latest) { $selectorCount++ }
    if (-not [string]::IsNullOrWhiteSpace($Path)) { $selectorCount++ }
    if (-not [string]::IsNullOrWhiteSpace($Fragment)) { $selectorCount++ }

    if ($selectorCount -eq 0) {
        return [PSCustomObject]@{
            Ok      = $false
            ListOnly = $true
            Path    = $null
            Error   = $null
            Matches = @(Get-MetraInspectRecentPlans -MetraRoot $MetraRoot)
        }
    }
    if ($selectorCount -gt 1) {
        return [PSCustomObject]@{
            Ok       = $false
            ListOnly = $false
            Path     = $null
            Error    = 'Only one plan selector is allowed: -Latest, filename fragment, or -Path.'
            Matches  = @()
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return [PSCustomObject]@{
                Ok       = $false
                ListOnly = $false
                Path     = $null
                Error    = "Plan file not found: $full"
                Matches  = @()
            }
        }
        $fullPath = [System.IO.Path]::GetFullPath($full)
        if (-not $fullPath.EndsWith('.plan.md', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [PSCustomObject]@{
                Ok       = $false
                ListOnly = $false
                Path     = $null
                Error    = "Plan -Path must be a *.plan.md file: $fullPath"
                Matches  = @()
            }
        }
        $allowed = $false
        foreach ($root in @(Get-MetraInspectPlanRoots -MetraRoot $MetraRoot)) {
            if (Test-MetraPathWithinRoot -Path $fullPath -Root $root) {
                $allowed = $true
                break
            }
        }
        if (-not $allowed) {
            return [PSCustomObject]@{
                Ok       = $false
                ListOnly = $false
                Path     = $null
                Error    = "Plan -Path must be under a known plan root (~/.cursor/plans or <metra>/.cursor/plans): $fullPath"
                Matches  = @()
            }
        }
        return [PSCustomObject]@{
            Ok       = $true
            ListOnly = $false
            Path     = $fullPath
            Error    = $null
            Matches  = @()
        }
    }

    $all = @(Get-MetraInspectRecentPlans -Limit 200 -MetraRoot $MetraRoot)
    if ($Latest) {
        if ($all.Count -eq 0) {
            return [PSCustomObject]@{
                Ok       = $false
                ListOnly = $false
                Path     = $null
                Error    = 'No *.plan.md files found under known plan roots.'
                Matches  = @()
            }
        }
        return [PSCustomObject]@{
            Ok       = $true
            ListOnly = $false
            Path     = [string]$all[0].Path
            Error    = $null
            Matches  = @($all[0])
        }
    }

    $frag = $Fragment.Trim()
    $fragLiteral = [regex]::Escape($frag)
    $hits = @($all | Where-Object { $_.Name -match $fragLiteral })
    if ($hits.Count -eq 0) {
        return [PSCustomObject]@{
            Ok       = $false
            ListOnly = $false
            Path     = $null
            Error    = "No plan filename matched fragment '$frag'."
            Matches  = @()
        }
    }
    if ($hits.Count -gt 1) {
        return [PSCustomObject]@{
            Ok       = $false
            ListOnly = $false
            Path     = $null
            Error    = "Ambiguous plan fragment '$frag'. Pass -Path or a more specific fragment."
            Matches  = $hits
        }
    }
    return [PSCustomObject]@{
        Ok       = $true
        ListOnly = $false
        Path     = [string]$hits[0].Path
        Error    = $null
        Matches  = $hits
    }
}

function Reduce-MetraInspectDiffFiles {
    <#
    .SYNOPSIS
        Classifies and caps changed files for the inspect prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Files,
        [int]$MaxFiles = 24,
        [int]$MaxBytesPerFile = 24000
    )

    $ordered = @(
        $Files |
            ForEach-Object {
                $cls = Get-MetraInspectFileClass -RelativePath ([string]$_.path)
                [PSCustomObject]@{
                    path    = [string]$_.path
                    content = [string]$_.content
                    class   = $cls
                }
            }
    )

    $skipped = @($ordered | Where-Object { $_.class -eq 'skip' })
    $nonSkip = @($ordered | Where-Object { $_.class -ne 'skip' })
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($cls in @('code', 'config', 'docs')) {
        foreach ($item in @($nonSkip | Where-Object { $_.class -eq $cls } | Sort-Object path)) {
            [void]$kept.Add($item)
        }
    }
    foreach ($item in @($nonSkip | Where-Object { $_.class -notin @('code', 'config', 'docs') } | Sort-Object path)) {
        [void]$kept.Add($item)
    }

    $reduced = New-Object System.Collections.Generic.List[object]
    $docsCollapsed = New-Object System.Collections.Generic.List[string]
    $omittedByFileCap = New-Object System.Collections.Generic.List[string]
    $atFileCap = $false
    foreach ($f in $kept) {
        if ($f.class -eq 'docs') {
            [void]$docsCollapsed.Add([string]$f.path)
            continue
        }
        if ($reduced.Count -ge $MaxFiles) {
            $atFileCap = $true
        }
        if ($atFileCap) {
            [void]$omittedByFileCap.Add([string]$f.path)
            continue
        }
        $content = [string]$f.content
        if ($content.Length -gt $MaxBytesPerFile) {
            $content = $content.Substring(0, $MaxBytesPerFile) + "`n...[truncated]..."
        }
        [void]$reduced.Add([PSCustomObject]@{
                path    = [string]$f.path
                content = $content
                class   = [string]$f.class
            })
    }

    # If only docs changed, include one collapsed summary entry.
    if ($reduced.Count -eq 0 -and $docsCollapsed.Count -gt 0) {
        [void]$reduced.Add([PSCustomObject]@{
                path    = '(docs)'
                content = "Documentation-only changes:`n- " + ($docsCollapsed -join "`n- ")
                class   = 'docs'
            })
    }
    # docs-collapsed is an intentional sidecar; MaxFiles applies to primary files only.
    elseif ($docsCollapsed.Count -gt 0) {
        [void]$reduced.Add([PSCustomObject]@{
                path    = '(docs-collapsed)'
                content = "Collapsed docs paths:`n- " + ($docsCollapsed -join "`n- ")
                class   = 'docs'
            })
    }

    $truncatedAny = $false
    foreach ($rf in $reduced) {
        if ([string]$rf.content -match '\[truncated\]') { $truncatedAny = $true; break }
    }

    return [PSCustomObject]@{
        Files            = @($reduced.ToArray())
        FileCount        = @($Files).Count
        ReducedFileCount = $reduced.Count
        SkippedFileCount = @($skipped).Count
        SkippedPaths     = @(@($skipped) | ForEach-Object { [string]$_.path })
        DocsCollapsed    = @($docsCollapsed.ToArray())
        Truncated        = $truncatedAny
        OmittedByFileCap = @($omittedByFileCap.ToArray())
    }
}

function Get-MetraInspectGitDiffFiles {
    <#
    .SYNOPSIS
        Collects inspectable file contents from git. Working-tree mode includes untracked text;
        -Base mode is three-dot Base...HEAD only (local dirty tree excluded, with warning).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Base
    )

    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
        throw "Not a git repository: $Root"
    }

    $hasBase = -not [string]::IsNullOrWhiteSpace($Base)
    $resolvedBase = $null
    if ($hasBase) {
        $resolvedBase = Resolve-MetraInspectGitBase -Root $Root -Base $Base
    }

    Push-Location -LiteralPath $Root
    try {
        $workingTreeDirty = $false
        $warning = $null
        $untrackedCount = 0
        $baseMode = if ($hasBase) { 'range' } else { 'working-tree' }

        if ($hasBase) {
            $workingTreeDirty = Test-MetraInspectWorkingTreeDirty
            if ($workingTreeDirty) {
                $warning = '-Base inspects committed range Base...HEAD only; local staged/unstaged/untracked edits are excluded.'
            }
            $rawDiff = & git --no-pager diff "$resolvedBase...HEAD" -- 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git diff failed: $($rawDiff | Out-String)"
            }
            $diffText = (@($rawDiff) | ForEach-Object { [string]$_ }) -join "`n"
        }
        else {
            $unstaged = & git --no-pager diff -- 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git diff failed: $($unstaged | Out-String)" }
            $staged = & git --no-pager diff --cached -- 2>&1
            if ($LASTEXITCODE -ne 0) { throw "git diff --cached failed: $($staged | Out-String)" }
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($x in @($unstaged)) { [void]$parts.Add([string]$x) }
            foreach ($x in @($staged)) { [void]$parts.Add([string]$x) }
            $diffText = ($parts.ToArray() -join "`n").Trim()
        }

        $files = New-Object System.Collections.Generic.List[object]
        $seen = @{}
        if (-not [string]::IsNullOrWhiteSpace($diffText)) {
            $currentPath = $null
            $buf = New-Object System.Text.StringBuilder
            foreach ($line in ($diffText -split "`r?`n")) {
                if ($line -match '^diff --git a/(.+?) b/(.+)$') {
                    if ($currentPath) {
                        [void]$files.Add([PSCustomObject]@{
                                path    = $currentPath
                                content = $buf.ToString()
                            })
                        $seen[$currentPath] = $true
                    }
                    $currentPath = $Matches[2]
                    $buf = New-Object System.Text.StringBuilder
                }
                if ($null -ne $currentPath) {
                    [void]$buf.AppendLine($line)
                }
            }
            if ($currentPath) {
                [void]$files.Add([PSCustomObject]@{
                        path    = $currentPath
                        content = $buf.ToString()
                    })
                $seen[$currentPath] = $true
            }
        }

        if (-not $hasBase) {
            $untracked = @(Get-MetraInspectUntrackedFiles)
            $untrackedCount = $untracked.Count
            foreach ($uf in $untracked) {
                $p = [string]$uf.path
                if ($seen.ContainsKey($p)) { continue }
                [void]$files.Add($uf)
                $seen[$p] = $true
            }
        }

        $head = [string](& git rev-parse HEAD 2>$null)
        return [PSCustomObject]@{
            Empty            = ($files.Count -eq 0)
            Files            = @($files.ToArray())
            GitHead          = $head
            RawDiff          = [string]$diffText
            UntrackedCount   = [int]$untrackedCount
            WorkingTreeDirty = [bool]$workingTreeDirty
            Warning          = $warning
            BaseMode         = $baseMode
            Base             = $(if ($resolvedBase) { $resolvedBase } else { '' })
        }
    }
    finally {
        Pop-Location
    }
}

function Get-MetraInspectAgentsText {
    [CmdletBinding()]
    param(
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { return $null }
    $raw = $null
    $source = $null
    $maxLen = 12000
    $agents = Join-Path $Root 'AGENTS.md'
    if (Test-Path -LiteralPath $agents) {
        $raw = Get-Content -LiteralPath $agents -Raw -ErrorAction Stop
        $source = 'AGENTS.md'
    }
    else {
        $readme = Join-Path $Root 'README.md'
        if (Test-Path -LiteralPath $readme) {
            $raw = Get-Content -LiteralPath $readme -Raw -ErrorAction Stop
            $source = 'README.md'
            $maxLen = 8000
        }
    }
    if ($null -eq $raw) { return $null }

    $scrub = Invoke-MetraAskSecretsScrubText -Text $raw
    if ($scrub.Refuse) {
        throw ("$source refused by secrets scrub: {0}" -f $scrub.Reason)
    }
    $text = [string]$scrub.Text
    if ($text.Length -gt $maxLen) {
        return $text.Substring(0, $maxLen) + "`n...[truncated]..."
    }
    return $text
}

function ConvertTo-MetraInspectScrubbedDiffParts {
    <#
    .SYNOPSIS
        Scrubs reduced diff file contents. Fail closed on Refuse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files
    )

    $scrubbed = New-Object System.Collections.Generic.List[object]
    foreach ($rf in @($Files)) {
        $scrub = Invoke-MetraAskSecretsScrubText -Text ([string](Get-MetraProp -Object $rf -Name 'content' -Default ''))
        $path = [string](Get-MetraProp -Object $rf -Name 'path' -Default '')
        if ($scrub.Refuse) {
            throw ("Diff content refused by secrets scrub ($path): {0}" -f $scrub.Reason)
        }
        [void]$scrubbed.Add([PSCustomObject]@{
                path    = $path
                content = [string]$scrub.Text
                class   = [string](Get-MetraProp -Object $rf -Name 'class' -Default '')
            })
    }
    return @($scrubbed.ToArray())
}

function Get-MetraInspectScrubbedPlanText {
    <#
    .SYNOPSIS
        Reads a plan file, scrubs secrets, optionally truncates. Fail closed on Refuse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxBytes = 60000
    )

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    $scrub = Invoke-MetraAskSecretsScrubText -Text $raw
    if ($scrub.Refuse) {
        throw ("Plan content refused by secrets scrub: {0}" -f $scrub.Reason)
    }
    $text = [string]$scrub.Text
    $truncated = $false
    if ($text.Length -gt $MaxBytes) {
        $text = $text.Substring(0, $MaxBytes) + "`n...[truncated]..."
        $truncated = $true
    }
    return [PSCustomObject]@{
        Text      = $text
        Truncated = $truncated
    }
}

function Get-MetraInspectJsonTextCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )

    $text = $Message.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }

    if ($text -match '(?s)```(?:json)?\s*\r?\n(.+?)\r?\n```') {
        return $Matches[1].Trim()
    }

    if ($text.StartsWith('```')) {
        $lines = @($text -split "`r?`n")
        if ($lines.Count -ge 3) {
            $end = $lines.Count - 1
            while ($end -gt 0 -and $lines[$end].Trim() -ne '```') { $end-- }
            if ($end -gt 1) {
                return ($lines[1..($end - 1)] -join "`n").Trim()
            }
        }
    }

    if ($text -notmatch '^\s*[\[\{]') {
        $startObj = $text.IndexOf('{')
        $startArr = $text.IndexOf('[')
        $start = -1
        if ($startObj -ge 0 -and $startArr -ge 0) { $start = [Math]::Min($startObj, $startArr) }
        elseif ($startObj -ge 0) { $start = $startObj }
        elseif ($startArr -ge 0) { $start = $startArr }
        if ($start -gt 0) {
            $text = $text.Substring($start).Trim()
            $lastObj = $text.LastIndexOf('}')
            $lastArr = $text.LastIndexOf(']')
            $last = [Math]::Max($lastObj, $lastArr)
            if ($last -ge 0 -and $last -lt ($text.Length - 1)) {
                $text = $text.Substring(0, $last + 1)
            }
        }
    }

    return $text
}

function Get-MetraInspectJsonPropertyNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Parsed
    )

    if ($null -eq $Parsed) { return @() }
    if ($Parsed -is [hashtable] -or $Parsed -is [System.Collections.IDictionary]) {
        return @($Parsed.Keys | ForEach-Object { [string]$_ })
    }
    if ($null -ne $Parsed.PSObject) {
        return @($Parsed.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    }
    return @()
}

function Test-MetraInspectWrongFindingsShape {
    <#
    .SYNOPSIS
        True when JSON parsed but looks like a plan summary or other non-findings object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Parsed
    )

    $names = @(Get-MetraInspectJsonPropertyNames -Parsed $Parsed)
    if ($names.Count -eq 0) { return $false }
    if ($names -contains 'findings') { return $false }

    $wrongKeys = @(
        'overview', 'implementation_steps', 'implementationSteps', 'steps', 'plan', 'summary',
        'title', 'description', 'sections', 'tasks', 'recommendations', 'phases', 'milestones'
    )
    foreach ($n in $names) {
        if ($wrongKeys -contains $n) { return $true }
    }

    $severity = [string](Get-MetraProp -Object $Parsed -Name 'severity' -Default '')
    if ($names.Count -ge 2 -and [string]::IsNullOrWhiteSpace($severity)) {
        return $true
    }

    return $false
}

function ConvertTo-MetraInspectFindings {
    <#
    .SYNOPSIS
        Parses model message into a findings array. Fail closed on non-JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message
    )

    $text = Get-MetraInspectJsonTextCandidate -Message $Message

    # Prefer array; also accept { "findings": [...] }
    try {
        $parsed = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]@{
            Ok       = $false
            Findings = @()
            Error    = 'Model output was not valid JSON.'
            ShapeMismatch = $false
            Excerpt  = if ($Message.Length -gt 500) { $Message.Substring(0, 500) + '...' } else { $Message }
        }
    }

    $arr = $null
    if ($null -eq $parsed) {
        $arr = @()
    }
    elseif ($parsed -is [System.Array]) {
        $arr = @($parsed)
    }
    else {
        $hasFindings = $false
        if ($parsed -is [hashtable] -or $parsed -is [System.Collections.IDictionary]) {
            $hasFindings = $parsed.Contains('findings') -or $parsed.ContainsKey('findings')
            if ($hasFindings) { $arr = @($parsed['findings']) }
        }
        elseif ($null -ne $parsed.PSObject -and $parsed.PSObject.Properties.Name -contains 'findings') {
            $hasFindings = $true
            $arr = @($parsed.findings)
        }

        if (-not $hasFindings -and -not [string]::IsNullOrWhiteSpace([string](Get-MetraProp -Object $parsed -Name 'severity' -Default ''))) {
            $arr = @($parsed)
        }
    }
    if ($null -eq $arr) {
        $shapeMismatch = Test-MetraInspectWrongFindingsShape -Parsed $parsed
        $propHint = (@(Get-MetraInspectJsonPropertyNames -Parsed $parsed) -join ', ')
        $err = if ($shapeMismatch) {
            @(
                'Engine returned wrong JSON shape (expected {"findings":[...]}).'
                if ($propHint) { "Got top-level keys: $propHint." }
                'This often happens with Ollama on plan inspect.'
                'Inspect retried once automatically; if this persists, try .\metra.ps1 ask engine set cursor or a stronger Ollama model.'
            ) -join ' '
        }
        else {
            'JSON did not contain a findings array.'
        }
        return [PSCustomObject]@{
            Ok            = $false
            Findings      = @()
            Error         = $err
            ShapeMismatch = [bool]$shapeMismatch
            Excerpt       = if ($Message.Length -gt 500) { $Message.Substring(0, 500) + '...' } else { $Message }
        }
    }

    $allowedSeverity = @('High', 'Medium', 'Low', 'Info')
    $allowedConfidence = @('High', 'Medium', 'Low')
    $allowedCategory = @('Security', 'Reliability', 'Performance', 'Maintainability', 'Standards', 'Scope')

    $norm = @(
        foreach ($f in $arr) {
            if ($null -eq $f) { continue }
            $severity = [string](Get-MetraProp -Object $f -Name 'severity' -Default 'Info')
            if ($allowedSeverity -notcontains $severity) { $severity = 'Info' }
            $confidence = [string](Get-MetraProp -Object $f -Name 'confidence' -Default 'Medium')
            if ($allowedConfidence -notcontains $confidence) { $confidence = 'Medium' }
            $category = [string](Get-MetraProp -Object $f -Name 'category' -Default 'Standards')
            if ($allowedCategory -notcontains $category) { $category = 'Standards' }
            [PSCustomObject]@{
                severity       = $severity
                confidence     = $confidence
                category       = $category
                file           = [string](Get-MetraProp -Object $f -Name 'file' -Default '')
                line           = $(
                    $ln = Get-MetraProp -Object $f -Name 'line' -Default $null
                    if ($null -eq $ln -or [string]::IsNullOrWhiteSpace([string]$ln)) {
                        $null
                    }
                    else {
                        $parsedLine = 0
                        if ([int]::TryParse([string]$ln, [ref]$parsedLine)) { $parsedLine } else { $null }
                    }
                )
                finding        = [string](Get-MetraProp -Object $f -Name 'finding' -Default '')
                recommendation = [string](Get-MetraProp -Object $f -Name 'recommendation' -Default '')
                evidence       = [string](Get-MetraProp -Object $f -Name 'evidence' -Default '')
            }
        }
    )

    return [PSCustomObject]@{
        Ok            = $true
        Findings      = $norm
        Error         = $null
        ShapeMismatch = $false
        Excerpt       = $null
    }
}

function New-MetraInspectReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('diff', 'plan')][string]$Mode,
        [Parameter(Mandatory)][object]$Provenance,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings
    )

    return [PSCustomObject]@{
        schemaVersion = 1
        mode          = $Mode
        provenance    = $Provenance
        findings      = @($Findings)
    }
}

function Save-MetraInspectReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][object]$Report,
        [string]$SlotKey
    )

    $stateRoot = Get-MetraInspectStateRoot
    if ([string]::IsNullOrWhiteSpace($SlotKey)) { $SlotKey = 'default' }
    $safe = ($SlotKey -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    $dir = Join-Path $stateRoot $safe
    $latestPath = Join-Path $dir 'latest.json'
    $pointerName = if ($Report.mode -eq 'plan') { 'last-plan.json' } else { 'last-diff.json' }
    $pointerPath = Join-Path $stateRoot $pointerName

    if (-not $PSCmdlet.ShouldProcess($latestPath, 'Persist inspect report and last pointer')) {
        return [PSCustomObject]@{
            LatestPath  = $latestPath
            PointerPath = $pointerPath
            Skipped     = $true
        }
    }

    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Report | ConvertTo-Json -Depth 10
    Write-MetraAtomicUtf8Text -Path $latestPath -Text $json

    $pointer = [ordered]@{
        mode             = [string]$Report.mode
        latestReportPath = $latestPath
        project          = [string](Get-MetraProp -Object $Report.provenance -Name 'project' -Default '')
        root             = [string](Get-MetraProp -Object $Report.provenance -Name 'root' -Default '')
        inputHash        = [string](Get-MetraProp -Object $Report.provenance -Name 'inputHash' -Default '')
        createdAtUtc     = [datetime]::UtcNow.ToString('o')
    }
    if ($Report.mode -eq 'plan') {
        $pointer.planPath = [string](Get-MetraProp -Object $Report.provenance -Name 'planPath' -Default '')
    }
    Write-MetraAtomicUtf8Text -Path $pointerPath -Text (($pointer | ConvertTo-Json -Depth 6))

    return [PSCustomObject]@{
        LatestPath  = $latestPath
        PointerPath = $pointerPath
        Skipped     = $false
    }
}

function Get-MetraInspectLastPointer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('diff', 'plan')][string]$Mode
    )
    $name = if ($Mode -eq 'plan') { 'last-plan.json' } else { 'last-diff.json' }
    $path = Join-Path (Get-MetraInspectStateRoot) $name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Build-MetraInspectPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('diff', 'plan')][string]$Mode,
        [string]$AgentsText,
        [string]$Payload,
        [switch]$ContextLimited
    )

    if ($Mode -eq 'plan') {
        $rubric = @'
Evaluate this implementation plan for Metra portfolio work. Review the plan for risks - do NOT summarize or rewrite the plan in your output.

Focus on:
- Scope discipline and phase boundaries
- Root isolation / blast radius
- Recommend-only / no auto-act violations
- Naming collisions with existing CLI (verify, audit, watch, decisions review)
- Fail-closed edges and missing acceptance criteria

Return ONLY a JSON object: {"findings":[...]}. Each finding object must include:
severity (High|Medium|Low|Info), confidence (High|Medium|Low), category (prefer Scope when relevant, else Security|Reliability|Performance|Maintainability|Standards),
file (plan path or section), line (number or null), finding, recommendation, evidence.
If no issues, return {"findings":[]}. No markdown or prose outside the JSON object.
'@
    }
    else {
        $rubric = @'
Review these git changes for Metra/portfolio hardening.

Focus on:
- Validation and parameter contracts
- ShouldProcess honesty
- Path safety
- Fail-closed edges
- Credential exposure
- Error handling / reliability

Return ONLY a JSON object: {"findings":[...]}. Each finding object must include:
severity (High|Medium|Low|Info), confidence (High|Medium|Low), category (Security|Reliability|Performance|Maintainability|Standards|Scope),
file, line (number or null), finding, recommendation, evidence.
If no issues, return {"findings":[]}. No markdown or prose outside the JSON object.
'@
    }

    $ctxNote = if ($ContextLimited) {
        "NOTE: Project context was not resolved. AGENTS.md / Decisions were not attached.`n"
    }
    else { '' }

    $agentsBlock = if ([string]::IsNullOrWhiteSpace($AgentsText)) { '(none)' } else { $AgentsText }

    return @"
$rubric

$ctxNote
AGENTS / project guidance:
$agentsBlock

--- INPUT ---
$Payload
"@
}

function Invoke-MetraInspectEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Cwd
    )

    $retrySuffix = @'

RETRY - WRONG SHAPE: Your previous response was not inspect findings JSON. Do NOT summarize the plan. Do NOT use overview, implementation_steps, steps, plan, title, or summary keys.
Return ONLY one object: {"findings":[...]} where each item has severity, confidence, category, file, line, finding, recommendation, evidence.
If no issues: {"findings":[]}. No markdown. No prose outside JSON.
'@

    $currentPrompt = $Prompt
    $lastParse = $null
    $engine = ''
    $model = ''

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $engineResult = Invoke-MetraAskEngine -Prompt $currentPrompt -Cwd $Cwd -Context @{ purpose = 'metra-inspect' } -TimeoutSec 600
        if (-not $engineResult.ok) {
            $msg = [string](Get-MetraProp -Object $engineResult -Name 'message' -Default 'Ask engine failed.')
            $err = [string](Get-MetraProp -Object $engineResult -Name 'error' -Default 'engine_error')
            return [PSCustomObject]@{
                Ok            = $false
                Message       = $msg
                Error         = $err
                Excerpt       = $null
                Engine        = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
                Model         = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
                Findings      = @()
                ShapeMismatch = $false
                RetryAttempt  = $attempt
            }
        }

        $engine = [string](Get-MetraProp -Object $engineResult -Name 'engine' -Default '')
        $model = [string](Get-MetraProp -Object $engineResult -Name 'model' -Default '')
        $parsed = ConvertTo-MetraInspectFindings -Message ([string]$engineResult.message)
        if ($parsed.Ok) {
            return [PSCustomObject]@{
                Ok            = $true
                Message       = [string]$engineResult.message
                Error         = $null
                Excerpt       = $null
                Engine        = $engine
                Model         = $model
                Findings      = @($parsed.Findings)
                ShapeMismatch = $false
                RetryAttempt  = $attempt
            }
        }

        $lastParse = $parsed
        if ($attempt -eq 0 -and $parsed.ShapeMismatch) {
            Write-Verbose 'Inspect engine returned wrong JSON shape; retrying with findings-only prompt.'
            $currentPrompt = $Prompt + "`n`n" + $retrySuffix
            continue
        }
        break
    }

    return [PSCustomObject]@{
        Ok            = $false
        Message       = [string]$lastParse.Error
        Error         = 'parse_failed'
        Excerpt       = [string]$lastParse.Excerpt
        Engine        = $engine
        Model         = $model
        Findings      = @()
        ShapeMismatch = [bool]$lastParse.ShapeMismatch
        RetryAttempt  = 1
    }
}

function Show-MetraInspectFindingsConsole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Report
    )

    $findings = @($Report.findings)
    Write-Host ("Inspect mode={0} model={1} findings={2}" -f $Report.mode, $Report.provenance.model, $findings.Count)
    if ($Report.provenance.contextLimited) {
        Write-Host 'WARNING: Project context not resolved; inspecting without AGENTS.md / Decisions context.' -ForegroundColor Yellow
    }
    if ($Report.mode -eq 'plan' -and $Report.provenance.planPath) {
        Write-Host ("Plan: {0}" -f $Report.provenance.planPath)
    }
    if ($Report.provenance.project) {
        Write-Host ("Project: {0} ({1})" -f $Report.provenance.project, $Report.provenance.root)
    }
    Write-Host ("Report: {0}" -f $Report.provenance.reportPath)

    if ($findings.Count -eq 0) {
        Write-Host 'No findings.'
        return
    }

    $order = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $sorted = @(
        $findings | Sort-Object @{ Expression = {
                $s = [string]$_.severity
                if ($order.ContainsKey($s)) { $order[$s] } else { 9 }
            }
        }, category, file
    )
    foreach ($f in $sorted) {
        $lineBit = if ($null -ne $f.line) { ":$($f.line)" } else { '' }
        Write-Host ("[{0}/{1}] {2} {3}{4}" -f $f.severity, $f.confidence, $f.category, $f.file, $lineBit)
        Write-Host ("  {0}" -f $f.finding)
        if ($f.recommendation) { Write-Host ("  -> {0}" -f $f.recommendation) }
    }
    Write-Host ''
    Write-Host 'Coding loop: summarize findings in chat; fix only operator-affirmed items; re-run the same inspect mode before pack/Bing/ship.'
}

function Invoke-MetraInspectDiff {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [string]$Base
    )

    $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode diff
    if (-not $ctx.Ok) { throw $ctx.Error }

    $diff = Get-MetraInspectGitDiffFiles -Root $ctx.Root -Base $Base
    if ($diff.Empty) {
        throw 'Nothing to inspect (no tracked diffs and no includable untracked files).'
    }

    if ($diff.WorkingTreeDirty -and $diff.Warning) {
        Write-Host ("WARNING: {0}" -f $diff.Warning) -ForegroundColor Yellow
    }

    $reduced = Reduce-MetraInspectDiffFiles -Files $diff.Files
    if ($WhatIfPreference) {
        Write-Host ("WhatIf: would inspect diff project={0} root={1} files={2} reduced={3} skipped={4}" -f $ctx.Project, $ctx.Root, $reduced.FileCount, $reduced.ReducedFileCount, $reduced.SkippedFileCount)
        return [PSCustomObject]@{
            WhatIf           = $true
            Mode             = 'diff'
            Project          = [string]$ctx.Project
            Root             = [string]$ctx.Root
            FileCount        = [int]$reduced.FileCount
            ReducedFileCount = [int]$reduced.ReducedFileCount
            SkippedFileCount = [int]$reduced.SkippedFileCount
        }
    }

    if (-not $PSCmdlet.ShouldProcess($ctx.Root, 'Inspect diff via Ask engine')) {
        return [PSCustomObject]@{
            Skipped = $true
            Mode    = 'diff'
            Project = [string]$ctx.Project
            Root    = [string]$ctx.Root
        }
    }

    $scrubbedFiles = @(ConvertTo-MetraInspectScrubbedDiffParts -Files $reduced.Files)
    $agents = Get-MetraInspectAgentsText -Root $ctx.Root
    $payload = (
        $scrubbedFiles | ForEach-Object {
            "### $($_.path) [$($_.class)]`n$($_.content)"
        }
    ) -join "`n`n"

    $prompt = Build-MetraInspectPrompt -Mode diff -AgentsText $agents -Payload $payload
    $engine = Invoke-MetraInspectEngine -Prompt $prompt -Cwd $ctx.Root
    if (-not $engine.Ok) {
        if ($engine.Excerpt) {
            throw ("Inspect failed: {0}`nExcerpt:`n{1}" -f $engine.Message, $engine.Excerpt)
        }
        throw ("Inspect engine unavailable: {0}" -f $engine.Message)
    }

    $parsed = [PSCustomObject]@{ Ok = $true; Findings = @($engine.Findings) }

    $inputHash = Get-MetraInspectInputHash -Parts @(
        $scrubbedFiles | ForEach-Object { [PSCustomObject]@{ path = $_.path; content = $_.content } }
    )

    $stateRoot = Get-MetraInspectStateRoot
    $safeSlot = (($ctx.Project -replace '[^\w\.-]', '_').Trim('_'))
    if ([string]::IsNullOrWhiteSpace($safeSlot)) { $safeSlot = 'default' }
    $reportPath = Join-Path (Join-Path $stateRoot $safeSlot) 'latest.json'

    $provenance = [ordered]@{
        engine              = $engine.Engine
        model               = $engine.Model
        inspectedAtUtc      = [datetime]::UtcNow.ToString('o')
        project             = $ctx.Project
        root                = $ctx.Root
        gitHead             = [string]$diff.GitHead
        fileCount           = [int]$reduced.FileCount
        reducedFileCount    = [int]$reduced.ReducedFileCount
        skippedFileCount    = [int]$reduced.SkippedFileCount
        truncated           = [bool]$reduced.Truncated
        inputHash           = $inputHash
        contextLimited      = $false
        base                = $(if ($diff.Base) { [string]$diff.Base } elseif ($Base) { $Base } else { '' })
        baseMode            = [string](Get-MetraProp -Object $diff -Name 'BaseMode' -Default 'working-tree')
        untrackedFileCount  = [int](Get-MetraProp -Object $diff -Name 'UntrackedCount' -Default 0)
        workingTreeDirty    = [bool](Get-MetraProp -Object $diff -Name 'WorkingTreeDirty' -Default $false)
        assessedFiles       = @($scrubbedFiles | ForEach-Object { $_.path })
        reportPath          = $reportPath
    }

    $report = New-MetraInspectReport -Mode diff -Provenance $provenance -Findings $parsed.Findings
    $null = Save-MetraInspectReport -Report $report -SlotKey $ctx.Project

    Write-Host ("Scope: files={0} reduced={1} skipped={2} untracked={3}" -f $reduced.FileCount, $reduced.ReducedFileCount, $reduced.SkippedFileCount, $provenance.untrackedFileCount)
    Show-MetraInspectFindingsConsole -Report $report
    return $report
}

function Invoke-MetraInspectPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [switch]$Latest,
        [string]$Path,
        [string]$Fragment
    )

    $resolved = Resolve-MetraInspectPlanPath -Latest:$Latest -Path $Path -Fragment $Fragment
    if ($resolved.ListOnly) {
        Write-Host 'Recent plans (use -Latest, a filename fragment, or -Path; -Name required for non-list):'
        if (@($resolved.Matches).Count -eq 0) {
            Write-Host '  (none found)'
            return [PSCustomObject]@{ Listed = $true; Matches = @() }
        }
        foreach ($m in @($resolved.Matches)) {
            Write-Host ("  {0:u}  {1}" -f $m.LastWriteTimeUtc, $m.Path)
        }
        return [PSCustomObject]@{ Listed = $true; Matches = @($resolved.Matches) }
    }
    if (-not $resolved.Ok) {
        if (@($resolved.Matches).Count -gt 0) {
            Write-Host $resolved.Error -ForegroundColor Yellow
            foreach ($m in @($resolved.Matches)) {
                Write-Host ("  {0}" -f $m.Path)
            }
        }
        throw $resolved.Error
    }

    Write-Host ("Resolved plan: {0}" -f $resolved.Path)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Plan inspect requires -Name <Project> so AGENTS.md matches the intended project (avoids attaching the wrong project from cwd).'
    }

    $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode plan
    if (-not $ctx.Ok) { throw $ctx.Error }
    if ($ctx.Warning) { Write-Host $ctx.Warning -ForegroundColor Yellow }

    if ($WhatIfPreference) {
        Write-Host ("WhatIf: would inspect plan project={0} path={1}" -f $ctx.Project, $resolved.Path)
        return [PSCustomObject]@{
            WhatIf   = $true
            Mode     = 'plan'
            Project  = [string]$ctx.Project
            Root     = [string]$ctx.Root
            PlanPath = [string]$resolved.Path
        }
    }

    if (-not $PSCmdlet.ShouldProcess($(if ($ctx.Root) { $ctx.Root } else { $resolved.Path }), 'Inspect plan via Ask engine')) {
        return [PSCustomObject]@{
            Skipped  = $true
            Mode     = 'plan'
            Project  = [string]$ctx.Project
            Root     = [string]$ctx.Root
            PlanPath = [string]$resolved.Path
        }
    }

    $planText = Get-MetraInspectScrubbedPlanText -Path $resolved.Path
    $text = [string]$planText.Text
    $truncated = [bool]$planText.Truncated

    $agents = $null
    if (-not $ctx.ContextLimited -and $ctx.Root) {
        $agents = Get-MetraInspectAgentsText -Root $ctx.Root
    }

    $prompt = Build-MetraInspectPrompt -Mode plan -AgentsText $agents -Payload $text -ContextLimited:$ctx.ContextLimited
    $cwd = if ($ctx.Root) { $ctx.Root } else { (Get-MetraRoot) }
    $engine = Invoke-MetraInspectEngine -Prompt $prompt -Cwd $cwd
    if (-not $engine.Ok) {
        if ($engine.Excerpt) {
            throw ("Inspect failed: {0}`nExcerpt:`n{1}" -f $engine.Message, $engine.Excerpt)
        }
        throw ("Inspect engine unavailable: {0}" -f $engine.Message)
    }

    $parsed = [PSCustomObject]@{ Ok = $true; Findings = @($engine.Findings) }

    $inputHash = Get-MetraInspectInputHash -Parts @(
        [PSCustomObject]@{ path = $resolved.Path; content = $text }
        [PSCustomObject]@{ path = 'project'; content = [string]$ctx.Project }
    )

    $provenance = [ordered]@{
        engine         = $engine.Engine
        model          = $engine.Model
        inspectedAtUtc = [datetime]::UtcNow.ToString('o')
        project        = $ctx.Project
        root           = $ctx.Root
        planPath       = $resolved.Path
        truncated      = $truncated
        inputHash      = $inputHash
        contextLimited = [bool]$ctx.ContextLimited
    }

    $slot = if ($ctx.Project) { "plan-$($ctx.Project)" } else { 'plan' }
    $stateRoot = Get-MetraInspectStateRoot
    $safeSlot = (($slot -replace '[^\w\.-]', '_').Trim('_'))
    $provenance['reportPath'] = Join-Path (Join-Path $stateRoot $safeSlot) 'latest.json'
    $report = New-MetraInspectReport -Mode plan -Provenance $provenance -Findings $parsed.Findings
    $null = Save-MetraInspectReport -Report $report -SlotKey $slot

    Show-MetraInspectFindingsConsole -Report $report
    return $report
}

function Get-MetraInspectBingPackProfile {
    [CmdletBinding()]
    param()
    return [PSCustomObject]@{
        MaxFiles         = 32
        MaxBytesPerFile  = 48000
        MaxPackBodyChars = 250000
        MaxPlanBytes     = 250000
    }
}

function Get-MetraInspectPesterTestCatalogText {
    <#
    .SYNOPSIS
        Extracts Describe/It names from *.Tests.ps1 on disk for Bing acceptance review.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$RelativePaths
    )

    $paths = @(
        $RelativePaths |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Replace('\', '/') } |
            Where-Object { $_ -match '(?i)\.Tests\.ps1$' } |
            Sort-Object -Unique
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('## Test catalog (Describe / It names)')
    [void]$sb.AppendLine('Full test names from disk; use for acceptance review when the diff appendix is truncated.')
    [void]$sb.AppendLine('')

    if ($paths.Count -eq 0) {
        [void]$sb.AppendLine('(no *.Tests.ps1 in pack scope)')
        return $sb.ToString().TrimEnd()
    }

    foreach ($rel in $paths) {
        $full = Join-Path $Root ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $raw = $null
        try {
            $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8 -ErrorAction Stop
        }
        catch {
            continue
        }
        if ($null -eq $raw) { $raw = '' }

        [void]$sb.AppendLine("### $rel")
        foreach ($line in @($raw -split "`r?`n")) {
            if ($line -match "Describe\s+['`"]([^'`"]+)['`"]") {
                [void]$sb.AppendLine("- Describe '$($Matches[1])'")
            }
            foreach ($m in [regex]::Matches($line, "\bIt\s+['`"]([^'`"]+)['`"]")) {
                [void]$sb.AppendLine("  - It '$($m.Groups[1].Value)'")
            }
        }
        [void]$sb.AppendLine('')
    }

    return $sb.ToString().TrimEnd()
}

function Format-MetraInspectPackManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Profile,
        [int]$MaxFiles,
        [int]$MaxBytesPerFile,
        [int]$MaxPackBodyChars,
        [string[]]$FilesIncluded = @(),
        [string[]]$PerFileTruncated = @(),
        [string[]]$OmittedByFileCap = @(),
        [string[]]$DocsCollapsed = @(),
        [switch]$PackBodyTruncated,
        [int]$PackBodyChars = 0
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Pack profile: $Profile (MaxFiles=$MaxFiles, MaxBytesPerFile=$MaxBytesPerFile, MaxPackBodyChars=$MaxPackBodyChars)")
    [void]$sb.AppendLine("Appendix chars: $PackBodyChars$(if ($PackBodyTruncated) { ' (truncated at cap)' } else { '' })")
    if (@($PerFileTruncated).Count -gt 0) {
        [void]$sb.AppendLine(('Per-file truncated: ' + (($PerFileTruncated | ForEach-Object { $_ }) -join ', ')))
    }
    if (@($OmittedByFileCap).Count -gt 0) {
        [void]$sb.AppendLine(('Omitted by file cap: ' + (($OmittedByFileCap | ForEach-Object { $_ }) -join ', ')))
    }
    if (@($DocsCollapsed).Count -gt 0) {
        [void]$sb.AppendLine(('Docs collapsed (paths only): ' + (($DocsCollapsed | ForEach-Object { $_ }) -join ', ')))
    }
    if (@($FilesIncluded).Count -gt 0) {
        [void]$sb.AppendLine(('Files in appendix: ' + (($FilesIncluded | ForEach-Object { $_ }) -join ', ')))
    }
    return $sb.ToString().TrimEnd()
}

function Build-MetraInspectPackDiffAppendix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][object[]]$Files,
        [ValidateSet('bing', 'default')][string]$Profile = 'bing'
    )

    $maxFiles = 24
    $maxBytesPerFile = 24000
    $maxPackBodyChars = 80000
    if ($Profile -eq 'bing') {
        $bing = Get-MetraInspectBingPackProfile
        $maxFiles = [int]$bing.MaxFiles
        $maxBytesPerFile = [int]$bing.MaxBytesPerFile
        $maxPackBodyChars = [int]$bing.MaxPackBodyChars
    }

    $reduced = Reduce-MetraInspectDiffFiles -Files $Files -MaxFiles $maxFiles -MaxBytesPerFile $maxBytesPerFile
    $scrubbedFiles = @(ConvertTo-MetraInspectScrubbedDiffParts -Files $reduced.Files)
    $packFileList = @($scrubbedFiles | ForEach-Object { $_.path })
    $packBody = (
        $scrubbedFiles | ForEach-Object {
            "### $($_.path) [$($_.class)]`n$($_.content)"
        }
    ) -join "`n`n"

    $packBodyTruncated = $false
    if ($maxPackBodyChars -gt 0 -and $packBody.Length -gt $maxPackBodyChars) {
        $packBody = $packBody.Substring(0, $maxPackBodyChars) + "`n...[truncated]..."
        $packBodyTruncated = $true
    }

    $perFileTruncated = @(
        $scrubbedFiles |
            Where-Object { [string]$_.content -match '\[truncated\]' } |
            ForEach-Object { [string]$_.path }
    )

    $allPaths = @($Files | ForEach-Object { ([string]$_.path).Replace('\', '/') })
    $testCatalog = Get-MetraInspectPesterTestCatalogText -Root $Root -RelativePaths $allPaths
    $manifest = Format-MetraInspectPackManifest -Profile $Profile `
        -MaxFiles $maxFiles -MaxBytesPerFile $maxBytesPerFile -MaxPackBodyChars $maxPackBodyChars `
        -FilesIncluded $packFileList -PerFileTruncated $perFileTruncated `
        -OmittedByFileCap @($(Get-MetraProp -Object $reduced -Name 'OmittedByFileCap' -Default @()) | ForEach-Object { $_ }) `
        -DocsCollapsed @($(Get-MetraProp -Object $reduced -Name 'DocsCollapsed' -Default @()) | ForEach-Object { $_ }) `
        -PackBodyTruncated:$packBodyTruncated -PackBodyChars $packBody.Length

    return [PSCustomObject]@{
        Body              = $packBody
        FileList          = $packFileList
        Manifest          = $manifest
        TestCatalog       = $testCatalog
        PackBodyTruncated = $packBodyTruncated
        Reduced           = $reduced
        ScrubbedFiles     = $scrubbedFiles
    }
}

function Format-MetraInspectPackMarkdown {
    [CmdletBinding()]
    param(
        [ValidateSet('diff', 'plan')][string]$Mode,
        [object[]]$Findings = @(),
        [string]$PackBody,
        [string[]]$PackFileList = @(),
        [string]$AssessedReportPath,
        [string]$InspectedAtUtc,
        [string]$Engine,
        [string]$Model,
        [switch]$BingOnly,
        [switch]$Stale,
        [string]$StaleDetail,
        [string]$PlanPath,
        [string]$Project,
        [string]$Root,
        [string[]]$AssessedFilesFallback = @(),
        [string]$PackManifest,
        [string]$TestCatalog
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# Metra Inspect pack (Bing comparison lane)')
    [void]$sb.AppendLine('')
    if ($BingOnly) {
        [void]$sb.AppendLine('Bing-only: no Ask engine run.')
    }
    [void]$sb.AppendLine("Mode: $Mode")
    if ($BingOnly) {
        [void]$sb.AppendLine('Assessed report: (none - Bing-only pack)')
        [void]$sb.AppendLine("PackedAtUtc: $InspectedAtUtc")
        [void]$sb.AppendLine('Model: (none - Bing-only pack)')
    }
    else {
        [void]$sb.AppendLine("Assessed report: $AssessedReportPath")
        [void]$sb.AppendLine("InspectedAtUtc: $InspectedAtUtc")
        [void]$sb.AppendLine("Model: $Engine / $Model")
    }
    if (-not [string]::IsNullOrWhiteSpace($Project)) {
        $rootBit = if (-not [string]::IsNullOrWhiteSpace($Root)) { " ($Root)" } else { '' }
        [void]$sb.AppendLine("Project: $Project$rootBit")
    }
    if (-not [string]::IsNullOrWhiteSpace($PackManifest)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($PackManifest)
    }
    if ($Stale) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('WARNING: Findings are from the assessed report; appendix body is rebuilt from current disk (not the assessed snapshot).')
        [void]$sb.AppendLine($StaleDetail)
        [void]$sb.AppendLine('Re-run inspect, then pack, if you need findings that match current disk.')
    }
    [void]$sb.AppendLine('')
    if ($Mode -eq 'diff') {
        [void]$sb.AppendLine('Bing preamble: harden for validation, ShouldProcess honesty, path safety, fail-closed edges, credential exposure, error handling.')
    }
    else {
        [void]$sb.AppendLine('Bing preamble: review plan for scope discipline, root isolation, recommend-only / no auto-act, naming collisions, phase boundaries, fail-closed edges, acceptance criteria.')
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Findings')
    if ($BingOnly) {
        [void]$sb.AppendLine('(none - Bing-only pack; no Ask engine run)')
    }
    else {
        foreach ($f in @($Findings)) {
            $lineBit = if ($null -ne $f.line -and "$($f.line)" -ne '') { ":$($f.line)" } else { '' }
            [void]$sb.AppendLine(("- [{0}/{1}] {2} {3}{4}: {5}" -f $f.severity, $f.confidence, $f.category, $f.file, $lineBit, $f.finding))
            if ($f.recommendation) { [void]$sb.AppendLine("  Recommendation: $($f.recommendation)") }
            if ($f.evidence) { [void]$sb.AppendLine("  Evidence: $($f.evidence)") }
        }
        if (@($Findings).Count -eq 0) {
            [void]$sb.AppendLine('(none)')
        }
    }

    [void]$sb.AppendLine('')
    if ($Mode -eq 'plan') {
        [void]$sb.AppendLine('## Plan (current disk scrub)')
        [void]$sb.AppendLine("Path: $PlanPath")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($(if ($null -eq $PackBody) { '' } else { $PackBody }))
    }
    else {
        [void]$sb.AppendLine('## Diff (current disk scrub)')
        $filesLine = @($PackFileList)
        if ($filesLine.Count -eq 0) {
            $filesLine = @($AssessedFilesFallback | ForEach-Object { $_ })
        }
        [void]$sb.AppendLine(('Files: ' + (($filesLine | ForEach-Object { $_ }) -join ', ')))
        [void]$sb.AppendLine('')
        if ([string]::IsNullOrWhiteSpace($PackBody)) {
            [void]$sb.AppendLine('(body unavailable - re-run inspect)')
        }
        else {
            [void]$sb.AppendLine($PackBody)
        }
        if (-not [string]::IsNullOrWhiteSpace($TestCatalog)) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine($TestCatalog)
        }
    }

    return $sb.ToString()
}

function Write-MetraInspectPackArtifact {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$PackText,
        [ValidateSet('diff', 'plan')][string]$Mode,
        [switch]$Stale
    )

    $packPath = Join-Path (Get-MetraInspectStateRoot) ("pack-{0}.md" -f $Mode)
    if (-not $PSCmdlet.ShouldProcess($packPath, 'Write inspect pack and copy to clipboard')) {
        return [PSCustomObject]@{
            Path    = $packPath
            Stale   = $Stale
            Mode    = $Mode
            Text    = $PackText
            Skipped = $true
        }
    }

    Write-MetraAtomicUtf8Text -Path $packPath -Text $PackText

    if ($PackText.Length -gt 100000) {
        Write-Host 'Pack is large; prefer opening the pack file in Bing instead of clipboard paste.' -ForegroundColor Yellow
    }

    try {
        Set-Clipboard -Value $PackText -ErrorAction Stop
        Write-Host 'Bing comparison pack copied to clipboard.'
    }
    catch {
        Write-Host 'Clipboard unavailable; pack written to file only.'
    }
    Write-Host ("Pack file: {0}" -f $packPath)
    return [PSCustomObject]@{
        Path    = $packPath
        Stale   = $Stale
        Mode    = $Mode
        Text    = $PackText
        Skipped = $false
    }
}

function Invoke-MetraInspectPackOnly {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('diff', 'plan')][string]$Mode = 'diff',
        [string]$Name,
        [switch]$Latest,
        [string]$Path,
        [string]$Fragment,
        [string]$Base
    )

    $packBody = $null
    $packFileList = @()
    $planPathOut = $null
    $project = $null
    $root = $null
    $appendix = $null
    $packManifest = $null
    $packedAtUtc = [datetime]::UtcNow.ToString('o')
    $bingProfile = Get-MetraInspectBingPackProfile

    if ($Mode -eq 'diff') {
        $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode diff
        if (-not $ctx.Ok) { throw $ctx.Error }
        $project = [string]$ctx.Project
        $root = [string]$ctx.Root

        $diff = Get-MetraInspectGitDiffFiles -Root $ctx.Root -Base $Base
        if ($diff.Empty) {
            throw 'Nothing to pack (no tracked diffs and no includable untracked files).'
        }
        if ($diff.WorkingTreeDirty -and $diff.Warning) {
            Write-Host ("WARNING: {0}" -f $diff.Warning) -ForegroundColor Yellow
        }

        $appendix = Build-MetraInspectPackDiffAppendix -Root $ctx.Root -Files $diff.Files -Profile bing
        $packFileList = @($appendix.FileList)
        $packBody = [string]$appendix.Body
        $packManifest = [string]$appendix.Manifest
        if ($appendix.PackBodyTruncated) {
            Write-Host 'WARNING: Diff appendix truncated at Bing pack body cap; see Test catalog section for full Describe/It names.' -ForegroundColor Yellow
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            throw 'Plan pack-only requires -Name <Project>.'
        }

        $resolved = Resolve-MetraInspectPlanPath -Latest:$Latest -Path $Path -Fragment $Fragment
        if ($resolved.ListOnly) {
            Write-Host 'Recent plans (use -Latest, a filename fragment, or -Path; -Name required for non-list):'
            if (@($resolved.Matches).Count -eq 0) {
                Write-Host '  (none found)'
                return [PSCustomObject]@{ Listed = $true; Matches = @() }
            }
            foreach ($m in @($resolved.Matches)) {
                Write-Host ("  {0:u}  {1}" -f $m.LastWriteTimeUtc, $m.Path)
            }
            return [PSCustomObject]@{ Listed = $true; Matches = @($resolved.Matches) }
        }
        if (-not $resolved.Ok) {
            if (@($resolved.Matches).Count -gt 0) {
                Write-Host $resolved.Error -ForegroundColor Yellow
                foreach ($m in @($resolved.Matches)) {
                    Write-Host ("  {0}" -f $m.Path)
                }
            }
            throw $resolved.Error
        }

        Write-Host ("Resolved plan: {0}" -f $resolved.Path)

        $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode plan
        if (-not $ctx.Ok) { throw $ctx.Error }
        if ($ctx.Warning) { Write-Host $ctx.Warning -ForegroundColor Yellow }
        $project = [string]$ctx.Project
        $root = [string]$ctx.Root
        $planPathOut = [string]$resolved.Path

        $planFull = [System.IO.Path]::GetFullPath($planPathOut)
        $planAllowed = $false
        foreach ($planRoot in @(Get-MetraInspectPlanRoots)) {
            if (Test-MetraPathWithinRoot -Path $planFull -Root $planRoot) {
                $planAllowed = $true
                break
            }
        }
        if (-not $planAllowed) {
            throw "Pack planPath must be under a known plan root: $planFull"
        }
        if (-not (Test-Path -LiteralPath $planFull -PathType Leaf)) {
            throw "Pack planPath missing on disk: $planFull"
        }

        $planText = Get-MetraInspectScrubbedPlanText -Path $planFull -MaxBytes ([int]$bingProfile.MaxPlanBytes)
        $packBody = [string]$planText.Text
        $packManifest = Format-MetraInspectPackManifest -Profile bing `
            -MaxFiles 0 -MaxBytesPerFile 0 -MaxPackBodyChars ([int]$bingProfile.MaxPlanBytes) `
            -FilesIncluded @([string]$planPathOut) -PackBodyTruncated:([bool]$planText.Truncated) -PackBodyChars $packBody.Length
    }

    if ($WhatIfPreference) {
        Write-Host ("WhatIf: would write Bing-only pack mode={0} project={1}" -f $Mode, $project)
        return [PSCustomObject]@{
            WhatIf  = $true
            Mode    = $Mode
            Project = $project
            Root    = $root
            Skipped = $true
        }
    }

    $packText = Format-MetraInspectPackMarkdown -Mode $Mode -Findings @() -PackBody $packBody -PackFileList $packFileList `
        -BingOnly -Project $project -Root $root -PlanPath $planPathOut -InspectedAtUtc $packedAtUtc `
        -PackManifest $packManifest `
        -TestCatalog $(if ($Mode -eq 'diff' -and $appendix) { [string]$appendix.TestCatalog } else { $null })

    return Write-MetraInspectPackArtifact -PackText $packText -Mode $Mode -Stale:$false
}

function Invoke-MetraInspectPack {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('diff', 'plan')][string]$Mode = 'diff'
    )

    $pointer = Get-MetraInspectLastPointer -Mode $Mode
    if (-not $pointer -or [string]::IsNullOrWhiteSpace([string]$pointer.latestReportPath)) {
        throw "No last $Mode inspect report. Run .\metra.ps1 inspect$(if ($Mode -eq 'plan') { ' plan' }) first."
    }

    $stateRoot = Get-MetraInspectStateRoot
    $reportPathRaw = [string]$pointer.latestReportPath
    $reportFull = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($reportPathRaw))
    if (-not (Test-MetraPathWithinRoot -Path $reportFull -Root $stateRoot)) {
        throw "Last $Mode report path must be under the inspect state root ($stateRoot): $reportFull"
    }
    if (-not (Test-Path -LiteralPath $reportFull -PathType Leaf)) {
        throw "Last $Mode report missing: $reportFull"
    }

    $report = Get-Content -LiteralPath $reportFull -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $stale = $false
    $staleDetail = $null
    $packBody = $null
    $packFileList = @()
    $appendix = $null
    $packManifest = $null
    $testCatalog = $null
    $bingProfile = Get-MetraInspectBingPackProfile

    try {
        if ($Mode -eq 'diff' -and $report.provenance.root) {
            $diff = Get-MetraInspectGitDiffFiles -Root ([string]$report.provenance.root) -Base ([string](Get-MetraProp -Object $report.provenance -Name 'base' -Default ''))
            if ($diff.Empty) {
                $stale = $true
                $staleDetail = 'Working tree is now empty; assessed report is stale.'
                $packFileList = @(@(Get-MetraProp -Object $report.provenance -Name 'assessedFiles' -Default @()) | ForEach-Object { $_ })
                $packBody = '(current tree empty - body omitted)'
            }
            else {
                $appendix = Build-MetraInspectPackDiffAppendix -Root ([string]$report.provenance.root) -Files $diff.Files -Profile bing
                $packFileList = @($appendix.FileList)
                $packBody = [string]$appendix.Body
                $packManifest = [string]$appendix.Manifest
                $testCatalog = [string]$appendix.TestCatalog
                if ($appendix.PackBodyTruncated) {
                    Write-Host 'WARNING: Diff appendix truncated at Bing pack body cap; see Test catalog section for full Describe/It names.' -ForegroundColor Yellow
                }
                $hash = Get-MetraInspectInputHash -Parts @(
                    $appendix.ScrubbedFiles | ForEach-Object { [PSCustomObject]@{ path = $_.path; content = $_.content } }
                )
                if ($hash -ne [string]$pointer.inputHash) {
                    $stale = $true
                    $staleDetail = 'Current working tree inputHash differs from the assessed report.'
                }
            }
        }
        elseif ($Mode -eq 'plan' -and $report.provenance.planPath) {
            $planPathRaw = [string]$report.provenance.planPath
            $planFull = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($planPathRaw))
            $planAllowed = $false
            foreach ($planRoot in @(Get-MetraInspectPlanRoots)) {
                if (Test-MetraPathWithinRoot -Path $planFull -Root $planRoot) {
                    $planAllowed = $true
                    break
                }
            }
            if (-not $planAllowed) {
                throw "Pack planPath must be under a known plan root: $planFull"
            }
            if (Test-Path -LiteralPath $planFull -PathType Leaf) {
                $planText = Get-MetraInspectScrubbedPlanText -Path $planFull -MaxBytes ([int]$bingProfile.MaxPlanBytes)
                $text = [string]$planText.Text
                $packBody = $text
                $packManifest = Format-MetraInspectPackManifest -Profile bing `
                    -MaxFiles 0 -MaxBytesPerFile 0 -MaxPackBodyChars ([int]$bingProfile.MaxPlanBytes) `
                    -FilesIncluded @($planFull) -PackBodyTruncated:([bool]$planText.Truncated) -PackBodyChars $text.Length
                $hash = Get-MetraInspectInputHash -Parts @(
                    [PSCustomObject]@{ path = $planFull; content = $text }
                    [PSCustomObject]@{ path = 'project'; content = [string]$report.provenance.project }
                )
                if ($hash -ne [string]$pointer.inputHash) {
                    $stale = $true
                    $staleDetail = 'Current plan file inputHash differs from the assessed report.'
                }
            }
            else {
                throw "Pack planPath missing on disk: $planFull"
            }
        }
    }
    catch {
        $stale = $true
        $staleDetail = "Could not re-hash current input: $($_.Exception.Message)"
        if ($Mode -eq 'plan' -and $_.Exception.Message -match 'refused by secrets scrub') {
            throw
        }
        if ($Mode -eq 'plan' -and $_.Exception.Message -match 'known plan root') {
            throw
        }
        if ($Mode -eq 'plan' -and $_.Exception.Message -match 'missing on disk') {
            throw
        }
    }

    if ($stale) {
        Write-Host "WARNING: $staleDetail" -ForegroundColor Yellow
        Write-Host 'Findings are assessed; appendix body is current disk scrub.' -ForegroundColor Yellow
    }

    if ($Mode -eq 'plan' -and [string]::IsNullOrWhiteSpace($packBody)) {
        $planPathProv = [string](Get-MetraProp -Object $report.provenance -Name 'planPath' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($planPathProv)) {
        # Rebuild failed earlier without throw - try once more under confine.
        $fbRaw = $planPathProv
        $fbFull = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($fbRaw))
        $fbAllowed = $false
        foreach ($planRoot in @(Get-MetraInspectPlanRoots)) {
            if (Test-MetraPathWithinRoot -Path $fbFull -Root $planRoot) {
                $fbAllowed = $true
                break
            }
        }
        if (-not $fbAllowed) {
            throw "Pack planPath must be under a known plan root: $fbFull"
        }
        if (Test-Path -LiteralPath $fbFull -PathType Leaf) {
            $planText = Get-MetraInspectScrubbedPlanText -Path $fbFull -MaxBytes ([int]$bingProfile.MaxPlanBytes)
            $packBody = [string]$planText.Text
            if (-not $packManifest) {
                $packManifest = Format-MetraInspectPackManifest -Profile bing `
                    -MaxFiles 0 -MaxBytesPerFile 0 -MaxPackBodyChars ([int]$bingProfile.MaxPlanBytes) `
                    -FilesIncluded @($fbFull) -PackBodyTruncated:([bool]$planText.Truncated) -PackBodyChars $packBody.Length
            }
        }
        }
    }

    $assessedFilesFallback = @(@(Get-MetraProp -Object $report.provenance -Name 'assessedFiles' -Default @()) | ForEach-Object { $_ })
    $packText = Format-MetraInspectPackMarkdown -Mode $Mode -Findings @($report.findings) -PackBody $packBody -PackFileList $packFileList `
        -AssessedReportPath $reportFull -InspectedAtUtc ([string]$report.provenance.inspectedAtUtc) `
        -Engine ([string]$report.provenance.engine) -Model ([string]$report.provenance.model) `
        -Stale:$stale -StaleDetail $staleDetail `
        -PlanPath ([string](Get-MetraProp -Object $report.provenance -Name 'planPath' -Default '')) `
        -Project ([string](Get-MetraProp -Object $report.provenance -Name 'project' -Default '')) `
        -Root ([string](Get-MetraProp -Object $report.provenance -Name 'root' -Default '')) `
        -AssessedFilesFallback $assessedFilesFallback -PackManifest $packManifest -TestCatalog $testCatalog

    return Write-MetraInspectPackArtifact -PackText $packText -Mode $Mode -Stale:$stale
}

function Show-MetraInspectCli {
    <#
    .SYNOPSIS
        CLI entry for metra.ps1 inspect.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Rest = @(),
        [string[]]$Name,
        [string]$Path,
        [string]$Base
    )

    $argsRest = @(
        @($Rest) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )
    if ($Name -and $Name.Count -gt 1) {
        throw 'inspect accepts a single -Name project.'
    }
    $projectName = if ($Name -and $Name.Count -gt 0) { [string]$Name[0] } else { $null }

    # Parse shared flags from Rest
    $latest = $false
    $fragment = $null
    $pathFromRest = $null
    $baseFromRest = $null
    $nameFromRest = $null
    $mode = 'diff'
    $packMode = $null

    $i = 0
    if ($argsRest.Count -gt 0 -and $argsRest[0] -ieq 'pack-only') {
        $mode = 'pack-only'
        $i = 1
        if ($argsRest.Count -gt 1 -and $argsRest[1] -ieq 'plan') {
            $packMode = 'plan'
            $i = 2
        }
        else {
            $packMode = 'diff'
        }
    }
    elseif ($argsRest.Count -gt 0 -and $argsRest[0] -ieq 'pack') {
        $mode = 'pack'
        $i = 1
        if ($argsRest.Count -gt 1 -and $argsRest[1] -ieq 'plan') {
            $packMode = 'plan'
            $i = 2
        }
        else {
            $packMode = 'diff'
        }
    }
    elseif ($argsRest.Count -gt 0 -and $argsRest[0] -ieq 'plan') {
        $mode = 'plan'
        $i = 1
    }

    while ($i -lt $argsRest.Count) {
        $tok = [string]$argsRest[$i]
        if ($tok -ieq '-Latest') {
            $latest = $true
            $i++
            continue
        }
        if ($tok -ieq '-Path' -and ($i + 1) -lt $argsRest.Count) {
            $pathFromRest = [string]$argsRest[$i + 1]
            $i += 2
            continue
        }
        if ($tok -ieq '-Name' -and ($i + 1) -lt $argsRest.Count) {
            $nameFromRest = [string]$argsRest[$i + 1]
            $i += 2
            continue
        }
        if ($tok -ieq '-Base' -and ($i + 1) -lt $argsRest.Count) {
            $baseFromRest = [string]$argsRest[$i + 1]
            $i += 2
            continue
        }
        if ($tok -like '-*') {
            throw "Unknown inspect argument: $tok"
        }
        if (($mode -eq 'plan' -or ($mode -eq 'pack-only' -and $packMode -eq 'plan')) -and [string]::IsNullOrWhiteSpace($fragment)) {
            $fragment = $tok
            $i++
            continue
        }
        throw "Unexpected inspect argument: $tok"
    }

    if ($nameFromRest) { $projectName = $nameFromRest }
    $planPath = if ($pathFromRest) { $pathFromRest } elseif ($Path) { $Path } else { $null }
    $baseRev = if ($baseFromRest) { $baseFromRest } elseif ($Base) { $Base } else { $null }

    $common = @{}
    if ($WhatIfPreference) { $common.WhatIf = $true }

    switch ($mode) {
        'pack-only' {
            return Invoke-MetraInspectPackOnly -Mode $packMode -Name $projectName -Latest:$latest -Path $planPath -Fragment $fragment -Base $baseRev @common
        }
        'pack' {
            return Invoke-MetraInspectPack -Mode $packMode @common
        }
        'plan' {
            return Invoke-MetraInspectPlan -Name $projectName -Latest:$latest -Path $planPath -Fragment $fragment @common
        }
        default {
            return Invoke-MetraInspectDiff -Name $projectName -Base $baseRev @common
        }
    }
}
