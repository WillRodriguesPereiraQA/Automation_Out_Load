. "$PSScriptRoot\set-jmeter-env.ps1"
$Root = Split-Path -Parent $PSScriptRoot
$Plan = Join-Path $Root "jmeter\blazedemo-load-test.jmx"
$ResultsDir = Join-Path $Root "results"
$ReportsDir = Join-Path $Root "reports\smoke-report"
$Jtl = Join-Path $ResultsDir "smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss').jtl"

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
if (Test-Path $ReportsDir) { Remove-Item -Recurse -Force $ReportsDir }

Write-Host "Smoke: 5 threads, 10s ramp, 30s duration"
$JmeterBat = Join-Path $env:JMETER_HOME "bin\jmeter.bat"
& $JmeterBat @("-n", "-t", $Plan, "-l", $Jtl, "-e", "-o", $ReportsDir, "-Jthreads=5", "-Jrampup=10", "-Jduration=30")

Write-Host "Relatorio: $ReportsDir\index.html"
