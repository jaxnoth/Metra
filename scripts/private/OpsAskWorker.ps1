# Ops Ask/Vision single-flight worker (BeginInvoke + SemaphoreSlim).
# Gate lives on the Ops listener runspace; workers Import-Module and own HttpListenerResponse.

if ($null -eq (Get-Variable -Name MetraOpsAskGate -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraOpsAskGate = [System.Threading.SemaphoreSlim]::new(1, 1)
}
if ($null -eq (Get-Variable -Name MetraOpsAskWorkerHandles -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraOpsAskWorkerHandles = [ordered]@{}
}
if ($null -eq (Get-Variable -Name MetraOpsAskWorkerSeq -Scope Script -ErrorAction SilentlyContinue)) {
    $script:MetraOpsAskWorkerSeq = 0
}

function Write-MetraOpsAskBusyResponse {
    <#
    .SYNOPSIS
        Stable 409 askBusy contract for concurrent Ask/Vision.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Response
    )

    Write-MetraOpsJsonResponse -Response $Response -StatusCode 409 -Object ([PSCustomObject]@{
            error   = 'askBusy'
            message = 'Another Ask or Vision request is already running.'
        })
}

function Sync-MetraOpsAskWorkerHandles {
    <#
    .SYNOPSIS
        EndInvoke + Dispose completed Ask workers; release the Ask gate when held.
        Call before creating a new worker and each accept-loop turn.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:MetraOpsAskWorkerHandles -or $script:MetraOpsAskWorkerHandles.Count -lt 1) {
        return
    }

    foreach ($jobId in @($script:MetraOpsAskWorkerHandles.Keys)) {
        $h = $script:MetraOpsAskWorkerHandles[$jobId]
        if (-not $h) {
            $script:MetraOpsAskWorkerHandles.Remove($jobId)
            continue
        }
        $ar = $h.AsyncResult
        if ($ar -and -not $ar.IsCompleted) { continue }

        $ps = $h.PowerShell
        if ($ps -and $ar) {
            try { $null = $ps.EndInvoke($ar) } catch {
                Write-Warning ("Ask worker EndInvoke failed ({0}): {1}" -f $jobId, $_.Exception.Message)
            }
        }
        if ($ps) {
            try { $ps.Dispose() } catch { }
        }
        if ([bool]$h.GateHeld) {
            try { $null = $script:MetraOpsAskGate.Release() } catch { }
            $h.GateHeld = $false
        }
        $script:MetraOpsAskWorkerHandles.Remove($jobId)
    }
}

function Clear-MetraOpsAskWorkerHandles {
    <#
    .SYNOPSIS
        Shutdown harvest: wait briefly for in-flight Ask workers, then force-dispose.
    #>
    [CmdletBinding()]
    param([int]$WaitMs = 5000)

    $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(0, $WaitMs))
    while ($script:MetraOpsAskWorkerHandles.Count -gt 0 -and [datetime]::UtcNow -lt $deadline) {
        Sync-MetraOpsAskWorkerHandles
        if ($script:MetraOpsAskWorkerHandles.Count -lt 1) { break }
        Start-Sleep -Milliseconds 100
    }
    foreach ($jobId in @($script:MetraOpsAskWorkerHandles.Keys)) {
        $h = $script:MetraOpsAskWorkerHandles[$jobId]
        $ps = $h.PowerShell
        $ar = $h.AsyncResult
        if ($ps -and $ar -and $ar.IsCompleted) {
            try { $null = $ps.EndInvoke($ar) } catch { }
        }
        if ($ps) {
            try { $ps.Dispose() } catch { }
        }
        if ($h.Response) {
            try { $h.Response.Close() } catch { }
        }
        if ([bool]$h.GateHeld) {
            try { $null = $script:MetraOpsAskGate.Release() } catch { }
        }
        $script:MetraOpsAskWorkerHandles.Remove($jobId)
    }
}

function Get-MetraOpsAskWorkerModulePath {
    [CmdletBinding()]
    param([string]$MetraRoot = (Get-MetraRoot))

    $psd1 = Join-Path $MetraRoot 'scripts\Metra.psd1'
    if (Test-Path -LiteralPath $psd1) { return $psd1 }
    return (Join-Path $MetraRoot 'scripts\Metra.psm1')
}

