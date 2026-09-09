# Metra Ink runtime host - Windows Inkle ink-engine-runtime (vendored).
# Narrative car only - not an Ask locomotive under engines/.

$script:MetraInkRuntimeLoaded = $false

function Get-MetraInkVendorRoot {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    return (Join-Path $MetraRoot 'narrative\vendor\ink')
}

function Initialize-MetraInkRuntime {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    if ($script:MetraInkRuntimeLoaded) { return }
    $dll = Join-Path (Get-MetraInkVendorRoot -MetraRoot $MetraRoot) 'ink-engine-runtime.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        throw "Ink runtime DLL missing: $dll. Restore narrative/vendor/ink from inkle/ink release assets."
    }
    Add-Type -Path $dll
    $script:MetraInkRuntimeLoaded = $true
}

function Get-MetraInkVendorVersion {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $path = Join-Path (Get-MetraInkVendorRoot -MetraRoot $MetraRoot) 'version.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Ink vendor version.json missing: $path"
    }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 10)
}

function Install-MetraInkInklecate {
    <#
    .SYNOPSIS
        Download inklecate_windows.zip for the pinned ink version into narrative/vendor/ink.
        inklecate.exe is gitignored (large self-contained build); runtime DLL stays tracked.
    #>
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $vendor = Get-MetraInkVendorRoot -MetraRoot $MetraRoot
    [void][System.IO.Directory]::CreateDirectory($vendor)
    $ver = Get-MetraInkVendorVersion -MetraRoot $MetraRoot
    $tag = [string]$ver.inkVersion
    if ([string]::IsNullOrWhiteSpace($tag)) { throw 'version.json missing inkVersion' }
    if (-not $tag.StartsWith('v')) { $tag = "v$tag" }
    $asset = [string]$ver.asset
    if ([string]::IsNullOrWhiteSpace($asset)) { $asset = 'inklecate_windows.zip' }
    $url = "https://github.com/inkle/ink/releases/download/$tag/$asset"
    $zip = Join-Path $env:TEMP ("metra-inklecate-" + [guid]::NewGuid().ToString('n') + '.zip')
    $extract = Join-Path $env:TEMP ("metra-inklecate-" + [guid]::NewGuid().ToString('n'))
    try {
        Write-Verbose "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $exeSrc = Get-ChildItem -LiteralPath $extract -Filter 'inklecate.exe' -Recurse -File | Select-Object -First 1
        if ($null -eq $exeSrc) { throw "inklecate.exe not found inside $asset" }
        Copy-Item -LiteralPath $exeSrc.FullName -Destination (Join-Path $vendor 'inklecate.exe') -Force
        foreach ($name in @('ink_compiler.dll', 'ink-engine-runtime.dll')) {
            $dllSrc = Get-ChildItem -LiteralPath $extract -Filter $name -Recurse -File | Select-Object -First 1
            if ($null -ne $dllSrc -and -not (Test-Path -LiteralPath (Join-Path $vendor $name))) {
                Copy-Item -LiteralPath $dllSrc.FullName -Destination (Join-Path $vendor $name) -Force
            }
        }
        $exeDest = Join-Path $vendor 'inklecate.exe'
        $expected = [string]$ver.inklecateSha256
        if (-not [string]::IsNullOrWhiteSpace($expected)) {
            $actual = (Get-FileHash -LiteralPath $exeDest -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $expected.ToLowerInvariant()) {
                Remove-Item -LiteralPath $exeDest -Force -ErrorAction SilentlyContinue
                throw "inklecate.exe SHA-256 mismatch (expected $expected, got $actual). Refusing to use untrusted compiler binary."
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-MetraInkInklecatePath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $exe = Join-Path (Get-MetraInkVendorRoot -MetraRoot $MetraRoot) 'inklecate.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        Install-MetraInkInklecate -MetraRoot $MetraRoot
    }
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "inklecate.exe missing after install attempt: $exe"
    }
    return $exe
}

function Get-MetraInkTagValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Tags,
        [Parameter(Mandatory)][string]$Prefix
    )
    if ($null -eq $Tags) { return $null }
    $needle = "$Prefix"
    foreach ($t in @($Tags)) {
        if ($null -eq $t) { continue }
        $s = [string]$t
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        if ($s.StartsWith($needle, [StringComparison]::OrdinalIgnoreCase)) {
            return $s.Substring($needle.Length).Trim()
        }
    }
    return $null
}

