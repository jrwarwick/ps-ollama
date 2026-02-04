#Requires -Modules Pester

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot 'ollama.psd1'
    Import-Module $ModulePath -Force

    # Test configuration path for isolation
    $script:TestConfigDir = Join-Path $TestDrive '.config/psllm'
    $script:TestConfigPath = Join-Path $script:TestConfigDir 'connection.json'
}

AfterAll {
    Remove-Module ollama -Force -ErrorAction SilentlyContinue
}

Describe 'Module Import' {
    It 'Should import the module without errors' {
        { Import-Module $ModulePath -Force } | Should -Not -Throw
    }

    It 'Should export the expected functions' {
        $expectedFunctions = @(
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

        $exportedFunctions = (Get-Module ollama).ExportedFunctions.Keys
        foreach ($func in $expectedFunctions) {
            $exportedFunctions | Should -Contain $func
        }
    }

    It 'Should export the expected aliases' {
        $module = Get-Module ollama
        $module.ExportedAliases.Keys | Should -Contain 'ollama-gen'
        $module.ExportedAliases.Keys | Should -Contain 'ollama-chat'
    }
}

Describe 'Get-OllamaConnection' {
    It 'Should return default host when no config exists' {
        $result = Get-OllamaConnection
        $result.Host | Should -Be 'http://127.0.0.1:11434'
    }
}

Describe 'Set-OllamaConnection' {
    BeforeAll {
        # Store original config path
        $script:OriginalConfigPath = (Get-Module ollama).Invoke({ $script:ConfigPath })
    }

    It 'Should create config with specified host' {
        InModuleScope ollama {
            $script:ConfigPath = Join-Path $TestDrive '.config/psllm/connection.json'
        }

        Set-OllamaConnection -Host 'http://192.168.1.100:11434'
        $result = Get-OllamaConnection
        $result.Host | Should -Be 'http://192.168.1.100:11434'
    }

    It 'Should trim trailing slashes from host' {
        InModuleScope ollama {
            $script:ConfigPath = Join-Path $TestDrive '.config/psllm/connection2.json'
        }

        Set-OllamaConnection -Host 'http://myserver:11434/'
        $result = Get-OllamaConnection
        $result.Host | Should -Be 'http://myserver:11434'
    }

    AfterAll {
        InModuleScope ollama -Parameters @{ Path = $script:OriginalConfigPath } {
            param($Path)
            $script:ConfigPath = $Path
        }
    }
}

Describe 'Test-OllamaConnection' {
    It 'Should return true when connection succeeds' {
        Mock Invoke-RestMethod {
            return @{ version = '0.1.0' }
        } -ModuleName ollama

        $result = Test-OllamaConnection -Host 'http://localhost:11434'
        $result | Should -BeTrue
    }

    It 'Should return false when connection fails' {
        Mock Invoke-RestMethod {
            throw 'Connection refused'
        } -ModuleName ollama

        $result = Test-OllamaConnection -Host 'http://localhost:11434' -WarningAction SilentlyContinue
        $result | Should -BeFalse
    }
}

Describe 'Get-OllamaVersion' {
    It 'Should return version information' {
        Mock Invoke-RestMethod {
            return @{ version = '0.3.14' }
        } -ModuleName ollama

        $result = Get-OllamaVersion
        $result.version | Should -Be '0.3.14'
    }
}

Describe 'Get-OllamaModel' {
    Context 'When listing all models' {
        It 'Should return list of models' {
            Mock Invoke-RestMethod {
                $model1 = [PSCustomObject]@{ name = 'llama3.2:latest'; size = 4000000000 }
                $model2 = [PSCustomObject]@{ name = 'mistral:latest'; size = 4500000000 }
                return [PSCustomObject]@{
                    models = @($model1, $model2)
                }
            } -ModuleName ollama

            $result = @(Get-OllamaModel)
            $result | Should -HaveCount 2
            $result[0].name | Should -Be 'llama3.2:latest'
        }
    }

    Context 'When showing specific model' {
        It 'Should return model details' {
            Mock Invoke-RestMethod {
                return @{
                    modelfile = 'FROM llama3.2'
                    parameters = 'temperature 0.7'
                    template = '{{ .Prompt }}'
                }
            } -ModuleName ollama

            $result = Get-OllamaModel -Name 'llama3.2'
            $result.modelfile | Should -Be 'FROM llama3.2'
        }
    }
}

Describe 'Get-OllamaRunningModel' {
    It 'Should return list of running models' {
        Mock Invoke-RestMethod {
            $model = [PSCustomObject]@{
                name = 'llama3.2:latest'
                size = 4000000000
                expires_at = '2024-01-01T00:00:00Z'
            }
            return [PSCustomObject]@{
                models = @($model)
            }
        } -ModuleName ollama

        $result = Get-OllamaRunningModel
        # Single item may be unwrapped by PowerShell, so access property directly
        $result.name | Should -Be 'llama3.2:latest'
    }
}

Describe 'Install-OllamaModel' {
    It 'Should pull the specified model' {
        Mock Invoke-RestMethod {
            return @{ status = 'success' }
        } -ModuleName ollama

        $result = Install-OllamaModel -Name 'llama3.2' -Confirm:$false
        $result.status | Should -Be 'success'

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Uri -like '*/api/pull' -and $Method -eq 'POST'
        }
    }
}

