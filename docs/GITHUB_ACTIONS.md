# JMeter no GitHub Actions

Visão geral do repositório: [README.md](../README.md).

## Workflows

| Arquivo | Gatilho | Carga | Falha o job se |
|---------|---------|-------|----------------|
| `jmeter-smoke.yml` | PR / push em `main` (só se `jmeter/` ou scripts mudarem) | 5 VUs, ramp 10 s, 30 s | **error rate > 0%** |
| `jmeter-load.yml` | Manual (`workflow_dispatch`) ou **segunda 09:00 UTC** | padrão 500 VUs, 60 s, 300 s | **error rate > 2%** (ajustável) |

## Disparar carga completa manualmente

1. GitHub → **Actions** → **JMeter Load (manual / schedule)** → **Run workflow**.
2. Ajuste threads / ramp / duration se necessário.
3. Baixe o artifact **jmeter-load-report-*** (JTL + HTML em `reports/ci-full-load/index.html`).

## Local (equivalente ao CI)

```bash
chmod +x scripts/jmeter-ci.sh
scripts/jmeter-ci.sh 5 10 30 pr-smoke 0
scripts/jmeter-ci.sh 500 60 300 full-load 2
```

## Observações

- O alvo é **BlazeDemo público** — o job de carga usa tolerância de **2%** para não bloquear por instabilidade do demo.
- Runners `ubuntu-latest` têm pouca CPU; 500 threads medem sobretudo o **servidor remoto**, não capacidade real de 500 clientes físicos.
- Para produção, aponte o `.jmx` para **staging próprio** e use smoke estrito (0%) + carga agendada com SLA do seu ambiente.
