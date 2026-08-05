# Metra proposal jail: shared legality checks for Ops preview and Host apply (Slice 3).
# Does not write project files. Host always re-runs apply-mode before disk writes (Slice 5).

$script:MetraProposalJailMaxFiles = 5
$script:MetraProposalJailMaxBytesPerFile = 262144   # 256 KiB
$script:MetraProposalJailMaxTotalBytes = 524288     # 512 KiB

$script:MetraProposalJailAllowedExtensions = @(
    '.md', '.txt', '.json', '.csv', '.yml', '.yaml'
)

$script:MetraProposalJailDeniedExtensions = @(
    '.exe', '.dll', '.ps1', '.bat', '.cmd', '.msi', '.pfx', '.key', '.pem', '.env'
)

$script:MetraProposalJailDeniedSegments = @(
    '.git', 'node_modules', 'bin', 'obj', '.vs'
)

$script:MetraProposalJailDeniedExactPaths = @(
    '.vscode/settings.json',
    'ops-preferences.local.json'
)

$script:MetraProposalJailDeniedNamePatterns = @(
    'credential', 'secret', 'token', 'password'
)

function Get-MetraProposalJailPolicy {
    return [pscustomobject]@{
        MaxFiles            = [int]$script:MetraProposalJailMaxFiles
        MaxBytesPerFile     = [int]$script:MetraProposalJailMaxBytesPerFile
        MaxTotalBytes       = [int]$script:MetraProposalJailMaxTotalBytes
        AllowedExtensions   = @($script:MetraProposalJailAllowedExtensions)
        DeniedExtensions    = @($script:MetraProposalJailDeniedExtensions)
        DeniedSegments      = @($script:MetraProposalJailDeniedSegments)
        DeniedExactPaths    = @($script:MetraProposalJailDeniedExactPaths)
        DeniedNamePatterns  = @($script:MetraProposalJailDeniedNamePatterns)
    }
}

function New-MetraProposalJailResult {
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [Parameter(Mandatory)][ValidateSet('Preview', 'Apply')][string]$Mode,
        [string]$ReasonCode = '',
        [string]$Message = '',
        [string]$PathRelative = ''
    )

    return [pscustomobject]@{
        Ok           = $Ok
        Mode         = $Mode
        ReasonCode   = $ReasonCode
        Message      = $Message
        PathRelative = $PathRelative
    }
}

function Get-MetraProposalJailNormalizedRelativePath {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathRelative
    )

    if ([string]::IsNullOrWhiteSpace($PathRelative)) {
        return ''
    }

    return ($PathRelative -replace '\\', '/').Trim().TrimStart('/')
}

function Test-MetraProposalJailPathSyntax {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$PathRelative
    )

    $normalized = Get-MetraProposalJailNormalizedRelativePath -PathRelative $PathRelative
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message 'Path is empty.' -PathRelative $PathRelative
    }

    if ($normalized.Contains(':') -or $normalized.StartsWith('\\') -or $normalized.StartsWith('//')) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message 'Absolute paths are not allowed.' -PathRelative $normalized
    }

    $segments = @($normalized -split '/' | Where-Object { $_ -ne '' })
    if ($segments.Count -eq 0) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message 'Path is empty.' -PathRelative $normalized
    }

    foreach ($segment in $segments) {
        if ($segment -eq '.' -or $segment -eq '..') {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message 'Path escape segments are not allowed.' -PathRelative $normalized
        }
        if ($segment.IndexOfAny([char[]]@([char]0)) -ge 0) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message 'Path contains invalid characters.' -PathRelative $normalized
        }
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview -PathRelative $normalized
}

