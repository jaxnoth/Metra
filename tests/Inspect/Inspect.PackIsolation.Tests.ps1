BeforeAll {
    $metaRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    Import-Module (Join-Path $metaRoot 'scripts\Metra.psd1') -Force -ErrorAction Stop
}

Describe 'Inspect per-slot pack isolation' {
    It 'writes pack-plan under project slot not inspect root' {
        InModuleScope Metra {
            $slotKey = "PackIsoTest_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            $packPath = Get-MetraInspectPackPath -SlotKey $slotKey -Mode 'plan'
            $rootPack = Join-Path (Get-MetraInspectStateRoot) 'pack-plan.md'

            try {
                [void](Ensure-MetraInspectSlotDirectory -SlotKey $slotKey)
                Write-MetraInspectPackArtifact -PackText '# test pack' -SlotKey $slotKey -Mode 'plan' -NoClipboard -Confirm:$false

                $packPath | Should -BeLike "*\inspect\$slotKey\pack-plan.md"
                Test-Path -LiteralPath $packPath | Should -Be $true
            }
            finally {
                $slot = Resolve-MetraInspectReviewSlotRoot -SlotKey $slotKey
                if (Test-Path -LiteralPath $slot.SlotRoot) {
                    Remove-Item -LiteralPath $slot.SlotRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It 'isolates pack-diff paths between two project slots' {
        InModuleScope Metra {
            $a = "PackIsoA_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            $b = "PackIsoB_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            try {
                Write-MetraInspectPackArtifact -PackText '# project A' -SlotKey $a -Mode 'diff' -NoClipboard -Confirm:$false
                Write-MetraInspectPackArtifact -PackText '# project B' -SlotKey $b -Mode 'diff' -NoClipboard -Confirm:$false

                $pathA = Get-MetraInspectPackPath -SlotKey $a -Mode 'diff'
                $pathB = Get-MetraInspectPackPath -SlotKey $b -Mode 'diff'
                $pathA | Should -Not -Be $pathB
                (Get-Content -LiteralPath $pathA -Raw) | Should -Match 'project A'
                (Get-Content -LiteralPath $pathB -Raw) | Should -Match 'project B'
            }
            finally {
                foreach ($sk in @($a, $b)) {
                    $slot = Resolve-MetraInspectReviewSlotRoot -SlotKey $sk
                    if (Test-Path -LiteralPath $slot.SlotRoot) {
                        Remove-Item -LiteralPath $slot.SlotRoot -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    It 'returns null when explicit SlotKey has no pointer (no cross-slot fallback)' {
        InModuleScope Metra {
            $metraSlot = "PackIsoMetra_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            $missingSlot = "PackIsoMissing_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
            try {
                $stateRoot = Get-MetraInspectStateRoot
                $pointerPath = Join-Path $stateRoot (Join-Path $metraSlot 'last-diff.json')
                $pointerDir = Split-Path -Parent $pointerPath
                New-Item -ItemType Directory -Path $pointerDir -Force | Out-Null
                $pointer = @{
                    mode             = 'diff'
                    latestReportPath = (Join-Path $pointerDir 'latest.json')
                    project          = $metraSlot
                    createdAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
                }
                Write-MetraAtomicUtf8Text -Path $pointerPath -Text (($pointer | ConvertTo-Json -Depth 6))

                Get-MetraInspectLastPointer -Mode 'diff' -SlotKey $missingSlot | Should -Be $null
            }
            finally {
                $slot = Resolve-MetraInspectReviewSlotRoot -SlotKey $metraSlot
                if (Test-Path -LiteralPath $slot.SlotRoot) {
                    Remove-Item -LiteralPath $slot.SlotRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
