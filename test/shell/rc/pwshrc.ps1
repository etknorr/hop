function prompt { "[" + (Split-Path -Leaf $PWD.ProviderPath) + "]> " }
Invoke-Expression (& hop init pwsh | Out-String)
Set-Location -LiteralPath "$env:HOP_T/repo"
