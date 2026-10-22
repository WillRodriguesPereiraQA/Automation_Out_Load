# Executa o perfil de carga (padrao 500 usuarios / 5 min) contra http://127.0.0.1:8080.
# O servidor local sobe na propria maquina e encerra ao final.
param(
    [int]$Threads = 500,
    [int]$RampUp = 60,
    [int]$Duration = 300,
    [string]$TargetHost = "127.0.0.1",
    [string]$Protocol = "",
    [int]$Port = 0,
    [switch]$AuthorizePublicTarget,
    [double]$MaxErrorRatePercent = 2,
    [double]$MaxFlowP95Ms = 3000
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\quality-gate.ps1"

function Resolve-PythonLauncher {
    $candidates = @(
        @{ Name = "py"; Prefix = @("-3") },
        @{ Name = "python"; Prefix = @() },
        @{ Name = "python3"; Prefix = @() }
    )
    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate.Name -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        & $cmd.Source @($candidate.Prefix) -c "import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)"
        if ($LASTEXITCODE -eq 0) {
            return @{ Executable = $cmd.Source; Prefix = $candidate.Prefix }
        }
    }
    throw "Python 3 nao encontrado. A carga em 127.0.0.1 sobe scripts\local-target.py."
}

function Start-LocalTarget {
    param(
        [Parameter(Mandatory = $true)][int]$ListenPort,
        [Parameter(Mandatory = $true)][string]$ScriptPath
    )
    $python = Resolve-PythonLauncher
    $stdout = Join-Path $env:TEMP "local-target-stdout.txt"
    $stderr = Join-Path $env:TEMP "local-target-stderr.txt"
    $proc = Start-Process -FilePath $python.Executable `
        -ArgumentList (@($python.Prefix) + @($ScriptPath, "$ListenPort")) `
        -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = (Get-Date).AddSeconds(15)
    do {
        if ($proc.HasExited) {
            $detail = ""
            if (Test-Path -LiteralPath $stderr) { $detail = Get-Content -Raw -LiteralPath $stderr }
            throw "Alvo local encerrou antes de escutar. $detail"
        }
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $client.Connect("127.0.0.1", $ListenPort)
            return $proc
        }
        catch {
            Start-Sleep -Milliseconds 200
        }
        finally {
            $client.Dispose()
        }
    } while ((Get-Date) -lt $deadline)
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    throw "Alvo local nao escutou em 127.0.0.1:${ListenPort}."
}

$resolvedHost = Resolve-LoadTargetHost $TargetHost
$isLoopback = $resolvedHost -eq "127.0.0.1" -or $resolvedHost -eq "localhost"
if (-not $Protocol) {
    if ($isLoopback) { $Protocol = "http" } else { $Protocol = "https" }
}
$Protocol = $Protocol.Trim().ToLowerInvariant()
if ($Protocol -notin @("http", "https")) {
    throw "Protocolo invalido: $Protocol"
}
if ($Port -eq 0) {
    if ($isLoopback -and $Protocol -eq "http") { $Port = 8080 } else { $Port = 443 }
}
if ($Port -lt 1 -or $Port -gt 65535) {
    throw "Porta invalida: $Port"
}

Assert-FullLoadTargetAllowed -Threads $Threads -Duration $Duration -TargetHost $resolvedHost -AuthorizePublicTarget ([bool]$AuthorizePublicTarget)

. "$PSScriptRoot\set-jmeter-env.ps1"
$Root = Split-Path -Parent $PSScriptRoot

$Plan = Join-Path $Root "jmeter\blazedemo-load-test.jmx"
$ServerScript = Join-Path $PSScriptRoot "local-target.py"
$ResultsDir = Join-Path $Root "results"
$ReportsDir = Join-Path $Root "reports\html-report"
$Jtl = Join-Path $ResultsDir "blazedemo-load-$(Get-Date -Format 'yyyyMMdd-HHmmss').jtl"
$Log = Join-Path $ResultsDir "jmeter-run.log"
$invariant = [Globalization.CultureInfo]::InvariantCulture
$server = $null

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null
if (Test-Path $ReportsDir) {
    Remove-Item -Recurse -Force $ReportsDir
}

try {
    if ($isLoopback -and $Protocol -eq "http") {
        Write-Host "Subindo alvo local http://127.0.0.1:${Port}"
        $server = Start-LocalTarget -ListenPort $Port -ScriptPath $ServerScript
    }

    Write-Host "Plano: $Plan"
    Write-Host "JTL:   $Jtl"
    Write-Host "HTML:  $ReportsDir"
    Write-Host "Carga: $Threads threads, ramp ${RampUp}s, duracao ${Duration}s, ${Protocol}://${resolvedHost}:${Port}"
    Write-Host ("Quality gate: error rate <= {0}% ; p95 do fluxo <= {1} ms" -f $MaxErrorRatePercent.ToString("0.##", $invariant), $MaxFlowP95Ms.ToString("0", $invariant))
    Write-Host "Iniciando teste..."

    $JmeterBat = Join-Path $env:JMETER_HOME "bin\jmeter.bat"
    & $JmeterBat @(
        "-n", "-t", $Plan, "-l", $Jtl, "-j", $Log, "-e", "-o", $ReportsDir,
        "-Jthreads=$($Threads)", "-Jrampup=$($RampUp)", "-Jduration=$($Duration)",
        "-JHOST=$resolvedHost", "-JPROTOCOL=$Protocol", "-JPORT=$Port"
    )
    $jmeterCode = $LASTEXITCODE

    if (-not (Test-Path -LiteralPath $Jtl)) {
        throw "JMeter nao gerou o JTL (codigo $jmeterCode)."
    }

    Assert-JtlQualityGate -JtlPath $Jtl -MaxErrorRatePercent $MaxErrorRatePercent -MaxFlowP95Ms $MaxFlowP95Ms

    if ($jmeterCode -ne 0) {
        throw "JMeter encerrou com codigo $jmeterCode."
    }

    Write-Host "Concluido."
    Write-Host "Abra o relatorio: $ReportsDir\index.html"
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
        Write-Host "Alvo local encerrado."
    }
}
