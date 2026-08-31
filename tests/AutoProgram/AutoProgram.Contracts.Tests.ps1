# Contract shape checks (lightweight — no external JSON schema engine required).
BeforeAll {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Get-Module Metra -ErrorAction SilentlyContinue | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module (Join-Path $repoRoot 'modules\AutoProgram\AutoProgram.psd1') -Force
    $script:Contracts = Join-Path $repoRoot 'modules\AutoProgram\Contracts\v1'
}

Describe 'AutoProgram contracts v1' {
    It 'ships required schema files' {
        $required = @(
            'routing-context.request.schema.json',
            'routing-context.result.schema.json',
            'plan-record.schema.json',
            'triage-candidate.schema.json',
            'queue-item.schema.json',
            'journal-entry.schema.json',
            'inspect-request.schema.json',
            'inspect-result.schema.json',
            'verify-request.schema.json',
            'verify-result.schema.json',
            'acceptance-record.schema.json',
            'blocker-report.schema.json'
        )
        foreach ($name in $required) {
            $path = Join-Path $script:Contracts $name
            Test-Path -LiteralPath $path | Should -BeTrue
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $json.PSObject.Properties.Name | Should -Contain 'properties'
        }
    }

    It 'routing context adapter returns v1 result shape' {
        $result = Get-AutoProgramRoutingContext -Request @{
            schemaVersion = 1
            query         = 'Metra'
            planPath      = ''
        }
        $result.schemaVersion | Should -Be 1
        $result.PSObject.Properties.Name | Should -Contain 'routingConfidence'
        $result.PSObject.Properties.Name | Should -Contain 'eligible'
        $result.PSObject.Properties.Name | Should -Contain 'minimumConfidence'
    }

    It 'frontmatter status:approved wins over body Pending' {
        InModuleScope AutoProgram {
            $dir = Join-Path ([IO.Path]::GetTempPath()) ('ap-ctr-' + [guid]::NewGuid().ToString('n'))
            try {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $planPath = Join-Path $dir 'fm.plan.md'
                $body = @"
---
name: Frontmatter Plan
overview: "Metra"
status: approved
bingReviewed: true
---

# Body

**Status:** Pending Bing Review
"@
                Write-AutoProgramAtomicUtf8Text -Path $planPath -Text $body
                $parsed = Read-MetraAutoprogramPlanFile -Path $planPath -MetraRoot (Get-AutoProgramHostRoot)
                $parsed.approved | Should -BeTrue
                $parsed.planStatus | Should -Match '(?i)approved'
                $parsed.bingReviewed | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
