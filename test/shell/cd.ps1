# cd.ps1: cd.sh for pwsh, with no terminal; the backslash name is the documented pwsh-on-Unix limitation, so it reports XFAIL.
Invoke-Expression (& hopx init pwsh | Out-String)
$R = "$env:HOPX_T/repo"
function check($n, $want) { if ($PWD.ProviderPath -eq $want) { "PASS $n" } else { "FAIL ${n}: PWD=$($PWD.ProviderPath) want=$want" } }
Set-Location -LiteralPath $R; hopx ./plain; check t0-plain "$R/plain"
Set-Location -LiteralPath $R; hopx './with space'; check t0-space "$R/with space"
Set-Location -LiteralPath $R; hopx './trail-space-backslash\ '
if ($PWD.ProviderPath -eq "$R/trail-space-backslash\ ") { 'PASS t0-trail-space-backslash' } else { "XFAIL t0-trail-space-backslash: pwsh on Unix reads \ as a separator, PWD=$($PWD.ProviderPath)" }
Set-Location -LiteralPath $R; hopx ./café; check t0-unicode "$R/café"
Set-Location -LiteralPath $R; hopx "./nl`nx"; check t0-newline "$R/nl`nx"
Set-Location -LiteralPath $R; hopx './brack[1]'; check t0-bracket "$R/brack[1]"
Set-Location -LiteralPath $R; hopx gamma; check resolve-jump "$R/beta/gamma"
Set-Location -LiteralPath $R; hopx with space; check resolve-two-words "$R/with space"
Set-Location -LiteralPath $R; hopx brack; check resolve-bracket "$R/brack[1]"
Set-Location -LiteralPath "$R/beta/gamma"; hopx /; check slash $R
Set-Location -LiteralPath $R; hopx alpha; hopx -; check dash $R
Set-Location -LiteralPath $R; hopx zzqx-nothing 2>$null
if ($LASTEXITCODE -eq 1 -and $PWD.ProviderPath -eq $R) { 'PASS no-match-rc1' } else { "FAIL no-match-rc1 rc=$LASTEXITCODE" }
Set-Location -LiteralPath $R; hopx -Z 2>$null
if ($LASTEXITCODE -eq 2) { 'PASS usage-rc2' } else { "FAIL usage-rc2 rc=$LASTEXITCODE" }
Set-Location -LiteralPath $R; $env:HOP_CODE = "$env:HOPX_T/stub/code-fail"; hopx --action=cd+open alpha 2>$null; $rc = $LASTEXITCODE; Remove-Item Env:HOP_CODE
if ($rc -eq 3 -and $PWD.ProviderPath -eq "$R/alpha") { 'PASS cd-then-fail' } else { "FAIL cd-then-fail rc=$rc PWD=$($PWD.ProviderPath)" }
Set-Location -LiteralPath $R; $d = & $global:__HopxBin gamma
if ($d -eq "$R/beta/gamma" -and $PWD.ProviderPath -eq $R) { 'PASS bare-binary-prints' } else { "FAIL bare-binary-prints d=$d" }
if (@(hopx -h | Select-String '^usage: hopx').Count -eq 1) { 'PASS stdout-pipe' } else { 'FAIL stdout-pipe' }
if (@(Get-ChildItem $env:TMPDIR -Filter 'hopx.*').Count -eq 0) { 'PASS no-cmdfile-left' } else { 'FAIL no-cmdfile-left' }
$h = Get-Content $env:HOPX_HISTFILE
if ($h[0] -like '*/beta/gamma' -and ($h -like '*/alpha').Count -eq 1) { 'PASS mru' } else { 'FAIL mru' }
if ($null -eq $env:HOPX_CMDFILE) { 'PASS env-clean' } else { 'FAIL env-clean HOPX_CMDFILE leaked' }
Set-Location -LiteralPath $R; try { Set-Location "$R/brack[1]" -ErrorAction Stop; "INFO plain Set-Location brack[1] -> $($PWD.ProviderPath)" } catch { "INFO plain Set-Location brack[1] fails, hence -LiteralPath" }
