# Requires Pester 5+. Run via:
# pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Metra.OperatorWorkingNotes.Tests.ps1"

BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Operator working notes' {
    It 'skips expired Observed entries outside the 30-day decay window' {
        InModuleScope Metra {
            $asOf = [DateTime]::Parse('2026-11-12T12:00:00Z').ToUniversalTime()
            $fresh = [pscustomobject]@{
                pattern         = 'fresh pattern'
                lastObservedUtc = '2026-11-01T12:00:00Z'
                instanceCount   = 1
            }
            $stale = [pscustomobject]@{
                pattern         = 'stale pattern'
                lastObservedUtc = '2026-09-01T12:00:00Z'
                instanceCount   = 3
            }
            Test-MetraOperatorWorkingNotesObservedActive -Entry $fresh -AsOfUtc $asOf | Should -BeTrue
            Test-MetraOperatorWorkingNotesObservedActive -Entry $stale -AsOfUtc $asOf | Should -BeFalse

            $notes = [pscustomobject]@{
                version  = 1
                stated   = @()
                observed = @($fresh, $stale)
                moments  = @()
            }
            $active = @(Select-MetraOperatorWorkingNotesActiveObserved -Notes $notes -AsOfUtc $asOf)
            $active.Count | Should -Be 1
            $active[0].pattern | Should -Be 'fresh pattern'
        }
    }

    It 'reset-on-reobserve increments count and moves lastObservedUtc' {
        InModuleScope Metra {
            $t0 = [DateTime]::Parse('2026-10-01T12:00:00Z').ToUniversalTime()
            $t1 = [DateTime]::Parse('2026-11-10T12:00:00Z').ToUniversalTime()
            $notes = [pscustomobject]@{
                version  = 1
                stated   = @()
                observed = @(
                    [pscustomobject]@{
                        id               = 'o1'
                        pattern          = 'parks threads'
                        evidence         = 'first'
                        instanceCount    = 1
                        firstObservedUtc = $t0.ToString('o')
                        lastObservedUtc  = $t0.ToString('o')
                    }
                )
                moments  = @()
            }
            $updated = Update-MetraOperatorWorkingNotesObservation -Notes $notes -Pattern 'parks threads' -Evidence 'again' -AsOfUtc $t1
            $updated.observed.Count | Should -Be 1
            $updated.observed[0].instanceCount | Should -Be 2
            $updated.observed[0].lastObservedUtc | Should -Be $t1.ToString('o')
            $updated.observed[0].evidence | Should -Be 'again'
            Test-MetraOperatorWorkingNotesObservedActive -Entry $updated.observed[0] -AsOfUtc $t1 | Should -BeTrue
        }
    }

    It 'formats prompt under the hard context byte cap and omits expired Observed' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-cap'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $asOf = [DateTime]::Parse('2026-11-12T12:00:00Z').ToUniversalTime()
            $blob = ('x' * 800)
            $payload = [ordered]@{
                version    = 1
                updatedUtc = $asOf.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ("Stated " + $blob); source = 'operator'; notedUtc = $asOf.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ("More stated " + $blob); source = 'operator'; notedUtc = $asOf.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ("Even more " + $blob); source = 'operator'; notedUtc = $asOf.ToString('o') }
                )
                observed   = @(
                    @{
                        id              = ([guid]::NewGuid().ToString('N'))
                        pattern         = 'should not appear'
                        evidence        = 'old'
                        instanceCount   = 9
                        lastObservedUtc = '2026-08-01T00:00:00Z'
                        firstObservedUtc = '2026-08-01T00:00:00Z'
                    }
                    @{
                        id              = ([guid]::NewGuid().ToString('N'))
                        pattern         = 'active pattern'
                        evidence        = 'recent'
                        instanceCount   = 2
                        lastObservedUtc = '2026-11-11T00:00:00Z'
                        firstObservedUtc = '2026-11-11T00:00:00Z'
                    }
                )
                moments    = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ("Moment " + $blob); notedUtc = $asOf.ToString('o') }
                )
            }
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

            $cap = Get-MetraOperatorWorkingNotesContextCapBytes
            $text = Format-MetraOperatorWorkingNotesForPrompt -MetraRoot $root -CapBytes $cap -AsOfUtc $asOf
            $text | Should -Not -BeNullOrEmpty
            $text | Should -Not -Match 'should not appear'
            $text | Should -Match 'active pattern'
            $text | Should -Match 'Do not announce these notes unprompted'
            [System.Text.Encoding]::UTF8.GetByteCount($text) | Should -BeLessOrEqual $cap
        }
    }

    It 'profile file map includes machine-data working-notes leaf' {
        InModuleScope Metra {
            $map = @(Get-MetraProfileFileMap)
            $map | Should -Contain 'machine-data/operator-working-notes.local.json'
            $live = Resolve-MetraProfileMappedLivePath -RelativePath 'machine-data/operator-working-notes.local.json' -MetraRoot (Get-MetraRoot)
            $live | Should -Match 'operator-working-notes\.local\.json$'
            Test-MetraProfileMachineDataRelative -RelativePath 'machine-data/operator-working-notes.local.json' | Should -BeTrue
            Test-MetraProfileMachineDataRelative -RelativePath 'docs/operator-contract.json' | Should -BeFalse
        }
    }

    It 'context cap respects UTF-8 multi-byte character boundaries' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-utf8'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            # Hiragana 'a' (U+3042) is 3 UTF-8 bytes; fill so a naive byte slice would split one.
            $unit = [string]([char]0x3042)
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ('Note ' + ($unit * 900)); source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
            $cap = 200
            $text = Format-MetraOperatorWorkingNotesForPrompt -MetraRoot $root -CapBytes $cap
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
            $bytes.Length | Should -BeLessOrEqual $cap
            # Round-trip decode must not throw / produce replacement for a split codepoint mid-string body
            { [System.Text.Encoding]::UTF8.GetString($bytes) } | Should -Not -Throw
            $text | Should -Match 'working-notes truncated'
        }
    }

    It 'profile notes CLI can add stated and observe with decay reset' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-cli'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $add = Add-MetraOperatorWorkingNoteStated -Text 'Prefer terse verdicts' -MetraRoot $root
            $add.Kind | Should -Be 'stated'
            $obs1 = Add-MetraOperatorWorkingNoteObservation -Pattern 'parks threads' -Evidence 'first' -MetraRoot $root
            $obs1.InstanceCount | Should -Be 1
            $obs2 = Add-MetraOperatorWorkingNoteObservation -Pattern 'parks threads' -Evidence 'again' -MetraRoot $root
            $obs2.InstanceCount | Should -Be 2
            $show = Invoke-MetraOperatorWorkingNotesCommand -Subcommand show -MetraRoot $root
            $show.StatedCount | Should -Be 1
            $show.ObservedActive | Should -Be 1
        }
    }

    It 'reset -WhatIf previews without throwing when ledger exists' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-reset-whatif'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Add-MetraOperatorWorkingNoteStated -Text 'keep me until force' -MetraRoot $root | Out-Null
            $preview = Reset-MetraOperatorWorkingNotes -MetraRoot $root -WhatIf
            $preview.WhatIf | Should -BeTrue
            $preview.Reset | Should -BeFalse
            $preview.Exists | Should -BeTrue
            $preview.RequiresForce | Should -BeTrue
            $preview.Message | Should -Match 'needs -Force'
            { Reset-MetraOperatorWorkingNotes -MetraRoot $root } | Should -Throw -ExpectedMessage '*-Force*'
            $still = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $still.stated.Count | Should -Be 1
        }
    }

    It 'blank ledger rows flag corrupt and refuse writes instead of silent drop' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-blank-row'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'good note'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = '   '; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); pattern = ''; evidence = 'oops'; instanceCount = 1; lastObservedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerCorrupt | Should -BeTrue
            $notes.DroppedRowCount | Should -Be 2
            $notes.stated.Count | Should -Be 1
            $notes.stated[0].text | Should -Be 'good note'

            { Add-MetraOperatorWorkingNoteStated -Text 'another' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*blank/unusable*'

            $onDisk = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            @($onDisk.stated).Count | Should -Be 2
            $onDisk.stated[1].text | Should -Be '   '

            { ConvertFrom-MetraOperatorWorkingNotesRawForPack -Raw $onDisk } |
                Should -Throw -ExpectedMessage '*blank/unusable*'
            $healed = ConvertFrom-MetraOperatorWorkingNotesRawForPack -Raw $onDisk -AllowDroppedRows
            $healed.DroppedRowCount | Should -BeGreaterOrEqual 1
            @($healed.Notes.stated).Count | Should -Be 1
        }
    }

    It 'profile status contentHash uses scrubbed working-notes pack text' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-status-hash'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Add-MetraOperatorWorkingNoteStated -Text 'Prefer terse verdicts' -MetraRoot $root | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $parsed = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $pack = ConvertFrom-MetraOperatorWorkingNotesRawForPack -Raw $parsed
            $packBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$pack.Text)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $hex = ($sha.ComputeHash($packBytes) | ForEach-Object { $_.ToString('x2') }) -join ''
            }
            finally {
                $sha.Dispose()
            }

            $status = Get-MetraProfileStatus -MetraRoot $root
            $status.ok | Should -BeTrue
            $rel = (Get-MetraOperatorWorkingNotesPackRelativePath) -replace '\\', '/'
            $row = @($status.files) | Where-Object { $_.relativePath -eq $rel } | Select-Object -First 1
            $row | Should -Not -BeNullOrEmpty
            $row.hash | Should -Be ("sha256:{0}" -f $hex)
        }
    }

    It 'add/observe/moment -WhatIf previews without writing' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-whatif-write'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $preview = Add-MetraOperatorWorkingNoteStated -Text 'would add' -MetraRoot $root -WhatIf
            $preview.WhatIf | Should -BeTrue
            $preview.Wrote | Should -BeFalse
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerExists | Should -BeFalse

            Add-MetraOperatorWorkingNoteStated -Text 'seed' -MetraRoot $root | Out-Null
            $obs = Add-MetraOperatorWorkingNoteObservation -Pattern 'parks threads' -Evidence 'x' -MetraRoot $root -WhatIf
            $obs.WhatIf | Should -BeTrue
            $obs.Wrote | Should -BeFalse
            $after = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $after.observed.Count | Should -Be 0
            $after.stated.Count | Should -Be 1

            $cli = Invoke-MetraOperatorWorkingNotesCommand -Subcommand add -ArgsRest @('stated', 'via cli', '-WhatIf') -MetraRoot $root
            $cli.WhatIf | Should -BeTrue
            $cli.Wrote | Should -BeFalse
            (Read-MetraOperatorWorkingNotes -MetraRoot $root).stated.Count | Should -Be 1
        }
    }

    It 'invalid id or timestamp rows flag corrupt (not silently kept)' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-bad-id'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = 'not-a-guid'; text = 'bad id'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'bad stamp'; source = 'operator'; notedUtc = 'yesterday-ish' }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'good'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerCorrupt | Should -BeTrue
            $notes.DroppedRowCount | Should -Be 2
            $notes.stated.Count | Should -Be 1
            $notes.stated[0].text | Should -Be 'good'
        }
    }

    It 'observe -Evidence -WhatIf throws Missing value and does not write' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-evidence-whatif'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Add-MetraOperatorWorkingNoteStated -Text 'seed' -MetraRoot $root | Out-Null
            { Invoke-MetraOperatorWorkingNotesCommand -Subcommand observe -ArgsRest @('x', '-Evidence', '-WhatIf') -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*Missing value for -Evidence*'
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            @($notes.observed).Count | Should -Be 0
            $notes.LedgerCorrupt | Should -BeFalse
        }
    }

    It 'blank or invalid root updatedUtc marks ledger corrupt; Format empty; add refuses' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-root-stamp'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $payload = [ordered]@{
                version    = 1
                updatedUtc = ''
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'ok'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerCorrupt | Should -BeTrue
            $notes.UpdatedUtcOk | Should -BeFalse
            Format-MetraOperatorWorkingNotesForPrompt -MetraRoot $root | Should -BeNullOrEmpty
            { Add-MetraOperatorWorkingNoteStated -Text 'nope' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*corrupt*'
        }
    }

    It 'unsupported schema version marks ledger corrupt and refuses writes' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-schema-ver'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            foreach ($ver in @(0, 2)) {
                $payload = [ordered]@{
                    version    = $ver
                    updatedUtc = [DateTime]::UtcNow.ToString('o')
                    stated     = @(
                        @{ id = ([guid]::NewGuid().ToString('N')); text = "v$ver"; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                    )
                    observed   = @()
                    moments    = @()
                }
                ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
                $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
                $notes.LedgerCorrupt | Should -BeTrue
                $notes.SchemaVersionOk | Should -BeFalse
                { Add-MetraOperatorWorkingNoteStated -Text 'nope' -MetraRoot $root } |
                    Should -Throw -ExpectedMessage '*corrupt*'
            }
        }
    }

    It 'Save-MetraOperatorWorkingNotes is not exported from the module' {
        $cmd = Get-Command Save-MetraOperatorWorkingNotes -Module Metra -ErrorAction SilentlyContinue
        $cmd | Should -BeNullOrEmpty
        InModuleScope Metra {
            Get-Command Save-MetraOperatorWorkingNotes -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'profile status returns null contentHash when working-notes are unexportable' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-status-null-hash'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'ok'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ''; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8
            $status = Get-MetraProfileStatus -MetraRoot $root
            $status.ok | Should -BeFalse
            $status.notesPackError | Should -Match 'blank/unusable'
            $status.contentHash | Should -BeNullOrEmpty
            # Ops /api/profile/status path: roster must accept null hash (B6).
            { Get-MetraProfileSatelliteRoster -PublisherHash $status.contentHash } | Should -Not -Throw
            $roster = Get-MetraProfileSatelliteRoster -PublisherHash $status.contentHash
            $roster.PublisherUnexportable | Should -BeTrue
        }
    }

    It 'blank notedUtc or lastObservedUtc marks ledger corrupt and refuses add' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-blank-stamp'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $goodId = [guid]::NewGuid().ToString('N')
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'missing stamp'; source = 'operator'; notedUtc = '' }
                    @{ id = $goodId; text = 'kept'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @(
                    @{
                        id               = ([guid]::NewGuid().ToString('N'))
                        pattern          = 'blank lastObserved'
                        evidence         = 'x'
                        instanceCount    = 1
                        lastObservedUtc  = ''
                        firstObservedUtc = [DateTime]::UtcNow.ToString('o')
                    }
                )
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerCorrupt | Should -BeTrue
            $notes.DroppedRowCount | Should -Be 2
            @($notes.stated).Count | Should -Be 1
            $notes.stated[0].text | Should -Be 'kept'
            @($notes.observed).Count | Should -Be 0

            { Add-MetraOperatorWorkingNoteStated -Text 'another' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*blank/unusable*'
            { Add-MetraOperatorWorkingNoteObservation -Pattern 'new pattern' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*blank/unusable*'
        }
    }

    It 'stated refuses past row cap; moments drop oldest' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-row-cap'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $max = Get-MetraOperatorWorkingNotesMaxRowsPerList
            $max | Should -Be 50
            # Seed stated to cap via direct save (fast), then refuse another add.
            $stated = @()
            for ($i = 0; $i -lt $max; $i++) {
                $stated += [pscustomobject]@{
                    id       = [guid]::NewGuid().ToString('N')
                    text     = "stated-$i"
                    source   = 'operator'
                    notedUtc = ([DateTime]::UtcNow.AddMinutes(-$i)).ToString('o')
                }
            }
            $seed = [pscustomobject]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = $stated
                observed   = @()
                moments    = @()
            }
            Save-MetraOperatorWorkingNotes -Notes $seed -MetraRoot $root -Force | Out-Null
            { Add-MetraOperatorWorkingNoteStated -Text 'one more' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*cap*'

            $moments = @()
            for ($i = 0; $i -lt $max; $i++) {
                $moments += [pscustomobject]@{
                    id       = [guid]::NewGuid().ToString('N')
                    text     = "moment-$i"
                    notedUtc = ([DateTime]::UtcNow.AddMinutes(-($max - $i))).ToString('o')
                }
            }
            $seed2 = [pscustomobject]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @()
                observed   = @()
                moments    = $moments
            }
            Save-MetraOperatorWorkingNotes -Notes $seed2 -MetraRoot $root -Force | Out-Null
            Add-MetraOperatorWorkingNoteMoment -Text 'newest' -MetraRoot $root | Out-Null
            $after = Read-MetraOperatorWorkingNotes -MetraRoot $root
            @($after.moments).Count | Should -Be $max
            @($after.moments | Where-Object { $_.text -eq 'newest' }).Count | Should -Be 1
            @($after.moments | Where-Object { $_.text -eq 'moment-0' }).Count | Should -Be 0
        }
    }

    It 'blank stated/moment add throws and does not corrupt the ledger' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-blank-add'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Add-MetraOperatorWorkingNoteStated -Text 'seed' -MetraRoot $root | Out-Null
            { Add-MetraOperatorWorkingNoteStated -Text '   ' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*blank/whitespace*'
            { Add-MetraOperatorWorkingNoteMoment -Text '' -MetraRoot $root } |
                Should -Throw -ExpectedMessage '*blank/whitespace*'
            $notes = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $notes.LedgerCorrupt | Should -BeFalse
            $notes.stated.Count | Should -Be 1
            $notes.moments.Count | Should -Be 0
        }
    }

    It 'profile status omits unexportable working-notes from contentHash' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-status-corrupt'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            $path = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $payload = [ordered]@{
                version    = 1
                updatedUtc = [DateTime]::UtcNow.ToString('o')
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'ok'; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                    @{ id = ([guid]::NewGuid().ToString('N')); text = ''; source = 'operator'; notedUtc = [DateTime]::UtcNow.ToString('o') }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path -Encoding utf8

            $status = Get-MetraProfileStatus -MetraRoot $root
            $status.ok | Should -BeFalse
            $status.notesPackError | Should -Match 'blank/unusable'
            $status.contentHash | Should -BeNullOrEmpty
            $rel = (Get-MetraOperatorWorkingNotesPackRelativePath) -replace '\\', '/'
            @($status.files | Where-Object { $_.relativePath -eq $rel }).Count | Should -Be 0
        }
    }

    It 'import requires -Force when only a legacy docs working-notes ledger exists' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-import-legacy'
            $packDir = Join-Path $TestDrive 'wn-import-legacy-pack'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $packDir 'machine-data') -Force | Out-Null
            $legacy = Join-Path $root 'docs\operator-working-notes.local.json'
            $asOf = [DateTime]::UtcNow.ToString('o')
            $livePayload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'legacy live'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            ($livePayload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $legacy -Encoding utf8
            $packPayload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'from pack'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            $packNotes = Join-Path $packDir 'machine-data\operator-working-notes.local.json'
            ($packPayload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $packNotes -Encoding utf8

            { Import-MetraProfile -Path $packDir -MetraRoot $root -Quiet } |
                Should -Throw -ExpectedMessage '*without -Force*'
            Test-Path -LiteralPath $legacy | Should -BeTrue
            (Get-Content -LiteralPath $legacy -Raw) | Should -Match 'legacy live'

            $null = Import-MetraProfile -Path $packDir -MetraRoot $root -Force -Quiet
            $docsLeftover = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter 'operator-working-notes.local.json*' -File -ErrorAction SilentlyContinue)
            $docsLeftover.Count | Should -Be 0
            $bakRoot = Join-Path (Get-MetraMachineDataRoot -MetraRoot $root) 'backups'
            $baks = @(Get-ChildItem -LiteralPath $bakRoot -Filter 'operator-working-notes.local.json*.bak-*' -File)
            $baks.Count | Should -BeGreaterOrEqual 1
            ($baks | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n" | Should -Match 'legacy live'
            $after = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $after.stated[0].text | Should -Be 'from pack'
        }
    }

    It 'import Force backs up machine-data working-notes before overwrite' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-import-machine'
            $packDir = Join-Path $TestDrive 'wn-import-machine-pack'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $packDir 'machine-data') -Force | Out-Null
            $live = Get-MetraOperatorWorkingNotesPath -MetraRoot $root
            $dir = Split-Path -Parent $live
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            $asOf = [DateTime]::UtcNow.ToString('o')
            $livePayload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'machine live'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            ($livePayload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $live -Encoding utf8
            $packPayload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'pack overwrite'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            $packNotes = Join-Path $packDir 'machine-data\operator-working-notes.local.json'
            ($packPayload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $packNotes -Encoding utf8

            $null = Import-MetraProfile -Path $packDir -MetraRoot $root -Force -Quiet
            $bakRoot = Join-Path (Get-MetraMachineDataRoot -MetraRoot $root) 'backups'
            $baks = @(Get-ChildItem -LiteralPath $bakRoot -Filter 'operator-working-notes.local.json.bak-*' -File)
            $baks.Count | Should -BeGreaterOrEqual 1
            (Get-Content -LiteralPath $baks[0].FullName -Raw) | Should -Match 'machine live'
            $after = Read-MetraOperatorWorkingNotes -MetraRoot $root
            $after.stated[0].text | Should -Be 'pack overwrite'
        }
    }

    It 'gitignore covers docs working-notes bak spill (defense in depth)' {
        $gi = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) '.gitignore') -Raw
        $gi | Should -Match '(?m)^docs/operator-working-notes\.local\.json\.bak-\*\s*$'
    }

    It 'export WhatIf does not migrate a docs-only working-notes ledger' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-export-whatif'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            $legacy = Join-Path $root 'docs\operator-working-notes.local.json'
            $asOf = [DateTime]::UtcNow.ToString('o')
            $payload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'legacy only'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $legacy -Encoding utf8
            # Seed a mapped non-notes file so export has something besides notes.
            '{"schemaVersion":1,"guidelines":[]}' | Set-Content -LiteralPath (Join-Path $root 'docs\operator-contract.json') -Encoding utf8

            $dest = Join-Path $TestDrive 'wn-export-whatif-out.zip'
            Mock Get-MetraRoot { $root }
            $result = Export-MetraProfile -Path $dest -WhatIf
            $result.WhatIf | Should -BeTrue
            Test-Path -LiteralPath $legacy | Should -BeTrue
            $machine = Resolve-MetraProfileMappedLivePath -RelativePath 'machine-data/operator-working-notes.local.json' -MetraRoot $root
            Test-Path -LiteralPath $machine | Should -BeFalse
            (Get-Content -LiteralPath $legacy -Raw) | Should -Match 'legacy only'
        }
    }

    It 'profile status hashes a docs-only working-notes ledger without migrating' {
        InModuleScope Metra {
            $root = Join-Path $TestDrive 'wn-status-legacy'
            New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
            $legacy = Join-Path $root 'docs\operator-working-notes.local.json'
            $asOf = [DateTime]::UtcNow.ToString('o')
            $payload = [ordered]@{
                version    = 1
                updatedUtc = $asOf
                stated     = @(
                    @{ id = ([guid]::NewGuid().ToString('N')); text = 'status legacy'; source = 'operator'; notedUtc = $asOf }
                )
                observed   = @()
                moments    = @()
            }
            ($payload | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $legacy -Encoding utf8
            '{"schemaVersion":1,"guidelines":[]}' | Set-Content -LiteralPath (Join-Path $root 'docs\operator-contract.json') -Encoding utf8

            $status = Get-MetraProfileStatus -MetraRoot $root
            $status.ok | Should -BeTrue
            $status.contentHash | Should -Match '^sha256:'
            Test-Path -LiteralPath $legacy | Should -BeTrue
            $machine = Resolve-MetraProfileMappedLivePath -RelativePath 'machine-data/operator-working-notes.local.json' -MetraRoot $root
            Test-Path -LiteralPath $machine | Should -BeFalse
        }
    }
}

