#Requires -Version 5.1

# ps-ollama - PowerShell wrapper for the Ollama API
# Configuration file path
$script:ConfigPath = Join-Path $HOME '.config/psllm/connection.json'
$script:DefaultHost = 'http://127.0.0.1:11434'

#region Connection Management

function Get-OllamaConnection {
    <#
    .SYNOPSIS
        Gets the current Ollama connection settings.
    .DESCRIPTION
        Retrieves the Ollama API connection configuration from the settings file
        or returns the default localhost configuration if no settings exist.
    .OUTPUTS
        PSCustomObject with Host property containing the Ollama API base URL.
    .EXAMPLE
        Get-OllamaConnection
        Returns the current connection settings.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (Test-Path $script:ConfigPath) {
        try {
            $config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            return $config
        }
        catch {
            Write-Warning "Failed to read config file: $_. Using defaults."
        }
    }

    return [PSCustomObject]@{
        Host = $script:DefaultHost
    }
}

function Set-OllamaConnection {
    <#
    .SYNOPSIS
        Sets the Ollama connection settings.
    .DESCRIPTION
        Configures and persists the Ollama API connection settings to the
        configuration file at $HOME/.config/psllm/connection.json
    .PARAMETER Host
        The base URL of the Ollama API (e.g., http://192.168.1.100:11434)
    .EXAMPLE
        Set-OllamaConnection -Host 'http://192.168.1.100:11434'
        Configures the module to connect to an Ollama instance on the local network.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Host
    )

    $config = [PSCustomObject]@{
        Host = $Host.TrimEnd('/')
    }

    $configDir = Split-Path $script:ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        if ($PSCmdlet.ShouldProcess($configDir, 'Create directory')) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
    }

    if ($PSCmdlet.ShouldProcess($script:ConfigPath, 'Save connection settings')) {
        $config | ConvertTo-Json | Set-Content $script:ConfigPath -Encoding UTF8
        Write-Verbose "Connection settings saved to $script:ConfigPath"
    }

    return $config
}

function Test-OllamaConnection {
    <#
    .SYNOPSIS
        Tests the connection to the Ollama API.
    .DESCRIPTION
        Attempts to connect to the Ollama API and retrieve version information
        to verify the connection is working.
    .PARAMETER Host
        Optional. The Ollama API host to test. If not specified, uses the configured host.
    .OUTPUTS
        Boolean indicating whether the connection was successful.
    .EXAMPLE
        Test-OllamaConnection
        Tests the connection using the configured settings.
    .EXAMPLE
        Test-OllamaConnection -Host 'http://192.168.1.100:11434'
        Tests connection to a specific Ollama host.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$Host
    )

    if (-not $Host) {
        $Host = (Get-OllamaConnection).Host
    }

    try {
        $response = Invoke-RestMethod -Uri "$Host/api/version" -Method Get -TimeoutSec 10
        Write-Verbose "Connected to Ollama version: $($response.version)"
        return $true
    }
    catch {
        Write-Warning "Failed to connect to Ollama at $Host : $_"
        return $false
    }
}

#endregion

#region Helper Functions

function Invoke-OllamaApi {
    <#
    .SYNOPSIS
        Internal helper to invoke Ollama API endpoints.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [switch]$Stream
    )

    $config = Get-OllamaConnection
    $uri = "$($config.Host)$Endpoint"

    $params = @{
        Uri = $uri
        Method = $Method
        ContentType = 'application/json'
    }

    if ($Body) {
        $params.Body = $Body | ConvertTo-Json -Depth 10
    }

    try {
        if ($Stream) {
            # For streaming, we need to handle the response differently
            $params.UseBasicParsing = $true
            $response = Invoke-WebRequest @params
            # Split response by newlines and parse each JSON object
            $response.Content -split "`n" | Where-Object { $_ -match '\S' } | ForEach-Object {
                try {
                    $_ | ConvertFrom-Json
                }
                catch {
                    Write-Verbose "Skipping non-JSON line: $_"
                }
            }
        }
        else {
            Invoke-RestMethod @params
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($_.ErrorDetails.Message) {
            try {
                $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
                $errorMessage = $errorDetails.error
            }
            catch {}
        }
        Write-Error "Ollama API error: $errorMessage"
    }
}

