<#
.SYNOPSIS
    Convert Markdown to Word (.docx) via Pandoc (Metra shareable-export tool).
.DESCRIPTION
    Portfolio-owned MD to Word. Markdown stays the source of truth in project repos.

    Mermaid fenced blocks are rendered to PNG (npx @mermaid-js/mermaid-cli) and embedded
    by default. Requires Node.js/npm. Use -SkipMermaidRender for a text note, or
    -KeepMermaid to leave code fences as-is.

    -Share writes under the Metra OneDrive share folder (Share\<Project>\), via
    paths.local.json (%LOCALAPPDATA%\Metra\paths.local.json).
.PARAMETER Path
    Input .md file (absolute, or relative to current directory / Metra root).
.PARAMETER OutFile
    Output .docx path. Default: beside the Markdown file (ignored when -Share).
.PARAMETER Share
    Write to Metra share root Share\<Project>\.
.PARAMETER Project
    Share project subfolder when -Share is set. Default: inferred from path, else Metra.
.PARAMETER KeepMermaid
    Leave ```mermaid blocks as code fences (no PNG render).
.PARAMETER SkipMermaidRender
    Replace Mermaid with a short text note (no Node/mmdc required).
.EXAMPLE
    .\tools\Export-MarkdownDocx.ps1 -Path ..\TicketTracker\docs\Ticket-Lifecycle-Metra.md -Share
.EXAMPLE
    .\metra.ps1 export docx ..\TicketTracker\docs\Ticket-Lifecycle-Metra.md -Share -Name TicketTracker
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [string]$OutFile,

    [switch]$Share,

    [string]$Project,

    [switch]$KeepMermaid,

    [switch]$SkipMermaidRender
)

$ErrorActionPreference = 'Stop'

function Get-MetraCheckoutRoot {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Resolve-Path -LiteralPath (Join-Path $here '..')).Path
}

function Find-Pandoc {
    $cmd = Get-Command pandoc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Pandoc\pandoc.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Pandoc\pandoc.exe'),
        (Join-Path ${env:ProgramFiles} 'Pandoc\pandoc.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Pandoc\pandoc.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Find-Npx {
    $cmd = Get-Command npx -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command npx.cmd -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Import-MetraModuleForExport {
    param([string]$MetraRoot)
    $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (-not (Test-Path -LiteralPath $psd1)) {
        throw "Metra module not found: $psd1"
    }
    Import-Module $psd1 -Force
}

function Convert-MermaidBlocksToImages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Markdown,
        [Parameter(Mandatory)][string]$WorkDir,
        [Parameter(Mandatory)][string]$NpxPath
    )

    $pattern = '(?ms)^```mermaid\r?\n(.*?)^```\s*$'
    $matches = [regex]::Matches($Markdown, $pattern)
    if ($matches.Count -eq 0) {
        return [PSCustomObject]@{ Markdown = $Markdown; ImageCount = 0 }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $result = $Markdown
    for ($i = $matches.Count - 1; $i -ge 0; $i--) {
        $m = $matches[$i]
        $body = $m.Groups[1].Value.TrimEnd()
        $stem = 'mermaid-{0}' -f ($i + 1)
        $mmdPath = Join-Path $WorkDir ($stem + '.mmd')
        $pngPath = Join-Path $WorkDir ($stem + '.png')
        [System.IO.File]::WriteAllText($mmdPath, $body + "`n", $utf8NoBom)

        Push-Location $WorkDir
        try {
            $npxCmd = if ($NpxPath -match '\.cmd$') { $NpxPath } else { 'npx.cmd' }
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $log = & $npxCmd --yes '@mermaid-js/mermaid-cli' -i $mmdPath -o $pngPath -b white --size 1200 2>&1
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $prevEap
            $log | Out-File -FilePath (Join-Path $WorkDir "$stem-mmdc.log") -Encoding utf8
        }
        finally {
            Pop-Location
        }
        if (-not (Test-Path -LiteralPath $pngPath)) {
            $alt = Join-Path $WorkDir ($stem + '-1.png')
            if (Test-Path -LiteralPath $alt) {
                Move-Item -LiteralPath $alt -Destination $pngPath -Force
            }
        }
        if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $pngPath)) {
            $err = ''
            $logFile = Join-Path $WorkDir "$stem-mmdc.log"
            if (Test-Path -LiteralPath $logFile) {
                $err = [System.IO.File]::ReadAllText($logFile)
            }
            $listing = @(Get-ChildItem -LiteralPath $WorkDir -Filter ($stem + '*') -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ', '
            throw "mermaid-cli failed for diagram $($i + 1) (exit $exitCode). Files: $listing. $err"
        }

        $replacement = "![Diagram $($i + 1)]($stem.png)`n"
        $result = $result.Substring(0, $m.Index) + $replacement + $result.Substring($m.Index + $m.Length)
    }

    return [PSCustomObject]@{
        Markdown   = $result
        ImageCount = $matches.Count
    }
}

function Resolve-ExportProjectName {
    param(
        [string]$Project,
        [string]$InputPath
    )
    if (-not [string]::IsNullOrWhiteSpace($Project)) { return $Project.Trim() }
    $norm = $InputPath -replace '/', '\'
    if ($norm -match '\\([^\\]+)\\docs\\' -or $norm -match '\\([^\\]+)\\[^\\]+\.md$') {
        # Prefer a sibling project folder name when path is under C:\Projects\<Name>\...
        if ($norm -match '(?i)\\Projects\\([^\\]+)\\') {
            $n = $Matches[1]
            if ($n -notin @('_meta', '_metra', 'Metra', 'metra')) { return $n }
        }
    }
    return 'Metra'
}