function Test-MetraProposalJailPathPolicy {
    param(
        [Parameter(Mandatory)][string]$PathRelative
    )

    $normalized = Get-MetraProposalJailNormalizedRelativePath -PathRelative $PathRelative
    $syntax = Test-MetraProposalJailPathSyntax -PathRelative $normalized
    if (-not $syntax.Ok) {
        return $syntax
    }

    $lower = $normalized.ToLowerInvariant()
    foreach ($exact in $script:MetraProposalJailDeniedExactPaths) {
        if ($lower -eq $exact.ToLowerInvariant()) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Path is denied by policy: $normalized" -PathRelative $normalized
        }
    }

    $segments = @($normalized -split '/')
    foreach ($segment in $segments) {
        $segLower = $segment.ToLowerInvariant()
        if ($script:MetraProposalJailDeniedSegments -contains $segLower) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Path segment '$segment' is denied by policy." -PathRelative $normalized
        }
    }

    foreach ($pattern in $script:MetraProposalJailDeniedNamePatterns) {
        if ($lower.Contains($pattern.ToLowerInvariant())) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Path matches denied name pattern '*$pattern*'." -PathRelative $normalized
        }
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview -PathRelative $normalized
}

function Get-MetraProposalJailExtension {
    param(
        [Parameter(Mandatory)][string]$PathRelative
    )

    $normalized = Get-MetraProposalJailNormalizedRelativePath -PathRelative $PathRelative
    $leaf = Split-Path -Leaf $normalized.Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        return ''
    }

    # Treat ".env" and "file.env" as extension .env
    if ($leaf.StartsWith('.') -and -not $leaf.Substring(1).Contains('.')) {
        return $leaf.ToLowerInvariant()
    }

    $ext = [System.IO.Path]::GetExtension($leaf)
    if ([string]::IsNullOrWhiteSpace($ext)) {
        return ''
    }
    return $ext.ToLowerInvariant()
}

function Test-MetraProposalJailExtensionPolicy {
    param(
        [Parameter(Mandatory)][string]$PathRelative
    )

    $normalized = Get-MetraProposalJailNormalizedRelativePath -PathRelative $PathRelative
    $ext = Get-MetraProposalJailExtension -PathRelative $normalized
    if ([string]::IsNullOrWhiteSpace($ext)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'File extension is required and must be on the allowlist.' -PathRelative $normalized
    }

    if ($script:MetraProposalJailDeniedExtensions -contains $ext) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "File type not allowed: $ext" -PathRelative $normalized
    }

    if ($script:MetraProposalJailAllowedExtensions -notcontains $ext) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "File type not allowed: $ext" -PathRelative $normalized
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview -PathRelative $normalized
}

function Test-MetraProposalJailContentLimits {
    param(
        [Parameter(Mandatory)][object[]]$Files
    )

    if ($null -eq $Files -or @($Files).Count -lt 1) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'Proposal must include at least one file.'
    }

    $count = @($Files).Count
    if ($count -gt $script:MetraProposalJailMaxFiles) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "File count $count exceeds limit $($script:MetraProposalJailMaxFiles)."
    }

    $totalBytes = 0L
    foreach ($file in $Files) {
        $pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
        $content = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
        if ($null -eq (Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8') -and -not (Test-MetraProposalEntryHasName -Entry $file -Name 'contentUtf8')) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'contentUtf8 is required.' -PathRelative $pathRelative
        }
        if ($content.Contains([char]0)) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'Binary content is not allowed (NUL byte found).' -PathRelative $pathRelative
        }

        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($content)
        if ($bytes -gt $script:MetraProposalJailMaxBytesPerFile) {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "File exceeds per-file size limit ($($script:MetraProposalJailMaxBytesPerFile) bytes)." -PathRelative $pathRelative
        }
        $totalBytes += $bytes
    }

    if ($totalBytes -gt $script:MetraProposalJailMaxTotalBytes) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Total content exceeds size limit ($($script:MetraProposalJailMaxTotalBytes) bytes)."
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview
}

function Test-MetraProposalJailProjectExists {
    param(
        [Parameter(Mandatory)][string]$Project,
        [string[]]$ProjectCatalog
    )

    if ([string]::IsNullOrWhiteSpace($Project)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'Project (route stop) is required.'
    }

    $names = @()
    if ($null -ne $ProjectCatalog) {
        $names = @($ProjectCatalog | ForEach-Object { [string]$_ })
    }
    else {
        $names = @(Get-MetraProjects | ForEach-Object { [string]$_.Name })
    }

    $match = $names | Where-Object { $_.Equals($Project, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $match) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Project not found in registry: $Project"
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview
}

function Resolve-MetraProposalJailRootPath {
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        throw 'RootPath is required.'
    }
    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "RootPath does not exist: $RootPath"
    }
    $item = Get-Item -LiteralPath $RootPath -Force
    if (-not $item.PSIsContainer) {
        throw "RootPath is not a directory: $RootPath"
    }
    return [System.IO.Path]::GetFullPath($item.FullName).TrimEnd('\', '/')
}

