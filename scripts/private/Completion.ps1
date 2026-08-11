# Generated from the original Metra.psm1 domain split. Edit this file directly.

# StrictMode-safe sentinel: Import-Module -Force resets script scope and re-registers.
$script:ArgumentCompletersRegistered = $false

function Register-MetraArgumentCompleters {
    if ($script:ArgumentCompletersRegistered) {
        return
    }

    # Closed over by completers: Register-ArgumentCompleter runs scriptblocks in the
    # caller's session, so a private module function would not resolve at tab time.
    $newCompletionResult = {
        param([Parameter(Mandatory)][string]$Name)

        $completion = if ($Name -match '\s') {
            "'$($Name.Replace("'", "''"))'"
        }
        else {
            $Name
        }

        [System.Management.Automation.CompletionResult]::new(
            $completion,
            $Name,
            'ParameterValue',
            $Name
        )
    }

    $projectCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        if (-not (Get-Command Get-MetraProject -ErrorAction Ignore)) {
            return
        }

        $word = [string]$wordToComplete.Trim("'`"")
        foreach ($name in @(
                Get-MetraProject |
                    Select-Object -ExpandProperty Name |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )) {
            if (-not $name.StartsWith($word, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            & $newCompletionResult -Name $name
        }
    }.GetNewClosure()

    $routingCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        if (-not (Get-Command Get-MetraRouting -ErrorAction Ignore)) {
            return
        }

        $word = [string]$wordToComplete.Trim("'`"")
        foreach ($name in @(
                Get-MetraRouting |
                    Select-Object -ExpandProperty Name |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )) {
            if (-not $name.StartsWith($word, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            & $newCompletionResult -Name $name
        }
    }.GetNewClosure()

    $rootCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        if (-not (Get-Command Get-MetraProjectRoot -ErrorAction Ignore)) {
            return
        }

        $word = [string]$wordToComplete.Trim("'`"")
        foreach ($name in @(
                Get-MetraProjectRoot -IncludeMissing |
                    Select-Object -ExpandProperty Name |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )) {
            if (-not $name.StartsWith($word, [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            & $newCompletionResult -Name $name
        }
    }.GetNewClosure()

    Register-ArgumentCompleter -CommandName @(
        'Get-MetraProject',
        'Get-MetraProjectStatus',
        'Update-MetraProject',
        'Invoke-MetraProjectCommand',
        'Copy-MetraProjectFile',
        'Test-MetraProjectContext',
        'Get-MetraChat'
    ) -ParameterName Name -ScriptBlock $projectCompleter

    Register-ArgumentCompleter -CommandName @(
        'Get-MetraRouting'
    ) -ParameterName Name -ScriptBlock $routingCompleter

    Register-ArgumentCompleter -CommandName @(
        'Get-MetraProject',
        'Get-MetraProjectRoot',
        'Get-MetraProjectStatus',
        'Update-MetraProject',
        'Invoke-MetraProjectCommand',
        'Copy-MetraProjectFile',
        'New-MetraProject',
        'Test-MetraProjectContext'
    ) -ParameterName Root -ScriptBlock $rootCompleter

    $script:ArgumentCompletersRegistered = $true
}
