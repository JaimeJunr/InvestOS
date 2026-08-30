# Visão geral de arquitetura

InvestOS não tem servidor, daemon ou banco de dados. Cada portfólio é uma pasta autocontida,
gerada **fora** do clone do InvestOS (mesmo padrão do BizOS: nome puro vai pra
`~/Documents/investos-<nome>`, caminho explícito é respeitado literalmente — ver
[`instalacao/comecando.md`](../instalacao/comecando.md)), e cada operação é um script standalone
invocado como `bin/<comando>.sh <caminho-do-portfolio>`.

## Estrutura de um portfólio

```
<portfolio>/
├── CLAUDE.md
├── _memoria/
├── .env                  # credenciais, gitignored
├── .mcp.json             # config declarativa de MCP (Alpha Vantage, Plaid) — condicional
├── .claude/
│   ├── settings.json
│   ├── skills/
│   └── commands/          # instalar.md (entrevista guiada) + status.md (briefing read-only)
├── portfolio.json        # {"mercado": "br" | "us" | "ambos"}
├── holdings.json          # posições — manual ou sincronizado via corretora
├── alocacao-alvo.json     # alocação-alvo + threshold de rebalanceamento
└── watchlist-fundos.json # opcional — fundos de interesse para o parser da CVM
```

## O padrão declarativo

A decisão mais importante do projeto — documentada em
[`produto/decisao-mecanismo-mcp-e-enum-mercado.md`](../produto/decisao-mecanismo-mcp-e-enum-mercado.md) —
é que **nenhuma integração externa tem client HTTP first-party**. MCPs (Alpha Vantage, Plaid) são
sempre config declarativa: `.mcp.json` referencia o servidor, `.env` guarda a credencial como
placeholder. Quem de fato chama a API é o Claude Code rodando dentro do portfólio, via o MCP.

Como consequência, todo script que precisaria falar com uma dessas APIs aceita em vez disso um
**override de fetch injetável** por variável de ambiente:

| Script | Variável de override | Fallback direto (sem MCP) |
|--------|----------------------|----------------------------|
| `bin/risco.sh` | `RISCO_HISTORY` | `brapi-quote.sh` (ações BR) / `cvm-informe.sh` (fundos BR) |
| `bin/alocacao.sh` | `ALOCACAO_QUOTE` | `brapi-quote.sh` (BR) |
| `bin/holdings-sync.sh` | `HOLDINGS_FETCH` | nenhum — sem credencial, não sincroniza |

Esse mesmo ponto de extensão é o que os testes usam para injetar respostas falsas
(`tests/helpers/fake-*.sh`) — nenhum teste do repositório faz uma chamada de rede real.

## Fontes de dados BR (implementação própria)

Diferente do mercado US/global (só MCP declarativo), o mercado brasileiro tem duas fontes
implementadas diretamente no repositório, escolhidas após um
[spike técnico](../../.ralph/investos/spikes/dados-mercado-br.md) validar viabilidade sem custo:

- **`bin/brapi-quote.sh`** — [brapi.dev](https://brapi.dev), ações/ETFs/FIIs.
- **`bin/cvm-informe.sh`** — [CVM Dados Abertos](https://dados.cvm.gov.br), fundos (ticker = CNPJ
  de 14 dígitos).

## Scripts de relatório: bash + Python

`alocacao.sh` e `risco.sh` seguem o mesmo formato: um script bash resolve e valida os arquivos de
entrada, busca cotações/histórico pelo mecanismo acima, e entrega o payload em JSON para um script
Python (`*-report.py`) que faz o cálculo de verdade (desvio de alocação, VaR/Sharpe/drawdown,
sugestão de rebalanceamento) e imprime o relatório.

## Testes

[Bats](https://github.com/bats-core/bats-core) sobre cada script bash, com helpers
`tests/helpers/fake-*.sh` substituindo qualquer chamada externa. Ver
[`desenvolvimento/contribuindo.md`](../desenvolvimento/contribuindo.md) para como rodar.