function Get-MetraInkChoiceMoveId {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Choice)
    $tags = $null
    try { $tags = $Choice.tags } catch { $tags = $null }
    if ($null -eq $tags) { $tags = @() }
    $id = Get-MetraInkTagValue -Tags @($tags) -Prefix 'move:'
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }
    return $id
}

function Get-MetraInkTerminalFromTags {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tags)
    $v = Get-MetraInkTagValue -Tags $Tags -Prefix 'terminal:'
    if ([string]::IsNullOrWhiteSpace($v)) { return '' }
    $v = $v.ToLowerInvariant()
    if ($v -notin @('success', 'fail')) {
        throw "Invalid Metra runtime tag terminal:'$v' (only success|fail)"
    }
    return $v
}

function New-MetraInkStoryFromJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoryJson,
        [string]$MetraRoot = (Get-MetraRoot)
    )
    Initialize-MetraInkRuntime -MetraRoot $MetraRoot
    return [Ink.Runtime.Story]::new($StoryJson)
}

function Get-MetraInkVariablesObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Story)
    $ht = [ordered]@{}
    try {
        foreach ($name in @($Story.variablesState)) {
            $raw = $Story.variablesState[[string]$name]
            $ht[[string]$name] = ConvertTo-MetraInkPlainValue -Value $raw
        }
    }
    catch { }
    if ($ht.Count -eq 0) {
        try {
            $vs = $Story.variablesState
            $field = $vs.GetType().GetField('_globalVariables', [Reflection.BindingFlags]'Instance,NonPublic')
            if ($null -ne $field) {
                $dict = $field.GetValue($vs)
                if ($null -ne $dict) {
                    foreach ($k in @($dict.Keys)) {
                        $ht[[string]$k] = ConvertTo-MetraInkPlainValue -Value $dict[$k]
                    }
                }
            }
        }
        catch { }
    }
    return [PSCustomObject]$ht
}

function ConvertTo-MetraInkPlainValue {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [float] -or $Value -is [string]) {
        return $Value
    }
    try {
        if ($null -ne $Value.PSObject.Properties['value']) { return $Value.value }
    }
    catch { }
    try {
        if ($null -ne $Value.PSObject.Properties['valueObject']) {
            return (ConvertTo-MetraInkPlainValue -Value $Value.valueObject)
        }
    }
    catch { }
    return $Value
}

function Invoke-MetraInkContinue {
    <#
    .SYNOPSIS
        Advance story text; return presented text, choices, terminal tag, ink state JSON.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Story,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $textParts = New-Object System.Collections.Generic.List[string]
    $allTags = New-Object System.Collections.Generic.List[string]
    while ($Story.canContinue) {
        $line = [string]$Story.Continue()
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            [void]$textParts.Add($line.TrimEnd())
        }
        foreach ($t in @($Story.currentTags)) {
            [void]$allTags.Add([string]$t)
        }
    }
    $terminal = ''
    try {
        $terminal = Get-MetraInkTerminalFromTags -Tags @($allTags.ToArray())
    }
    catch {
        throw
    }

    $choices = New-Object System.Collections.Generic.List[object]
    $idx = 0
    foreach ($c in @($Story.currentChoices)) {
        $moveId = Get-MetraInkChoiceMoveId -Choice $c
        [void]$choices.Add([PSCustomObject]@{
                index       = $idx
                inkIndex    = [int]$c.index
                id          = $(if ($moveId) { $moveId } else { '' })
                label       = ([string]$c.text).Trim()
                description = ''
                tags        = @($c.tags)
            })
        $idx++
    }

    return [PSCustomObject]@{
        text       = ($textParts -join [Environment]::NewLine).Trim()
        terminal   = $terminal
        choices    = [object[]]$choices.ToArray()
        inkState   = [string]$Story.state.ToJson()
        variables  = (Get-MetraInkVariablesObject -Story $Story)
        canContinue = [bool]$Story.canContinue
    }
}

