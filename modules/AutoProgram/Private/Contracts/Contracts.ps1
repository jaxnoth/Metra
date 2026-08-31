# Lightweight JSON Schema (draft-07 subset) validation for Contracts/v1 — no external engine.

function Get-AutoProgramContractSchemaPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $file = if ($Name -match '\.schema\.json$') { $Name } else { "$Name.schema.json" }
    return Join-Path $script:AutoProgramModuleRoot (Join-Path 'Contracts\v1' $file)
}

function Get-AutoProgramContractSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $path = Get-AutoProgramContractSchemaPath -Name $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Contract schema not found: $Name ($path)"
    }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Test-AutoProgramContract {
    <#
    .SYNOPSIS
        Validates an object against a Contracts/v1 JSON schema. Throws on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Schema,
        [Parameter(Mandatory)]$Object
    )

    $schemaDoc = Get-AutoProgramContractSchema -Name $Schema
    $errors = New-Object System.Collections.Generic.List[string]
    Test-AutoProgramContractNode -Schema $schemaDoc -Value $Object -Path '$' -Errors $errors
    if ($errors.Count -gt 0) {
        throw ("Contract validation failed ({0}): {1}" -f $Schema, ($errors -join '; '))
    }
    return $true
}

function Get-AutoProgramSchemaProp {
    param(
        $Schema,
        [Parameter(Mandatory)][string]$Name
    )
    $prop = $Schema.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-AutoProgramContractNode {
    param(
        $Schema,
        $Value,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $Schema) { return }

    $type = [string](Get-AutoProgramSchemaProp -Schema $Schema -Name 'type')
    if ($type -eq 'object') {
        if ($null -eq $Value) {
            [void]$Errors.Add("$Path must be an object")
            return
        }
        $props = @{}
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($k in $Value.Keys) { $props[[string]$k] = $Value[$k] }
        }
        else {
            foreach ($p in $Value.PSObject.Properties) { $props[$p.Name] = $p.Value }
        }

        foreach ($req in @($Schema.required)) {
            if (-not $props.ContainsKey([string]$req)) {
                [void]$Errors.Add("$Path missing required property '$req'")
            }
        }

        $schemaProps = Get-AutoProgramSchemaProp -Schema $Schema -Name 'properties'
        if ($schemaProps) {
            foreach ($name in $props.Keys) {
                $propSchema = $null
                $propDef = $schemaProps.PSObject.Properties[$name]
                if ($propDef) {
                    $propSchema = $propDef.Value
                }
                if ($null -eq $propSchema) {
                    if ((Get-AutoProgramSchemaProp -Schema $Schema -Name 'additionalProperties') -eq $false) {
                        [void]$Errors.Add("$Path has disallowed property '$name'")
                    }
                    continue
                }
                Test-AutoProgramContractNode -Schema $propSchema -Value $props[$name] -Path "$Path.$name" -Errors $Errors
            }
        }
        return
    }

    if ($type -eq 'array') {
        if ($null -eq $Value) {
            [void]$Errors.Add("$Path must be an array")
            return
        }
        $items = @($Value)
        $itemsSchema = Get-AutoProgramSchemaProp -Schema $Schema -Name 'items'
        if ($itemsSchema) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                Test-AutoProgramContractNode -Schema $itemsSchema -Value $items[$i] -Path "$Path[$i]" -Errors $Errors
            }
        }
        return
    }

    if ($null -eq $Value -and $type) {
        [void]$Errors.Add("$Path must not be null")
        return
    }

    if ($Schema.PSObject.Properties.Name -contains 'const') {
        $expected = Get-AutoProgramSchemaProp -Schema $Schema -Name 'const'
        $actual = $Value
        if ($expected -is [int] -or $expected -is [long]) {
            try { $actual = [int]$Value } catch { }
        }
        if ($actual -ne $expected) {
            [void]$Errors.Add("$Path must equal '$expected' (got '$Value')")
        }
    }

    switch ($type) {
        'string' {
            if ($Value -is [datetime]) {
                $Value = $Value.ToString('o')
            }
            if ($Value -isnot [string]) {
                [void]$Errors.Add("$Path must be a string")
                return
            }
            $pattern = Get-AutoProgramSchemaProp -Schema $Schema -Name 'pattern'
            if ($pattern -and ($Value -notmatch [string]$pattern)) {
                [void]$Errors.Add("$Path must match pattern $pattern")
            }
        }
        'integer' {
            try {
                $n = [int64]$Value
            }
            catch {
                [void]$Errors.Add("$Path must be an integer")
                return
            }
            $min = Get-AutoProgramSchemaProp -Schema $Schema -Name 'minimum'
            $max = Get-AutoProgramSchemaProp -Schema $Schema -Name 'maximum'
            if ($null -ne $min -and $n -lt [int64]$min) {
                [void]$Errors.Add("$Path below minimum $min")
            }
            if ($null -ne $max -and $n -gt [int64]$max) {
                [void]$Errors.Add("$Path above maximum $max")
            }
        }
        'number' {
            try {
                $n = [double]$Value
            }
            catch {
                [void]$Errors.Add("$Path must be a number")
                return
            }
            $min = Get-AutoProgramSchemaProp -Schema $Schema -Name 'minimum'
            $max = Get-AutoProgramSchemaProp -Schema $Schema -Name 'maximum'
            if ($null -ne $min -and $n -lt [double]$min) {
                [void]$Errors.Add("$Path below minimum $min")
            }
            if ($null -ne $max -and $n -gt [double]$max) {
                [void]$Errors.Add("$Path above maximum $max")
            }
        }
        'boolean' {
            if ($Value -isnot [bool]) {
                [void]$Errors.Add("$Path must be a boolean")
            }
        }
    }
}
