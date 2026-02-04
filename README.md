# PowerShell ollama Module

Simple PowerShell wrapper for HTTP API based interfaces to LLMs, particularly Ollama. We don't assume that the ollama instance is running literally on localhost, but probably on a dedicated host on the local subnet, probably on a docker/podman/oci host.

Persistent settings for ollama connection definition should be stored in $HOME/.config/psllm/connection.json
minimally:
```json
{
  "Host": "http://ollama-docker-server.local:11434"
}
```

```powershell
#some examples

install-ollamamodel llama3.2:3b

invoke-ollamagenerate -prompt "Today's date is $(get-date) . Please tell me which the next two holidays are and what date each will occur upon. Also, for each of these holidays, are they typically gift giving holidays in the U.S.?" -Model ((Get-OllamaRunningModel).name ?? "llama3.2:3b") 
| select response


$prompt_text = "From the following list of IT employees, please make a thoughtful selection of three employees who would be best suited to lead a project on upgrading our company's cybersecurity infrastructure. Consider their job titles and descriptions in your selection.`n {0} `nDo not select any names that are not from the above list. Provide your answer in a bulleted list format, with each bullet point containing the employee's name followed by a brief explanation of why they were chosen." -f (get-aduser -filter {department -like "*INFORMATION SYS*" -AND enabled -eq "True" -AND Description -notlike "*Contractor*" }  -Properties name, title, department, location, description | select Name,Description,Title | Out-String)

invoke-ollamagenerate -Model ((Get-OllamaRunningModel).name ?? "llama3.2:3b") -prompt $prompt_text | select response
```
