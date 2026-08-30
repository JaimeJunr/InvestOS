# InvestOS

**A Claude Code harness for personal investment portfolios.**

[Português](README.pt-BR.md)

InvestOS generates isolated, self-contained portfolio folders — one per portfolio — each wired
with a curated set of public Claude Code plugins, skills, and MCPs for investment research,
market data, portfolio/risk management, and read-only brokerage integration. No server, no
database: every operation is a standalone script you run against a portfolio folder.

Built in the spirit of [BizOS](https://github.com/JaimeJunr/BizOS) (a Claude Code harness for
small businesses), but for personal investing.

## What it does

- **Generates a new portfolio** with one interactive command — pick which domains to enable
  (research, risk, market data, brokerage) and which market (Brazil, US/global, or both).
- **Curates external plugins/MCPs** instead of building everything from scratch — see
  [`catalog.json`](catalog.json).
- **Covers Brazilian market data directly** ([brapi.dev](https://brapi.dev) for stocks/ETFs/FIIs,
  [CVM Dados Abertos](https://dados.cvm.gov.br) for funds) — no ready-made public MCP existed for
  this, so InvestOS implements it.
- **Computes real risk metrics** — historical VaR, Sharpe ratio, max drawdown, allocation drift,
  rebalancing suggestions — never executes an order.
- **Reads brokerage positions read-only** via a declarative MCP (Plaid / Interactive Brokers),
  with credentials isolated per portfolio and a fail-safe fallback to manual holdings.

## What it explicitly does not do

- Give investment advice or execute trades.
- Build new plugins from scratch for every domain — it curates what already exists publicly.
- Store credentials anywhere but the portfolio's own `.env`.

## Quick start

```bash
git clone https://github.com/JaimeJunr/InvestOS.git
cd InvestOS
bin/setup.sh my-portfolio
cd my-portfolio && claude
```

Then, inside Claude Code, run `/instalar` — a guided interview that sets up your positions,
target allocation, and rebalancing threshold. `/status` gives you a read-only briefing afterwards.

See [`docs/instalacao/comecando.md`](docs/instalacao/comecando.md) for the full walkthrough
(requirements, first commands, credential setup).

## Documentation

Full docs live in [`docs/`](docs/INDEX.md) (Portuguese — matches the codebase's comments and the
author's primary language):

- [Getting started](docs/instalacao/comecando.md)
- [Architecture](docs/arquitetura/visao-geral.md)
- [Contributing](docs/desenvolvimento/contribuindo.md)
- [Product vision & the 5 features](docs/produto/visao-e-motivacao.md)

## How this was built

InvestOS was specified through a formal PRD (CRIA framework) and implemented end-to-end by an
autonomous TDD loop — every user story went through red→green tests, lint, typecheck, and an
independent-reviewer gate with mutation testing before being marked done. Partway through, the
loop hit a genuine architectural ambiguity (no enum for the "market" field, no defined mechanism
for "MCP integrated and functional") and correctly stopped instead of guessing — the ambiguity was
resolved via a PRD update, documented in
[`docs/produto/decisao-mecanismo-mcp-e-enum-mercado.md`](docs/produto/decisao-mecanismo-mcp-e-enum-mercado.md).

## License

[MIT](LICENSE)