function Complete-MetraOpsAskHttpWork {
    <#
    .SYNOPSIS
        Runs desk or vision Ask work and writes the HTTP response (worker or sync).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Work,
        [Parameter(Mandatory)]$Response,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    $kind = [string](Get-MetraProp -Object $Work -Name 'kind' -Default '')
    if ($kind -eq 'vision') {
        $visionReq = Get-MetraProp -Object $Work -Name 'visionRequest' -Default $null
        if ($null -eq $visionReq) {
            $bodyObj = Get-MetraProp -Object $Work -Name 'body' -Default $null
            if ($null -eq $bodyObj) {
                Write-MetraOpsBadRequest -Response $Response -Message 'JSON body required'
                return
            }
            $visionReq = ConvertTo-MetraVisionAskRequest -Body $bodyObj
        }
        $deviceId = [string](Get-MetraProp -Object $Work -Name 'deviceId' -Default '')
        $visionResult = Invoke-MetraVisionAskHandler -Request $visionReq -MetraRoot $MetraRoot -DeviceId $deviceId
        $visionStatus = Get-MetraVisionAskHttpStatusCode -Envelope $visionResult
        Write-MetraOpsJsonResponse -Response $Response -StatusCode $visionStatus -Object $visionResult -Depth 12
        return
    }

    if ($kind -ne 'desk') {
        Write-MetraOpsJsonResponse -Response $Response -StatusCode 500 -Object ([PSCustomObject]@{
                error = "Unknown Ask work kind: $kind"
            })
        return
    }

    $prompt = [string](Get-MetraProp -Object $Work -Name 'prompt' -Default '')
    $sessionId = [string](Get-MetraProp -Object $Work -Name 'sessionId' -Default '')
    $recallSessionId = [string](Get-MetraProp -Object $Work -Name 'recallSessionId' -Default '')
    $imageIds = @((Get-MetraProp -Object $Work -Name 'imageIds' -Default @()) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $resolvedImages = @()
    $journalImages = @()
    if ($imageIds.Count -gt 0) {
        $resolved = Resolve-MetraAskImages -ImageIds $imageIds
        if (-not $resolved.ok) {
            Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = [string]$resolved.error })
            return
        }
        $resolvedImages = @($resolved.images)
        $journalImages = @($resolved.journal)
    }
    if ([string]::IsNullOrWhiteSpace($prompt) -and $resolvedImages.Count -gt 0) {
        $prompt = Get-MetraAskImageDefaultPrompt
    }
    $headerClient = [string](Get-MetraProp -Object $Work -Name 'headerClient' -Default '')
    $bodyClient = [string](Get-MetraProp -Object $Work -Name 'bodyClient' -Default '')
    $clientHint = [string](Get-MetraProp -Object $Work -Name 'clientHint' -Default '')
    $client = [string](Get-MetraProp -Object $Work -Name 'client' -Default '')
    $origin = [string](Get-MetraProp -Object $Work -Name 'origin' -Default '')
    $requestedPolicy = [string](Get-MetraProp -Object $Work -Name 'requestedPolicy' -Default '')
    $trustedClient = [bool](Get-MetraProp -Object $Work -Name 'trustedClient' -Default $false)
    $isLoopback = [bool](Get-MetraProp -Object $Work -Name 'isLoopback' -Default $false)

    try {
        $ask = Get-MetraDeskAskResult -Prompt $prompt -SessionId $sessionId -RecallSessionId $recallSessionId `
            -Images $resolvedImages -MetraRoot $MetraRoot `
            -HeaderClient $headerClient -BodyClient $bodyClient -ClientHint $clientHint `
            -RequestedPolicy $requestedPolicy `
            -TrustedClientContext:$trustedClient -IsLoopback:$isLoopback
    }
    catch {
        Write-MetraOpsJsonResponse -Response $Response -StatusCode 400 -Object ([PSCustomObject]@{ error = $_.Exception.Message })
        return
    }

    $journalSession = [string]$ask.sessionId
    if ([string]::IsNullOrWhiteSpace($journalSession)) { $journalSession = $sessionId }
    $journalPrompt = [string](Get-MetraProp -Object $ask -Name 'scrubbedPrompt' -Default '')
    if ([string]::IsNullOrWhiteSpace($journalPrompt)) {
        $secretsGate = [bool](Get-MetraProp -Object $ask -Name 'secretsRefuse' -Default $false) -or `
            [bool](Get-MetraProp -Object $ask -Name 'secretsScrubbed' -Default $false)
        if ($secretsGate) {
            $journalPrompt = ''
        }
        else {
            $journalPrompt = $prompt
        }
    }
    $askJournalImages = @(Get-MetraProp -Object $ask -Name 'images' -Default $journalImages)
    $entry = Add-MetraDeskAskEntry `
        -Prompt $journalPrompt `
        -Handoff $ask.handoff `
        -Message ([string]$ask.message) `
        -SessionId $journalSession `
        -Origin $origin `
        -Client $client `
        -ClientHint $clientHint `
        -Engine ([string]$ask.engine) `
        -Model ([string]$ask.model) `
        -Answered ([bool]$ask.answered) `
        -Capability $ask.capability `
        -Images $askJournalImages `
        -MetraRoot $MetraRoot
    $askLane = [string](Get-MetraProp -Object $ask -Name 'lane' -Default '')
    $askLaneReason = [string](Get-MetraProp -Object $ask -Name 'reason' -Default '')
    $showWhere = Test-MetraAskShowWhere -Handoff $ask.handoff -Lane $askLane -LaneReason $askLaneReason
    Write-MetraOpsJsonResponse -Response $Response -Object ([PSCustomObject]@{
            entry             = $entry
            handoff           = $ask.handoff
            message           = [string]$ask.message
            sessionId         = [string]$entry.sessionId
            capability        = $ask.capability
            engine            = $ask.engine
            model             = $ask.model
            answered          = [bool]$ask.answered
            answerType        = [string](Get-MetraProp -Object $ask -Name 'answerType' -Default '')
            evidenceQuality   = [string](Get-MetraProp -Object $ask -Name 'evidenceQuality' -Default '')
            nextStep          = [string](Get-MetraProp -Object $ask -Name 'nextStep' -Default '')
            showWhere         = [bool]$showWhere
            suggestCapture    = [bool](Get-MetraProp -Object $ask -Name 'suggestCapture' -Default $false)
            lane              = $askLane
            reason            = $askLaneReason
            responseObjective = [string](Get-MetraProp -Object $ask -Name 'responseObjective' -Default '')
            intentConfidence  = [double](Get-MetraProp -Object $ask -Name 'intentConfidence' -Default 0)
            routeScore        = [int](Get-MetraProp -Object $ask -Name 'routeScore' -Default 0)
            turnMode          = [string](Get-MetraProp -Object $ask -Name 'turnMode' -Default '')
            voice             = $(Get-MetraProp -Object $ask -Name 'voice' -Default $null)
            continuity        = $ask.continuity
            intentClass       = $(Get-MetraProp -Object $ask -Name 'intentClass' -Default $null)
            policy            = $(Get-MetraProp -Object $ask -Name 'policy' -Default $null)
            policySource      = $(Get-MetraProp -Object $ask -Name 'policySource' -Default $null)
            reasonCode        = $(Get-MetraProp -Object $ask -Name 'reasonCode' -Default $null)
            evidenceDepth     = $(Get-MetraProp -Object $ask -Name 'evidenceDepth' -Default $null)
            conversationExecutionEnabled = [bool](Get-MetraProp -Object $ask -Name 'conversationExecutionEnabled' -Default $false)
            secretsScrubbed   = [bool](Get-MetraProp -Object $ask -Name 'secretsScrubbed' -Default $false)
            secretsNotice     = $(Get-MetraProp -Object $ask -Name 'secretsNotice' -Default $null)
            secretsKinds      = @(Get-MetraProp -Object $ask -Name 'secretsKinds' -Default @())
            secretsReason     = $(Get-MetraProp -Object $ask -Name 'secretsReason' -Default $null)
            images            = @(Get-MetraProp -Object $entry -Name 'images' -Default @())
        }) -Depth 12
}

