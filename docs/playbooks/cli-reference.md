---
metraMemory: procedural
defaultContext: false
loadWhen:
  - metra.ps1
  - cli commands
  - setup
  - workspace
  - profile
  - azdo
ceiling:
  - Prefer routing/ctx over ad-hoc portfolio search
---

> Moved from `AGENTS.md` during A2 desk split. Preserve A1 done-when / On hard stop content unless intentionally revised.

# Metra CLI reference

Entry: `.\metra.ps1`. Inspect detail: [inspect-loop.md](inspect-loop.md).

```powershell
.\metra.ps1 setup
.\metra.ps1 setup -Profile .\profiles\sample -Force
.\metra.ps1 list
.\metra.ps1 list -Root personal
.\metra.ps1 roots
.\metra.ps1 routing
.\metra.ps1 routing -MissingOnly
.\metra.ps1 ctx
.\metra.ps1 ctx -Query "ticket disk"
.\metra.ps1 audit
.\metra.ps1 audit -Name Solarwinds,TicketTracker,Trivia
.\metra.ps1 audit -DriftOnly
.\metra.ps1 selfdoc
.\metra.ps1 workspace
.\metra.ps1 chats -Name Solarwinds -Query "disk alert"
.\metra.ps1 import-profile -Path .\profiles\sample -Preview
.\metra.ps1 import-profile -Path .\profiles\addons\humor-desk -Preview
.\metra.ps1 import-profile -Path .\profiles\addons\teaching-gentle -Preview
.\metra.ps1 export-profile -Path $env:TEMP\my-metra-profile.zip
.\metra.ps1 profile show
.\metra.ps1 profile note "Prefer terse verdicts before detail."
.\metra.ps1 profile promote "Prefer terse verdicts before detail."
.\metra.ps1 decisions search "datamanager"
.\metra.ps1 decisions harvest -Preview
.\metra.ps1 decisions review
.\metra.ps1 ask sessions
.\metra.ps1 ask get <sessionId>
.\metra.ps1 ask recall "gateway msal"
.\metra.ps1 capture list
.\metra.ps1 coverage
.\metra.ps1 inspect
.\metra.ps1 inspect -Name Metra
.\metra.ps1 inspect plan
.\metra.ps1 inspect plan -Latest -Name Metra
.\metra.ps1 inspect plan <filename-fragment> -Name Metra
.\metra.ps1 inspect pack
.\metra.ps1 inspect pack plan
.\metra.ps1 inspect pack-only -Name Metra
.\metra.ps1 inspect pack-only agents -Name <Project>
.\metra.ps1 inspect pack-only plan -Latest -Name Metra
.\metra.ps1 azdo status|repos|get|gaps|tree|search|ideas
.\metra.ps1 ops
.\metra.ps1 unblock
.\packaging\Build-MetraInstaller.ps1
.\metra.ps1 routing -Name TicketTracker
.\metra.ps1 routing -Query "gateway msal"
.\metra.ps1 verify
```

Focused module tests (PowerShell 7 + Pester 5+): `pwsh -NoProfile -File .\tests\Invoke-MetraTests.ps1`

HTML Ops desk contributors:

```powershell
cd ops
npm install
npm run build
```
