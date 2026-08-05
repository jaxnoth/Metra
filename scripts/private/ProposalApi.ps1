# Metra Ops proposal HTTP handlers (Slice 4). Preview + request-apply only - never writes project roots.

function Test-MetraOpsProposalCallerAllowed {
    <#
    .SYNOPSIS
        Non-loopback gate: proposal create / request-apply need Host-issued local session token (Slice 8).
    #>
    param(
        [bool]$IsLoopback = $true,
        [string]$SessionToken
    )

    if ($IsLoopback) {
        return $true
    }

    return (Test-MetraOpsLocalSessionToken -SessionToken $SessionToken)
}

function Test-MetraOpsRequestIsLoopback {
    param(
        [Parameter(Mandatory)]$Request
    )

    try {
        $addr = $Request.RemoteEndPoint.Address
        return [System.Net.IPAddress]::IsLoopback($addr)
    }
    catch {
        return $false
    }
}

function ConvertTo-MetraProposalApiFileSpecs {
    param($Files)

    $out = @()
    foreach ($file in @($Files)) {
        if ($null -eq $file) { continue }
        $spec = @{
            pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
            action       = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
            contentUtf8  = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
        }
        $previousHash = Get-MetraProposalEntryValue -Entry $file -Name 'previousHash'
        if (-not [string]::IsNullOrWhiteSpace([string]$previousHash)) {
            $spec['previousHash'] = [string]$previousHash
        }
        $out += ,$spec
    }
    return $out
}

function Resolve-MetraProposalApiRootPath {
    param(
        [Parameter(Mandatory)][string]$Project,
        [string]$RootPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RootPath)) {
        return $RootPath.TrimEnd('\', '/')
    }

    $match = @(Get-MetraProjects) | Where-Object {
        [string]$_.Name -eq $Project
    } | Select-Object -First 1

    if (-not $match) {
        throw "Project not found in registry: $Project"
    }
    return [string]$match.Path
}

function New-MetraProposalDiffText {
    param(
        [Parameter(Mandatory)]$Proposal
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('Proposal: {0}' -f $Proposal.Id))
    $lines.Add(('Project: {0}' -f $Proposal.Body.project))
    $lines.Add(('Summary: {0}' -f $Proposal.Body.summary))
    $lines.Add(('ContentHash: {0}' -f $Proposal.Body.contentHash))
    $lines.Add('')

    foreach ($file in @($Proposal.Body.files)) {
        $pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
        $action = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
        $content = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
        $lines.Add(('--- {0} ({1})' -f $pathRelative, $action))
        $preview = $content
        if ($preview.Length -gt 4000) {
            $preview = $preview.Substring(0, 4000) + "`n... [truncated]"
        }
        foreach ($line in ($preview -split "`r?`n", -1)) {
            $lines.Add(('+ {0}' -f $line))
        }
        $lines.Add('')
    }

    return ($lines -join "`n")
}

function Save-MetraProposalDiffText {
    param(
        [Parameter(Mandatory)]$Proposal
    )

    $diff = New-MetraProposalDiffText -Proposal $Proposal
    $path = Join-Path $Proposal.StoreRoot ($Proposal.Id + '.diff.txt')
    Set-Content -LiteralPath $path -Value $diff -Encoding UTF8
    return $path
}