Describe 'Profile Ops notesPackError sanitization' {
    It 'export 409 keeps notesPackError local-only and status sanitizes for non-local' {
        $ops = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\private\OpsServer.ps1') -Raw
        $ops | Should -Match 'notesPackReasonCode'
        $ops | Should -Match 'Profile pack is not exportable \(working-notes or status gate\)\.'
        $ops | Should -Match 'Profile export 409 notesPackError \(server log only\)'
        $ops | Should -Match 'Profile status notesPackError \(server log only\)'
        $ops | Should -Match "payload\['notesPackError'\]"
        # 409 detail gate is local-authority only (device/bearer get reasonCode without raw error).
        $idx = $ops.IndexOf("`$path -eq '/api/profile/export'")
        $idx | Should -BeGreaterThan 0
        $exportSlice = $ops.Substring($idx, [Math]::Min(4500, $ops.Length - $idx))
        $exportSlice | Should -Match 'Test-MetraOpsRequestHasLocalAuthority'
        $exportSlice | Should -Match 'profilePackUnexportable'
    }

    It 'profile status/export 500 sanitize exception detail for non-local callers' {
        $ops = Get-Content -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\private\OpsServer.ps1') -Raw
        $ops | Should -Match 'Profile status 500 \(server log only\)'
        $ops | Should -Match 'Profile export 500 \(server log only\)'
        $ops | Should -Match "error\s*=\s*'Profile status failed\.'"
        $ops | Should -Match "error\s*=\s*'Profile export failed\.'"
        $ops | Should -Match "reasonCode\s*=\s*'profileStatusFailed'"
        $ops | Should -Match "reasonCode\s*=\s*'profileExportFailed'"
    }
}

Describe 'Desk familiarity retirement' {
    It 'profile familiarity throws a clear retired error' {
        InModuleScope Metra {
            { Invoke-MetraDeskFamiliarityCommand -Subcommand show } | Should -Throw -ExpectedMessage '*retired*'
        }
    }
}
