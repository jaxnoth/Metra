# Registry Loom policy: operator paths and verify commands, not plan prose.
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Loom\Loom.ProjectPolicy.Tests.ps1"
BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra, Loom, Yarn -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $script:RepoRoot 'modules\Loom\Loom.psd1') -Force
}

AfterAll {
    InModuleScope Loom {
        $script:LoomRegistryPolicyOverride = $null
    }
    Get-Module Metra, Loom, Yarn -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
}

Describe 'Loom registry project policy' {
    It 'keeps relative prefixes and drops escape paths and broken commands' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomAllowedPaths   = @('internal', 'cmd', 'internal\pkg', '../evil', 'C:\Windows', '/etc', '')
                loomVerifyCommands = @('go test ./...', "go test`r`nRemove-Item x", '')
                loomCursorModel    = "claude`nsonnet-test"
            }
            try {
                $policy = Get-LoomRegistryLoomPolicy -RegistryName 'SamplePersonal'
                @($policy.allowedPaths) | Should -Be @('internal', 'cmd', 'internal/pkg')
                @($policy.verifyCommands) | Should -Be @('go test ./...')
                [string]$policy.cursorModel | Should -Be ''
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }

    It 'accepts a single-string path and a model slug' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomAllowedPaths = 'cmd'
                loomCursorModel  = 'claude-sonnet-test'
            }
            try {
                $policy = Get-LoomRegistryLoomPolicy -RegistryName 'SamplePersonal'
                @($policy.allowedPaths) | Should -Be @('cmd')
                [string]$policy.cursorModel | Should -Be 'claude-sonnet-test'
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }

    It 'enqueues registry paths and verify when the plan names neither' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('loom-pol-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-LoomHostRoot
            $planRoot = Join-Path $metraRoot ('docs\.ap-policy-' + [guid]::NewGuid().ToString('n'))
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomAllowedPaths   = @('internal', 'cmd', '../evil')
                loomVerifyCommands = @('go test ./...')
            }
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot 'personal.plan.md'
                $body = @"
---
name: Metra personal policy
overview: "Metra personal project policy"
status: Approved
todos:
  - id: t1
    content: "Touch random-folder only in prose"
    status: pending
---

# Implement

Edit random-folder/foo.

- Tests must pass.
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                $item = Invoke-MetraLoomEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot
                @($item.contract.allowedPaths) | Should -Contain 'internal'
                @($item.contract.allowedPaths) | Should -Contain 'cmd'
                @($item.contract.allowedPaths) | Should -Not -Contain '../evil'
                @($item.contract.allowedPaths) | Should -Not -Contain 'random-folder'
                @($item.contract.verifyCommands) | Should -Be @('go test ./...')
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'fails closed when a hashtable entry has an unusable loomVerifyCommands value' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = @{
                loomVerifyCommands = @("go test`r`nRemove-Item x")
            }
            try {
                $policy = Get-LoomRegistryLoomPolicy -RegistryName 'SamplePersonal'
                $policy.verifyInvalid | Should -BeTrue
                $plan = [PSCustomObject]@{
                    project        = [PSCustomObject]@{ registryName = 'SamplePersonal' }
                    verifyCommands = @()
                }
                { Resolve-MetraLoomVerifyCommands -Plan $plan -UseDefault } | Should -Throw '*policy-validation*'
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }

    It 'rejects enqueue when loomVerifyCommands is present but unusable' {
        InModuleScope Loom {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('loom-pol-' + [guid]::NewGuid().ToString('n'))
            $metraRoot = Get-LoomHostRoot
            $planRoot = Join-Path $metraRoot ('docs\.ap-policy-' + [guid]::NewGuid().ToString('n'))
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomVerifyCommands = @("go test`r`nRemove-Item x")
            }
            try {
                New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
                $planPath = Join-Path $planRoot 'invalid-verify.plan.md'
                $body = @"
---
name: Metra invalid verify policy
overview: "Metra invalid verify policy"
status: Approved
todos: []
---

# Implement

- Tests must pass.
"@
                Write-LoomAtomicUtf8Text -Path $planPath -Text $body
                { Invoke-MetraLoomEnqueueFromPlan -Root $root -Path $planPath -MetraRoot $metraRoot } | Should -Throw '*policy-validation*'
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $planRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'keeps the metra verify default when loomVerifyCommands is absent' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomAllowedPaths = @('cmd')
            }
            try {
                $plan = [PSCustomObject]@{
                    project        = [PSCustomObject]@{ registryName = 'SamplePersonal' }
                    verifyCommands = @()
                }
                @(Resolve-MetraLoomVerifyCommands -Plan $plan -UseDefault) | Should -Be @('.\metra.ps1 verify')
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }

    It 'keeps a recognized plan verify line ahead of the registry command' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomVerifyCommands = @('go test ./...')
            }
            try {
                $plan = [PSCustomObject]@{
                    project        = [PSCustomObject]@{ registryName = 'SamplePersonal' }
                    verifyCommands = @('Invoke-Pester -Path tests')
                }
                @(Resolve-MetraLoomVerifyCommands -Plan $plan -UseDefault) | Should -Be @('Invoke-Pester -Path tests')
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }

    It 'keeps a recognized plan verify line when the registry field is unusable' {
        InModuleScope Loom {
            $script:LoomRegistryPolicyOverride = [PSCustomObject]@{
                loomVerifyCommands = @("go test`r`nRemove-Item x")
            }
            try {
                $plan = [PSCustomObject]@{
                    project        = [PSCustomObject]@{ registryName = 'SamplePersonal' }
                    verifyCommands = @('Invoke-Pester -Path tests')
                }
                @(Resolve-MetraLoomVerifyCommands -Plan $plan -UseDefault) | Should -Be @('Invoke-Pester -Path tests')
            }
            finally {
                $script:LoomRegistryPolicyOverride = $null
            }
        }
    }
}
