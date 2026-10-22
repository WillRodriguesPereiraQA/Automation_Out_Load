# Automation Out Load

Testes de carga com **JMeter** contra o site de demonstração [BlazeDemo](https://www.blazedemo.com), simulando reserva de voos (GET home + POST `reserve.php`).

Sript reprodutível, relatório HTML, execução local (Windows) e pipelines no **GitHub Actions**.

## Estrutura

```text
jmeter/blazedemo-load-test.jmx   # plano de teste (500 VUs padrão, parametrizável)
scripts/
  run-smoke-test.ps1             # validação leve (~40 s) + quality gate
  run-load-test.ps1              # 500×5 min em http://127.0.0.1:8080
  local-target.py                # servidor local do perfil de carga
  quality-gate.ps1               # erro + p95 do fluxo (Windows)
  evaluate-quality-gate.py       # erro + p95 do fluxo (CI)
  jmeter-ci.sh                   # mesmo fluxo para Linux / CI
docs/
  RELATORIO_E_ANALISE.md         # plano, métricas e análise das execuções
  GITHUB_ACTIONS.md              # detalhes dos workflows
reports/html-report/             # último dashboard gerado localmente (não versionado)
results/                         # arquivos .jtl (não versionados)
.github/workflows/               # smoke em PR + carga manual autorizada
```

## Pré-requisitos

- **Java 8+** (recomendado 21)
- **JMeter 5.6.3** — Windows: `winget install DEVCOM.JMeter`
- **Python 3** — sobe o alvo local da carga completa

## Executar localmente (Windows)

Na raiz do repositório:

```powershell
.\scripts\run-smoke-test.ps1
.\scripts\run-load-test.ps1
```

O smoke usa 5 usuários por 30 s no demo público. A carga de 500 usuários por 5 minutos sobe `scripts/local-target.py` e fala com **http://127.0.0.1:8080** na máquina de quem executa. No demo público, sem `-AuthorizePublicTarget`, só inicia validação leve: até 10 usuários e 60 s. Os dois scripts reprovam se a taxa de erro ou o p95 do fluxo passar do limite (smoke: 0% e 3000 ms; carga: 2% e 3000 ms).

## CI/CD

| Workflow | Quando | Objetivo |
|----------|--------|----------|
| `jmeter-smoke.yml` | PR (mudanças em `jmeter/` ou no gate) | Validação leve no demo; falha se erro **> 0%** ou p95 do fluxo **> 3000 ms** |
| `jmeter-load.yml` | Manual | 500×5 min em **127.0.0.1:8080**; falha se erro **> 2%** ou p95 do fluxo **> 3000 ms** |

Ver [docs/GITHUB_ACTIONS.md](docs/GITHUB_ACTIONS.md).

## Relatório e entrega

- Abrir `reports/html-report/index.html` após o teste completo.
- Análise consolidada (3 execuções reais, gargalos e conclusão): [docs/RELATORIO_E_ANALISE.md](docs/RELATORIO_E_ANALISE.md).

## Observação

O BlazeDemo é um **servidor compartilhado**. A validação leve pode usar esse demo. O perfil de **500 usuários por 5 minutos** usa `127.0.0.1` na máquina de quem executa o teste.