#endregion

#region Model Management

function Get-OllamaModel {
    <#
    .SYNOPSIS
        Gets information about Ollama models.
    .DESCRIPTION
        Lists all locally available models or shows detailed information about a specific model.
    .PARAMETER Name
        Optional. The name of a specific model to get detailed information about.
    .PARAMETER Verbose
        When showing a specific model, includes additional verbose output.
    .OUTPUTS
        List of models or detailed model information.
    .EXAMPLE
        Get-OllamaModel
        Lists all locally available models.
    .EXAMPLE
        Get-OllamaModel -Name 'llama3.2'
        Shows detailed information about the llama3.2 model.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name
    )

    if ($Name) {
        # Show specific model details
        $body = @{ name = $Name }
        Invoke-OllamaApi -Endpoint '/api/show' -Method POST -Body $body
    }
    else {
        # List all models
        $response = Invoke-OllamaApi -Endpoint '/api/tags' -Method GET
        $response.models
    }
}

function Get-OllamaRunningModel {
    <#
    .SYNOPSIS
        Gets currently running/loaded Ollama models.
    .DESCRIPTION
        Returns a list of models that are currently loaded in memory.
    .OUTPUTS
        List of running models with their memory usage and expiration details.
    .EXAMPLE
        Get-OllamaRunningModel
        Lists all models currently loaded in memory.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $response = Invoke-OllamaApi -Endpoint '/api/ps' -Method GET
    $response.models
}

function Install-OllamaModel {
    <#
    .SYNOPSIS
        Downloads/pulls an Ollama model.
    .DESCRIPTION
        Downloads a model from the Ollama library to make it available locally.
    .PARAMETER Name
        The name of the model to download (e.g., 'llama3.2', 'mistral', 'codellama').
    .PARAMETER Insecure
        Allow insecure connections to the library (only for custom registries).
    .EXAMPLE
        Install-OllamaModel -Name 'llama3.2'
        Downloads the llama3.2 model.
    .EXAMPLE
        Install-OllamaModel -Name 'mistral:7b-instruct'
        Downloads a specific variant of the mistral model.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [switch]$Insecure
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Download Ollama model')) {
        $body = @{
            name = $Name
            stream = $false
        }
        if ($Insecure) {
            $body.insecure = $true
        }

        Write-Host "Pulling model '$Name'... This may take a while." -ForegroundColor Cyan
        $response = Invoke-OllamaApi -Endpoint '/api/pull' -Method POST -Body $body
        if ($response.status -eq 'success') {
            Write-Host "Model '$Name' downloaded successfully." -ForegroundColor Green
        }
        $response
    }
}

function Uninstall-OllamaModel {
    <#
    .SYNOPSIS
        Removes an Ollama model.
    .DESCRIPTION
        Deletes a locally downloaded model to free up disk space.
    .PARAMETER Name
        The name of the model to remove.
    .EXAMPLE
        Uninstall-OllamaModel -Name 'llama3.2'
        Removes the llama3.2 model from local storage.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Delete Ollama model')) {
        $body = @{ name = $Name }
        Invoke-OllamaApi -Endpoint '/api/delete' -Method DELETE -Body $body
        Write-Host "Model '$Name' has been removed." -ForegroundColor Yellow
    }
}

