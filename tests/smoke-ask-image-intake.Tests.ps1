#Requires -Version 7
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Metra.psm1') -Force

Describe 'Ask image intake smoke - Ladder 3' {
    It 'stages small png then Ask (Cursor path or honest degrade)' {
        InModuleScope Metra {
            $fixture = Join-Path (Get-MetraRoot) 'tests\fixtures\orion-dashboard.png'
            Test-Path -LiteralPath $fixture | Should -BeTrue
            $bytes = [IO.File]::ReadAllBytes($fixture)
            $meta = Save-MetraPlaceUpload -FileName 'orion-dashboard.png' -Bytes $bytes -ContentType 'image/png'
            $resolved = Resolve-MetraAskImages -ImageIds @($meta.id)
            $resolved.ok | Should -BeTrue

            $settings = Get-MetraAskSettings
            if ($settings.engine -eq 'cursor' -and (Test-MetraAskEngineHealth -TimeoutSec 2)) {
                $ask = Get-MetraDeskAskResult -Prompt 'Describe what matters in this screenshot for the next check.' `
                    -Images $resolved.images
                $ask.images | Should -Not -BeNullOrEmpty
                @($ask.images)[0].fileName | Should -Match 'orion-dashboard'
                ($ask.images[0].PSObject.Properties.Name) | Should -Not -Contain 'path'
                $ask.answerType | Should -BeIn @('provisional', 'grounded', 'degraded')
                $ask.message | Should -Not -BeNullOrEmpty
            }
            else {
                Mock Get-MetraAskSettings {
                    [PSCustomObject]@{ engine = 'ollama'; model = 'llama'; cursorPort = 7381 }
                }
                $deg = Invoke-MetraAskEngine -Prompt 'Describe' -Cwd (Get-MetraRoot) -Images $resolved.images
                $deg.ok | Should -BeFalse
                $deg.error | Should -Be 'image_vision_unsupported'
                $deg.message | Should -Match 'Cursor'
            }

            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('metra-l3-smoke-j-' + [guid]::NewGuid().ToString('n'))
            New-Item -ItemType Directory -Path (Join-Path $tmp 'docs') -Force | Out-Null
            try {
                $entry = Add-MetraDeskAskEntry `
                    -Prompt 'Describe what matters in this screenshot for the next check.' `
                    -Message 'Smoke journal pointer only.' `
                    -SessionId 'l3-smoke' `
                    -Images $resolved.journal `
                    -MetraRoot $tmp
                @($entry.images).Count | Should -Be 1
                $raw = Get-Content -LiteralPath (Get-MetraDeskAskLogPath -MetraRoot $tmp) -Raw -Encoding UTF8
                $raw | Should -Match 'orion-dashboard'
                $raw | Should -Not -Match 'dataBase64'
                $raw | Should -Not -Match 'ops-place-quarantine'
            }
            finally {
                Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
