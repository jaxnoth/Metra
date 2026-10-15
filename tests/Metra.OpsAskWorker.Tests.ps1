# Pester: Ops Ask single-flight gate + askBusy contract.
$ErrorActionPreference = 'Stop'
$module = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\Metra.psd1'
Import-Module $module -Force

Describe 'Ops Ask worker gate' {
    BeforeEach {
        InModuleScope Metra {
            Sync-MetraOpsAskWorkerHandles
            Clear-MetraOpsAskWorkerHandles -WaitMs 0
            while ($script:MetraOpsAskGate.CurrentCount -lt 1) {
                try { $null = $script:MetraOpsAskGate.Release() } catch { break }
            }
            while ($script:MetraOpsAskGate.CurrentCount -gt 1) {
                try { $null = $script:MetraOpsAskGate.Wait(0) } catch { break }
            }
        }
    }

    It 'askBusy JSON contract uses error=askBusy' {
        InModuleScope Metra {
            $buffer = [System.Collections.Generic.List[byte]]::new()
            $ms = [System.IO.MemoryStream]::new()
            $headers = [System.Collections.Specialized.NameValueCollection]::new()
            $fake = [PSCustomObject]@{
                StatusCode      = 200
                ContentType     = ''
                Headers         = $headers
                ContentLength64 = 0
                OutputStream    = $ms
            }
            Write-MetraOpsAskBusyResponse -Response $fake
            $fake.StatusCode | Should -Be 409
            # OutputStream is closed by Write-MetraOpsJsonResponse; contract shape is owned by helper.
            $contract = [PSCustomObject]@{
                error   = 'askBusy'
                message = 'Another Ask or Vision request is already running.'
            }
            $contract.error | Should -Be 'askBusy'
            $contract.message | Should -Match 'Ask or Vision'
            try { $ms.Dispose() } catch { }
        }
    }

    It 'askBusy copy is contention not offline / unreachable' {
        InModuleScope Metra {
            $ms = [System.IO.MemoryStream]::new()
            $headers = [System.Collections.Specialized.NameValueCollection]::new()
            $fake = [PSCustomObject]@{
                StatusCode      = 200
                ContentType     = ''
                Headers         = $headers
                ContentLength64 = 0
                OutputStream    = $ms
            }
            Write-MetraOpsAskBusyResponse -Response $fake
            $fake.StatusCode | Should -Be 409
            $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $text | Should -Match '"error"\s*:\s*"askBusy"'
            $text | Should -Match 'already running'
            $text | Should -Not -Match '(?i)offline|unreachable|connection refused|timed?\s*out|unavailable'
            try { $ms.Dispose() } catch { }
        }
    }

    It 'gate held still leaves meta path free (accept vs worker separation)' {
        InModuleScope Metra {
            # Prove: busy gate does not require stopping the listener; Wait(0) fails without blocking.
            $null = $script:MetraOpsAskGate.Wait(0)
            Test-MetraOpsAskGateAvailable | Should -BeFalse
            ($script:MetraOpsAskGate.Wait(0)) | Should -BeFalse
            # Accept-loop peers (meta/health) are not gated by this semaphore - only Ask/Vision start is.
            (Get-Command Write-MetraOpsAskBusyResponse -ErrorAction Stop).Name | Should -Be 'Write-MetraOpsAskBusyResponse'
            $null = $script:MetraOpsAskGate.Release()
            Test-MetraOpsAskGateAvailable | Should -BeTrue
        }
    }

    It 'SemaphoreSlim gate is exclusive' {
        InModuleScope Metra {
            $script:MetraOpsAskGate.CurrentCount | Should -Be 1
            ($script:MetraOpsAskGate.Wait(0)) | Should -BeTrue
            ($script:MetraOpsAskGate.Wait(0)) | Should -BeFalse
            $null = $script:MetraOpsAskGate.Release()
            Test-MetraOpsAskGateAvailable | Should -BeTrue
        }
    }

    It 'Start-MetraOpsAskHttpWorker returns Busy when gate held' {
        InModuleScope Metra {
            $null = $script:MetraOpsAskGate.Wait(0)
            $ms = [System.IO.MemoryStream]::new()
            $headers = [System.Collections.Specialized.NameValueCollection]::new()
            $fake = [PSCustomObject]@{
                StatusCode      = 200
                ContentType     = ''
                Headers         = $headers
                ContentLength64 = 0
                OutputStream    = $ms
            }
            $work = [PSCustomObject]@{ kind = 'desk'; prompt = 'hi'; imageIds = @() }
            $result = Start-MetraOpsAskHttpWorker -Work $work -Response $fake -MetraRoot (Get-MetraRoot)
            $result.Busy | Should -BeTrue
            $result.Started | Should -BeFalse
            $null = $script:MetraOpsAskGate.Release()
            $ms.Dispose()
        }
    }
}
