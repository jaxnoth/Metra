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

