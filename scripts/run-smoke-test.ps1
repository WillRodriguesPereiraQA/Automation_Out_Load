# Validacao leve: 5 usuarios, 30 s. Quality gate estrito (erro 0% e p95 do fluxo).
param(
    [string]$TargetHost = "www.blazedemo.com",
    [double]$MaxErrorRatePercent = 0,
    [double]$MaxFlowP95Ms = 3000
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\quality-gate.ps1"
$resolvedHost = Resolve-LoadTargetHost $TargetHost

. "$PSScriptRoot\set-jmeter-env.ps1"
$Root = Split-Path -Parent $PSScriptRoot
$Plan = Join-Path $Root "jmeter\blazedemo-load-test.jmx"
$ResultsDir = Join-Path $Root "results"
$ReportsDir = Join-Path $Root "reports\smoke-report"
$Jtl = Join-Path $ResultsDir "smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss').jtl"
$invariant = [Globalization.CultureInfo]::InvariantCulture

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
if (Test-Path $ReportsDir) { Remove-Item -Recurse -Force $ReportsDir }

Write-Host "Smoke: 5 threads, 10s ramp, 30s duration, host $resolvedHost"
Write-Host ("Quality gate: error rate <= {0}% ; p95 do fluxo <= {1} ms" -f $MaxErrorRatePercent.ToString("0.##", $invariant), $MaxFlowP95Ms.ToString("0", $invariant))
$JmeterBat = Join-Path $env:JMETER_HOME "bin\jmeter.bat"
& $JmeterBat @("-n", "-t", $Plan, "-l", $Jtl, "-e", "-o", $ReportsDir, "-Jthreads=5", "-Jrampup=10", "-Jduration=30", "-JHOST=$resolvedHost")
$jmeterCode = $LASTEXITCODE

if (-not (Test-Path -LiteralPath $Jtl)) {
    throw "JMeter nao gerou o JTL (codigo $jmeterCode)."
}

Assert-JtlQualityGate -JtlPath $Jtl -MaxErrorRatePercent $MaxErrorRatePercent -MaxFlowP95Ms $MaxFlowP95Ms

if ($jmeterCode -ne 0) {
    throw "JMeter encerrou com codigo $jmeterCode."
}

Write-Host "Relatorio: $ReportsDir\index.html"
