# hopx init pwsh: Invoke-Expression (& hopx init pwsh | Out-String), in $PROFILE.

# The path is baked in because the function below shadows the binary, and pwsh has no `command` to reach past it.
$global:__HopxBin = '@BIN@'

function global:@CMD@ {
	if ($args.Count -eq 1 -and $args[0] -eq '-') {
		Set-Location -
		return
	}
	$f = Join-Path ([IO.Path]::GetTempPath()) ("hopx.{0}.{1}" -f $PID, (Get-Random))
	# pwsh has no per-command env prefix, so the variable is set and then removed even when the binary throws.
	$env:HOPX_CMDFILE = $f
	$dir = $null
	$rc = 0
	try {
		& $global:__HopxBin @args
		$rc = $LASTEXITCODE
	} finally {
		Remove-Item Env:HOPX_CMDFILE -ErrorAction SilentlyContinue
		if (Test-Path -LiteralPath $f) {
			# Explicit UTF-8: Windows PowerShell 5.1 would otherwise read the file in the ANSI code page.
			$dir = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
			Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
		}
	}
	# -LiteralPath: a plain Set-Location treats [ ] * ? in a directory name as wildcards.
	# - A failed cd reports and returns 1, like `cd || return`, rather than throwing out of the caller's script.
	if ($dir) {
		Set-Location -LiteralPath $dir
		if (-not $?) { $rc = 1 }
	}
	$global:LASTEXITCODE = $rc
}

Register-ArgumentCompleter -Native -CommandName @CMD@ -ScriptBlock {
	param($wordToComplete, $commandAst, $cursorPosition)
	$words = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.ToString() })
	if ($wordToComplete -eq '') { $words += '' }
	& $global:__HopxBin __complete @words | ForEach-Object {
		$c, $d = $_ -split "`t", 2
		if (-not $d) { $d = $c }
		[System.Management.Automation.CompletionResult]::new($c, $c, 'ParameterValue', $d)
	}
}

# InvokePrompt re-runs the prompt function after the cd, and PSReadLine keeps the half-typed buffer as it was.
# - Get-Command, not Get-Module: under `pwsh -NoExit -Command` and some hosts PSReadLine isn't imported yet, and lookup autoloads it.
if (Get-Command Set-PSReadLineKeyHandler -ErrorAction Ignore) {
	Set-PSReadLineKeyHandler -Chord 'Ctrl+g', 'Alt+g' -BriefDescription hopx -Description 'hopx without losing the typed line' -ScriptBlock {
		@CMD@
		[Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
	}
}