function Get-MetraProposalApiView {
    <#
    .SYNOPSIS
        Public proposal view for Ops HTTP - omits raw nonce (Host reads meta privately).
    #>
    param(
        [Parameter(Mandatory)]$Proposal,
        [switch]$IncludeFileContent
    )

    $files = @()
    foreach ($file in @($Proposal.Body.files)) {
        $row = [ordered]@{
            pathRelative = [string](Get-MetraProposalEntryValue -Entry $file -Name 'pathRelative')
            action       = [string](Get-MetraProposalEntryValue -Entry $file -Name 'action')
        }
        $previousHash = Get-MetraProposalEntryValue -Entry $file -Name 'previousHash'
        if (-not [string]::IsNullOrWhiteSpace([string]$previousHash)) {
            $row['previousHash'] = [string]$previousHash
        }
        if ($IncludeFileContent) {
            $row['contentUtf8'] = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
        }
        else {
            $content = [string](Get-MetraProposalEntryValue -Entry $file -Name 'contentUtf8')
            $row['contentBytes'] = [System.Text.Encoding]::UTF8.GetByteCount($content)
        }
        $files += ,[pscustomobject]$row
    }

    return [pscustomobject]@{
        id            = [string]$Proposal.Id
        status        = [string]$Proposal.Status
        schemaVersion = [int]$Proposal.Body.schemaVersion
        project       = [string]$Proposal.Body.project
        routeStop     = [string]$Proposal.Body.routeStop
        rootPath      = [string]$Proposal.Body.rootPath
        summary       = [string]$Proposal.Body.summary
        source        = [string]$Proposal.Body.source
        contentHash   = [string]$Proposal.Body.contentHash
        createdAt     = [string]$Proposal.Body.createdAt
        expiresAt     = [string]$Proposal.ExpiresAt
        resultMessage = $(if ($Proposal.Meta.resultMessage) { [string]$Proposal.Meta.resultMessage } else { $null })
        files         = $files
    }
}

function Get-MetraProposalApiStatusView {
    param(
        [Parameter(Mandatory)]$Proposal
    )

    return [pscustomobject]@{
        id            = [string]$Proposal.Id
        status        = [string]$Proposal.Status
        contentHash   = [string]$Proposal.ContentHash
        expiresAt     = [string]$Proposal.ExpiresAt
        resultMessage = $(if ($Proposal.Meta.resultMessage) { [string]$Proposal.Meta.resultMessage } else { $null })
        updatedAt     = [string]$Proposal.Meta.updatedAt
    }
}