Describe 'Uninstall-OllamaModel' {
    It 'Should delete the specified model' {
        Mock Invoke-RestMethod {
            return $null
        } -ModuleName ollama

        { Uninstall-OllamaModel -Name 'llama3.2' -Confirm:$false } | Should -Not -Throw

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Uri -like '*/api/delete' -and $Method -eq 'DELETE'
        }
    }
}

Describe 'Copy-OllamaModel' {
    It 'Should copy the model to new name' {
        Mock Invoke-RestMethod {
            return $null
        } -ModuleName ollama

        { Copy-OllamaModel -Source 'llama3.2' -Destination 'my-llama' -Confirm:$false } | Should -Not -Throw

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Uri -like '*/api/copy' -and $Method -eq 'POST'
        }
    }
}

Describe 'Invoke-OllamaGenerate' {
    It 'Should generate text with the specified model and prompt' {
        Mock Invoke-RestMethod {
            return @{
                model = 'llama3.2'
                response = 'PowerShell is a task automation framework.'
                done = $true
                eval_count = 10
                eval_duration = 1000000000
            }
        } -ModuleName ollama

        $result = Invoke-OllamaGenerate -Model 'llama3.2' -Prompt 'What is PowerShell?'
        $result.response | Should -BeLike '*PowerShell*'
        $result.done | Should -BeTrue
    }

    It 'Should include system message when specified' {
        Mock Invoke-RestMethod {
            param($Body)
            $bodyObj = $Body | ConvertFrom-Json
            return @{
                response = 'Test response'
                done = $true
                system_included = ($null -ne $bodyObj.system)
            }
        } -ModuleName ollama

        $result = Invoke-OllamaGenerate -Model 'llama3.2' -Prompt 'Test' -System 'You are a helpful assistant'

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Body -like '*system*'
        }
    }

    It 'Should include temperature in options when specified' {
        Mock Invoke-RestMethod {
            return @{ response = 'Test'; done = $true }
        } -ModuleName ollama

        Invoke-OllamaGenerate -Model 'llama3.2' -Prompt 'Test' -Temperature 0.5

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Body -like '*temperature*' -and $Body -like '*0.5*'
        }
    }

    It 'Should support pipeline input for prompt' {
        Mock Invoke-RestMethod {
            return @{ response = 'Test response'; done = $true }
        } -ModuleName ollama

        $result = 'What is 2+2?' | Invoke-OllamaGenerate -Model 'llama3.2'
        $result.response | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-OllamaChat' {
    Context 'Simple message mode' {
        It 'Should send a chat message and return response' {
            Mock Invoke-RestMethod {
                return @{
                    model = 'llama3.2'
                    message = @{
                        role = 'assistant'
                        content = 'Hello! How can I help you today?'
                    }
                    done = $true
                }
            } -ModuleName ollama

            $result = Invoke-OllamaChat -Model 'llama3.2' -Message 'Hello!'
            $result.message.content | Should -BeLike '*Hello*'
            $result.message.role | Should -Be 'assistant'
        }

        It 'Should include system message when specified' {
            Mock Invoke-RestMethod {
                return @{
                    message = @{ role = 'assistant'; content = 'Arrr!' }
                    done = $true
                }
            } -ModuleName ollama

            Invoke-OllamaChat -Model 'llama3.2' -Message 'Hello' -System 'You are a pirate'

            Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
                $Body -like '*system*' -and $Body -like '*pirate*'
            }
        }
    }

    Context 'Message history mode' {
        It 'Should send message history array' {
            Mock Invoke-RestMethod {
                return @{
                    message = @{ role = 'assistant'; content = '40' }
                    done = $true
                }
            } -ModuleName ollama

            $messages = @(
                @{ role = 'user'; content = 'What is 2+2?' }
                @{ role = 'assistant'; content = '4' }
                @{ role = 'user'; content = 'Multiply that by 10' }
            )

            $result = Invoke-OllamaChat -Model 'llama3.2' -Messages $messages
            $result.message.content | Should -Be '40'
        }
    }

    It 'Should support the ollama-chat alias' {
        Mock Invoke-RestMethod {
            return @{
                message = @{ role = 'assistant'; content = 'Hi!' }
                done = $true
            }
        } -ModuleName ollama

        $result = ollama-chat -Model 'llama3.2' -Message 'Hello'
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-OllamaEmbedding' {
    It 'Should generate embeddings for text input' {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                model = 'nomic-embed-text'
                embeddings = @(0.1, 0.2, 0.3, 0.4, 0.5)
            }
        } -ModuleName ollama

        $result = Get-OllamaEmbedding -Model 'nomic-embed-text' -Input 'Hello world'
        $result.embeddings | Should -Not -BeNullOrEmpty
        # Single embedding returned as flat array
        $result.embeddings | Should -HaveCount 5
    }

    It 'Should handle multiple inputs' {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{
                model = 'nomic-embed-text'
                # Real API returns array of arrays, but we test the response structure
                embeddings = @(0.1, 0.2, 0.3, 0.4, 0.5, 0.6)
                embedding_count = 2
            }
        } -ModuleName ollama

        $result = Get-OllamaEmbedding -Model 'nomic-embed-text' -Input @('First', 'Second')
        $result.embeddings | Should -Not -BeNullOrEmpty
        $result.embedding_count | Should -Be 2
    }

    It 'Should include truncate option when specified' {
        Mock Invoke-RestMethod {
            return [PSCustomObject]@{ embeddings = @(0.1) }
        } -ModuleName ollama

        Get-OllamaEmbedding -Model 'nomic-embed-text' -Input 'Test' -Truncate

        Should -Invoke Invoke-RestMethod -ModuleName ollama -ParameterFilter {
            $Body -like '*truncate*true*'
        }
    }
}

Describe 'Error Handling' {
    It 'Should handle API errors gracefully' {
        Mock Invoke-RestMethod {
            $errorResponse = @{ error = 'model not found' } | ConvertTo-Json
            $exception = [System.Net.WebException]::new('API Error')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ApiError',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null
            )
            throw $errorRecord
        } -ModuleName ollama

        { Get-OllamaModel -Name 'nonexistent' -ErrorAction Stop } | Should -Throw
    }
}

Describe 'Parameter Validation' {
    It 'Should reject invalid temperature values' {
        { Invoke-OllamaGenerate -Model 'test' -Prompt 'test' -Temperature 3.0 } | Should -Throw
        { Invoke-OllamaGenerate -Model 'test' -Prompt 'test' -Temperature -1.0 } | Should -Throw
    }

    It 'Should require Model parameter for generation' {
        { Invoke-OllamaGenerate -Prompt 'test' } | Should -Throw
    }

    It 'Should require Prompt parameter for generation' {
        { Invoke-OllamaGenerate -Model 'test' } | Should -Throw
    }

    It 'Should require Model parameter for chat' {
        { Invoke-OllamaChat -Message 'test' } | Should -Throw
    }
}
