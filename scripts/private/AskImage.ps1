# Ask image intake (Ladder 3) - Place quarantine resolve + journal pointers.
# Future: optional magic-byte MIME sniff (PNG/JPEG/GIF/WebP) beyond extension checks.

$script:MetraAskImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp')
$script:MetraAskImageMaxCount = 3
# Match Place upload ceiling (scripts/private/Place.ps1 MetraPlaceMaxUploadBytes).
$script:MetraAskImageMaxBytes = 8MB
$script:MetraAskImageDefaultPrompt = 'Describe what matters in this screenshot for the next check.'
$script:MetraAskImageNormMaxEdge = 1280
$script:MetraAskImageNormJpegQuality = 85

function Get-MetraAskImageDefaultPrompt {
    return [string]$script:MetraAskImageDefaultPrompt
}

function Get-MetraAskImageNormalizeRoot {
    $root = Join-Path $env:LOCALAPPDATA 'Metra\ask\normalized'
    if (-not (Test-Path -LiteralPath $root)) {
        $null = New-Item -ItemType Directory -Path $root -Force
    }
    return $root
}

function ConvertTo-MetraAskNormalizedImage {
    <#
    .SYNOPSIS
        Authoritative Ask image normalize: max edge 1280, JPEG ~85, no upscale.
        Returns path/mime/byte sizes. On failure, returns the original path (fail-open).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Id,
        [string]$FileName = ''
    )

    $preBytes = 0
    try { $preBytes = [long](Get-Item -LiteralPath $Path).Length } catch { }

    $result = [PSCustomObject]@{
        path         = $Path
        mimeType     = Get-MetraAskImageMimeType -FileName $(if ($FileName) { $FileName } else { $Path })
        preBytes     = $preBytes
        postBytes    = $preBytes
        normalized   = $false
        maxEdge      = [int]$script:MetraAskImageNormMaxEdge
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        return $result
    }

    $img = $null
    $bmp = $null
    try {
        $img = [System.Drawing.Image]::FromFile($Path)
        # Apply simple EXIF orientation when present (tag 0x0112).
        try {
            if (@($img.PropertyIdList) -contains 0x0112) {
                $orient = $img.GetPropertyItem(0x0112).Value[0]
                switch ($orient) {
                    3 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                    6 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                    8 { $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
                }
            }
        }
        catch { }

        $w = [int]$img.Width
        $h = [int]$img.Height
        $maxEdge = [int]$script:MetraAskImageNormMaxEdge
        $scale = 1.0
        $longest = [Math]::Max($w, $h)
        if ($longest -gt $maxEdge -and $longest -gt 0) {
            $scale = $maxEdge / [double]$longest
        }
        $nw = [Math]::Max(1, [int][Math]::Round($w * $scale))
        $nh = [Math]::Max(1, [int][Math]::Round($h * $scale))

        $bmp = New-Object System.Drawing.Bitmap $nw, $nh
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($img, 0, 0, $nw, $nh)
        }
        finally { $g.Dispose() }

        $outDir = Get-MetraAskImageNormalizeRoot
        $safeId = ($Id -replace '[^\w\-]', '_')
        $outPath = Join-Path $outDir ($safeId + '.jpg')
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' } |
            Select-Object -First 1
        if (-not $codec) {
            $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        }
        else {
            $encoder = [System.Drawing.Imaging.Encoder]::Quality
            $eps = New-Object System.Drawing.Imaging.EncoderParameters 1
            $eps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter $encoder, ([long]$script:MetraAskImageNormJpegQuality)
            $bmp.Save($outPath, $codec, $eps)
            $eps.Dispose()
        }
        $post = [long](Get-Item -LiteralPath $outPath).Length
        $result.path = $outPath
        $result.mimeType = 'image/jpeg'
        $result.postBytes = $post
        $result.normalized = $true
        return $result
    }
    catch {
        return $result
    }
    finally {
        if ($bmp) { try { $bmp.Dispose() } catch { } }
        if ($img) { try { $img.Dispose() } catch { } }
    }
}