function Copy-OllamaModel {
    <#
    .SYNOPSIS
        Copies an Ollama model to a new name.
    .DESCRIPTION
        Creates a copy of an existing model with a new name.
    .PARAMETER Source
        The name of the source model to copy.
    .PARAMETER Destination
        The name for the new model copy.
    .EXAMPLE
        Copy-OllamaModel -Source 'llama3.2' -Destination 'my-llama'
        Creates a copy of llama3.2 named my-llama.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    if ($PSCmdlet.ShouldProcess("$Source -> $Destination", 'Copy Ollama model')) {
        $body = @{
            source = $Source
            destination = $Destination
        }
        Invoke-OllamaApi -Endpoint '/api/copy' -Method POST -Body $body
        Write-Host "Model '$Source' copied to '$Destination'." -ForegroundColor Green
    }
}

#endregion

#region Generation Functions

function Invoke-OllamaGenerate {
    <#
    .SYNOPSIS
        Generates text using an Ollama model.
    .DESCRIPTION
        Sends a prompt to the Ollama generate endpoint and returns the generated text.
        Supports streaming and various generation options.
    .PARAMETER Model
        The name of the model to use for generation.
    .PARAMETER Prompt
        The input prompt for text generation.
    .PARAMETER System
        Optional system message to set the model's behavior.
    .PARAMETER Template
        Optional prompt template to use.
    .PARAMETER Context
        Context from a previous generation for conversation continuity.
    .PARAMETER Images
        Array of base64-encoded images for multimodal models.
    .PARAMETER Format
        Response format. Use 'json' for JSON output.
    .PARAMETER Temperature
        Controls randomness (0.0-2.0). Lower is more deterministic.
    .PARAMETER Stream
        Whether to stream the response. Default is false for easier handling.
    .PARAMETER Raw
        If set, disables templating and passes prompt directly to model.
    .PARAMETER KeepAlive
        How long to keep model loaded (e.g., '5m', '1h', '-1' for indefinite).
    .OUTPUTS
        Generated text response or streaming response objects.
    .EXAMPLE
        Invoke-OllamaGenerate -Model 'llama3.2' -Prompt 'What is PowerShell?'
        Generates a response about PowerShell.
    .EXAMPLE
        Invoke-OllamaGenerate -Model 'llama3.2' -Prompt 'Explain recursion' -Temperature 0.7
        Generates a more creative response with higher temperature.
    #>
    [CmdletBinding()]
    [Alias('ollama-gen')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Model,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [string]$Template,

        [Parameter()]
        [array]$Context,

        [Parameter()]
        [string[]]$Images,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature,

        [Parameter()]
        [switch]$Stream,

        [Parameter()]
        [switch]$Raw,

        [Parameter()]
        [string]$KeepAlive
    )

    $body = @{
        model = $Model
        prompt = $Prompt
        stream = [bool]$Stream
    }

    if ($System) { $body.system = $System }
    if ($Template) { $body.template = $Template }
    if ($Context) { $body.context = $Context }
    if ($Images) { $body.images = $Images }
    if ($Format) { $body.format = $Format }
    if ($Raw) { $body.raw = $true }
    if ($KeepAlive) { $body.keep_alive = $KeepAlive }

    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.options = @{ temperature = $Temperature }
    }

    $response = Invoke-OllamaApi -Endpoint '/api/generate' -Method POST -Body $body -Stream:$Stream

    if ($Stream) {
        $response
    }
    else {
        $response
    }
}

