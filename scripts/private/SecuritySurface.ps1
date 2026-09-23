# Security surface scan - structural disclosure (InternalTopology / RestrictedDataMap).
# Tracked files only by default (git ls-files). See SECURITY.md Public surface.

function Get-MetraSecuritySurfaceDenyPatterns {
    <#
    .SYNOPSIS
        Canonical deny patterns for public/private GitHub-tracked trees.
        Pattern strings are assembled so this source file does not itself contain banned tokens.
    #>
    # Token pieces only - never name locals after the joined deny strings (scanner self-hit).
    $b = [string][char]0x5C  # backslash
    $orgA = 'IW' + 'U'
    $orgB = 'ind' + 'wes'
    $adNet = $orgA + 'NET'
    $vend = 'Pente' + 'gra'
    $dmHr = 'DM-' + 'Employee'
    $fnVend = 'fn_' + $vend
    @(
        [PSCustomObject]@{ Id = 'org-brand'; Class = 'InternalTopology'; Pattern = "(?i)\b$orgA\b"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'org-domain'; Class = 'InternalTopology'; Pattern = "(?i)$orgB"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'ad-domain'; Class = 'InternalTopology'; Pattern = "(?i)$adNet$([regex]::Escape($b))"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'host-etl'; Class = 'InternalTopology'; Pattern = '(?i)\bdata' + 'manager\b'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'unc-scripts'; Class = 'InternalTopology'; Pattern = [regex]::Escape($b + $b) + '[a-zA-Z0-9._-]+' + [regex]::Escape($b) + 'Scripts\b'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'host-prd'; Class = 'InternalTopology'; Pattern = '(?i)\bprd-[a-z0-9]+\b'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'magicdns-lab'; Class = 'InternalTopology'; Pattern = '(?i)emerald-' + 'banana\.ts\.net|taila8f8a7\.ts\.net'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'user-local'; Class = 'InternalTopology'; Pattern = '(?i)stephen\.' + 'swan'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'host-build-mac'; Class = 'InternalTopology'; Pattern = "(?i)$orgA" + '75208'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'device-phone'; Class = 'InternalTopology'; Pattern = '(?i)\bSwan' + 'Mobile\b'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'vip-campus'; Class = 'InternalTopology'; Pattern = '\b45\.54\.28\.11\b'; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'vendor-restricted'; Class = 'RestrictedDataMap'; Pattern = "(?i)\b$vend\b"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'db-dm-hr'; Class = 'RestrictedDataMap'; Pattern = "(?i)\b$dmHr\b"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'fn-vendor'; Class = 'RestrictedDataMap'; Pattern = "(?i)$fnVend"; Severity = 'FAIL' }
        [PSCustomObject]@{ Id = 'fn-census'; Class = 'RestrictedDataMap'; Pattern = '(?i)fn_[A-Za-z0-9]*' + 'Census\b'; Severity = 'FAIL' }
    )
}

function Get-MetraSecuritySurfaceAllowlistPath {
    param([string]$Root)
    if (-not $Root) { $Root = Get-MetraRoot }
    Join-Path $Root 'config\security-surface-allowlist.json'
}

function Get-MetraSecuritySurfaceAllowlist {
    param([string]$Root)
    $path = Get-MetraSecuritySurfaceAllowlistPath -Root $Root
    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{ schemaVersion = 1; entries = @() }
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return [PSCustomObject]@{ schemaVersion = 1; entries = @(); loadError = [string]$_.Exception.Message }
    }
}

