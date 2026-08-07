# Metra Ask llama.cpp (Advanced / experimental)

Escape hatch only. **Never** auto-recommended - even on high-end GPUs.

Configure `ask.engine=llamacpp` and `ask.llamacpp.baseUrl` (default `http://127.0.0.1:8080`) pointing at an OpenAI-compatible `llama-server`.

```powershell
.\metra.ps1 ask engine set llamacpp
```

Uses the same PowerShell `openai_compat` path as Ollama/enterprise.