function Restore-MetraInkStoryState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Story,
        [string]$InkStateJson
    )
    if ([string]::IsNullOrWhiteSpace($InkStateJson)) { return }
    $Story.state.LoadJson($InkStateJson)
}

function Invoke-MetraInkChooseMove {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Story,
        [Parameter(Mandatory)][string]$MoveId
    )

    $matches = @()
    $i = 0
    foreach ($c in @($Story.currentChoices)) {
        $id = Get-MetraInkChoiceMoveId -Choice $c
        if ($id -eq $MoveId) {
            $matches += [PSCustomObject]@{ Index = $i; Choice = $c }
        }
        $i++
    }
    if ($matches.Count -eq 0) {
        return $null
    }
    if ($matches.Count -gt 1) {
        throw "Duplicate move id '$MoveId' among current choices"
    }
    $Story.ChooseChoiceIndex([int]$matches[0].Choice.index)
    return $matches[0]
}

function Test-MetraInkSourceValidation {
    <#
    .SYNOPSIS
        Static validate story.ink for Metra move/terminal tags before/after compile.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InkPath,
        [Parameter(Mandatory)][string]$PackId
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $InkPath)) {
        [void]$errors.Add("story.ink missing: $InkPath")
        return [PSCustomObject]@{ Ok = $false; Errors = [string[]]$errors.ToArray(); MoveIds = @(); Graph = $null }
    }
    $raw = [System.IO.File]::ReadAllText($InkPath, [System.Text.Encoding]::UTF8)
    $moveIds = New-Object System.Collections.Generic.List[string]
    $choiceNodes = New-Object System.Collections.Generic.List[object]
    $terminals = New-Object System.Collections.Generic.List[string]

    # Choice lines: * or + optionally with condition, then text, optional tags (non-bracket form preferred for Choice.tags)
    $choiceRegex = [regex]'^\s*[\*\+]\s*(?:\{[^\}]*\}\s*)?(?:\[(?<label>[^\]]+)\]|(?<bare>[^\r\n#]+))(?<tags>(?:\s*#[^\r\n]+)*)'
    $lineNum = 0
    foreach ($line in ($raw -split "`r?`n")) {
        $lineNum++
        $tm = [regex]::Matches($line, '#\s*terminal:([A-Za-z0-9_]+)')
        foreach ($m in $tm) {
            $tv = $m.Groups[1].Value.ToLowerInvariant()
            [void]$terminals.Add($tv)
            if ($tv -notin @('success', 'fail')) {
                [void]$errors.Add("Line ${lineNum}: invalid terminal tag '$tv' (only success|fail)")
            }
        }
        if ($line -notmatch '^\s*[\*\+]') { continue }
        # Divert-only or sticky without player text still count if * 
        $cm = $choiceRegex.Match($line)
        if (-not $cm.Success) { continue }
        $label = $cm.Groups['label'].Value
        if ([string]::IsNullOrWhiteSpace($label)) { $label = $cm.Groups['bare'].Value.Trim() }
        $tagBlob = $cm.Groups['tags'].Value
        $mm = [regex]::Match($tagBlob, '#\s*move:([A-Za-z0-9_]+)')
        if (-not $mm.Success) {
            [void]$errors.Add("Line ${lineNum}: choice '$label' missing # move:<id> tag")
            continue
        }
        $mid = $mm.Groups[1].Value
        if ($moveIds -contains $mid) {
            [void]$errors.Add("Duplicate move id '$mid' (line $lineNum)")
        }
        [void]$moveIds.Add($mid)
        [void]$choiceNodes.Add([PSCustomObject]@{
                line   = $lineNum
                id     = $mid
                label  = $label.Trim()
            })
    }

    $knotRegex = [regex]'^\s*===+\s*(?<knot>[A-Za-z0-9_]+)\s*===+'
    $knots = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($raw -split "`r?`n")) {
        $km = $knotRegex.Match($line)
        if ($km.Success) { [void]$knots.Add($km.Groups['knot'].Value) }
    }

    $graph = [PSCustomObject]@{
        packId    = $PackId
        generated = (Get-Date).ToUniversalTime().ToString('o')
        knots     = [string[]]$knots.ToArray()
        moves     = [object[]]$choiceNodes.ToArray()
        terminals = [string[]]@($terminals | Select-Object -Unique)
    }

    return [PSCustomObject]@{
        Ok      = ($errors.Count -eq 0)
        Errors  = [string[]]$errors.ToArray()
        MoveIds = [string[]]$moveIds.ToArray()
        Graph   = $graph
    }
}

