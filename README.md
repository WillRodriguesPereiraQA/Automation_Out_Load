# Automation Out Load

Testes de carga com **JMeter** contra o site de demonstração [BlazeDemo](https://www.blazedemo.com), simulando reserva de voos (GET home + POST `reserve.php`).

Sript reprodutível, relatório HTML, execução local (Windows) e pipelines no **GitHub Actions**.

## Estrutura

```text
jmeter/blazedemo-load-test.jmx   # plano de teste (500 VUs padrão, parametrizável)
scripts/
  run-smoke-test.ps1             # validação rápida (~40 s)
  run-load-test.ps1              # carga completa (~6 min) + HTML
  jmeter-ci.sh                   # mesmo fluxo para Linux / CI
docs/
  RELATORIO_E_ANALISE.md         # plano, métricas e análise das execuções
  GITHUB_ACTIONS.md              # detalhes dos workflows
reports/html-report/             # último dashboard gerado localmente (não versionado)
results/                         # arquivos .jtl (não versionados)
.github/workflows/               # smoke em PR + carga manual/agendada
```

## Pré-requisitos

- **Java 8+** (recomendado 21)
- **JMeter 5.6.3** — Windows: `winget install DEVCOM.JMeter`

## Executar localmente (Windows)

Na raiz do repositório:

```powershell
.\scripts\run-smoke-test.ps1   # 5 usuários, 30 s
.\scripts\run-load-test.ps1    # 500 usuários, 5 min → reports/html-report/index.html
```

Parâmetros opcionais no load: `.\scripts\run-load-test.ps1 -Threads 100 -RampUp 30 -Duration 120`

## CI/CD

| Workflow | Quando | Objetivo |
|----------|--------|----------|
| `jmeter-smoke.yml` | PR (mudanças em `jmeter/`) | Garantir que o script roda; **0%** de erro |
| `jmeter-load.yml` | Manual ou segundas 09:00 UTC | Carga 500×5 min; falha se erro **> 2%** |

Ver [docs/GITHUB_ACTIONS.md](docs/GITHUB_ACTIONS.md).

## Relatório e entrega

- Abrir `reports/html-report/index.html` após o teste completo.
- Análise consolidada (3 execuções reais, gargalos e conclusão): [docs/RELATORIO_E_ANALISE.md](docs/RELATORIO_E_ANALISE.md).

## Observação

O BlazeDemo é um **servidor compartilhado**. Resultados variam entre execuções;
