# Executa teste de carga BlazeDemo (500 usuarios / 5 min) e gera relatorio HTML
param(
    [int]$Threads = 500,
    [int]$RampUp = 60,
    [int]$Duration = 300
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\set-jmeter-env.ps1"
$Root = Split-Path -Parent $PSScriptRoot

$Plan = Join-Path $Root "jmeter\blazedemo-load-test.jmx"
$ResultsDir = Join-Path $Root "results"
$ReportsDir = Join-Path $Root "reports\html-report"
$Jtl = Join-Path $ResultsDir "blazedemo-load-$(Get-Date -Format 'yyyyMMdd-HHmmss').jtl"
$Log = Join-Path $ResultsDir "jmeter-run.log"

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
if (Test-Path $ReportsDir) {
    Remove-Item -Recurse -Force $ReportsDir
}

Write-Host "Plano: $Plan"
Write-Host "JTL:   $Jtl"
Write-Host "HTML:  $ReportsDir"
Write-Host "Carga: $Threads threads, ramp ${RampUp}s, duracao ${Duration}s"
Write-Host "Iniciando teste..."

$JmeterBat = Join-Path $env:JMETER_HOME "bin\jmeter.bat"
& $JmeterBat @(
    "-n", "-t", $Plan, "-l", $Jtl, "-j", $Log, "-e", "-o", $ReportsDir,
    "-Jthreads=$($Threads)", "-Jrampup=$($RampUp)", "-Jduration=$($Duration)"
)

Write-Host "Concluido."
Write-Host "Abra o relatorio: $ReportsDir\index.html"