function Invoke-MetraInkCompilePack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackId,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    if ([string]::IsNullOrWhiteSpace($PackId) -or $PackId -match '[\\/]|(\.\.)') {
        throw "Invalid pack id: $PackId"
    }
    $packDir = Join-Path (Get-MetraNarrativePacksRoot -MetraRoot $MetraRoot) $PackId
    $packJsonPath = Join-Path $packDir 'pack.json'
    $inkPath = Join-Path $packDir 'story.ink'
    $outJson = Join-Path $packDir 'story.json'
    $graphPath = Join-Path $packDir 'story.graph.json'

    if (-not (Test-Path -LiteralPath $packJsonPath)) { throw "pack.json missing for $PackId" }
    if (-not (Test-Path -LiteralPath $inkPath)) { throw "story.ink missing for $PackId" }

    $packMeta = Get-Content -LiteralPath $packJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
    $metaId = [string]$packMeta.id
    if (-not [string]::Equals($metaId, $PackId, [StringComparison]::OrdinalIgnoreCase)) {
        throw "pack.json id '$metaId' does not match folder '$PackId'"
    }

    $validation = Test-MetraInkSourceValidation -InkPath $inkPath -PackId $PackId
    if (-not $validation.Ok) {
        throw ("Ink Metra validation failed for ${PackId}:`n - " + ($validation.Errors -join "`n - "))
    }

    $exe = Get-MetraInkInklecatePath -MetraRoot $MetraRoot
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = "-o `"$outJson`" `"$inkPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Read stdout/stderr concurrently to avoid pipe deadlock when both buffers fill.
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(120000)) {
        try { $proc.Kill() } catch { }
        throw "inklecate timed out for $PackId after 120s"
    }
    $completed = [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask), 15000)
    if (-not $completed) {
        throw "inklecate output read timed out for $PackId"
    }
    $stdout = [string]$stdoutTask.Result
    $stderr = [string]$stderrTask.Result
    if ($proc.ExitCode -ne 0) {
        throw "inklecate failed for $PackId (exit $($proc.ExitCode)): $stderr $stdout"
    }
    if (-not (Test-Path -LiteralPath $outJson)) {
        throw "inklecate did not write $outJson"
    }

    # Smoke-load compiled JSON
    $storyJson = [System.IO.File]::ReadAllText($outJson, [System.Text.Encoding]::UTF8)
    $story = New-MetraInkStoryFromJson -StoryJson $storyJson -MetraRoot $MetraRoot
    [void](Invoke-MetraInkContinue -Story $story -MetraRoot $MetraRoot)

    $graphJson = ($validation.Graph | ConvertTo-Json -Depth 8)
    [System.IO.File]::WriteAllText($graphPath, $graphJson + "`n", [System.Text.UTF8Encoding]::new($false))

    return [PSCustomObject]@{
        PackId     = $PackId
        StoryJson  = $outJson
        GraphJson  = $graphPath
        MoveCount  = @($validation.MoveIds).Count
        Terminals  = $validation.Graph.terminals
    }
}

function Invoke-MetraInkCompileAllPacks {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))
    $root = Get-MetraNarrativePacksRoot -MetraRoot $MetraRoot
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'story.ink'))) { continue }
        [void]$results.Add((Invoke-MetraInkCompilePack -PackId $dir.Name -MetraRoot $MetraRoot))
    }
    return [object[]]$results.ToArray()
}
