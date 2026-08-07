# Metra Ask Ollama engine (recommended path)

Ollama is the **default consumer Ask engine**. Metra talks to it with a PowerShell-native OpenAI-compatible client (`AskOpenAICompat.ps1`) - **no Node**.

| Setting | Default |
|---------|---------|
| `ask.engine` | `ollama` |
| `ask.ollama.baseUrl` | `http://127.0.0.1:11434` |
| `ask.ollama.model` | pin from recommend (e.g. `qwen2.5:7b`) |
| `ask.ollama.sizeBand` | `small` / `medium` |

```powershell
.\metra.ps1 ask recommend
.\metra.ps1 ask accept          # install runtime + pull model + ask test
.\metra.ps1 ask engine show
```

Modest vs Balanced is **model pin size**, not a different runtime. GPT4All is watch-only (not first-class).

## Silent install (no Launch UI)

`ask accept` installs Ollama **silently**: it drops the `%LOCALAPPDATA%\Ollama\upgraded` hidden-start marker so the desktop app starts hidden (tray + local API, no Launch window), then runs the signed `OllamaSetup.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES`. If the signed download is unavailable it falls back to `winget --silent --override "/VERYSILENT ..."`, then to teaching `https://ollama.com/download`. Metra Ask only needs the local API on `127.0.0.1:11434`; the desktop UI is optional chrome.

## Updates

Ops Host caches Ollama currency (with Metra) under `%LOCALAPPDATA%\Metra\updates-status.local.json`. Settings **Updates** shows status and an **Update Ollama** button - nothing upgrades until clicked. Apply reuses the silent path above.