function Invoke-MetraOpsProposalCommand {
    <#
    .SYNOPSIS
        Proposal API command surface used by Ops HTTP. No project-root writes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [string]$Body = '',
        [bool]$IsLoopback = $true,
        [string]$SessionToken,
        [string]$StoreRoot,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $method = $Method.ToUpperInvariant()
    $path = $Path.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) { $path = '/' }

    $match = [regex]::Match($path, '^/api/proposals(?:/([^/]+)(?:/(diff|request-apply|status|apply))?)?$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $proposalId = $match.Groups[1].Value
    $action = $match.Groups[2].Value.ToLowerInvariant()

    # Explicitly reject a tempting /apply name - HTTP must only request-apply.
    if ($action -eq 'apply') {
        return @{
            StatusCode  = 404
            Object      = [pscustomobject]@{
                error = 'not found - use POST /api/proposals/{id}/request-apply'
            }
            Text        = $null
            ContentType = 'application/json; charset=utf-8'
        }
    }

    $mutating = ($method -eq 'POST' -and (
            ([string]::IsNullOrWhiteSpace($proposalId) -and [string]::IsNullOrWhiteSpace($action)) -or
            $action -eq 'request-apply'
        ))
    if ($mutating -and -not (Test-MetraOpsProposalCallerAllowed -IsLoopback:$IsLoopback -SessionToken $SessionToken)) {
        return @{
            StatusCode  = 403
            Object      = [pscustomobject]@{
                error      = 'Proposal create and request-apply require a local session when Ops is not loopback.'
                reasonCode = 'localSessionRequired'
            }
            Text        = $null
            ContentType = 'application/json; charset=utf-8'
        }
    }

    try {
        if ($method -eq 'POST' -and [string]::IsNullOrWhiteSpace($proposalId) -and [string]::IsNullOrWhiteSpace($action)) {
            if ([string]::IsNullOrWhiteSpace($Body)) {
                return @{
                    StatusCode = 400
                    Object     = [pscustomobject]@{ error = 'JSON body required' }
                }
            }
            $parsed = $Body | ConvertFrom-Json
            $project = [string](Get-MetraProp -Object $parsed -Name 'project' -Default '')
            $summary = [string](Get-MetraProp -Object $parsed -Name 'summary' -Default '')
            $source = [string](Get-MetraProp -Object $parsed -Name 'source' -Default 'ask')
            $routeStop = [string](Get-MetraProp -Object $parsed -Name 'routeStop' -Default $project)
            $rootPathIn = [string](Get-MetraProp -Object $parsed -Name 'rootPath' -Default '')
            $schemaVersion = [int](Get-MetraProp -Object $parsed -Name 'schemaVersion' -Default 1)
            $filesRaw = Get-MetraProp -Object $parsed -Name 'files' -Default @()
            $files = ConvertTo-MetraProposalApiFileSpecs -Files $filesRaw

            if ([string]::IsNullOrWhiteSpace($project) -or [string]::IsNullOrWhiteSpace($summary) -or @($files).Count -lt 1) {
                return @{
                    StatusCode = 400
                    Object     = [pscustomobject]@{ error = 'project, summary, and files are required' }
                }
            }

            $rootPath = Resolve-MetraProposalApiRootPath -Project $project -RootPath $rootPathIn
            $jail = Test-MetraProposalJailPreview -Project $project -RootPath $rootPath -Files $files -SchemaVersion $schemaVersion
            if (-not $jail.Ok) {
                return @{
                    StatusCode = 400
                    Object     = [pscustomobject]@{
                        error      = $jail.Message
                        reasonCode = $jail.ReasonCode
                        pathRelative = $jail.PathRelative
                    }
                }
            }

            $created = New-MetraProposal `
                -Project $project `
                -RouteStop $routeStop `
                -RootPath $rootPath `
                -Summary $summary `
                -Files $files `
                -Source $source `
                -SchemaVersion $schemaVersion `
                -StoreRoot $StoreRoot

            $null = Save-MetraProposalDiffText -Proposal $created
            return @{
                StatusCode = 201
                Object     = Get-MetraProposalApiView -Proposal $created -IncludeFileContent
            }
        }

        if ([string]::IsNullOrWhiteSpace($proposalId)) {
            return @{
                StatusCode = 404
                Object     = [pscustomobject]@{ error = 'not found' }
            }
        }

        if ($method -eq 'GET' -and [string]::IsNullOrWhiteSpace($action)) {
            $proposal = Get-MetraProposal -Id $proposalId -StoreRoot $StoreRoot
            return @{
                StatusCode = 200
                Object     = Get-MetraProposalApiView -Proposal $proposal -IncludeFileContent
            }
        }

        if ($method -eq 'GET' -and $action -eq 'status') {
            $proposal = Get-MetraProposal -Id $proposalId -StoreRoot $StoreRoot
            return @{
                StatusCode = 200
                Object     = Get-MetraProposalApiStatusView -Proposal $proposal
            }
        }

        if ($method -eq 'GET' -and $action -eq 'diff') {
            $proposal = Get-MetraProposal -Id $proposalId -StoreRoot $StoreRoot
            $diffPath = Join-Path $proposal.StoreRoot ($proposal.Id + '.diff.txt')
            if (-not (Test-Path -LiteralPath $diffPath)) {
                $null = Save-MetraProposalDiffText -Proposal $proposal
            }
            $text = Get-Content -LiteralPath $diffPath -Raw -Encoding UTF8
            return @{
                StatusCode  = 200
                Object      = $null
                Text        = $text
                ContentType = 'text/plain; charset=utf-8'
            }
        }

        if ($method -eq 'POST' -and $action -eq 'request-apply') {
            $null = Sync-MetraProposalExpiration -Id $proposalId -StoreRoot $StoreRoot
            $updated = Request-MetraProposalApply -Id $proposalId -StoreRoot $StoreRoot
            return @{
                StatusCode = 200
                Object     = Get-MetraProposalApiStatusView -Proposal $updated
            }
        }

        return @{
            StatusCode = 405
            Object     = [pscustomobject]@{ error = 'method not allowed' }
        }
    }
    catch {
        $msg = [string]$_.Exception.Message
        $code = 400
        if ($msg -match 'not found' -or $msg -match 'Proposal file not found') {
            $code = 404
        }
        elseif ($msg -match 'Illegal proposal status') {
            $code = 409
        }
        return @{
            StatusCode = $code
            Object     = [pscustomobject]@{ error = $msg }
        }
    }
}