function Resolve-MetraProposalJailTargetPath {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$PathRelative
    )

    $syntax = Test-MetraProposalJailPathSyntax -PathRelative $PathRelative
    if (-not $syntax.Ok) {
        return $null
    }

    $rootFull = Resolve-MetraProposalJailRootPath -RootPath $RootPath
    $combined = [System.IO.Path]::GetFullPath((Join-Path $rootFull (($syntax.PathRelative -replace '/', '\'))))
    $rootPrefix = $rootFull.TrimEnd('\') + '\'
    if (-not $combined.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        -not $combined.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $combined
}

function Test-MetraProposalJailReparsePoint {
    param(
        [Parameter(Mandatory)][string]$FullPath
    )

    # Reject if any existing ancestor (or the leaf) is a reparse point - blocks symlink escape.
    $current = $FullPath
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $true
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    return $false
}

function Test-MetraProposalJailFileEntryPreview {
    param(
        [Parameter(Mandatory)]$File
    )

    $pathRelative = [string](Get-MetraProposalEntryValue -Entry $File -Name 'pathRelative')
    $action = [string](Get-MetraProposalEntryValue -Entry $File -Name 'action')

    if ($action -notin @('create', 'replace')) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message "Action not allowed: $action" -PathRelative $pathRelative
    }

    $pathCheck = Test-MetraProposalJailPathPolicy -PathRelative $pathRelative
    if (-not $pathCheck.Ok) {
        return $pathCheck
    }

    $extCheck = Test-MetraProposalJailExtensionPolicy -PathRelative $pathCheck.PathRelative
    if (-not $extCheck.Ok) {
        return $extCheck
    }

    $previousHash = Get-MetraProposalEntryValue -Entry $File -Name 'previousHash'
    if ($action -eq 'replace' -and [string]::IsNullOrWhiteSpace([string]$previousHash)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'Replace requires previousHash.' -PathRelative $pathCheck.PathRelative
    }
    if ($action -eq 'create' -and -not [string]::IsNullOrWhiteSpace([string]$previousHash)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode policyDenied -Message 'Create must not include previousHash.' -PathRelative $pathCheck.PathRelative
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview -PathRelative $pathCheck.PathRelative
}

function Test-MetraProposalJailPreview {
    <#
    .SYNOPSIS
        Ops preview eligibility - legality without trusting Host apply authority.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][object[]]$Files,
        [int]$SchemaVersion = 1,
        [string[]]$ProjectCatalog,
        [switch]$SkipProjectLookup,
        [switch]$SkipRootExists
    )

    if (-not (Test-MetraProposalSchemaVersion -SchemaVersion $SchemaVersion)) {
        return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode schemaRejected -Message 'Unknown schemaVersion.'
    }

    if (-not $SkipProjectLookup) {
        $projectCheck = Test-MetraProposalJailProjectExists -Project $Project -ProjectCatalog $ProjectCatalog
        if (-not $projectCheck.Ok) {
            return $projectCheck
        }
    }

    if (-not $SkipRootExists) {
        try {
            $null = Resolve-MetraProposalJailRootPath -RootPath $RootPath
        }
        catch {
            return New-MetraProposalJailResult -Ok:$false -Mode Preview -ReasonCode pathRejected -Message $_.Exception.Message
        }
    }

    $limits = Test-MetraProposalJailContentLimits -Files $Files
    if (-not $limits.Ok) {
        return $limits
    }

    foreach ($file in $Files) {
        $entry = Test-MetraProposalJailFileEntryPreview -File $file
        if (-not $entry.Ok) {
            return $entry
        }
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Preview -Message 'Preview eligible.'
}

function Test-MetraProposalJailApply {
    <#
    .SYNOPSIS
        Host apply authority checks - fresh root/path resolve, reparse reject, previousHash / create existence.
    .DESCRIPTION
        Always re-run even if Ops preview passed. Does not write files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][object[]]$Files,
        [int]$SchemaVersion = 1,
        [string[]]$ProjectCatalog,
        [switch]$SkipProjectLookup
    )

    $preview = Test-MetraProposalJailPreview `
        -Project $Project `
        -RootPath $RootPath `
        -Files $Files `
        -SchemaVersion $SchemaVersion `
        -ProjectCatalog $ProjectCatalog `
        -SkipProjectLookup:$SkipProjectLookup
    if (-not $preview.Ok) {
        return [pscustomobject]@{
            Ok           = $false
            Mode         = 'Apply'
            ReasonCode   = $preview.ReasonCode
            Message      = $preview.Message
            PathRelative = $preview.PathRelative
        }
    }

    try {
        $rootFull = Resolve-MetraProposalJailRootPath -RootPath $RootPath
    }
    catch {
        return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode pathRejected -Message $_.Exception.Message
    }

    if (Test-MetraProposalJailReparsePoint -FullPath $rootFull) {
        return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode pathRejected -Message 'Project root is a reparse point and is not allowed.'
    }

    foreach ($file in $Files) {
        $pathRelative = Get-MetraProposalJailNormalizedRelativePath -PathRelative ([string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative'))
        $action = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
        $target = Resolve-MetraProposalJailTargetPath -RootPath $rootFull -PathRelative $pathRelative
        if ([string]::IsNullOrWhiteSpace($target)) {
            return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode pathRejected -Message 'Path outside project root.' -PathRelative $pathRelative
        }

        if (Test-MetraProposalJailReparsePoint -FullPath $target) {
            return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode pathRejected -Message 'Target path involves a reparse/symlink and is not allowed.' -PathRelative $pathRelative
        }

        $exists = Test-Path -LiteralPath $target -PathType Leaf
        if ($action -eq 'create') {
            if ($exists) {
                return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode fileChanged -Message 'Create target already exists.' -PathRelative $pathRelative
            }
            continue
        }

        if ($action -eq 'replace') {
            if (-not $exists) {
                return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode fileChanged -Message 'Replace target does not exist.' -PathRelative $pathRelative
            }

            $previousHash = [string](Get-MetraProposalEntryValue -Entry $file -Name 'previousHash')
            $bytes = [System.IO.File]::ReadAllBytes($target)
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            $currentHash = ConvertTo-MetraProposalSha256 -Text $text
            if ($currentHash -ne $previousHash) {
                return New-MetraProposalJailResult -Ok:$false -Mode Apply -ReasonCode hashMismatch -Message 'File changed since proposal (previousHash mismatch).' -PathRelative $pathRelative
            }
        }
    }

    return New-MetraProposalJailResult -Ok:$true -Mode Apply -Message 'Apply eligible.'
}

function Test-MetraProposalJail {
    <#
    .SYNOPSIS
        Dual-pass entry point. Preview = Ops eligibility; Apply = Host authority (+ preview rules).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Preview', 'Apply')][string]$Mode,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][object[]]$Files,
        [int]$SchemaVersion = 1,
        [string[]]$ProjectCatalog,
        [switch]$SkipProjectLookup,
        [switch]$SkipRootExists
    )

    if ($Mode -eq 'Preview') {
        return Test-MetraProposalJailPreview `
            -Project $Project `
            -RootPath $RootPath `
            -Files $Files `
            -SchemaVersion $SchemaVersion `
            -ProjectCatalog $ProjectCatalog `
            -SkipProjectLookup:$SkipProjectLookup `
            -SkipRootExists:$SkipRootExists
    }

    return Test-MetraProposalJailApply `
        -Project $Project `
        -RootPath $RootPath `
        -Files $Files `
        -SchemaVersion $SchemaVersion `
        -ProjectCatalog $ProjectCatalog `
        -SkipProjectLookup:$SkipProjectLookup
}
