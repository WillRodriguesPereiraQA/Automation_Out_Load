# JMeter no GitHub Actions

Visão geral do repositório: [README.md](../README.md).

## Workflows

| Arquivo | Gatilho | Carga | Quality gate |
|---------|---------|-------|----------------|
| `jmeter-smoke.yml` | PR / push em `main` (se `jmeter/` ou o gate mudarem) | 5 VUs, ramp 10 s, 30 s, demo público | erro **> 0%** ou p95 do fluxo **> 3000 ms** |
| `jmeter-load.yml` | Manual (`workflow_dispatch`) | padrão 500 VUs, 60 s, 300 s em `127.0.0.1:8080` | erro **> 2%** ou p95 do fluxo **> 3000 ms** |

O p95 é o da transação `TX - Fluxo completo reserva` (tempo do fluxo, sem think time). O p99 do mesmo fluxo aparece no log. A decisão de latência usa o p95, no critério já adotado na análise (`P95 TX < 3 s`). O percentil é nearest-rank sobre o `elapsed` do JTL: posição `ceil(0,95 × n)`.

## Ambiente da carga completa

O padrão da carga completa é **http://127.0.0.1:8080**. O job sobe `scripts/local-target.py` no runner, que escuta só nessa interface. Quem clonar o repositório em outra máquina usa o mesmo endereço e atinge o processo local dela.

No demo público (`blazedemo.com` e subdomínios), sem **authorize_public_target**, só inicia a validação leve: até **10 usuários** e **60 s**. Para apontar a carga completa ao demo, troque o host para `www.blazedemo.com`, o protocolo para `https`, a porta para `443` e marque a autorização.

O job encerra antes do JMeter quando a combinação de alvo e perfil não é permitida. O smoke segue como validação leve contra o demo. A carga completa não tem agendamento.

A autorização libera o alvo. O quality gate de erro e de p95 continua valendo. Os limiares podem ser ajustados no disparo quando o SLA do ambiente controlado for outro.

## Disparar carga completa manualmente

1. GitHub → **Actions** → **JMeter Load (manual)** → **Run workflow**.
2. O host padrão já é `127.0.0.1` (protocolo `http`, porta `8080`). Mude esses campos só para outro ambiente.
3. Ajuste threads, ramp, duration, taxa de erro e p95 se precisar.
4. Baixe o artifact **jmeter-load-report-*** (JTL + HTML em `reports/ci-full-load/index.html`).

## Local (equivalente ao CI)

```bash
chmod +x scripts/jmeter-ci.sh
scripts/jmeter-ci.sh 5 10 30 pr-smoke 0 3000
TARGET_HOST=127.0.0.1 PROTOCOL=http PORT=8080 scripts/jmeter-ci.sh 500 60 300 full-load 2 3000
AUTHORIZE_PUBLIC_TARGET=true scripts/jmeter-ci.sh 500 60 300 full-load 2 3000 www.blazedemo.com
```

No Windows:

```powershell
.\scripts\run-smoke-test.ps1
.\scripts\run-load-test.ps1
```

## Observações

- O limiar de **2%** de erro na carga completa absorve instabilidade pontual. Na execução 3 do relatório, o erro ficou em cerca de **1,02%** (passaria nesse limiar) e o p95 do fluxo em **3012 ms** (reprova no gate de latência).
- No alvo local, 500 threads medem o `local-target.py` e a máquina que executa o JMeter.
- O plano lê host, protocolo e porta em `${__P(HOST)}`, `${__P(PROTOCOL)}` e `${__P(PORT)}`. Sem essas propriedades, o padrão do plano continua `https://www.blazedemo.com:443` (smoke).
