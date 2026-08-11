# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.AskImage.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
    $script:TinyPng = [Convert]::FromBase64String(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    )
}

Describe 'Ask image resolve' {
    It 'no image ids returns ok with empty arrays' {
        InModuleScope Metra {
            $r = Resolve-MetraAskImages -ImageIds @()
            $r.ok | Should -BeTrue
            @($r.images).Count | Should -Be 0
            @($r.journal).Count | Should -Be 0
        }
    }

    It 'more than 3 image ids returns error' {
        InModuleScope Metra {
            $over = Resolve-MetraAskImages -ImageIds @('a', 'b', 'c', 'd')
            $over.ok | Should -BeFalse
            $over.error | Should -Match 'at most 3'
        }
    }

    It 'unknown id returns error' {
        InModuleScope Metra {
            $r = Resolve-MetraAskImages -ImageIds @('deadbeefdeadbeefdeadbeefdeadbeef')
            $r.ok | Should -BeFalse
            $r.error | Should -Match 'Unknown image id'
        }
    }

    It 'non-image fileName returns error' {
        InModuleScope Metra {
            $txt = Save-MetraPlaceUpload -FileName 'notes.txt' -Bytes ([Text.Encoding]::UTF8.GetBytes('hello')) -ContentType 'text/plain'
            $bad = Resolve-MetraAskImages -ImageIds @($txt.id)
            $bad.ok | Should -BeFalse
            $bad.error | Should -Match 'png/jpeg/gif/webp'
        }
    }

    It 'valid png returns image with path/mimeType and journal without path' {
        InModuleScope Metra -Parameters @{ Png = $script:TinyPng } {
            $img = Save-MetraPlaceUpload -FileName 'ok.png' -Bytes $Png -ContentType 'image/png'
            $ok = Resolve-MetraAskImages -ImageIds @($img.id)
            $ok.ok | Should -BeTrue
            @($ok.images).Count | Should -Be 1
            $ok.images[0].path | Should -Not -BeNullOrEmpty
            $ok.images[0].mimeType | Should -Be 'image/png'
            @($ok.journal).Count | Should -Be 1
            ($ok.journal[0].PSObject.Properties.Name) | Should -Not -Contain 'path'
            ($ok.journal[0].PSObject.Properties.Name) | Should -Not -Contain 'mimeType'
            $ok.journal[0].id | Should -Be $img.id
        }
    }

    It 'duplicate ids are de-duped' {
        InModuleScope Metra -Parameters @{ Png = $script:TinyPng } {
            $img = Save-MetraPlaceUpload -FileName 'dup.png' -Bytes $Png -ContentType 'image/png'
            $ok = Resolve-MetraAskImages -ImageIds @($img.id, $img.id, $img.id)
            $ok.ok | Should -BeTrue
            @($ok.images).Count | Should -Be 1
            @($ok.journal).Count | Should -Be 1
        }
    }

    It 'journal never includes local path' {
        InModuleScope Metra -Parameters @{ Png = $script:TinyPng } {
            $img = Save-MetraPlaceUpload -FileName 'j.png' -Bytes $Png -ContentType 'image/png'
            $ok = Resolve-MetraAskImages -ImageIds @($img.id)
            $json = $ok.journal | ConvertTo-Json -Compress
            $json | Should -Not -Match ([regex]::Escape($img.path))
            $json | Should -Not -Match 'ops-place-quarantine'
        }
    }

    It 'resolved path outside quarantine is rejected' {
        $outside = Join-Path $TestDrive 'escape.png'
        [System.IO.File]::WriteAllBytes($outside, $script:TinyPng)
        InModuleScope Metra -Parameters @{ OutsidePath = $outside } {
            Mock Get-MetraPlaceUploadMeta {
                [PSCustomObject]@{
                    id       = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                    fileName = 'escape.png'
                    path     = $OutsidePath
                }
            }
            $r = Resolve-MetraAskImages -ImageIds @('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
            $r.ok | Should -BeFalse
            $r.error | Should -Match 'Place quarantine'
        }
    }

    It 'oversized image is rejected' {
        InModuleScope Metra -Parameters @{ Png = $script:TinyPng } {
            $prev = $script:MetraAskImageMaxBytes
            try {
                $script:MetraAskImageMaxBytes = 10
                $q = Get-MetraPlaceQuarantineRoot
                $id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                $path = Join-Path $q "$id-big.png"
                [System.IO.File]::WriteAllBytes($path, $Png)
                $metaPath = Join-Path $q "$id.json"
                [PSCustomObject]@{
                    id       = $id
                    fileName = 'big.png'
                    path     = $path
                    size     = $Png.Length
                } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8
                $r = Resolve-MetraAskImages -ImageIds @($id)
                $r.ok | Should -BeFalse
                $r.error | Should -Match 'MB limit'
            }
            finally {
                $script:MetraAskImageMaxBytes = $prev
            }
        }
    }

    It 'path extension mismatch with image fileName is rejected' {
        InModuleScope Metra -Parameters @{ Drive = $TestDrive } {
            $q = Get-MetraPlaceQuarantineRoot
            $id = 'cccccccccccccccccccccccccccccccc'
            $path = Join-Path $q "$id-notes.txt"
            Set-Content -LiteralPath $path -Value 'not an image' -Encoding UTF8
            [PSCustomObject]@{
                id       = $id
                fileName = 'fake.png'
                path     = $path
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $q "$id.json") -Encoding UTF8
            $r = Resolve-MetraAskImages -ImageIds @($id)
            $r.ok | Should -BeFalse
            $r.error | Should -Match 'png/jpeg/gif/webp'
        }
    }

    It 'missing quarantine file returns operator-facing error' {
        InModuleScope Metra {
            $q = Get-MetraPlaceQuarantineRoot
            $id = 'dddddddddddddddddddddddddddddddd'
            [PSCustomObject]@{
                id       = $id
                fileName = 'gone.png'
                path     = (Join-Path $q "$id-gone.png")
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $q "$id.json") -Encoding UTF8
            $r = Resolve-MetraAskImages -ImageIds @($id)
            $r.ok | Should -BeFalse
            $r.error | Should -Match 'no longer available in Place quarantine'
        }
    }
}
