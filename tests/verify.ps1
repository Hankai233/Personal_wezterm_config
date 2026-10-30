$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wez = (Get-Command wezterm -ErrorAction SilentlyContinue).Source
if (-not $wez) { $wez = 'C:\Program Files\WezTerm\wezterm.exe' }
if (-not (Test-Path $wez)) { Write-Error "wezterm not found"; exit 1 }

$out = Join-Path $env:TEMP ('wezterm-tests-' + [guid]::NewGuid().ToString('N') + '.txt')
$env:WEZTERM_CONFIG_HOME = $root
$env:WEZTEST_OUT = $out
# wezterm writes log_warn to stderr; with $ErrorActionPreference='Stop' PowerShell 5.1
# turns native stderr into a terminating NativeCommandError even when redirected to $null.
# Relax it only around the native call: log lines must not affect assertions.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $wez --config-file (Join-Path $root 'tests\harness.lua') show-keys *> $null
$ErrorActionPreference = $prevEap

# The wezterm CLI may return before the config finishes; wait for the results file (max 10s)
$deadline = (Get-Date).AddSeconds(10)
while (-not (Test-Path $out) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }

$lines = Get-Content $out -ErrorAction SilentlyContinue
if (-not $lines) { Write-Error "test harness produced no output: $out"; exit 1 }
$lines | ForEach-Object { Write-Host $_ }
$summary = $lines | Where-Object { $_ -like 'SUMMARY*' }
if (-not $summary) { Write-Error 'no SUMMARY line'; exit 1 }
$fails = @($lines | Where-Object { $_ -like 'FAIL*' })
if ($fails.Count -gt 0) { Write-Error ("failed assertions: " + $fails.Count); exit 1 }

# Real-entrypoint gate: the suite above loads tests/harness.lua, which is a different
# entrypoint from the shipped wezterm.lua -> require 'init'. Assert the real entrypoint
# loads cleanly too. wezterm prints config-load errors to stderr but still exits 0, so
# the subcommand's exit code is meaningless here; the captured text is what we assert.
# Any module calling the async wezterm.glob during config load shows up as
# 'attempt to yield across a C-call boundary', so this gate also pins that.
$entry = Join-Path $root 'wezterm.lua'
$loadText = ''
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $loadText = (& $wez --config-file $entry ls-fonts 2>&1 | Out-String)
} finally {
  $ErrorActionPreference = $prevEap
}
$loadBad = @($loadText -split "`r?`n" | Where-Object { $_ -match 'runtime error|attempt to yield' })
if ($loadBad.Count -gt 0) {
  $loadBad | ForEach-Object { Write-Host $_ }
  Write-Error 'real entrypoint wezterm.lua failed to load'
  exit 1
}

Write-Host 'ALL PASS'
exit 0
