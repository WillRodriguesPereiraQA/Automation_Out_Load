# Politica de alvo e quality gate (taxa de erro + p95 do fluxo).
# Percentil nearest-rank: ceil(percentil/100 * n), base 1. Igual a evaluate-quality-gate.py.
# O p99 do fluxo e apenas informado.

function Resolve-LoadTargetHost {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$HostName)
    $normalized = $HostName.Trim().ToLowerInvariant()
    $normalized = $normalized -replace '^https?://', ''
    $normalized = ($normalized -split '/')[0]
    $normalized = ($normalized -split ':')[0]
    if ($normalized -notmatch '^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$') {
        throw "REPROVADO: host invalido: '$HostName'."
    }
    return $normalized
}

function Test-PublicDemoHost {
    param([Parameter(Mandatory = $true)][string]$HostName)
    return ($HostName -eq "blazedemo.com" -or $HostName.EndsWith(".blazedemo.com"))
}

function Test-LightProfile {
    param([Parameter(Mandatory = $true)][int]$Threads, [Parameter(Mandatory = $true)][int]$Duration)
    return ($Threads -le 10 -and $Duration -le 60)
}

function Assert-FullLoadTargetAllowed {
    param(
        [Parameter(Mandatory = $true)][int]$Threads,
        [Parameter(Mandatory = $true)][int]$Duration,
        [Parameter(Mandatory = $true)][string]$TargetHost,
        [bool]$AuthorizePublicTarget = $false
    )
    $TargetHost = Resolve-LoadTargetHost $TargetHost
    $publicDemo = Test-PublicDemoHost -HostName $TargetHost
    if ($publicDemo -and -not $AuthorizePublicTarget -and -not (Test-LightProfile -Threads $Threads -Duration $Duration)) {
        throw ("REPROVADO: no demo publico, sem autorizacao explicita, so a validacao leve (ate 10 usuarios e 60 s) pode iniciar.`n" +
            "Alvo atual: $TargetHost. Pedido: $Threads usuarios por $Duration s.`n" +
            "Para este alvo, use .\scripts\run-smoke-test.ps1.`n" +
            "A carga completa (500 usuarios / 5 min) exige -TargetHost de um ambiente controlado ou -AuthorizePublicTarget.")
    }
    if ($Threads -ge 500 -and $Duration -ge 300) {
        $profile = "carga completa"
    }
    elseif (Test-LightProfile -Threads $Threads -Duration $Duration) {
        $profile = "validacao leve"
    }
    else {
        $profile = "carga intermediaria"
    }
    if ($publicDemo -and $AuthorizePublicTarget) {
        Write-Host "Alvo: $TargetHost (demo publico, autorizacao explicita). Perfil: $profile."
    }
    elseif ($publicDemo) {
        Write-Host "Alvo: $TargetHost. Perfil: ${profile}: $Threads usuarios, $Duration s."
    }
    else {
        Write-Host "Alvo: $TargetHost (ambiente controlado). Perfil: $profile."
    }
}

function Get-NearestRankPercentile {
    param(
        [Parameter(Mandatory = $true)][double[]]$Values,
        [Parameter(Mandatory = $true)][double]$Percentile
    )
    $sorted = @($Values | Sort-Object)
    $count = $sorted.Count
    if ($count -eq 0) {
        throw "Percentil sem amostras."
    }
    $rank = [int][Math]::Ceiling(($Percentile / 100.0) * $count)
    if ($rank -lt 1) { $rank = 1 }
    if ($rank -gt $count) { $rank = $count }
    return [double]$sorted[$rank - 1]
}

function Assert-JtlQualityGate {
    param(
        [Parameter(Mandatory = $true)][string]$JtlPath,
        [Parameter(Mandatory = $true)][double]$MaxErrorRatePercent,
        [Parameter(Mandatory = $true)][double]$MaxFlowP95Ms,
        [string]$FlowLabel = "TX - Fluxo completo reserva"
    )
    if (-not (Test-Path -LiteralPath $JtlPath)) {
        throw "REPROVADO: JTL nao encontrado: $JtlPath"
    }
    $rows = @(Import-Csv -LiteralPath $JtlPath)
    if ($rows.Count -eq 0) {
        throw "REPROVADO: nenhuma amostra no JTL."
    }
    $columns = @($rows[0].PSObject.Properties.Name)
    foreach ($required in @("elapsed", "label", "success")) {
        if ($columns -notcontains $required) {
            throw "REPROVADO: JTL sem a coluna '$required'."
        }
    }

    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $failures = @($rows | Where-Object { $_.success.Trim().ToLowerInvariant() -eq "false" }).Count
    $total = $rows.Count
    $rate = ($failures / [double]$total) * 100.0
    Write-Host ("Samples: {0}  Failures: {1}  Error rate: {2}%  (max {3}%)" -f $total, $failures, $rate.ToString("0.0000", $invariant), $MaxErrorRatePercent.ToString("0.0000", $invariant))

    $flow = @(
        $rows |
            Where-Object { $_.label -eq $FlowLabel } |
            ForEach-Object { [double]::Parse($_.elapsed, $invariant) }
    )
    if ($flow.Count -eq 0) {
        throw "REPROVADO: nenhuma amostra do fluxo '$FlowLabel'."
    }

    $p95 = Get-NearestRankPercentile -Values $flow -Percentile 95
    $p99 = Get-NearestRankPercentile -Values $flow -Percentile 99
    Write-Host ("Flow '{0}': samples={1}  p95={2} ms  p99={3} ms  (max p95 {4} ms)" -f $FlowLabel, $flow.Count, $p95.ToString("0", $invariant), $p99.ToString("0", $invariant), $MaxFlowP95Ms.ToString("0", $invariant))

    $failed = $false
    if ($rate -gt ($MaxErrorRatePercent + 0.00001)) {
        Write-Host ("REPROVADO: taxa de erro {0}% excede o maximo {1}%." -f $rate.ToString("0.0000", $invariant), $MaxErrorRatePercent.ToString("0.0000", $invariant))
        $failed = $true
    }
    if ($p95 -gt ($MaxFlowP95Ms + 0.00001)) {
        Write-Host ("REPROVADO: p95 do fluxo {0} ms excede o maximo {1} ms." -f $p95.ToString("0", $invariant), $MaxFlowP95Ms.ToString("0", $invariant))
        $failed = $true
    }
    if ($failed) {
        throw "REPROVADO: quality gate de performance."
    }
    Write-Host "APROVADO: taxa de erro e p95 do fluxo dentro dos limites."
}
