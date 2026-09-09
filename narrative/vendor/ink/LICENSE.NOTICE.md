# Ink vendor notice

This folder vendors binaries from the [inkle/ink](https://github.com/inkle/ink) project
(release pinned in `version.json`, asset `inklecate_windows.zip`).

- `ink-engine-runtime.dll` - Ink story runtime (**tracked**; required to play committed `story.json`)
- `ink_compiler.dll` - optional companion from the zip (may be present locally)
- `inklecate.exe` - Ink compiler (**gitignored**; ~60MB self-contained). Fetched automatically on
  `.\metra.ps1 narrative compile` via `Install-MetraInkInklecate` when missing.

Ink is licensed under the MIT License. See https://github.com/inkle/ink/blob/master/LICENSE.txt

Metra does not modify these binaries. Pin recorded in `version.json`.