function Start-MetraOpsAskHttpWorker {
    <#
    .SYNOPSIS
        Single-flight Ask/Vision worker. Returns Busy=$true when gate not acquired.
        On Busy=$false / Started=$true, caller must not write or close Response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Work,
        [Parameter(Mandatory)]$Response,
        [string]$MetraRoot = (Get-MetraRoot)
    )

    Sync-MetraOpsAskWorkerHandles

    if (-not $script:MetraOpsAskGate.Wait(0)) {
        return [PSCustomObject]@{ Busy = $true; Started = $false; Error = $null }
    }

    $gateHeld = $true
    $ps = $null
    try {
        $modulePath = Get-MetraOpsAskWorkerModulePath -MetraRoot $MetraRoot
        # Serialize work for the child (images may include file paths / small metadata only).
        $workJson = ($Work | ConvertTo-Json -Depth 12 -Compress)
        $ps = [powershell]::Create()
        $null = $ps.AddScript({
                param($ModulePath, $Root, $WorkJson, $HttpResponse)
                Import-Module $ModulePath -Force
                try {
                    $workObj = $WorkJson | ConvertFrom-Json
                    Complete-MetraOpsAskHttpWork -Work $workObj -Response $HttpResponse -MetraRoot $Root
                }
                catch {
                    try {
                        Write-MetraOpsJsonResponse -Response $HttpResponse -StatusCode 500 -Object ([PSCustomObject]@{
                                error = $_.Exception.Message
                            })
                    }
                    catch { }
                }
            }).AddArgument($modulePath).AddArgument($MetraRoot).AddArgument($workJson).AddArgument($Response)

        $async = $ps.BeginInvoke()
        $script:MetraOpsAskWorkerSeq++
        $jobId = "ask-{0}" -f $script:MetraOpsAskWorkerSeq
        $script:MetraOpsAskWorkerHandles[$jobId] = @{
            PowerShell  = $ps
            AsyncResult = $async
            GateHeld    = $true
            Response    = $Response
            StartedAt   = [datetime]::UtcNow
        }
        $gateHeld = $false
        $ps = $null
        return [PSCustomObject]@{ Busy = $false; Started = $true; JobId = $jobId; Error = $null }
    }
    catch {
        if ($ps) { try { $ps.Dispose() } catch { } }
        if ($gateHeld) {
            try { $null = $script:MetraOpsAskGate.Release() } catch { }
        }
        return [PSCustomObject]@{
            Busy    = $false
            Started = $false
            Error   = $_.Exception.Message
        }
    }
}

function Test-MetraOpsAskGateAvailable {
    <#
    .SYNOPSIS
        Test helper: whether the Ask single-flight gate is free (CurrentCount -gt 0).
    #>
    [CmdletBinding()]
    param()

    Sync-MetraOpsAskWorkerHandles
    return ($script:MetraOpsAskGate.CurrentCount -gt 0)
}
