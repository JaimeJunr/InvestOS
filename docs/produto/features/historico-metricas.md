[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Histórico e Métricas Avançadas

**Prioridade:** P1. 6ª feature — foi adicionada depois das 5 originais, numa iteração de PRD
separada (ver [a decisão de mecanismo de MCP](../decisao-mecanismo-mcp-e-enum-mercado.md) para o
padrão de como essas iterações funcionam). Diferente das outras, esta depende de **acumular dado
ao longo do tempo** — não tem retroatividade, então métricas de histórico só ficam úteis depois de
algumas semanas/meses de uso real.

## Duas infraestruturas de dado novas

- **`bin/nav-snapshot.sh <slug>`** — registra o valor total atual da carteira (reaproveita
  `bin/alocacao.sh`) em `<slug>/nav-historico.json`. Rodar mais de uma vez no mesmo dia sobrescreve
  a entrada daquele dia com o valor mais recente — nunca duplica, nunca faz média.
- **`bin/transacao.sh <slug> registrar <tipo> <valor> [data]`** — log manual de
  aportes/resgates/compras/vendas em `<slug>/transacoes.json` (`tipo` ∈
  `aporte|resgate|compra|venda`). O InvestOS não executa ordem, então esse registro depende de
  você contar pro sistema o que já fez.

## Benchmark, para os dois mercados

- **`bin/benchmark-quote.sh <slug> br`** — histórico do Ibovespa (`^BVSP`) via brapi.dev, mesmo
  mecanismo já usado pra ações BR (até 3 meses no free tier).
- **`bin/benchmark-quote.sh <slug> us`** — S&P 500 (`^GSPC`). Não existe fonte oficial gratuita —
  a função `INDEX_DATA` da Alpha Vantage que cobriria isso é premium-only, mesmo com uma chave
  gratuita conectada via MCP; o fallback documentado é yfinance, não-oficial e sem quota garantida.

## As 4 categorias de métricas

| Comando | O que reporta | Depende de |
|---------|----------------|------------|
| `bin/diagnostico.sh` | Concentração no maior ativo, exposição br/us, % em liquidez D+0/D+1, dividend yield 12m | só `holdings.json` atual |
| `bin/contra-benchmark.sh` | Beta, Alfa, R², Tracking Error | `nav-historico.json` + benchmark |
| `bin/retorno.sh` | TWR (retorno ponderado pelo tempo) e MWR (ponderado pelo dinheiro) | `nav-historico.json` + `transacoes.json` |
| `bin/eficiencia.sh` | Sortino, giro de carteira, alíquota efetiva de IR | `nav-historico.json` + `transacoes.json` |

Toda métrica que dependa de histórico ainda não acumulado reporta a string `"histórico
insuficiente"` (ou `"dado insuficiente"`, pra giro/alíquota) — nunca calcula um número instável ou
inventado.

## O que esta feature explicitamente não faz

- **Nenhuma métrica vira regra prescritiva.** `bin/diagnostico.sh` reporta "42% concentrado em
  PETR4" — nunca "você não deveria passar de X%". Isso vale pra toda a feature, não só essa
  métrica: nenhum threshold de alocação por perfil, nenhuma recomendação de "prefira X sobre Y"
  entra em código ou em texto de skill. Todo o material de "fatores de sucesso", "manutenção de
  resultado", "reversão de fracasso" e "construção de portfólio ideal (Markowitz)" trazido durante
  o planejamento cai sob esse mesmo non-goal — vira conhecimento geral do agente, não vira parte do
  InvestOS.
- **Não calcula Imposto de Renda devido de verdade.** A alíquota efetiva de `bin/eficiencia.sh`
  usa `impostoPago`/`ganhoRealizado` só se você os registrar manualmente em `transacoes.json` — sem
  isso, "dado insuficiente". Compensação de prejuízo (DARF) fica fora de escopo.
- **Sem backfill retroativo.** `nav-historico.json` e `transacoes.json` nascem vazios; a série
  começa a existir a partir de quando você começa a usar a feature.
