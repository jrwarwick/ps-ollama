# ps-llm
Simple PowerShell wrapper for HTTP API based interfaces to LLMs, particularly Ollama. We don't assume that the ollama instance is running literally on localhost, but probably on a dedicated host on the local subnet.

Persistent settings for ollama connection definition should be stored in $HOME/.config/psllm/connection.json