function Invoke-OllamaChat {
    <#
    .SYNOPSIS
        Sends a chat message to an Ollama model.
    .DESCRIPTION
        Generates a chat response using the Ollama chat API. Supports message history,
        system prompts, and tool calling.
    .PARAMETER Model
        The name of the model to use for chat.
    .PARAMETER Message
        The user's message to send.
    .PARAMETER Messages
        Full message history array with role/content objects.
    .PARAMETER System
        System message to set the assistant's behavior.
    .PARAMETER Format
        Response format. Use 'json' for JSON output.
    .PARAMETER Temperature
        Controls randomness (0.0-2.0). Lower is more deterministic.
    .PARAMETER Stream
        Whether to stream the response. Default is false.
    .PARAMETER KeepAlive
        How long to keep model loaded (e.g., '5m', '1h').
    .OUTPUTS
        Chat response with message content.
    .EXAMPLE
        Invoke-OllamaChat -Model 'llama3.2' -Message 'Hello, how are you?'
        Sends a simple chat message.
    .EXAMPLE
        $messages = @(
            @{ role = 'user'; content = 'What is 2+2?' }
            @{ role = 'assistant'; content = '4' }
            @{ role = 'user'; content = 'And what is that times 10?' }
        )
        Invoke-OllamaChat -Model 'llama3.2' -Messages $messages
        Continues a conversation with message history.
    #>
    [CmdletBinding(DefaultParameterSetName = 'SimpleMessage')]
    [Alias('ollama-chat')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Model,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'SimpleMessage', ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory, ParameterSetName = 'MessageHistory')]
        [array]$Messages,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [string]$Format,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature,

        [Parameter()]
        [switch]$Stream,

        [Parameter()]
        [string]$KeepAlive
    )

    $body = @{
        model = $Model
        stream = [bool]$Stream
    }

    if ($PSCmdlet.ParameterSetName -eq 'SimpleMessage') {
        $body.messages = @(
            @{
                role = 'user'
                content = $Message
            }
        )
        if ($System) {
            $body.messages = @(
                @{ role = 'system'; content = $System }
            ) + $body.messages
        }
    }
    else {
        $body.messages = $Messages
    }

    if ($Format) { $body.format = $Format }
    if ($KeepAlive) { $body.keep_alive = $KeepAlive }

    if ($PSBoundParameters.ContainsKey('Temperature')) {
        $body.options = @{ temperature = $Temperature }
    }

    $response = Invoke-OllamaApi -Endpoint '/api/chat' -Method POST -Body $body -Stream:$Stream

    if ($Stream) {
        $response
    }
    else {
        $response
    }
}

#endregion

#region Embeddings

function Get-OllamaEmbedding {
    <#
    .SYNOPSIS
        Generates embeddings for the given text.
    .DESCRIPTION
        Uses an Ollama embedding model to generate vector embeddings for text input.
        Useful for semantic search, clustering, and similarity comparisons.
    .PARAMETER Model
        The name of the embedding model to use (e.g., 'nomic-embed-text', 'all-minilm').
    .PARAMETER Input
        The text to generate embeddings for. Can be a single string or array of strings.
    .PARAMETER Truncate
        Truncates the input to fit the model's context length.
    .PARAMETER KeepAlive
        How long to keep the model loaded.
    .OUTPUTS
        Embedding response with vector data.
    .EXAMPLE
        Get-OllamaEmbedding -Model 'nomic-embed-text' -Input 'Hello world'
        Generates embeddings for the text "Hello world".
    .EXAMPLE
        Get-OllamaEmbedding -Model 'all-minilm' -Input @('First text', 'Second text')
        Generates embeddings for multiple texts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Model,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [object]$Input,

        [Parameter()]
        [switch]$Truncate,

        [Parameter()]
        [string]$KeepAlive
    )

    $body = @{
        model = $Model
        input = $Input
    }

    if ($Truncate) { $body.truncate = $true }
    if ($KeepAlive) { $body.keep_alive = $KeepAlive }

    Invoke-OllamaApi -Endpoint '/api/embed' -Method POST -Body $body
}

#endregion

#region Utility Functions

function Get-OllamaVersion {
    <#
    .SYNOPSIS
        Gets the Ollama API version.
    .DESCRIPTION
        Returns the version information of the connected Ollama instance.
    .OUTPUTS
        Version information object.
    .EXAMPLE
        Get-OllamaVersion
        Returns the Ollama version.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Invoke-OllamaApi -Endpoint '/api/version' -Method GET
}

#endregion

# Export aliases
Export-ModuleMember -Function * -Alias *
