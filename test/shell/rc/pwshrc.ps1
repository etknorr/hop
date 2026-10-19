function prompt { "[" + (Split-Path -Leaf $PWD.ProviderPath) + "]> " }
Invoke-Expression (& hopx init pwsh | Out-String)
Set-Location -LiteralPath "$env:HOPX_T/repo"