function Test-MetraAskImageFileName {
    <#
    .SYNOPSIS
        True when the path or file name has an Ask-allowed image extension (png/jpeg/gif/webp).
    .NOTES
        Name kept for callers; this checks extension allow-list, not full file-name safety.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$FileName)
    if ([string]::IsNullOrWhiteSpace($FileName)) { return $false }
    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    return ($script:MetraAskImageExtensions -contains $ext)
}

function Get-MetraAskImageMimeType {
    param([Parameter(Mandatory)][string]$FileName)
    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    switch ($ext) {
        '.png' { return 'image/png' }
        '.jpg' { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.gif' { return 'image/gif' }
        '.webp' { return 'image/webp' }
        default { return 'application/octet-stream' }
    }
}

function Resolve-MetraAskImages {
    <#
    .SYNOPSIS
        Resolve Place quarantine ids for Ask vision. Rejects non-image types and caps at 3.
        Engine path may include quarantine path; journal pointer is id + fileName only.
    .NOTES
        Only resolves files already under the Place quarantine root (containment + size + extension).
    #>
    [CmdletBinding()]
    param(
        [string[]]$ImageIds = @()
    )

    $ids = @(
        $ImageIds |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($ids.Count -eq 0) {
        return [PSCustomObject]@{
            ok      = $true
            error   = $null
            images  = @()
            journal = @()
        }
    }

    if ($ids.Count -gt $script:MetraAskImageMaxCount) {
        return [PSCustomObject]@{
            ok      = $false
            error   = "Ask accepts at most $($script:MetraAskImageMaxCount) images per turn."
            images  = @()
            journal = @()
        }
    }

    $quarantineRoot = Get-MetraPlaceQuarantineRoot
    $resolved = [System.Collections.Generic.List[object]]::new()
    $journal = [System.Collections.Generic.List[object]]::new()

    foreach ($id in $ids) {
        $meta = @(Get-MetraPlaceUploadMeta -Id $id) | Select-Object -First 1
        if (-not $meta) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Unknown image id: $id"
                images  = @()
                journal = @()
            }
        }
        $fileName = [string](Get-MetraProp -Object $meta -Name 'fileName' -Default '')
        $path = [string](Get-MetraProp -Object $meta -Name 'path' -Default '')
        # Defensive: both metadata name and quarantine path must look like allowed images.
        if (-not (Test-MetraAskImageFileName -FileName $fileName) -or
            -not (Test-MetraAskImageFileName -FileName $path)) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Ask image intake accepts png/jpeg/gif/webp only. Refused: $fileName"
                images  = @()
                journal = @()
            }
        }
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Image file is no longer available in Place quarantine: $id"
                images  = @()
                journal = @()
            }
        }
        if (-not (Test-MetraPathWithinRoot -Path $path -Root $quarantineRoot)) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Ask image intake only resolves files inside Place quarantine. Refused id: $id"
                images  = @()
                journal = @()
            }
        }
        try {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
        }
        catch {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Image file is no longer available in Place quarantine: $id"
                images  = @()
                journal = @()
            }
        }
        if ($item.Length -gt [long]$script:MetraAskImageMaxBytes) {
            $mb = [math]::Round($script:MetraAskImageMaxBytes / 1MB, 1)
            return [PSCustomObject]@{
                ok      = $false
                error   = "Ask image exceeds ${mb} MB limit. Refused: $fileName"
                images  = @()
                journal = @()
            }
        }
        $safeId = [string](Get-MetraProp -Object $meta -Name 'id' -Default $id)
        # Authoritative normalize once here; Cursor sidecar must not resize again.
        $norm = ConvertTo-MetraAskNormalizedImage -Path $path -Id $safeId -FileName $fileName
        $resolved.Add([PSCustomObject]@{
                id        = $safeId
                fileName  = $fileName
                path      = [string]$norm.path
                mimeType  = [string]$norm.mimeType
                preBytes  = [long]$norm.preBytes
                postBytes = [long]$norm.postBytes
                normalized = [bool]$norm.normalized
            })
        $journal.Add([PSCustomObject]@{
                id       = $safeId
                fileName = $fileName
            })
    }

    return [PSCustomObject]@{
        ok      = $true
        error   = $null
        images  = @($resolved)
        journal = @($journal)
    }
}