$metraRoot = Get-MetraCheckoutRoot
$pandoc = Find-Pandoc
if (-not $pandoc) {
    throw @"
Pandoc not found on PATH or under LocalAppData/Program Files.
Install: winget install --id JohnMacFarlane.Pandoc -e
Then reopen the shell (or refresh PATH) and retry.
"@
}

$inPath = $Path
if (-not [System.IO.Path]::IsPathRooted($inPath)) {
    $fromCwd = Join-Path (Get-Location).Path $Path
    $fromMetra = Join-Path $metraRoot $Path
    if (Test-Path -LiteralPath $fromCwd) { $inPath = $fromCwd }
    elseif (Test-Path -LiteralPath $fromMetra) { $inPath = $fromMetra }
    else { $inPath = $fromCwd }
}
if (-not (Test-Path -LiteralPath $inPath)) {
    throw "Markdown file not found: $Path"
}
$inPath = (Resolve-Path -LiteralPath $inPath).Path

$projectName = Resolve-ExportProjectName -Project $Project -InputPath $inPath

if ($Share) {
    Import-MetraModuleForExport -MetraRoot $metraRoot
    $null = Initialize-MetraShareLayout
    $shareDir = Get-MetraShareProjectPath -Project $projectName
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($inPath) + '.docx'
    $OutFile = Join-Path $shareDir $baseName
}
elseif ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = [System.IO.Path]::ChangeExtension($inPath, '.docx')
}
elseif (-not [System.IO.Path]::IsPathRooted($OutFile)) {
    $OutFile = Join-Path (Get-Location).Path $OutFile
}

$workMd = $inPath
$tempDir = $null
$mermaidRendered = 0

if (-not $KeepMermaid) {
    $raw = [System.IO.File]::ReadAllText($inPath)
    $pattern = '(?ms)^```mermaid\r?\n(.*?)^```\s*$'
    if ([regex]::IsMatch($raw, $pattern)) {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("metra-md2docx-{0}" -f [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($tempDir)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $tempMd = Join-Path $tempDir 'source.md'

        if ($SkipMermaidRender) {
            $note = "**Diagram note:** Mermaid was not rendered (-SkipMermaidRender). See the Markdown source for the flowchart.`n`n"
            $replaced = [regex]::Replace($raw, $pattern, $note)
            [System.IO.File]::WriteAllText($tempMd, $replaced, $utf8NoBom)
            $workMd = $tempMd
        }
        else {
            $npx = Find-Npx
            if (-not $npx) {
                throw "Node/npx not found. Install Node.js, or re-run with -SkipMermaidRender / -KeepMermaid."
            }
            Write-Host 'Rendering Mermaid diagram(s) via @mermaid-js/mermaid-cli...' -ForegroundColor Cyan
            $converted = Convert-MermaidBlocksToImages -Markdown $raw -WorkDir $tempDir -NpxPath $npx
            [System.IO.File]::WriteAllText($tempMd, $converted.Markdown, $utf8NoBom)
            $workMd = $tempMd
            $mermaidRendered = [int]$converted.ImageCount
        }
    }
}

try {
    $outDir = Split-Path -Parent $OutFile
    if ($outDir) { [void][System.IO.Directory]::CreateDirectory($outDir) }

    if ($tempDir) {
        $pandocOut = Join-Path $tempDir 'output.docx'
    }
    else {
        $pandocOut = Join-Path ([System.IO.Path]::GetTempPath()) ("metra-md2docx-out-{0}.docx" -f [guid]::NewGuid().ToString('N'))
    }

    $pandocArgs = @(
        $workMd,
        '-f', 'markdown',
        '-t', 'docx',
        '-o', $pandocOut,
        '--standalone'
    )
    if ($tempDir) {
        $pandocArgs += "--resource-path=$tempDir"
    }
    & $pandoc @pandocArgs
    if ($LASTEXITCODE -ne 0) {
        throw "pandoc failed with exit code $LASTEXITCODE"
    }

    try {
        Copy-Item -LiteralPath $pandocOut -Destination $OutFile -Force -ErrorAction Stop
    }
    catch {
        $alt = [System.IO.Path]::Combine(
            $outDir,
            ([System.IO.Path]::GetFileNameWithoutExtension($OutFile) + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.docx')
        )
        Copy-Item -LiteralPath $pandocOut -Destination $alt -Force
        Write-Warning ("Could not overwrite locked file '{0}'. Wrote '{1}' instead. Close Word/OneDrive lock and re-run, or use the dated copy." -f $OutFile, $alt)
        $OutFile = $alt
    }
    finally {
        if ($pandocOut -ne $OutFile -and (Test-Path -LiteralPath $pandocOut) -and -not $tempDir) {
            Remove-Item -LiteralPath $pandocOut -Force -ErrorAction SilentlyContinue
        }
    }
}
finally {
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$item = Get-Item -LiteralPath $OutFile
$extra = if ($mermaidRendered -gt 0) { "; embedded $mermaidRendered Mermaid PNG(s)" } else { '' }
Write-Host ("Wrote {0} ({1:N0} bytes) via {2}{3}" -f $item.FullName, $item.Length, $pandoc, $extra) -ForegroundColor Green
