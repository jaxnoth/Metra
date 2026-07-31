# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Read-MetraRegistryFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $doc = Get-Content -Raw -Path $Path | ConvertFrom-Json
    foreach ($p in @(Get-MetraProp -Object $doc -Name 'projects' -Default @())) {
        $p | Add-Member -NotePropertyName 'source' -NotePropertyValue $Source -Force
    }
    return $doc
}

function Get-MetraProjectRegistry {
    <#
    .SYNOPSIS
        Loads the agent routing registry: shared projects.json plus optional projects.local.json.
    .DESCRIPTION
        projects.json is the git-tracked, shareable subset. projects.local.json is machine or
        person specific (personal folders, private work entries) and is not committed. Local
        entries with the same name replace the shared entry, so a coworker clone never sees
        them. Use -SharedOnly to inspect exactly what ships to others.
    #>
    [CmdletBinding()]
    param(
        [switch]$SharedOnly
    )

    $metraRoot = Get-MetraRoot
    $sharedPath = Join-Path $metraRoot 'projects.json'
    $localPath = Join-Path $metraRoot 'projects.local.json'

    $shared = Read-MetraRegistryFile -Path $sharedPath -Source 'shared'
    if (-not $shared) {
        throw "Missing project registry: $sharedPath"
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $index = @{}
    foreach ($p in @(Get-MetraProp -Object $shared -Name 'projects' -Default @())) {
        $key = ([string]$p.name).ToLowerInvariant()
        $index[$key] = $projects.Count
        [void]$projects.Add($p)
    }

    $routing = Get-MetraProp -Object $shared -Name 'routing'
    $localLoaded = $false
    $extraSources = @()

    if (-not $SharedOnly) {
        # A root may carry its own registry file so entries travel with the folder itself
        # (for example a cloud-synced personal root that reaches a second machine).
        foreach ($projectRoot in @(Get-MetraRoots)) {
            if (-not $projectRoot.RegistryFile) { continue }
            $rootRegistryPath = [System.Environment]::ExpandEnvironmentVariables($projectRoot.RegistryFile)
            if (-not [System.IO.Path]::IsPathRooted($rootRegistryPath)) {
                $rootRegistryPath = Join-Path $projectRoot.Path $rootRegistryPath
            }
            $rootRegistry = Read-MetraRegistryFile -Path $rootRegistryPath -Source $projectRoot.Name
            if (-not $rootRegistry) { continue }
            $extraSources += $rootRegistryPath
            foreach ($p in @(Get-MetraProp -Object $rootRegistry -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if (-not (Get-MetraProp -Object $p -Name 'root')) {
                    $p | Add-Member -NotePropertyName 'root' -NotePropertyValue $projectRoot.Name -Force
                }
                if ($index.ContainsKey($key)) {
                    $projects[$index[$key]] = $p
                }
                else {
                    $index[$key] = $projects.Count
                    [void]$projects.Add($p)
                }
            }
        }

        $local = Read-MetraRegistryFile -Path $localPath -Source 'local'
        if ($local) {
            $localLoaded = $true
            foreach ($p in @(Get-MetraProp -Object $local -Name 'projects' -Default @())) {
                $key = ([string]$p.name).ToLowerInvariant()
                if ($index.ContainsKey($key)) {
                    $projects[$index[$key]] = $p
                }
                else {
                    $index[$key] = $projects.Count
                    [void]$projects.Add($p)
                }
            }
            $localRouting = Get-MetraProp -Object $local -Name 'routing'
            if ($localRouting -and $routing) {
                foreach ($prop in $localRouting.PSObject.Properties) {
                    $routing | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
            elseif ($localRouting) {
                $routing = $localRouting
            }
        }
    }

    return [PSCustomObject]@{
        version      = Get-MetraProp -Object $shared -Name 'version' -Default 1
        updated      = Get-MetraProp -Object $shared -Name 'updated' -Default ''
        routing      = $routing
        projects     = @($projects.ToArray())
        sharedPath   = $sharedPath
        localPath    = $localPath
        localLoaded  = $localLoaded
        rootRegistry = @($extraSources)
    }
}

function Get-MetraRoutingTable {
    <#
    .SYNOPSIS
        Resolves registry entries against what is actually on disk, with stub advice.
    .DESCRIPTION
        Every registry entry may declare "optional": true plus "whenPresent" / "whenMissing"
        advice. Present projects expose their real entry file and commands; absent optional
        projects return advice instead of counting as drift. That lets one shared registry
        describe capabilities a coworker may or may not have installed.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name,
        [switch]$SharedOnly,
        [switch]$MissingOnly
    )

    $registry = Get-MetraProjectRegistry -SharedOnly:$SharedOnly
    $disk = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $disk[$p.Name.ToLowerInvariant()] = $p
    }

    $rows = foreach ($reg in @($registry.projects)) {
        $regName = [string]$reg.name
        if ($Name -and $Name.Count -gt 0) {
            $wanted = @($Name | ForEach-Object { $_.ToLowerInvariant() })
            if ($wanted -notcontains $regName.ToLowerInvariant()) { continue }
        }

        $onDisk = $disk[$regName.ToLowerInvariant()]
        $present = $null -ne $onDisk
        if ($MissingOnly -and $present) { continue }

        $optional = [bool](Get-MetraProp -Object $reg -Name 'optional' -Default $false)
        $advice = if ($present) {
            [string](Get-MetraProp -Object $reg -Name 'whenPresent' -Default '')
        }
        else {
            [string](Get-MetraProp -Object $reg -Name 'whenMissing' -Default '')
        }
        if (-not $advice -and -not $present) {
            $advice = "Not on this machine. Ask the user for the details this project would have provided; do not invent them."
        }

        [PSCustomObject]@{
            Name         = $regName
            Source       = [string](Get-MetraProp -Object $reg -Name 'source' -Default 'shared')
            Root         = if ($present) { [string]$onDisk.Root } else { '' }
            Present      = $present
            Optional     = $optional
            Entry        = [string](Get-MetraProp -Object $reg -Name 'entry' -Default 'AGENTS.md')
            Capabilities = @(Get-MetraProp -Object $reg -Name 'capabilities' -Default @())
            Triggers     = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
            Serves       = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
            Advice       = $advice
            Path         = if ($present) { [string]$onDisk.Path } else { '' }
        }
    }

    return @($rows | Sort-Object @{ Expression = 'Present'; Descending = $true }, Name)
}

function Get-MetraRegistryProject {
    param(
        [Parameter(Mandatory)]$Registry,
        [Parameter(Mandatory)][string]$Name
    )

    @($Registry.projects) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Get-MetraQueryTokens {
    param([string]$Query)
    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    return @(
        ($Query.ToLowerInvariant() -split '\W+') |
            Where-Object { $_ -and $_.Length -gt 1 }
    )
}

function Get-MetraScoredRoutingProjects {
    <#
    .SYNOPSIS
        Scores present registry projects for a query (same rules as ctx).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query,
        [int]$Limit = 25
    )

    if ($Limit -lt 1) { $Limit = 25 }
    $tokens = @(Get-MetraQueryTokens -Query $Query)
    if ($tokens.Count -eq 0) { return @() }

    $registry = Get-MetraProjectRegistry
    $disk = @{}
    foreach ($p in @(Get-MetraProjects)) {
        $disk[$p.Name.ToLowerInvariant()] = $p
    }

    $scored = New-Object System.Collections.Generic.List[object]
    foreach ($reg in @($registry.projects)) {
        $regName = [string]$reg.name
        $onDisk = $disk[$regName.ToLowerInvariant()]
        if (-not $onDisk) { continue }

        $purpose = [string](Get-MetraProp -Object $reg -Name 'purpose' -Default '')
        $triggers = @(Get-MetraProp -Object $reg -Name 'triggers' -Default @())
        $serves = @(Get-MetraProp -Object $reg -Name 'serves' -Default @())
        $hay = (@($regName) + $triggers + @($purpose) | ForEach-Object { [string]$_ }) -join ' '
        $hayLower = $hay.ToLowerInvariant()
        $score = 0
        $matchedTokens = New-Object System.Collections.Generic.List[string]
        foreach ($t in $tokens) {
            if ($hayLower.Contains($t)) {
                $score++
                [void]$matchedTokens.Add($t)
            }
            if ($regName.ToLowerInvariant() -eq $t) { $score += 2 }
        }
        if ($score -le 0) { continue }

        [void]$scored.Add([PSCustomObject]@{
                Name          = $regName
                Root          = [string]$onDisk.Root
                Path          = [string]$onDisk.Path
                Purpose       = $purpose
                Triggers      = @($triggers)
                Serves        = @($serves)
                Score         = $score
                MatchedTokens = [string[]]@($matchedTokens.ToArray())
                HayLower      = $hayLower
            })
    }

    return @(
        $scored |
            Sort-Object @{ Expression = 'Score'; Descending = $true }, Name |
            Select-Object -First $Limit
    )
}

function Test-MetraRoutingAmbiguity {
    <#
    .SYNOPSIS
        True when primary and runner-up scores are close per Why Here v1 rules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$PrimaryScore,
        [int]$RunnerUpScore
    )

    if ($RunnerUpScore -le 0) { return $false }
    $diff = $PrimaryScore - $RunnerUpScore
    if ($diff -le 1) { return $true }
    if ($PrimaryScore -ge 2 -and $RunnerUpScore -ge ([math]::Ceiling($PrimaryScore * 0.5))) {
        return $true
    }
    return $false
}

function Get-MetraRoutingAmbiguity {
    <#
    .SYNOPSIS
        Picks primary (+ optional close runner-up) for a routing query.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Query
    )

    $scored = @(Get-MetraScoredRoutingProjects -Query $Query -Limit 10)
    if ($scored.Count -eq 0) {
        return [PSCustomObject]@{
            Primary       = $null
            RunnerUp      = $null
            IsAmbiguous   = $false
            FavoredTokens = @()
        }
    }

    $primary = $scored[0]
    $runnerUp = if ($scored.Count -gt 1) { $scored[1] } else { $null }
    $ambiguous = $false
    $favored = @()
    if ($runnerUp) {
        $ambiguous = Test-MetraRoutingAmbiguity -PrimaryScore ([int]$primary.Score) -RunnerUpScore ([int]$runnerUp.Score)
        if ($ambiguous) {
            $favoredList = New-Object System.Collections.Generic.List[string]
            foreach ($t in @(Get-MetraQueryTokens -Query $Query)) {
                $inPrimary = $primary.HayLower.Contains($t)
                $inRunner = $runnerUp.HayLower.Contains($t)
                if ($inPrimary -and -not $inRunner) {
                    [void]$favoredList.Add($t)
                }
            }
            # If none exclusive, show tokens that matched primary
            if ($favoredList.Count -eq 0) {
                foreach ($t in @($primary.MatchedTokens | Select-Object -Unique)) {
                    [void]$favoredList.Add($t)
                }
            }
            $favored = [string[]]@($favoredList.ToArray())
        }
        else {
            $runnerUp = $null
        }
    }

    return [PSCustomObject]@{
        Primary       = $primary
        RunnerUp      = $runnerUp
        IsAmbiguous   = $ambiguous
        FavoredTokens = $favored
    }
}

