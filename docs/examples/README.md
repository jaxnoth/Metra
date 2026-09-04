# Config examples

Tracked starter JSON for machine-local live files under `%LOCALAPPDATA%\Metra\` (and `ops\` for Ask/Capture ledgers).

```powershell
Copy-Item .\docs\examples\client-auth.example.json (Join-Path $env:LOCALAPPDATA 'Metra\client-auth.local.json')
Copy-Item .\docs\examples\azdo.local.example.json (Join-Path $env:LOCALAPPDATA 'Metra\azdo.local.json')
Copy-Item .\docs\examples\ticket-watch.local.example.json (Join-Path $env:LOCALAPPDATA 'Metra\ticket-watch.local.json')
Copy-Item .\docs\examples\desk-familiarity.local.example.json (Join-Path $env:LOCALAPPDATA 'Metra\desk-familiarity.local.json')
Copy-Item .\docs\examples\operator-contract.example.json .\docs\operator-contract.json
Copy-Item .\docs\examples\decision-registry.example.json .\docs\decision-registry.json
```

OCC and Decision Registry live files remain under `docs\` until a dedicated migration. Ops Ask/Capture/Attention/Place/Preferences live under `%LOCALAPPDATA%\Metra\ops\`.