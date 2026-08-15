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
        [int]$MaxBytesPerFile = 24000,
        [switch]$IncludeDocs
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
        if ($f.class -eq 'docs' -and -not $IncludeDocs) {
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

    $allowedSeverity = @('Critical', 'High', 'Medium', 'Low', 'Info')
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
severity (Critical|High|Medium|Low|Info), confidence (High|Medium|Low), category (prefer Scope when relevant, else Security|Reliability|Performance|Maintainability|Standards),
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

Review loop regression revert (Inspect.ps1 loop/baseline code):
- Restore-MetraInspectReviewGitBaseline is intentional **manifest-only** restore: copies baseline manifest paths back; warns on diff extras; does **not** delete new/unlisted files (operator may keep useful work from a failed fix batch).
- Do **not** report manifest-only restore or "extras left unchanged" warnings as High/Medium defects. Use Info at most if noting operator follow-up.
- Do report missing path containment, untrusted baselinePath, or resume root mismatch.
- Save-MetraInspectReviewGitBaseline may omit non-leaf or missing-on-disk diff paths; it warns with captured/total counts and stores baselineCoverage on pendingBaseline. Warn-not-fail is intentional; do not flag loud omission warnings as High/Medium.

Return ONLY a JSON object: {"findings":[...]}. Each finding object must include:
severity (Critical|High|Medium|Low|Info), confidence (High|Medium|Low), category (Security|Reliability|Performance|Maintainability|Standards|Scope),
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

    $order = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Info = 4 }
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
    <#
    .SYNOPSIS
        Larger caps for inspect pack / Bing comparison lane (full doc bodies, more files).
    #>
    [CmdletBinding()]
    param()
    return [PSCustomObject]@{
        MaxFiles         = 64
        MaxBytesPerFile  = 96000
        MaxPackBodyChars = 750000
        MaxPlanBytes     = 750000
        IncludeDocs      = $true
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
    $includeDocs = $false
    if ($Profile -eq 'bing') {
        $bing = Get-MetraInspectBingPackProfile
        $maxFiles = [int]$bing.MaxFiles
        $maxBytesPerFile = [int]$bing.MaxBytesPerFile
        $maxPackBodyChars = [int]$bing.MaxPackBodyChars
        $includeDocs = [bool](Get-MetraProp -Object $bing -Name 'IncludeDocs' -Default $true)
    }

    $reduced = Reduce-MetraInspectDiffFiles -Files $Files -MaxFiles $maxFiles -MaxBytesPerFile $maxBytesPerFile -IncludeDocs:$includeDocs
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

function Test-MetraInspectRelativePathInA2DeskScope {
    <#
    .SYNOPSIS
        True when a repo-relative path belongs to an A2 desk split pack (stub + playbooks).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath
    )

    $p = ([string]$RelativePath).Replace('\', '/').Trim()
    while ($p.StartsWith('./', [System.StringComparison]::Ordinal)) {
        $p = $p.Substring(2)
    }
    if ($p -ieq 'AGENTS.md') { return $true }
    if ($p -like 'docs/playbooks/*') { return $true }
    return $false
}

function Get-MetraInspectA2DeskRelativePaths {
    <#
    .SYNOPSIS
        Sorted AGENTS.md plus docs/playbooks/*.md paths under a project root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $agentsPath = Join-Path $Root 'AGENTS.md'
    if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
        throw 'A2 desk pack requires AGENTS.md at project root.'
    }

    $paths = New-Object System.Collections.Generic.List[string]
    [void]$paths.Add('AGENTS.md')

    $playbookDir = Join-Path $Root 'docs/playbooks'
    if (Test-Path -LiteralPath $playbookDir -PathType Container) {
        $rootFull = [System.IO.Path]::GetFullPath($Root)
        if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar
        }
        Get-ChildItem -LiteralPath $playbookDir -Filter '*.md' -File -Recurse -ErrorAction Stop |
            ForEach-Object {
                $rel = $_.FullName.Substring($rootFull.Length).Replace('\', '/')
                [void]$paths.Add($rel)
            }
    }

    return @($paths.ToArray() | Sort-Object -Unique)
}

function Get-MetraInspectA2DeskPackFiles {
    <#
    .SYNOPSIS
        Builds A2 desk pack file objects from disk, preferring git diff bodies when present.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [object[]]$DiffFiles = @()
    )

    $diffByPath = @{}
    foreach ($f in @($DiffFiles)) {
        $p = ([string](Get-MetraProp -Object $f -Name 'path' -Default '')).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not (Test-MetraInspectRelativePathInA2DeskScope -RelativePath $p)) { continue }
        $diffByPath[$p] = $f
    }

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($rel in @(Get-MetraInspectA2DeskRelativePaths -Root $Root)) {
        if ($diffByPath.ContainsKey($rel)) {
            [void]$files.Add($diffByPath[$rel])
            continue
        }

        $full = Join-Path $Root ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        $raw = Get-Content -LiteralPath $full -Raw -Encoding utf8 -ErrorAction Stop
        if ($null -eq $raw) { $raw = '' }
        $prefix = "A2 DESK FILE: $rel`nFull file from disk (not a git diff)."
        [void]$files.Add([PSCustomObject]@{
                path    = $rel
                content = "$prefix`n$raw"
            })
    }

    return @($files.ToArray())
}

function Format-MetraInspectA2DeskAuditSummary {
    <#
    .SYNOPSIS
        Stub line budget audit plus playbook counts for A2 desk packs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$DeskPaths = @()
    )

    $agentsPath = Join-Path $Root 'AGENTS.md'
    $audit = Get-MetraAgentsLineAuditForPath -AgentsPath $agentsPath

    $playbookPaths = @(
        @($DeskPaths) |
            Where-Object { (Test-MetraInspectRelativePathInA2DeskScope -RelativePath $_) -and ($_ -notlike 'AGENTS.md') }
    )
    $playbookLines = 0
    foreach ($rel in $playbookPaths) {
        $full = Join-Path $Root ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $playbookLines += Get-MetraFilePhysicalLineCount -Path $full
        }
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('## A2 desk audit')
    [void]$sb.AppendLine([string]$audit.Message)
    [void]$sb.AppendLine("Playbooks: $($playbookPaths.Count) files, $playbookLines total lines under docs/playbooks/")
    [void]$sb.AppendLine('Scope: AGENTS.md stub + docs/playbooks/*.md only (other working-tree changes excluded).')
    return $sb.ToString().TrimEnd()
}

function Format-MetraInspectPackMarkdown {
    [CmdletBinding()]
    param(
        [ValidateSet('diff', 'plan', 'agents')][string]$Mode,
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
        [string]$TestCatalog,
        [string]$AgentsAuditSummary
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
    if (-not [string]::IsNullOrWhiteSpace($AgentsAuditSummary)) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($AgentsAuditSummary)
    }
    if ($Stale) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('WARNING: Findings are from the assessed report; appendix body is rebuilt from current disk (not the assessed snapshot).')
        [void]$sb.AppendLine($StaleDetail)
        [void]$sb.AppendLine('Re-run inspect, then pack, if you need findings that match current disk.')
    }
    [void]$sb.AppendLine('')
    if ($Mode -eq 'diff') {
        [void]$sb.AppendLine('Bing preamble: harden for validation, ShouldProcess honesty, path safety, fail-closed edges, credential exposure, error handling. Inspect loop regression revert is manifest-only plus warn on extras (not auto-delete unlisted files) by design.')
    }
    elseif ($Mode -eq 'agents') {
        [void]$sb.AppendLine('Bing preamble: review A2 desk split - stub under line budget, playbook index and safety ceilings in stub only, loadWhen/front matter on playbooks, provenance lines, content parity with pre-split AGENTS (done-when / On hard stop preserved), no procedure warehouse in stub, playbook bodies not always-on.')
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
        $sectionTitle = if ($Mode -eq 'agents') { '## A2 desk split (current disk scrub)' } else { '## Diff (current disk scrub)' }
        [void]$sb.AppendLine($sectionTitle)
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
        [ValidateSet('diff', 'plan', 'agents')][string]$Mode,
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

    if ($PackText.Length -gt 500000) {
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
        [ValidateSet('diff', 'plan', 'agents')][string]$Mode = 'diff',
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
    $agentsAuditSummary = $null
    $packedAtUtc = [datetime]::UtcNow.ToString('o')
    $bingProfile = Get-MetraInspectBingPackProfile

    if ($Mode -eq 'agents') {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            throw 'A2 desk pack-only requires -Name <Project>.'
        }

        $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode diff
        if (-not $ctx.Ok) { throw $ctx.Error }
        $project = [string]$ctx.Project
        $root = [string]$ctx.Root

        $diff = Get-MetraInspectGitDiffFiles -Root $ctx.Root -Base $Base
        if ($diff.Warning) {
            Write-Host ("WARNING: {0}" -f $diff.Warning) -ForegroundColor Yellow
        }

        $deskFiles = @(Get-MetraInspectA2DeskPackFiles -Root $ctx.Root -DiffFiles $diff.Files)
        if ($deskFiles.Count -eq 0) {
            throw 'Nothing to pack (no AGENTS.md or docs/playbooks/*.md found).'
        }

        $deskPaths = @($deskFiles | ForEach-Object { [string]$_.path })
        $agentsAuditSummary = Format-MetraInspectA2DeskAuditSummary -Root $ctx.Root -DeskPaths $deskPaths

        $appendix = Build-MetraInspectPackDiffAppendix -Root $ctx.Root -Files $deskFiles -Profile bing
        $packFileList = @($appendix.FileList)
        $packBody = [string]$appendix.Body
        $packManifest = [string]$appendix.Manifest
        if ($appendix.PackBodyTruncated) {
            Write-Host 'WARNING: A2 desk appendix truncated at Bing pack body cap.' -ForegroundColor Yellow
        }
    }
    elseif ($Mode -eq 'diff') {
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
        -TestCatalog $(if (($Mode -eq 'diff' -or $Mode -eq 'agents') -and $appendix) { [string]$appendix.TestCatalog } else { $null }) `
        -AgentsAuditSummary $agentsAuditSummary

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

function Get-MetraInspectReviewLoopMaxLoops {
    [CmdletBinding()]
    param()

    return 5
}

function Get-MetraInspectReviewSeverityTier {
    <#
    .SYNOPSIS
        Maps inspect finding severity to review-loop tiers Critical|High|Medium|Low.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Severity
    )

    switch -Regex ($Severity) {
        '^Critical$' { return 'Critical' }
        '^High$' { return 'High' }
        '^Medium$' { return 'Medium' }
        default { return 'Low' } # Low and Info
    }
}

function Get-MetraInspectReviewSeverityCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings
    )

    $counts = [ordered]@{
        Critical = 0
        High     = 0
        Medium   = 0
        Low      = 0
    }
    foreach ($f in @($Findings)) {
        if ($null -eq $f) { continue }
        $tier = Get-MetraInspectReviewSeverityTier -Severity ([string]$f.severity)
        $counts[$tier]++
    }
    return [PSCustomObject]$counts
}

function Test-MetraInspectReviewSeverityCountsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Left,
        [Parameter(Mandatory)][object]$Right
    )

    foreach ($tier in @('Critical', 'High', 'Medium', 'Low')) {
        if ([int]$Left.$tier -ne [int]$Right.$tier) { return $false }
    }
    return $true
}

function Test-MetraInspectReviewGoalMet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Counts
    )

    return ([int]$Counts.Critical -eq 0 -and [int]$Counts.High -eq 0 -and [int]$Counts.Medium -le 2)
}

function Test-MetraInspectReviewRegressed {
    <#
    .SYNOPSIS
        True when post-fix severity counts are worse than the saved baseline (Critical/High/Medium only).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Baseline,
        [Parameter(Mandatory)][object]$Current
    )

    foreach ($tier in @('Critical', 'High', 'Medium')) {
        if ([int]$Current.$tier -gt [int]$Baseline.$tier) {
            return $true
        }
    }
    return $false
}

function Get-MetraInspectReviewWorkingTreeInputHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Base
    )

    $diff = Get-MetraInspectGitDiffFiles -Root $Root -Base $Base
    if ($diff.Empty) { return 'empty' }
    return Get-MetraInspectInputHash -Parts @(
        @($diff.Files) | ForEach-Object { [PSCustomObject]@{ path = $_.path; content = $_.content } }
    )
}

function Get-MetraInspectReviewBaselineDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][int]$RoundNum
    )

    $safe = ($SlotKey -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    return Join-Path (Join-Path (Get-MetraInspectStateRoot) $safe) ("baselines/r{0}" -f $RoundNum)
}

function Test-MetraInspectReviewManifestRelativePath {
    <#
    .SYNOPSIS
        True when a manifest/git-relative path is safe to join (no .., not rooted).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $false }
    $normalized = ($RelativePath -replace '\\', '/').Trim()
    if ($normalized -match '(^|/)\.\.(/|$)') { return $false }
    return $true
}

function Resolve-MetraInspectReviewManifestPathPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$ContainerRoot
    )

    if (-not (Test-MetraInspectReviewManifestRelativePath -RelativePath $RelativePath)) {
        throw "Inspect review baseline rejected unsafe manifest path: $RelativePath"
    }

    $destFull = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $RelativePath))
    $srcFull = [System.IO.Path]::GetFullPath((Join-Path $ContainerRoot $RelativePath))
    if (-not (Test-MetraPathWithinRoot -Path $destFull -Root $ProjectRoot)) {
        throw "Inspect review baseline manifest path escapes project root: $RelativePath"
    }
    if (-not (Test-MetraPathWithinRoot -Path $srcFull -Root $ContainerRoot)) {
        throw "Inspect review baseline manifest path escapes baseline directory: $RelativePath"
    }

    return [PSCustomObject]@{
        Relative = [string]$RelativePath
        Src      = $srcFull
        Dest     = $destFull
    }
}

function Assert-MetraInspectReviewBaselinePath {
    <#
    .SYNOPSIS
        Fail closed when persisted baselinePath is outside the expected inspect state slot directory.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][int]$RoundNum
    )

    if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
        throw 'Inspect review baselinePath is empty.'
    }

    $stateRoot = Get-MetraInspectStateRoot
    $baselineFull = [System.IO.Path]::GetFullPath($BaselinePath)
    if (-not (Test-MetraPathWithinRoot -Path $baselineFull -Root $stateRoot)) {
        throw "Inspect review baselinePath is outside inspect state root: $BaselinePath"
    }

    $expected = Get-MetraInspectReviewBaselineDirectory -SlotKey $SlotKey -RoundNum $RoundNum
    $expectedFull = [System.IO.Path]::GetFullPath($expected)
    if (-not [string]::Equals($expectedFull, $baselineFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("Inspect review baselinePath does not match expected round directory. Expected: {0} Actual: {1}" -f $expectedFull, $baselineFull)
    }
}

function Save-MetraInspectReviewGitBaseline {
    <#
    .SYNOPSIS
        Snapshots inspect-scope working tree files for regression revert.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][int]$RoundNum,
        [string]$Base
    )

    $dir = Get-MetraInspectReviewBaselineDirectory -SlotKey $SlotKey -RoundNum $RoundNum
    if (-not $PSCmdlet.ShouldProcess($dir, 'Save inspect review baseline snapshot')) {
        return [PSCustomObject]@{
            Path              = $dir
            GitHead           = ''
            InputHash         = Get-MetraInspectReviewWorkingTreeInputHash -Root $Root -Base $Base
            Manifest          = @()
            DiffPathCount     = 0
            ManifestPathCount = 0
            OmittedPaths      = @()
        }
    }

    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $diff = Get-MetraInspectGitDiffFiles -Root $Root -Base $Base
    $manifest = New-Object System.Collections.Generic.List[string]
    $rejected = New-Object System.Collections.Generic.List[string]
    $eligible = New-Object System.Collections.Generic.List[string]
    $omitted = New-Object System.Collections.Generic.List[string]
    foreach ($f in @($diff.Files)) {
        $rel = [string]$f.path
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        if (-not (Test-MetraInspectReviewManifestRelativePath -RelativePath $rel)) {
            [void]$rejected.Add($rel)
            continue
        }
        [void]$eligible.Add($rel)
        $src = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            [void]$omitted.Add($rel)
            continue
        }
        $pair = Resolve-MetraInspectReviewManifestPathPair -RelativePath $rel -ProjectRoot $Root -ContainerRoot $dir
        $destParent = Split-Path -Parent $pair.Dest
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $pair.Src -Destination $pair.Dest -Force
        [void]$manifest.Add($rel)
    }
    if ($rejected.Count -gt 0) {
        $preview = if ($rejected.Count -le 5) { ($rejected -join ', ') } else { (($rejected | Select-Object -First 5) -join ', ') + '...' }
        throw ("Inspect review baseline rejected {0} inspect-scope path(s): {1}" -f $rejected.Count, $preview)
    }
    if ($omitted.Count -gt 0) {
        $preview = if ($omitted.Count -le 5) { ($omitted -join ', ') } else { (($omitted | Select-Object -First 5) -join ', ') + '...' }
        Write-Warning ("Inspect review baseline captured {0}/{1} inspect-scope diff path(s); {2} omitted (non-leaf or missing on disk): {3}" -f $manifest.Count, $eligible.Count, $omitted.Count, $preview)
    }
    Write-MetraAtomicUtf8Text -Path (Join-Path $dir 'manifest.json') -Text ($manifest | ConvertTo-Json -Compress)

    return [PSCustomObject]@{
        Path              = $dir
        GitHead           = [string]$diff.GitHead
        InputHash         = Get-MetraInspectReviewWorkingTreeInputHash -Root $Root -Base $Base
        Manifest          = @($manifest.ToArray())
        DiffPathCount     = [int]$eligible.Count
        ManifestPathCount = [int]$manifest.Count
        OmittedPaths      = @($omitted.ToArray())
    }
}

function Restore-MetraInspectReviewGitBaseline {
    <#
    .SYNOPSIS
        Restores manifest-listed inspect-scope files from a saved baseline directory.
        Does not delete diff files outside the manifest; warns when extras remain.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$BaselinePath,
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][int]$RoundNum,
        [string]$Base
    )

    Assert-MetraInspectReviewBaselinePath -BaselinePath $BaselinePath -SlotKey $SlotKey -RoundNum $RoundNum

    if (-not $PSCmdlet.ShouldProcess($Root, 'Restore inspect review baseline (regression revert)')) {
        return
    }

    $manifestPath = Join-Path $BaselinePath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Inspect review baseline manifest missing: $manifestPath"
    }
    $manifest = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json) | ForEach-Object { [string]$_ })

    foreach ($rel in $manifest) {
        $pair = Resolve-MetraInspectReviewManifestPathPair -RelativePath $rel -ProjectRoot $Root -ContainerRoot $BaselinePath
        if (Test-Path -LiteralPath $pair.Src -PathType Leaf) {
            $destParent = Split-Path -Parent $pair.Dest
            if (-not (Test-Path -LiteralPath $destParent)) {
                New-Item -ItemType Directory -Path $destParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $pair.Src -Destination $pair.Dest -Force
        }
        elseif (Test-Path -LiteralPath $pair.Dest) {
            Remove-Item -LiteralPath $pair.Dest -Force -ErrorAction Stop
        }
    }

    $currentDiff = Get-MetraInspectGitDiffFiles -Root $Root -Base $Base
    $extras = @(@($currentDiff.Files) | ForEach-Object { [string]$_.path } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and ($manifest -notcontains $_)
        })
    if ($extras.Count -gt 0) {
        $preview = if ($extras.Count -le 5) { ($extras -join ', ') } else { (($extras | Select-Object -First 5) -join ', ') + '...' }
        Write-Warning ("Regression revert restored manifest files only; {0} diff file(s) were left unchanged: {1}" -f $extras.Count, $preview)
    }
}

function Export-MetraInspectReviewFixQueue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][object]$Report,
        [int]$RoundNum
    )

    $safe = ($SlotKey -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    $path = Join-Path (Join-Path (Get-MetraInspectStateRoot) $safe) 'fix-queue.json'
    $items = @(@($Report.findings) | ForEach-Object {
            [ordered]@{
                severity       = [string]$_.severity
                confidence     = [string]$_.confidence
                category       = [string]$_.category
                file           = [string]$_.file
                line           = [int](Get-MetraProp -Object $_ -Name 'line' -Default 0)
                finding        = [string]$_.finding
                recommendation = [string]$_.recommendation
            }
        })
    $payload = [ordered]@{
        exportedAtUtc = [datetime]::UtcNow.ToString('o')
        round         = $RoundNum
        reportPath    = [string](Get-MetraProp -Object $Report.provenance -Name 'reportPath' -Default '')
        findings      = $items
    }
    Write-MetraAtomicUtf8Text -Path $path -Text ($payload | ConvertTo-Json -Depth 8)
    return $path
}

function Write-MetraInspectReviewFixGuidance {
    [CmdletBinding()]
    param(
        [string]$FixQueuePath,
        [switch]$RunUntilGoal
    )

    Write-Host ''
    Write-Host 'Coding loop rhythm:' -ForegroundColor Cyan
    Write-Host '1. Summarize Critical/High (then actionable Medium) in chat.'
    Write-Host '2. Agent applies affirmed fixes only.'
    Write-Host '3. Run inspect loop again - verifies after fixes; reverts the tree if counts regress.'
    Write-Host '4. Repeat until goal, convergence, or MaxLoops. Bing pack is after the loop, not between rounds.'
    if ($FixQueuePath) {
        Write-Host ("Fix queue: {0}" -f $FixQueuePath) -ForegroundColor DarkGray
    }
    if ($RunUntilGoal) {
        Write-Host 'Full loop (-RunAll): re-invoke inspect loop -RunAll after each fix batch until the session completes.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'Next: apply fixes, then run inspect loop again (same session).' -ForegroundColor Yellow
    }
}

function Get-MetraInspectReviewGrade {
    <#
    .SYNOPSIS
        Informational grade from review severity counts (never overrides severity reporting).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Counts
    )

    if ([int]$Counts.Critical -gt 0) { return 'D' }
    if ([int]$Counts.High -gt 0) { return 'C' }
    if ([int]$Counts.Medium -le 2) { return 'A' }
    if ([int]$Counts.Medium -le 5) { return 'B' }
    return 'B'
}

function Get-MetraInspectReviewLoopStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey
    )

    $safe = ($SlotKey -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'default' }
    return Join-Path (Join-Path (Get-MetraInspectStateRoot) $safe) 'review-loop.json'
}

function Get-MetraInspectReviewLoopHistoryPath {
    [CmdletBinding()]
    param()

    return Join-Path (Get-MetraInspectStateRoot) 'review-loop-history.jsonl'
}

function Get-MetraInspectReviewLoopState {
    <#
    .SYNOPSIS
        Loads persisted review-loop session state. Missing file returns $null; corrupt file fails closed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SlotKey
    )

    $path = Get-MetraInspectReviewLoopStatePath -SlotKey $SlotKey
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read inspect review loop state ($path): $($_.Exception.Message). Run inspect loop -Reset to start a new session."
    }
}

function Assert-MetraInspectReviewLoopRootMatch {
    <#
    .SYNOPSIS
        Fail closed when persisted review-loop root does not match the currently resolved project root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PersistedRoot,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CurrentRoot
    )

    if ([string]::IsNullOrWhiteSpace($PersistedRoot)) {
        throw 'Inspect review loop state is missing root. Run inspect loop -Reset to start a new session.'
    }
    if ([string]::IsNullOrWhiteSpace($CurrentRoot)) {
        throw 'Inspect review loop could not resolve project root. Run inspect loop -Reset to start a new session.'
    }

    $persistedFull = [System.IO.Path]::GetFullPath($PersistedRoot)
    $currentFull = [System.IO.Path]::GetFullPath($CurrentRoot)
    if (-not [string]::Equals($persistedFull, $currentFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("Inspect review loop root mismatch (persisted: {0}; current: {1}). Run inspect loop -Reset." -f $persistedFull, $currentFull)
    }
}

function Save-MetraInspectReviewLoopState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$SlotKey,
        [Parameter(Mandatory)][object]$State
    )

    $path = Get-MetraInspectReviewLoopStatePath -SlotKey $SlotKey
    if (-not $PSCmdlet.ShouldProcess($path, 'Persist inspect review loop state')) {
        return [PSCustomObject]@{ Path = $path; Skipped = $true }
    }

    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-MetraAtomicUtf8Text -Path $path -Text ($State | ConvertTo-Json -Depth 12)
    return [PSCustomObject]@{ Path = $path; Skipped = $false }
}

function Add-MetraInspectReviewLoopHistoryEntry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][object]$State
    )

    $path = Get-MetraInspectReviewLoopHistoryPath
    if (-not $PSCmdlet.ShouldProcess($path, 'Append review loop metrics history')) {
        return
    }

    $entry = [ordered]@{
        completedAtUtc    = [datetime]::UtcNow.ToString('o')
        project           = [string]$State.project
        root              = [string]$State.root
        inspectMode       = [string]$State.inspectMode
        LoopsUsed         = [int]$State.LoopsUsed
        FinalGrade        = [string]$State.FinalGrade
        CriticalCount     = [int]$State.CriticalCount
        HighCount         = [int]$State.HighCount
        MediumCount       = [int]$State.MediumCount
        LowCount          = [int]$State.LowCount
        TerminationReason = [string]$State.TerminationReason
        maxLoops          = [int]$State.maxLoops
    }
    $line = ($entry | ConvertTo-Json -Compress -Depth 6)
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
}

function Write-MetraInspectReviewRoundSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Round,
        [Parameter(Mandatory)][object]$Counts
    )

    Write-Host ''
    Write-Host ("Review round {0}" -f $Round) -ForegroundColor Cyan
    Write-Host ("Critical: {0}" -f $Counts.Critical)
    Write-Host ("High: {0}" -f $Counts.High)
    Write-Host ("Medium: {0}" -f $Counts.Medium)
    Write-Host ("Low: {0}" -f $Counts.Low)
}

function Write-MetraInspectReviewLoopFinalSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State
    )

    Write-Host ''
    Write-Host ("Review Grade: {0}" -f $State.FinalGrade) -ForegroundColor $(if ($State.FinalGrade -eq 'A') { 'Green' } else { 'Yellow' })
    Write-Host ("Loops Used: {0}/{1}" -f $State.LoopsUsed, $State.maxLoops)
    Write-Host 'Round Trend:'
    foreach ($round in @($State.rounds)) {
        $parts = @()
        if ([int]$round.critical -gt 0) { $parts += ("Critical {0}" -f $round.critical) }
        if ([int]$round.high -gt 0) { $parts += ("High {0}" -f $round.high) }
        if ([int]$round.medium -gt 0) { $parts += ("Medium {0}" -f $round.medium) }
        if ([int]$round.low -gt 0) { $parts += ("Low {0}" -f $round.low) }
        if ($parts.Count -eq 0) { $parts = @('none') }
        Write-Host ("R{0} -> {1}" -f $round.round, ($parts -join ' '))
    }
    Write-Host ("Termination Reason: {0}" -f $State.TerminationReason)
    if ($State.TerminationReason -eq 'Convergence detected') {
        Write-Host 'Review convergence reached. Additional passes are not producing meaningful reduction.' -ForegroundColor Yellow
    }
    if ($State.TerminationReason -eq 'Maximum loop count reached') {
        Write-Host 'MaxLoops is a protection fence, not success. Run inspect pack for Bing review when ready.' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'After the loop completes, run inspect pack for external (Bing) review - not between rounds.'
}

function Resolve-MetraInspectReviewTermination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$LatestCounts,
        [int]$CompletedCycles = 0,
        [object]$PreviousVerifyCounts = $null,
        [int]$MaxLoops = 5
    )

    if (Test-MetraInspectReviewGoalMet -Counts $LatestCounts) {
        return [PSCustomObject]@{
            Complete          = $true
            TerminationReason = 'Goal achieved'
            LoopsUsed         = $CompletedCycles
        }
    }
    if ($null -ne $PreviousVerifyCounts -and $CompletedCycles -ge 2) {
        if (Test-MetraInspectReviewSeverityCountsEqual -Left $LatestCounts -Right $PreviousVerifyCounts) {
            return [PSCustomObject]@{
                Complete          = $true
                TerminationReason = 'Convergence detected'
                LoopsUsed         = $CompletedCycles
            }
        }
    }
    if ($CompletedCycles -ge $MaxLoops) {
        return [PSCustomObject]@{
            Complete          = $true
            TerminationReason = 'Maximum loop count reached'
            LoopsUsed         = $CompletedCycles
        }
    }
    return [PSCustomObject]@{
        Complete          = $false
        TerminationReason = $null
        LoopsUsed         = $CompletedCycles
    }
}

function Invoke-MetraInspectReviewLoop {
    <#
    .SYNOPSIS
        Goal-based inspect review loop: assess, fix (agent), verify with regression revert, repeat until goal or fence.
        One step per invocation. -RunAll marks a full-loop session (re-invoke after each fix batch until complete).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [string]$Base,
        [switch]$Reset,
        [switch]$RunAll,
        [ValidateRange(0, 20)]
        [int]$MaxLoops = 0
    )

    $ctx = Resolve-MetraInspectProjectContext -Name $Name -Mode diff
    if (-not $ctx.Ok) { throw $ctx.Error }

    $slotKey = [string]$ctx.Project
    if ([string]::IsNullOrWhiteSpace($slotKey)) { $slotKey = 'default' }

    $loaded = if ($Reset) { $null } else { Get-MetraInspectReviewLoopState -SlotKey $slotKey }
    if (-not $Reset -and $null -ne $loaded) {
        Assert-MetraInspectReviewLoopRootMatch -PersistedRoot ([string]$loaded.root) -CurrentRoot ([string]$ctx.Root)
    }
    if (-not $Reset -and $null -ne $loaded -and $loaded.active -eq $false -and -not [string]::IsNullOrWhiteSpace([string]$loaded.TerminationReason)) {
        Write-Host 'Review loop session already complete. Use -Reset to start a new session.' -ForegroundColor Yellow
        Write-MetraInspectReviewLoopFinalSummary -State $loaded
        return $loaded
    }

    if ($PSBoundParameters.ContainsKey('MaxLoops') -and [int]$MaxLoops -gt 0) {
        # explicit CLI wins over persisted session
    }
    elseif ($null -ne $loaded -and [int]$loaded.maxLoops -ge 1 -and [int]$loaded.maxLoops -le 20) {
        $MaxLoops = [int]$loaded.maxLoops
    }
    else {
        $MaxLoops = Get-MetraInspectReviewLoopMaxLoops
    }

    if ($Reset -or $null -eq $loaded) {
        $state = [PSCustomObject]@{
            schemaVersion     = 1
            project           = [string]$ctx.Project
            root              = [string]$ctx.Root
            inspectMode       = 'diff'
            maxLoops          = $MaxLoops
            startedAtUtc      = [datetime]::UtcNow.ToString('o')
            updatedAtUtc      = [datetime]::UtcNow.ToString('o')
            active            = $true
            phase             = $null
            runUntilGoal      = [bool]$RunAll
            pendingBaseline   = $null
            lastVerifyCounts  = $null
            completedCycles   = 0
            rounds            = @()
            LoopsUsed         = 0
            FinalGrade        = $null
            CriticalCount     = 0
            HighCount         = 0
            MediumCount       = 0
            LowCount          = 0
            TerminationReason = $null
        }
    }
    else {
        $state = $loaded
        if ($RunAll) {
            $state.runUntilGoal = $true
        }
        $state.maxLoops = $MaxLoops
    }

    if ($MaxLoops -lt 1 -or $MaxLoops -gt 20) {
        throw "inspect loop MaxLoops must be 1-20 after resolution; got $MaxLoops."
    }

    if ($WhatIfPreference) {
        $next = if ([string]$state.phase -eq 'AwaitingFix') { 'verify-after-fix' } else { 'assess' }
        Write-Host ("WhatIf: would run inspect review loop ({0}) for {1}" -f $next, $ctx.Project)
        return [PSCustomObject]@{ WhatIf = $true; Project = $ctx.Project; MaxLoops = $MaxLoops; Phase = $state.phase }
    }

    $loopShouldProcess = @{ Confirm = $false }

    $pending = $state.pendingBaseline
    $isVerify = ($state.phase -eq 'AwaitingFix') -and ($null -ne $pending)
    if ($isVerify) {
        $currentHash = Get-MetraInspectReviewWorkingTreeInputHash -Root $ctx.Root -Base $Base
        $baselineHash = [string](Get-MetraProp -Object $pending -Name 'inputHash' -Default '')
        if ($currentHash -eq $baselineHash) {
            Write-Host 'No working-tree changes since the last assess. Apply fixes, then run inspect loop again.' -ForegroundColor Yellow
            if ($state.runUntilGoal) {
                Write-Host 'Full loop (-RunAll): waiting for a fix batch before the next verify pass.' -ForegroundColor DarkGray
            }
            $null = Save-MetraInspectReviewLoopState @loopShouldProcess -SlotKey $slotKey -State $state
            return $state
        }

        Write-Host 'Verify pass: inspecting after fix batch (regression revert enabled).' -ForegroundColor Cyan
    }
    else {
        Write-Host 'Assess pass: baseline inspect before fixes.' -ForegroundColor Cyan
    }

    $report = Invoke-MetraInspectDiff -Name $Name -Base $Base
    $reportSkipped = [bool](Get-MetraProp -Object $report -Name 'Skipped' -Default $false)
    if ($null -eq $report) {
        Write-Warning 'Inspect review loop stopped: inspect diff returned no report.'
        return $state
    }
    if ($reportSkipped) {
        Write-Host 'Inspect review loop stopped: inspect diff was skipped (confirm denied or dry-run).' -ForegroundColor Yellow
        return $state
    }

    $counts = Get-MetraInspectReviewSeverityCounts -Findings @($report.findings)

    if ($isVerify) {
        $baselineCounts = [PSCustomObject]@{
            Critical = [int](Get-MetraProp -Object $pending -Name 'critical' -Default 0)
            High     = [int](Get-MetraProp -Object $pending -Name 'high' -Default 0)
            Medium   = [int](Get-MetraProp -Object $pending -Name 'medium' -Default 0)
            Low      = [int](Get-MetraProp -Object $pending -Name 'low' -Default 0)
        }
        if (Test-MetraInspectReviewRegressed -Baseline $baselineCounts -Current $counts) {
            $baselinePath = [string](Get-MetraProp -Object $pending -Name 'baselinePath' -Default '')
            if ([string]::IsNullOrWhiteSpace($baselinePath)) {
                throw 'Inspect review regression detected but baselinePath is missing from session state.'
            }
            Write-Host ''
            Write-Host 'Regression detected (Critical/High/Medium increased). Reverting working tree to pre-fix baseline.' -ForegroundColor Red
            Write-Host ("Before: Critical={0} High={1} Medium={2} | After: Critical={3} High={4} Medium={5}" -f `
                    $baselineCounts.Critical, $baselineCounts.High, $baselineCounts.Medium, `
                    $counts.Critical, $counts.High, $counts.Medium)
            Restore-MetraInspectReviewGitBaseline @loopShouldProcess -Root $ctx.Root -BaselinePath $baselinePath -SlotKey $slotKey -RoundNum ([int]$state.LoopsUsed) -Base $Base
            $state | Add-Member -NotePropertyName lastRegressionAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
            $state | Add-Member -NotePropertyName lastRegressionReverted -NotePropertyValue $true -Force
            $state.updatedAtUtc = [datetime]::UtcNow.ToString('o')
            $null = Save-MetraInspectReviewLoopState @loopShouldProcess -SlotKey $slotKey -State $state
            $fixQueuePath = Export-MetraInspectReviewFixQueue -SlotKey $slotKey -Report $report -RoundNum ([int]$state.LoopsUsed)
            Write-MetraInspectReviewFixGuidance -FixQueuePath $fixQueuePath -RunUntilGoal:([bool]$state.runUntilGoal)
            return $state
        }
    }

    $roundNum = if ($isVerify) { [int]$state.LoopsUsed } else { @($state.rounds).Count + 1 }
    if (-not $isVerify) {
        $round = [PSCustomObject]@{
            round      = $roundNum
            atUtc      = [datetime]::UtcNow.ToString('o')
            critical   = [int]$counts.Critical
            high       = [int]$counts.High
            medium     = [int]$counts.Medium
            low        = [int]$counts.Low
            reportPath = [string](Get-MetraProp -Object $report.provenance -Name 'reportPath' -Default '')
            pass       = 'assess'
        }
        $state.rounds = @(@($state.rounds) + @($round))
        $state.LoopsUsed = $roundNum
    }
    else {
        $rounds = @($state.rounds)
        if ($rounds.Count -gt 0) {
            $last = $rounds[$rounds.Count - 1]
            $last | Add-Member -NotePropertyName verifiedAtUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
            $last | Add-Member -NotePropertyName critical -NotePropertyValue ([int]$counts.Critical) -Force
            $last | Add-Member -NotePropertyName high -NotePropertyValue ([int]$counts.High) -Force
            $last | Add-Member -NotePropertyName medium -NotePropertyValue ([int]$counts.Medium) -Force
            $last | Add-Member -NotePropertyName low -NotePropertyValue ([int]$counts.Low) -Force
            $last | Add-Member -NotePropertyName pass -NotePropertyValue 'verify' -Force
            $state.rounds = $rounds
        }
    }

    $state.CriticalCount = [int]$counts.Critical
    $state.HighCount = [int]$counts.High
    $state.MediumCount = [int]$counts.Medium
    $state.LowCount = [int]$counts.Low
    $state.updatedAtUtc = [datetime]::UtcNow.ToString('o')
    $state.FinalGrade = Get-MetraInspectReviewGrade -Counts $counts

    $baselineSnap = Save-MetraInspectReviewGitBaseline @loopShouldProcess -Root $ctx.Root -SlotKey $slotKey -RoundNum $roundNum -Base $Base
    $state.pendingBaseline = [PSCustomObject]@{
        inputHash         = [string]$baselineSnap.InputHash
        gitHead           = [string]$baselineSnap.GitHead
        baselinePath      = [string]$baselineSnap.Path
        critical          = [int]$counts.Critical
        high              = [int]$counts.High
        medium            = [int]$counts.Medium
        low               = [int]$counts.Low
        baselineCoverage  = [PSCustomObject]@{
            diffPathCount     = [int](Get-MetraProp -Object $baselineSnap -Name 'DiffPathCount' -Default 0)
            manifestPathCount = [int](Get-MetraProp -Object $baselineSnap -Name 'ManifestPathCount' -Default 0)
            omittedPaths      = @((Get-MetraProp -Object $baselineSnap -Name 'OmittedPaths' -Default @()))
        }
    }
    $state.phase = 'AwaitingFix'

    Write-MetraInspectReviewRoundSummary -Round $roundNum -Counts $counts
    if ($isVerify) {
        Write-Host 'Verify pass accepted (no regression).' -ForegroundColor Green
        $state.completedCycles = [int]$state.completedCycles + 1
    }

    $previousVerify = $state.lastVerifyCounts
    $term = Resolve-MetraInspectReviewTermination -LatestCounts $counts -CompletedCycles ([int]$state.completedCycles) -PreviousVerifyCounts $previousVerify -MaxLoops $MaxLoops
    if ($isVerify) {
        $state.lastVerifyCounts = [PSCustomObject]@{
            Critical = [int]$counts.Critical
            High     = [int]$counts.High
            Medium   = [int]$counts.Medium
            Low      = [int]$counts.Low
        }
    }
    if ($term.Complete) {
        $state.active = $false
        $state.phase = $null
        $state.TerminationReason = [string]$term.TerminationReason
        $null = Save-MetraInspectReviewLoopState @loopShouldProcess -SlotKey $slotKey -State $state
        Add-MetraInspectReviewLoopHistoryEntry @loopShouldProcess -State $state
        Write-MetraInspectReviewLoopFinalSummary -State $state
        return $state
    }

    $fixQueuePath = Export-MetraInspectReviewFixQueue -SlotKey $slotKey -Report $report -RoundNum $roundNum
    $null = Save-MetraInspectReviewLoopState @loopShouldProcess -SlotKey $slotKey -State $state
    Write-MetraInspectReviewFixGuidance -FixQueuePath $fixQueuePath -RunUntilGoal:([bool]$state.runUntilGoal)
    return $state
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
    $reset = $false
    $runAll = $false
    $maxLoops = 0

    $i = 0
    if ($argsRest.Count -gt 0 -and $argsRest[0] -ieq 'pack-only') {
        $mode = 'pack-only'
        $i = 1
        if ($argsRest.Count -gt 1 -and $argsRest[1] -ieq 'plan') {
            $packMode = 'plan'
            $i = 2
        }
        elseif ($argsRest.Count -gt 1 -and $argsRest[1] -ieq 'agents') {
            $packMode = 'agents'
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
    elseif ($argsRest.Count -gt 0 -and $argsRest[0] -ieq 'loop') {
        $mode = 'loop'
        $i = 1
    }

    while ($i -lt $argsRest.Count) {
        $tok = [string]$argsRest[$i]
        if ($mode -eq 'loop' -and $tok -ieq '-Reset') {
            $reset = $true
            $i++
            continue
        }
        if ($mode -eq 'loop' -and $tok -ieq '-RunAll') {
            $runAll = $true
            $i++
            continue
        }
        if ($mode -eq 'loop' -and $tok -ieq '-MaxLoops' -and ($i + 1) -lt $argsRest.Count) {
            $parsedMaxLoops = 0
            if (-not [int]::TryParse([string]$argsRest[$i + 1], [ref]$parsedMaxLoops) -or $parsedMaxLoops -lt 1 -or $parsedMaxLoops -gt 20) {
                throw 'inspect loop -MaxLoops must be an integer from 1 to 20.'
            }
            $maxLoops = $parsedMaxLoops
            $i += 2
            continue
        }
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
        'loop' {
            $loopParams = @{
                Name = $projectName
                Base = $baseRev
                Reset = $reset
                RunAll = $runAll
            }
            if ($maxLoops -gt 0) { $loopParams.MaxLoops = $maxLoops }
            return Invoke-MetraInspectReviewLoop @loopParams @common
        }
        default {
            return Invoke-MetraInspectDiff -Name $projectName -Base $baseRev @common
        }
    }
}