function Write-MetraForWhom {
    <#
    .SYNOPSIS
        Writes a For whom? audience block to the host (omit when empty).
    #>
    [CmdletBinding()]
    param(
        [string[]]$Serves
    )

    $audiences = @($Serves | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($audiences.Count -eq 0) { return }

    Write-Host 'For whom?'
    foreach ($s in $audiences) {
        Write-Host ("  {0}" -f $s)
    }
}

function Show-MetraRoutingCli {
    <#
    .SYNOPSIS
        CLI host output for routing (For whom? / Why Here). Compatibility export for metra.ps1.
    #>
    [CmdletBinding()]
    param(
        [string]$Query,
        [string[]]$Name,
        [switch]$SharedOnly,
        [switch]$MissingOnly
    )

    if (-not [string]::IsNullOrWhiteSpace($Query) -and (-not $Name -or $Name.Count -eq 0) -and -not $SharedOnly -and -not $MissingOnly) {
        $amb = Get-MetraRoutingAmbiguity -Query $Query
        if (-not $amb.Primary) {
            Write-Host ("No present projects matched query: {0}" -f $Query) -ForegroundColor Yellow
            return
        }

        $primary = $amb.Primary
        Write-Host ("Primary: {0} (score={1})" -f $primary.Name, $primary.Score) -ForegroundColor Cyan
        if ($primary.Purpose) {
            Write-Host ("  {0}" -f $primary.Purpose)
        }
        Write-Host ("  triggers: {0}" -f ($(if ($primary.Triggers.Count -gt 0) { $primary.Triggers -join ', ' } else { '(none)' })))
        if (@($primary.Serves).Count -gt 0) {
            Write-Host ''
            Write-MetraForWhom -Serves $primary.Serves
        }
        $why = @(Get-MetraWhyHere -Project $primary.Name -Query $Query -Limit 3)
        if ($why.Count -gt 0) {
            Write-Host ''
            Write-MetraWhyHere -Project $primary.Name -Decisions $why
        }
        if ($amb.IsAmbiguous -and $amb.RunnerUp) {
            $runner = $amb.RunnerUp
            Write-Host ''
            Write-Host ("Runner-up: {0} (score={1})" -f $runner.Name, $runner.Score) -ForegroundColor Yellow
            if (@($runner.Serves).Count -gt 0) {
                Write-MetraForWhom -Serves $runner.Serves
                Write-Host ''
            }
            $whyNot = @(Get-MetraWhyHere -Project $runner.Name -Query $Query -Limit 2)
            Write-MetraWhyNot -Project $runner.Name -Decisions $whyNot -FavoredTokens $amb.FavoredTokens
        }
        return
    }

    $rows = @(Get-MetraRoutingTable -Name $Name -SharedOnly:$SharedOnly -MissingOnly:$MissingOnly)
    if ($rows.Count -eq 0) {
        Write-Host 'No registry entries matched.' -ForegroundColor Yellow
        return
    }

    $rows |
        Select-Object Name, Source, Root, Present, Optional,
            @{ n = 'Triggers'; e = { ($_.Triggers -join ', ') } } |
        Format-Table -AutoSize
    foreach ($row in @($rows | Where-Object { -not $_.Present })) {
        Write-Host ("{0}: {1}" -f $row.Name, $row.Advice) -ForegroundColor Yellow
    }
    Write-Host ("{0} entr(ies); {1} present" -f $rows.Count, @($rows | Where-Object Present).Count)

    # For whom / Why Here only when -Name scopes the stop (not full-table dump)
    if ($Name -and $Name.Count -gt 0 -and -not $MissingOnly) {
        foreach ($row in @($rows | Where-Object Present)) {
            if (@($row.Serves).Count -gt 0) {
                Write-Host ''
                Write-MetraForWhom -Serves $row.Serves
            }
            $why = @(Get-MetraWhyHere -Project $row.Name -Query $Query -Limit 3)
            if ($why.Count -gt 0) {
                Write-Host ''
                Write-MetraWhyHere -Project $row.Name -Decisions $why
            }
        }
    }
}