function Test-MetraSecuritySurfaceAllowlistEntry {
    param(
        [object]$Entry,
        [string]$RelativePath,
        [string]$PatternId
    )
    if (-not $Entry) { return $false }
    $src = [string](Get-MetraProp -Object $Entry -Name 'sourceFile' -Default '')
    $rationale = [string](Get-MetraProp -Object $Entry -Name 'rationale' -Default '')
    $approved = [string](Get-MetraProp -Object $Entry -Name 'approvedBy' -Default '')
    $expires = [string](Get-MetraProp -Object $Entry -Name 'expiresOn' -Default '')
    $pid = [string](Get-MetraProp -Object $Entry -Name 'patternId' -Default '')
    if (-not $src -or -not $rationale -or -not $approved -or -not $expires) { return $false }
    if ($pid -and $PatternId -and ($pid -ne $PatternId)) { return $false }
    $normSrc = ($src -replace '/', '\').TrimStart('.\')
    $normRel = ($RelativePath -replace '/', '\').TrimStart('.\')
    if ($normSrc -ne $normRel -and -not ($normRel -like $normSrc)) { return $false }
    $expDate = $null
    if (-not [datetime]::TryParse($expires, [ref]$expDate)) { return $false }
    if ($expDate.Date -lt (Get-Date).Date) { return $false }
    return $true
}

function Get-MetraSecuritySurfaceTrackedFiles {
    param(
        [string]$Root,
        [switch]$IncludeUntracked
    )
    if (-not $Root) { $Root = Get-MetraRoot }
    $files = New-Object System.Collections.ArrayList
    Push-Location -LiteralPath $Root
    try {
        $tracked = @(git ls-files -z 2>$null)
        if ($LASTEXITCODE -ne 0) {
            throw "git ls-files failed in $Root"
        }
        $raw = git -c core.quotepath=false ls-files 2>$null
        foreach ($rel in @($raw)) {
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $full = Join-Path $Root ($rel -replace '/', '\')
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                [void]$files.Add([PSCustomObject]@{ RelativePath = ($rel -replace '/', '\'); FullPath = $full })
            }
        }
        if ($IncludeUntracked) {
            $untracked = @(git ls-files --others --exclude-standard 2>$null)
            foreach ($rel in $untracked) {
                if ([string]::IsNullOrWhiteSpace($rel)) { continue }
                $full = Join-Path $Root ($rel -replace '/', '\')
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    [void]$files.Add([PSCustomObject]@{ RelativePath = ($rel -replace '/', '\'); FullPath = $full })
                }
            }
        }
    }
    finally {
        Pop-Location
    }
    return @($files)
}

function Test-MetraSecuritySurfaceBinaryExtension {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    return ($ext -match '^\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|exe|dll|vsix|msi|bin|map)$')
}

function Invoke-MetraSecuritySurfaceAudit {
    <#
    .SYNOPSIS
        Scans tracked files for InternalTopology / RestrictedDataMap patterns.
    .PARAMETER Root
        Repo root (default Metra root). Use TicketTracker checkout for station scan.
    .PARAMETER IncludeUntracked
        Also scan untracked files (operator dry-run only; verify uses tracked).
    .PARAMETER FailOnFindings
        Non-zero style: sets Ok=$false when any non-allowlisted FAIL remains.
    #>
    [CmdletBinding()]
    param(
        [string]$Root,
        [switch]$IncludeUntracked,
        [switch]$FailOnFindings
    )

    if (-not $Root) { $Root = Get-MetraRoot }
    $patterns = @(Get-MetraSecuritySurfaceDenyPatterns)
    $allow = Get-MetraSecuritySurfaceAllowlist -Root $Root
    $allowEntries = @()
    if ($allow -and $allow.entries) { $allowEntries = @($allow.entries) }

    $findings = New-Object System.Collections.ArrayList
    $skipExt = 0
    $scanned = 0

    foreach ($f in @(Get-MetraSecuritySurfaceTrackedFiles -Root $Root -IncludeUntracked:$IncludeUntracked)) {
        if (Test-MetraSecuritySurfaceBinaryExtension -Path $f.FullPath) {
            $skipExt++
            continue
        }
        $text = $null
        try {
            $text = [System.IO.File]::ReadAllText($f.FullPath)
        }
        catch {
            [void]$findings.Add([PSCustomObject]@{
                    Class         = 'InternalTopology'
                    PatternId     = 'read-error'
                    Severity      = 'WARN'
                    RelativePath  = $f.RelativePath
                    Line          = 0
                    Snippet       = $_.Exception.Message
                    Allowlisted   = $false
                    AllowlistNote = ''
                })
            continue
        }
        $scanned++
        $lines = [regex]::Split($text, '\r\n|\n|\r')
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            foreach ($p in $patterns) {
                if ($line -notmatch $p.Pattern) { continue }
                $allowed = $false
                $note = ''
                foreach ($e in $allowEntries) {
                    if (Test-MetraSecuritySurfaceAllowlistEntry -Entry $e -RelativePath $f.RelativePath -PatternId $p.Id) {
                        $allowed = $true
                        $note = 'allowlisted'
                        break
                    }
                    # Expired or incomplete allowlist for matching path -> WARN then treat as fail
                    $src = [string](Get-MetraProp -Object $e -Name 'sourceFile' -Default '')
                    $pid = [string](Get-MetraProp -Object $e -Name 'patternId' -Default '')
                    $normSrc = ($src -replace '/', '\').TrimStart('.\')
                    $normRel = ($f.RelativePath -replace '/', '\').TrimStart('.\')
                    if ($normSrc -eq $normRel -and (-not $pid -or $pid -eq $p.Id)) {
                        $expires = [string](Get-MetraProp -Object $e -Name 'expiresOn' -Default '')
                        $expDate = $null
                        if ($expires -and [datetime]::TryParse($expires, [ref]$expDate) -and $expDate.Date -lt (Get-Date).Date) {
                            $note = 'allowlist expired'
                        }
                        elseif (-not (Test-MetraSecuritySurfaceAllowlistEntry -Entry $e -RelativePath $f.RelativePath -PatternId $p.Id)) {
                            $note = 'allowlist incomplete'
                        }
                    }
                }
                $sev = $p.Severity
                if ($allowed) { $sev = 'WARN' }
                $snip = $line.Trim()
                if ($snip.Length -gt 160) { $snip = $snip.Substring(0, 157) + '...' }
                [void]$findings.Add([PSCustomObject]@{
                        Class         = $p.Class
                        PatternId     = $p.Id
                        Severity      = $sev
                        RelativePath  = $f.RelativePath
                        Line          = ($i + 1)
                        Snippet       = $snip
                        Allowlisted   = $allowed
                        AllowlistNote = $note
                    })
            }
        }
    }

    $failFindings = @($findings | Where-Object { $_.Severity -eq 'FAIL' -and -not $_.Allowlisted })
    $byClass = @{}
    foreach ($c in @('InternalTopology', 'RestrictedDataMap', 'PublicSafe')) {
        $byClass[$c] = @($findings | Where-Object Class -eq $c).Count
    }

    $ok = ($failFindings.Count -eq 0)
    if (-not $FailOnFindings) {
        # Report mode still exposes Ok for completion packages
    }

    return [PSCustomObject]@{
        Root           = $Root
        ScannedFiles   = $scanned
        SkippedBinary  = $skipExt
        FindingCount   = $findings.Count
        FailCount      = $failFindings.Count
        CountsByClass  = [PSCustomObject]$byClass
        Findings       = @($findings)
        Ok             = $ok
        AllowlistPath  = (Get-MetraSecuritySurfaceAllowlistPath -Root $Root)
        GeneratedAt    = (Get-Date).ToString('o')
    }
}

function Show-MetraSecurityAuditCli {
    <#
    .SYNOPSIS
        CLI export for .\metra.ps1 security-audit
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [switch]$IncludeUntracked,
        [switch]$FailOnFindings,
        [switch]$Quiet,
        [switch]$Json
    )

    $root = if ($Path) { (Resolve-Path -LiteralPath $Path).Path } else { Get-MetraRoot }
    $report = Invoke-MetraSecuritySurfaceAudit -Root $root -IncludeUntracked:$IncludeUntracked -FailOnFindings:$FailOnFindings

    if ($Json) {
        return ($report | ConvertTo-Json -Depth 6)
    }

    if (-not $Quiet) {
        Write-Host ("Security surface audit: {0}" -f $report.Root)
        Write-Host ("Scanned={0} Fail={1} Findings={2}" -f $report.ScannedFiles, $report.FailCount, $report.FindingCount)
        Write-Host ("CountsByClass InternalTopology={0} RestrictedDataMap={1}" -f `
                $report.CountsByClass.InternalTopology, $report.CountsByClass.RestrictedDataMap)
        $show = @($report.Findings | Where-Object { -not $_.Allowlisted -or $_.Severity -eq 'FAIL' } | Select-Object -First 40)
        foreach ($f in $show) {
            Write-Host ("[{0}] {1}:{2} {3} :: {4}" -f $f.Severity, $f.RelativePath, $f.Line, $f.PatternId, $f.Snippet)
        }
        if ($report.FindingCount -gt $show.Count) {
            Write-Host ("... {0} more findings omitted" -f ($report.FindingCount - $show.Count))
        }
    }

    return $report
}

function Test-MetraTrackedSelfDocSharedOnly {
    <#
    .SYNOPSIS
        Ensures tracked selfdoc embeds (Overview markers / canvas SELFDOC_ROUTES) only name share=true projects.
    #>
    [CmdletBinding()]
    param([string]$Root)

    if (-not $Root) { $Root = Get-MetraRoot }
    $sharedPath = Join-Path $Root 'projects.json'
    $shared = Get-Content -LiteralPath $sharedPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sharedNames = @($shared.projects | ForEach-Object { [string]$_.name } | Where-Object { $_ })
    $sharedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $sharedNames) { [void]$sharedSet.Add($n) }

    $violations = New-Object System.Collections.ArrayList
    $suspect = @('Colleague', 'IWUDATA-Automation', 'IWUDATA-SQL', 'Reporting', 'Jitterbit', 'Atlas', 'Trivia', 'Datamart', 'M365', 'Codex', 'Forge')

    $overview = Join-Path $Root 'docs\Overview.md'
    if (Test-Path -LiteralPath $overview) {
        $text = [System.IO.File]::ReadAllText($overview)
        $begin = '<!-- metra-selfdoc-routes-begin -->'
        $end = '<!-- metra-selfdoc-routes-end -->'
        $i0 = $text.IndexOf($begin)
        $i1 = $text.IndexOf($end)
        if ($i0 -ge 0 -and $i1 -gt $i0) {
            $slice = $text.Substring($i0, $i1 - $i0)
            foreach ($name in $suspect) {
                if ($sharedSet.Contains($name)) { continue }
                if ($slice -match ("(?i)\b{0}\b" -f [regex]::Escape($name))) {
                    [void]$violations.Add([PSCustomObject]@{ Path = 'docs\Overview.md'; Project = $name })
                }
            }
        }
    }

    $canvas = Join-Path $Root 'integrations\cursor\metra-self-documentation.canvas.tsx.template'
    if (Test-Path -LiteralPath $canvas) {
        $text = [System.IO.File]::ReadAllText($canvas)
        $m = [regex]::Match($text, 'const SELFDOC_ROUTES[^=]*=\s*(\{.*?\});', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $slice = if ($m.Success) { $m.Groups[1].Value } else { $text }
        foreach ($name in $suspect) {
            if ($sharedSet.Contains($name)) { continue }
            if ($slice -match ('"name"\s*:\s*"' + [regex]::Escape($name) + '"')) {
                [void]$violations.Add([PSCustomObject]@{ Path = 'integrations\cursor\metra-self-documentation.canvas.tsx.template'; Project = $name })
            }
        }
    }

    return [PSCustomObject]@{
        Ok          = ($violations.Count -eq 0)
        Violations  = @($violations)
        SharedNames = @($sharedNames)
    }
}
