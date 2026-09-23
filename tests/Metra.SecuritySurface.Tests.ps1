BeforeAll {
    $metraRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $metraRoot 'scripts\Metra.psd1') -Force
}

Describe 'Security surface' {
    It 'audits tracked Metra tree with zero FAIL' {
        $r = Invoke-MetraSecuritySurfaceAudit -Root (Get-MetraRoot)
        $r.Ok | Should -BeTrue
        $r.FailCount | Should -Be 0
    }

    It 'keeps tracked selfdoc embeds shared-only' {
        $s = Test-MetraTrackedSelfDocSharedOnly -Root (Get-MetraRoot)
        $s.Ok | Should -BeTrue
    }

    It 'assembles deny patterns without embedding banned tokens in source' {
        $path = Join-Path (Get-MetraRoot) 'scripts\private\SecuritySurface.ps1'
        $text = [System.IO.File]::ReadAllText($path)
        $adNeedle = ('IW' + 'UNET') + [string][char]0x5C
        $vendNeedle = 'Pente' + 'gra'
        $dmNeedle = 'DM-' + 'Employee'
        $text.Contains($adNeedle) | Should -BeFalse
        $text.Contains($vendNeedle) | Should -BeFalse
        $text.Contains($dmNeedle) | Should -BeFalse
    }
}
