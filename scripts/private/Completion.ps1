# Generated from the original Metra.psm1 domain split. Edit this file directly.

function Register-MetraArgumentCompleters {
    $projectCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        $word = $wordToComplete.Trim("'`"")
        foreach ($name in @(Get-MetraProject | Select-Object -ExpandProperty Name -Unique | Sort-Object)) {
            if ($name -notlike "$word*") { continue }
            $completion = if ($name -match '\s') { "'$($name.Replace("'", "''"))'" } else { $name }
            [System.Management.Automation.CompletionResult]::new($completion, $name, 'ParameterValue', $name)
        }
    }

    $routingCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        $word = $wordToComplete.Trim("'`"")
        foreach ($name in @(Get-MetraRouting | Select-Object -ExpandProperty Name -Unique | Sort-Object)) {
            if ($name -notlike "$word*") { continue }
            $completion = if ($name -match '\s') { "'$($name.Replace("'", "''"))'" } else { $name }
            [System.Management.Automation.CompletionResult]::new($completion, $name, 'ParameterValue', $name)
        }
    }

    $rootCompleter = {
        param($commandName, $parameterName, $wordToComplete)

        $word = $wordToComplete.Trim("'`"")
        foreach ($name in @(Get-MetraProjectRoot -IncludeMissing | Select-Object -ExpandProperty Name -Unique | Sort-Object)) {
            if ($name -notlike "$word*") { continue }
            $completion = if ($name -match '\s') { "'$($name.Replace("'", "''"))'" } else { $name }
            [System.Management.Automation.CompletionResult]::new($completion, $name, 'ParameterValue', $name)
        }
    }

    Register-ArgumentCompleter -CommandName @(
        'Get-MetraProject',
        'Get-MetraProjectStatus',
        'Update-MetraProject',
        'Invoke-MetraProjectCommand',
        'Copy-MetraProjectFile',
        'Test-MetraProjectContext'
    ) -ParameterName Name -ScriptBlock $projectCompleter

    Register-ArgumentCompleter -CommandName @(
        'Get-MetraRouting',
        'Get-MetraChat'
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
}

