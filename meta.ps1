# Silent compatibility shim - prefer .\metra.ps1
& (Join-Path $PSScriptRoot 'metra.ps1') @args
