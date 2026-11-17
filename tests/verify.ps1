$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wez = (Get-Command wezterm -ErrorAction SilentlyContinue).Source
if (-not $wez) { $wez = 'C:\Program Files\WezTerm\wezterm.exe' }
if (-not (Test-Path $wez)) { Write-Error "wezterm not found"; exit 1 }

$out = Join-Path $env:TEMP ('wezterm-tests-' + [guid]::NewGuid().ToString('N') + '.txt')
$env:WEZTERM_CONFIG_HOME = $root
$env:WEZTEST_OUT = $out
try {
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

  # The harness writes BOM-less UTF-8; Windows PowerShell 5.1 decodes files as ANSI by
  # default (ACP 936 here), which turns the Chinese assertion names into mojibake, so
  # force UTF8. Keep this script ASCII-only for the same reason: a BOM-less script with
  # non-ASCII characters is decoded as ANSI by 5.1 as well, so its text would be mangled.
  $lines = Get-Content -Encoding UTF8 $out -ErrorAction SilentlyContinue
  if (-not $lines) { Write-Error "test harness produced no output: $out"; exit 1 }
  $lines | ForEach-Object { Write-Host $_ }
  $summary = $lines | Where-Object { $_ -like 'SUMMARY*' }
  if (-not $summary) { Write-Error 'no SUMMARY line'; exit 1 }
  $fails = @($lines | Where-Object { $_ -like 'FAIL*' })
  if ($fails.Count -gt 0) { Write-Error ("failed assertions: " + $fails.Count); exit 1 }
  # Pin the assertion count so deleting assertions cannot pass silently: a harness that
  # reports 'pass=0 fail=0' still has a SUMMARY line and no FAIL lines. Bump this number
  # (and README.md) together with any intentional change to the assertion count.
  $expectedPass = 285
  $summaryLine = [string]($summary | Select-Object -First 1)
  if ($summaryLine -notmatch 'pass=(\d+) fail=(\d+)') { Write-Error ("unparsable SUMMARY line: " + $summaryLine); exit 1 }
  if ([int]$matches[1] -ne $expectedPass) {
    Write-Error ("unexpected assertion count: pass=" + $matches[1] + ", expected " + $expectedPass); exit 1
  }

  # Real-entrypoint gate: the suite above loads tests/harness.lua, which is a different
  # entrypoint from the shipped wezterm.lua -> require 'init'. Assert the real entrypoint
  # loads cleanly too. wezterm prints config-load errors to stderr but still exits 0, so
  # the subcommand's exit code is meaningless here; the captured text is what we assert.
  # Any module calling the async wezterm.glob during config load shows up as
  # 'attempt to yield across a C-call boundary', so this gate also pins that.
  # A failed load (root-config syntax error, appearance/colors/module error) falls back
  # to the defaults and prints no 'Primary font:' section at all, so require that success
  # marker too; and any 'ERROR' log line from the load is a failure. Matching ERROR
  # case-sensitively as a whole word keeps a font path containing 'error' from tripping
  # the gate, while the runtime-error pattern above stays case-insensitive.
  # 'Unable to load a font' catches a typo in settings.font: the load still succeeds and
  # still prints a fallback 'Primary font:', so without it a wrong family name would pass.
  $entry = Join-Path $root 'wezterm.lua'
  $loadText = ''
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $loadText = (& $wez --config-file $entry ls-fonts 2>&1 | Out-String)
  } finally {
    $ErrorActionPreference = $prevEap
  }
  $loadLines = @($loadText -split "`r?`n")
  $loadBad = @($loadLines | Where-Object { ($_ -cmatch '\bERROR\b') -or ($_ -match 'runtime error|attempt to yield') -or ($_ -match 'Unable to load a font') })
  if ($loadBad.Count -gt 0) {
    $loadBad | ForEach-Object { Write-Host $_ }
    Write-Error 'real entrypoint wezterm.lua failed to load'
    exit 1
  }
  $fontLines = @($loadLines | Where-Object { $_ -match '^Primary font:' })
  if ($fontLines.Count -eq 0) {
    Write-Host 'ls-fonts printed no "Primary font:" success marker (config load failed or produced no output)'
    Write-Error 'real entrypoint wezterm.lua failed to load'
    exit 1
  }

  # Key-table gate: prove the real entrypoint's key bindings reached the effective key
  # table. A config that raises at load time makes the CLI fall back to the defaults
  # silently: no stderr text and exit code 0, so the ls-fonts gate above cannot see it
  # (e.g. key='Left' instead of 'LeftArrow' broke every binding while all tests stayed
  # green). Custom bindings are action_callback actions and render as EmitEvent(...) in
  # show-keys, so their presence proves the keys module ran and was accepted.
  $keyText = ''
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $keyText = (& $wez --config-file $entry show-keys 2>&1 | Out-String)
  } finally {
    $ErrorActionPreference = $prevEap
  }
  $missing = @()
  if ($keyText -notmatch 'ALT\s+LeftArrow\s+->\s+EmitEvent') { $missing += 'ALT LeftArrow' }
  if ($keyText -notmatch 'SHIFT \| CTRL\s+\?\s+->\s+EmitEvent') { $missing += 'SHIFT|CTRL ?' }
  # CTRL Q closes the current pane, CTRL H opens the SSH host picker, CTRL Y cycles the
  # SSH sort mode. Any action that fails to construct at load time makes the whole config
  # silently fall back to the default key table, so all of these lines must really appear
  # in show-keys. CTRL A is deliberately unbound (no select-all).
  if ($keyText -notmatch 'CTRL\s+Q\s+->\s+EmitEvent') { $missing += 'CTRL Q' }
  if ($keyText -notmatch 'CTRL\s+H\s+->\s+EmitEvent') { $missing += 'CTRL H' }
  if ($keyText -notmatch 'CTRL\s+Y\s+->\s+EmitEvent') { $missing += 'CTRL Y' }
  if ($missing.Count -gt 0) {
    Write-Host ('show-keys is missing custom bindings: ' + ($missing -join ', '))
    Write-Error 'real entrypoint keys not applied (show-keys shows defaults)'
    exit 1
  }

  Write-Host 'ALL PASS'
  exit 0
} finally {
  # The suite writes its results to a guid-named TEMP file; never leave it behind,
  # including when a gate above exits early or throws.
  Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
}
