# beforeShellExecution: ask before git push (public push security policy).
# Hard block remains scripts/githooks/pre-push after inspect hooks install.
$ErrorActionPreference = 'Stop'
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Output '{"permission":"allow"}'
    exit 0
}
try {
    $evt = $raw | ConvertFrom-Json
}
catch {
    Write-Output '{"permission":"allow"}'
    exit 0
}

$cmd = ''
if ($evt.PSObject.Properties['command']) {
    $cmd = [string]$evt.command
}
if ($cmd -notmatch '(?i)\bgit(\.exe)?\s+push\b') {
    Write-Output '{"permission":"allow"}'
    exit 0
}
if ($env:METRA_SKIP_SECURITY_PUSH -eq '1') {
    Write-Output '{"permission":"allow"}'
    exit 0
}

$msg = 'Public push security: run .\metra.ps1 security-audit -Force before push; ship bites also need identifying-info security review (docs/playbooks/public-push-security.md). Git pre-push blocks FAIL after inspect hooks install.'
$payload = [ordered]@{
    permission   = 'ask'
    user_message = $msg
    agent_message = $msg
}
$payload | ConvertTo-Json -Compress
exit 0
