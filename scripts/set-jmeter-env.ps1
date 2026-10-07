# Carrega JMETER_HOME para esta sessao (JMeter instalado via winget DEVCOM.JMeter)
$JmeterRoot = "$env:LOCALAPPDATA\Programs\JMeter"
if (-not (Test-Path "$JmeterRoot\bin\jmeter.bat")) {
    throw "JMeter nao encontrado em $JmeterRoot. Instale: winget install DEVCOM.JMeter"
}
$env:JMETER_HOME = $JmeterRoot
$bin = Join-Path $JmeterRoot "bin"
if ($env:Path -notlike "*$bin*") {
    $env:Path = "$bin;$env:Path"
}
Write-Host "JMETER_HOME=$env:JMETER_HOME"
jmeter -v 2>&1 | Select-Object -First 3
