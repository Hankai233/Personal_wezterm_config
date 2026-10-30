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

# wezterm 的 CLI 可能很快返回；等结果文件落盘（最多 10 秒）
$deadline = (Get-Date).AddSeconds(10)
while (-not (Test-Path $out) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }

$lines = Get-Content $out -ErrorAction SilentlyContinue
if (-not $lines) { Write-Error "test harness produced no output: $out"; exit 1 }
$lines | ForEach-Object { Write-Host $_ }
$summary = $lines | Where-Object { $_ -like 'SUMMARY*' }
if (-not $summary) { Write-Error 'no SUMMARY line'; exit 1 }
$fails = @($lines | Where-Object { $_ -like 'FAIL*' })
if ($fails.Count -gt 0) { Write-Error ("failed assertions: " + $fails.Count); exit 1 }
Write-Host 'ALL PASS'
exit 0
