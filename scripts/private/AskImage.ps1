# Ask image intake (Ladder 3) - Place quarantine resolve + journal pointers.
# Future: optional magic-byte MIME sniff (PNG/JPEG/GIF/WebP) beyond extension checks.

$script:MetraAskImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp')
$script:MetraAskImageMaxCount = 3
# Match Place upload ceiling (scripts/private/Place.ps1 MetraPlaceMaxUploadBytes).
$script:MetraAskImageMaxBytes = 8MB
$script:MetraAskImageDefaultPrompt = 'Describe what matters in this screenshot for the next check.'

function Get-MetraAskImageDefaultPrompt {
    return [string]$script:MetraAskImageDefaultPrompt
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
        $resolved.Add([PSCustomObject]@{
                id       = $safeId
                fileName = $fileName
                path     = $path
                mimeType = Get-MetraAskImageMimeType -FileName $fileName
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
