# Metra Profile Sync v1 tests (HQ-published, satellite-pulled)

Describe 'Metra Profile Sync' {
    BeforeAll {
        $module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
        Import-Module $module -Force
    }

    It 'file map excludes secrets and ticket caches' {
        $map = @(Get-MetraProfileFileMap)
        ($map -join '|') | Should -Not -Match '(?i)secret|ticket|cache|credential|\.env'
        $map | Should -Contain 'docs/operator-contract.json'
        $map | Should -Contain '.cursor/rules/metra-persona.local.mdc'
    }

    It 'Get-MetraProfileStatus returns contentHash and profilePackVersion' {
        $status = Get-MetraProfileStatus
        $status.ok | Should -BeTrue
        $status.profilePackVersion | Should -Be 1
        $status.contentHash | Should -Match '^sha256:[a-f0-9]{64}$'
        $status.fileCount | Should -BeGreaterOrEqual 0
    }

    It 'contentHash is stable when files are unchanged' {
        $a = Get-MetraProfileStatus
        $b = Get-MetraProfileStatus
        $a.contentHash | Should -Be $b.contentHash
    }

    It 'contentHash changes when mapped profile content changes' {
        $root = Get-MetraRoot
        $probeRel = 'docs/operator-contract.json'
        $probe = Join-Path $root ($probeRel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $created = $false
        $backup = $null
        if (Test-Path -LiteralPath $probe) {
            $backup = Get-Content -LiteralPath $probe -Raw -Encoding UTF8
        }
        else {
            $created = $true
            $dir = Split-Path -Parent $probe
            if (-not (Test-Path -LiteralPath $dir)) {
                $null = New-Item -ItemType Directory -Path $dir -Force
            }
            '{"schemaVersion":1,"guidelines":[]}' | Set-Content -Path $probe -Encoding utf8
        }

        try {
            $before = Get-MetraProfileStatus
            Add-Content -LiteralPath $probe -Value "`n# metra-profile-sync-test $($([guid]::NewGuid().ToString('N')))" -Encoding utf8
            $after = Get-MetraProfileStatus
            $after.contentHash | Should -Not -Be $before.contentHash
        }
        finally {
            if ($created -and (Test-Path -LiteralPath $probe)) {
                Remove-Item -LiteralPath $probe -Force
            }
            elseif ($null -ne $backup) {
                Set-Content -LiteralPath $probe -Value $backup -Encoding utf8 -NoNewline
            }
        }
    }

    It 'Export-MetraProfile manifest includes contentHash and profilePackVersion' {
        $zip = Join-Path $env:TEMP ("metra-profile-sync-test-" + [guid]::NewGuid().ToString('N') + '.zip')
        try {
            $null = Export-MetraProfile -Path $zip
            Test-Path -LiteralPath $zip | Should -BeTrue
            $tmp = Join-Path $env:TEMP ("metra-profile-sync-unpack-" + [guid]::NewGuid().ToString('N'))
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
            $manifestPath = Get-ChildItem -LiteralPath $tmp -Filter 'metra-profile.json' -Recurse -File |
                Select-Object -First 1 -ExpandProperty FullName
            $manifestPath | Should -Not -BeNullOrEmpty
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.profilePackVersion | Should -Be 1
            $manifest.contentHash | Should -Match '^sha256:'
            @($manifest.files).Count | Should -BeGreaterThan 0
            $first = @($manifest.files)[0]
            $first.relativePath | Should -Not -BeNullOrEmpty
            $first.hash | Should -Match '^sha256:'
        }
        finally {
            if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
            Get-ChildItem -LiteralPath $env:TEMP -Filter 'metra-profile-sync-unpack-*' -Directory -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'profile sync token issue and verify' {
        $dataDir = Join-Path $env:TEMP ("metra-profile-sync-auth-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $dataDir -Force
        try {
            $issued = Initialize-MetraProfileSyncToken -Rotate -DataDir $dataDir
            $issued.Created | Should -BeTrue
            $issued.Token | Should -Not -BeNullOrEmpty
            Test-MetraProfileSyncToken -SyncToken $issued.Token -DataDir $dataDir | Should -BeTrue
            Test-MetraProfileSyncToken -SyncToken 'deadbeef' -DataDir $dataDir | Should -BeFalse
            Test-MetraProfileSyncToken -SyncToken '' -DataDir $dataDir | Should -BeFalse
        }
        finally {
            Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Sync-MetraProfile -WhatIf does not write lastAppliedHash' {
        $root = Get-MetraRoot
        $statePath = Join-Path $root 'docs\profile-sync.local.json'
        $backup = $null
        if (Test-Path -LiteralPath $statePath) {
            $backup = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        }

        $status = Get-MetraProfileStatus
        $remoteHash = 'sha256:' + ('a' * 64)
        if ($remoteHash -eq $status.contentHash) {
            $remoteHash = 'sha256:' + ('b' * 64)
        }
        $remote = [PSCustomObject]@{
            ok                 = $true
            profilePackVersion = 1
            contentHash        = $remoteHash
            maxWriteUtc        = [DateTime]::UtcNow.ToString('o')
            fileCount          = $status.fileCount
            files              = @()
        }

        try {
            $state = [ordered]@{
                lastAppliedHash = $status.contentHash
                lastSyncUtc     = [DateTime]::UtcNow.ToString('o')
                syncToken       = 'unit-test-token'
            }
            ($state | ConvertTo-Json) | Set-Content -Path $statePath -Encoding utf8
            $before = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
            $result = Sync-MetraProfile -WhatIf -RemoteStatus $remote -Quiet
            $result.WhatIf | Should -BeTrue
            $result.Imported | Should -BeFalse
            $result.AlreadyCurrent | Should -BeFalse
            $after = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
            $after | Should -Be $before
        }
        finally {
            if ($null -ne $backup) {
                Set-Content -LiteralPath $statePath -Value $backup -Encoding utf8 -NoNewline
            }
            elseif (Test-Path -LiteralPath $statePath) {
                Remove-Item -LiteralPath $statePath -Force
            }
        }
    }

    It 'Sync-MetraProfile no-ops when lastAppliedHash matches' {
        $root = Get-MetraRoot
        $statePath = Join-Path $root 'docs\profile-sync.local.json'
        $backup = $null
        if (Test-Path -LiteralPath $statePath) {
            $backup = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
        }

        $status = Get-MetraProfileStatus
        try {
            $state = [ordered]@{
                lastAppliedHash = $status.contentHash
                lastSyncUtc     = [DateTime]::UtcNow.ToString('o')
                syncToken       = 'unit-test-token'
            }
            ($state | ConvertTo-Json) | Set-Content -Path $statePath -Encoding utf8
            $before = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
            $result = Sync-MetraProfile -RemoteStatus $status -Quiet
            $result.AlreadyCurrent | Should -BeTrue
            $result.Imported | Should -BeFalse
            $after = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
            $after | Should -Be $before
        }
        finally {
            if ($null -ne $backup) {
                Set-Content -LiteralPath $statePath -Value $backup -Encoding utf8 -NoNewline
            }
            elseif (Test-Path -LiteralPath $statePath) {
                Remove-Item -LiteralPath $statePath -Force
            }
        }
    }
}
