@{
    RootModule = 'ps-ollama.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'a3f5c8d2-1b4e-4f6a-9c7d-8e2b3a1f5d4c'
    Author = 'ps-ollama contributors'
    CompanyName = 'Community'
    Copyright = '(c) 2024-2026. All rights reserved.'
    Description = 'A PowerShell wrapper module for the Ollama API. Provides cmdlets to interact with Ollama LLM instances for text generation, chat, embeddings, and model management.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-OllamaConnection',
        'Set-OllamaConnection',
        'Test-OllamaConnection',
        'Get-OllamaModel',
        'Get-OllamaRunningModel',
        'Get-OllamaVersion',
        'Invoke-OllamaGenerate',
        'Invoke-OllamaChat',
        'Get-OllamaEmbedding',
        'Install-OllamaModel',
        'Uninstall-OllamaModel',
        'Copy-OllamaModel'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @(
        'ollama-gen',
        'ollama-chat'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('Ollama', 'LLM', 'AI', 'ChatGPT', 'LocalAI', 'MachineLearning')
            LicenseUri = 'https://github.com/jrwarwick/ps-ollama/blob/main/LICENSE'
            ProjectUri = 'https://github.com/jrwarwick/ps-ollama'
            ReleaseNotes = 'Initial release with core Ollama API wrapper functions.'
        }
    }
}
