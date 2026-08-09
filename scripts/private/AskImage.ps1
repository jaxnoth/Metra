# Ask image intake (Ladder 3) - Place quarantine resolve + journal pointers.

$script:MetraAskImageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.webp')
$script:MetraAskImageMaxCount = 3
$script:MetraAskImageDefaultPrompt = 'Describe what matters in this screenshot for the next check.'

function Get-MetraAskImageDefaultPrompt {
    return [string]$script:MetraAskImageDefaultPrompt
}

function Test-MetraAskImageFileName {
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
        if (-not (Test-MetraAskImageFileName -FileName $fileName)) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Ask image intake accepts png/jpeg/gif/webp only. Refused: $fileName"
                images  = @()
                journal = @()
            }
        }
        $path = [string](Get-MetraProp -Object $meta -Name 'path' -Default '')
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            return [PSCustomObject]@{
                ok      = $false
                error   = "Quarantine file missing for image id: $id"
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
