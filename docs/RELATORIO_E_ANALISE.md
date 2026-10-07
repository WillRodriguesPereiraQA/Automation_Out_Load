# Testes Automatizados de Carga — BlazeDemo (JMeter)

## Tarefa 1 — Plano de teste

| Item | Configuração |
|------|----------------|
| Alvo | `https://www.blazedemo.com` |
| Usuários simultâneos | **500** threads (via `-Jthreads` / propriedade) |
| Duração | **300 s** (5 min), scheduler ativo |
| Ramp-up | **60 s** |
| Cenário | GET `/` → POST `/reserve.php` (Paris → Buenos Aires) |
| Think time | 1–3 s entre iterações |
| Artefato | `jmeter/blazedemo-load-test.jmx` |

### Qualidade do script

- Variáveis (`HOST`, `PROTOCOL`, `FROM_PORT`, `TO_PORT`) no Test Plan.
- Cookie Manager, Cache Manager e Keep-Alive.
- **Transaction Controller** (`TX - Fluxo completo reserva`) para tempo de negócio.
- Assertions: HTTP 200; duração máxima 5 s (home) e 8 s (POST).
- Timeouts: connect 10 s, response 30 s.
- Relatório HTML via CLI: `-e -o reports/html-report`.

### Métricas principais

| Métrica | Uso |
|---------|-----|
| Throughput (req/s) | Capacidade sob carga |
| P90 / P95 / P99 | Experiência e cauda longa |
| Error % | HTTP, timeouts e falhas de assertion |
| Connect Time | Rede vs saturação do servidor |

---

## Tarefa 2 — Como gerar o relatório

### Local (Windows)

```powershell
.\scripts\run-smoke-test.ps1
.\scripts\run-load-test.ps1
```

Dashboard: `reports/html-report/index.html`  
JTL mais recente (última carga local): `results/blazedemo-load-20261007-170535.jtl`

### CI (GitHub Actions)

Smoke em PR e carga manual/agendada — ver [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md).

---

## Execuções realizadas (500 VUs / 5 min)

Ambiente local: **Windows 11**, **JMeter 5.6.3**, **OpenJDK 21**, 12 CPUs lógicas.

| # | JTL | Horário (BRT) | Amostras | Error % | P95 TX (ms) | Throughput total (req/s) | Observação |
|---|-----|---------------|----------|---------|-------------|---------------------------|------------|
| 1 | `blazedemo-load-20261007-164429.jtl` | 16:44–16:49 | 55 659 | **0,011** | 1 259 | 185,7 | 6 falhas: GET lento + `NoHttpResponseException` |
| 2 | `blazedemo-load-20261007-165712.jtl` | 16:57–17:02 | 55 221 | **0,002** | 1 443 | 184,6 | 1 falha: `NoHttpResponseException` no POST |
| 3 | `blazedemo-load-20261007-170535.jtl` | 17:05–17:10 | 50 739 | **1,017** | 3 012 | 169,4 | 516 falhas: mostly **Duration Assertion** (servidor lento) |

O relatório HTML em `reports/html-report/` reflete a **execução 3** (última rodada).

### Tabela detalhada — execução 1 (melhor equilíbrio latência/erro)

| Label | Samples | Error % | Throughput | Avg (ms) | P90 | P95 | P99 |
|-------|---------|---------|------------|----------|-----|-----|-----|
| GET `/` | 27 702 | 0,022 | 92,6 | 442 | 581 | 680 | 924 |
| POST `reserve.php` | 27 457 | 0,00 | 92,3 | 440 | 580 | 675 | 912 |
| TX fluxo | 27 912 | 0,021 | 92,6 | 896 | 1 114 | 1 259 | 2 243 |
| **Total** | **55 659** | **0,011** | **185,7** | 452 | 599 | 709 | 2 152 |

### Tabela detalhada — execução 3 (última; pior dia do demo)

| Label | Samples | Error % | Throughput | Avg (ms) | P90 | P95 | P99 |
|-------|---------|---------|------------|----------|-----|-----|-----|
| GET `/` | 25 238 | 1,696 | 84,3 | 685 | 898 | 1 309 | 6 007 |
| POST `reserve.php` | 25 001 | 0,352 | 84,1 | 683 | 921 | 1 405 | 6 123 |
| TX fluxo | 25 466 | 2,007 | 84,5 | 1 374 | 1 980 | 3 012 | 8 282 |
| **Total** | **50 739** | **1,017** | **169,4** | 692 | 750 | 1 033 | 5 034 |

---

## Análise consolidada

### Throughput

Nas execuções 1 e 2, o throughput ficou estável (~**184–186 req/s** agregados, ~**92 req/s** por sampler). Na execução 3 caiu para ~**169 req/s** com latência maior — sinal de **degradação do host de demo**, não de falha do plano JMeter.

### Latência

Comportamento típico: GET e POST com médias próximas (~440–680 ms); o TX soma as etapas (P95 entre **~1,3 s e 3,0 s** conforme a execução). P99 do TX pode ultrapassar **5–8 s** quando o servidor está sob stress.

### Erros

| Tipo | Quando apareceu |
|------|-----------------|
| **Duration Assertion** (HTTP 200, tempo > limite) | Predominante na execução 3 |
| **`NoHttpResponseException`** | Execuções 1 e 2 (pontual) |
| **POST sem erro HTTP** | Execução 1; execução 2 com 1 falha de conexão |

As falhas correlacionam-se com **500 threads ativas** e limites do **BlazeDemo público**, não com erro de URL ou parâmetros do formulário.

### Gargalos identificados

1. **Recurso mais sensível:** GET `/` e fluxo TX (inclui picos na home).
2. **Sintoma:** error rate de **~0,01%** a **~1%** entre runs; P95 TX até **~3 s** no pior caso.
3. **Causa provável:** capacidade variável do servidor de demonstração + assertions de SLA (5 s / 8 s).
4. **Mitigações:** ramp-up maior; testes escalonados; repetir execuções e usar mediana de runs; em projeto real, alvo **staging próprio**.

---

## Conclusão

O plano JMeter atende ao objetivo pedido (**500 usuários simultâneos por 5 minutos**) e gera métricas acionáveis (throughput, percentis, erros por label). O BlazeDemo **suportou a carga na maioria das execuções** com error rate **&lt; 0,02%** (runs 1 e 2) e P95 TX **&lt; 1,5 s**, atendendo critérios usuais (**error &lt; 1%**, **P95 TX &lt; 3 s**). A **execução 3** mostra que o mesmo script, no mesmo cliente, pode **reprovar** critério de 1% em dias de instabilidade do demo (**~1,02%** de erro).

**Resultado pedagógico:** script e relatório adequados; **SLA sobre site de terceiros** deve ser interpretado com tolerância ou substituído por ambiente controlado. O CI reflete isso: smoke estrito em PR, carga completa com limiar **2%** de erro.

---

## Entrega

| Item | Caminho |
|------|---------|
| Script JMeter | `jmeter/blazedemo-load-test.jmx` |
| Evidências | `results/blazedemo-load-*.jtl` (local) |
| Dashboard | `reports/html-report/index.html` |
| Análise | Este arquivo |
| Automação CI | `.github/workflows/jmeter-smoke.yml`, `jmeter-load.yml` |
