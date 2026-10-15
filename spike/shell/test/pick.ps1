# pick.ps1: pick.sh for pwsh, on a terminal from script(1).
Invoke-Expression (& hopx init pwsh | Out-String)
$R = "$env:HOPX_T/repo"
function check($n, $want) { if ($PWD.ProviderPath -eq $want) { "PASS $n" } else { "FAIL ${n}: PWD=$($PWD.ProviderPath) want=$want" } }
function withopts($o, [scriptblock]$b) { $env:FZF_DEFAULT_OPTS = $o; try { & $b } finally { Remove-Item Env:FZF_DEFAULT_OPTS } }
Set-Location -LiteralPath $R; withopts '--bind=load:abort' { hopx -p alpha }
if ($LASTEXITCODE -eq 130 -and $PWD.ProviderPath -eq $R) { 'PASS cancel-130' } else { "FAIL cancel-130 rc=$LASTEXITCODE" }
Set-Location -LiteralPath $R; withopts '--bind=load:accept' { hopx -p gamma }; check picker-enter "$R/beta/gamma"
Set-Location -LiteralPath $R; withopts '--bind=load:accept' { hopx -p with space }; check picker-space "$R/with space"
Set-Location -LiteralPath $R; withopts '--bind=load:accept' { hopx -p brack }; check picker-bracket "$R/brack[1]"
Set-Location -LiteralPath $R; withopts "--bind='load:print(ctrl-y)+accept'" { hopx -p gamma | Out-Null }
if ((Get-Content -Raw "$env:HOPX_T/clip" -ErrorAction Ignore) -eq "$R/beta/gamma" -and $PWD.ProviderPath -eq $R) { 'PASS picker-copy' } else { "FAIL picker-copy PWD=$($PWD.ProviderPath)" }
