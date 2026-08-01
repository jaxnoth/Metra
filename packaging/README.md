# Metra packaging

Build the per-user Windows installer (product distribution channel).

```powershell
cd C:\Projects\_metra   # or your Metra checkout
.\packaging\Build-MetraInstaller.ps1
```

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php). If `ISCC.exe` is missing:

```powershell
winget install -e --id JRSoftware.InnoSetup
```

Or set `METRA_ISCC` to the full path of `ISCC.exe`.

## Outputs

| Path | Role |
|------|------|
| `packaging/out/MetraSetup-{version}.exe` | Versioned artifact (`ModuleVersion` from `scripts/Metra.psd1`) |
| `packaging/out/MetraSetup.exe` | Same build, convenience name for Releases |

`packaging/stage/` is temporary (deleted after a successful compile unless `-KeepStage`).

## Architecture

- Installer replaces **product** files; never stages user state (`metra.config.json`, local registries, `*.local.mdc`, generated packs).
- Upgrades reuse the prior install directory (`UsePreviousAppDir`) under a stable AppId.
- Post-install task (checked by default) runs `Metra-Setup.cmd -NoPause` -> setup.
- Start Menu **Metra Setup** launches `Metra-Setup.cmd` (no pack chooser in the wizard).
- Optional Persona Add-ons stay `import-profile` / `setup -Profile` after install.

Unsigned builds may show SmartScreen: More info -> Run anyway.
