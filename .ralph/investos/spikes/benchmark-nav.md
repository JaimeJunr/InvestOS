# Spike — Viabilidade de dados de benchmark (Ibovespa/S&P 500) para Beta/Alfa/Tracking Error

## Hipóteses

- **H1:** Ibovespa (`^BVSP`) tem histórico diário disponível de graça via brapi.dev, mesmo padrão já
  usado pra ações BR. → validar via docs/free-tier da brapi.
- **H2:** S&P 500 tem histórico diário disponível de graça via Alpha Vantage (mesmo MCP já
  declarado no `.mcp.json` pra mercado US). → validar via docs da Alpha Vantage.
- **H3:** Se H2 falhar, `yfinance` com ticker `^GSPC` cobre o S&P 500 como fallback não-oficial
  (mesmo padrão já aceito pra ações BR no spike anterior). → validar via docs do yfinance.

## Critério de conclusão

Pelo menos 1 fonte viável (sem custo, sem contrato) para o benchmark de cada mercado (BR e
US/global) — ou veredito explícito de inviabilidade/gap se nenhuma existir.

## Evidências (preenchido em 2026-08-30)

**H1 — confirmada.** brapi.dev cobre `^BVSP` (Ibovespa) via `GET /api/quote/%5EBVSP?range=3mo&interval=1d`,
mesmo endpoint/free-tier já usado pra ações (15.000 req/mês, até 3 meses de histórico no plano
gratuito). Histórico mais longo exigiria plano pago da brapi ou o Public Data Hub da B3 (download
manual, não é API JSON conveniente).

**H2 — refutada.** A função `INDEX_DATA` da Alpha Vantage (`function=INDEX_DATA&symbol=SPX`) existe
e retorna OHLC diário, mas é **endpoint premium** — a chave gratuita (25 req/dia) não dá acesso a
histórico de índice. Conectar via MCP com chave gratuita não contorna essa entitlement.

**H3 — confirmada como fallback, com a mesma ressalva já aceita pra ações BR.** `yfinance` com
ticker `^GSPC` funciona pra histórico diário do S&P 500, mas é client não-oficial, sem quota
garantida (mesmo caveat do fallback de ações BR já documentado no projeto).

## Conclusão / decisão

**Viável com escopo assimétrico entre os dois mercados:**

- **Benchmark BR (Ibovespa):** `^BVSP` via brapi.dev — mesmo mecanismo/limite (3 meses) já aceito
  pra ações BR. Beta/Alfa/Tracking Error/R² contra o Ibovespa cabem no v1 desta feature, com o
  mesmo limite de 3 meses de histórico do plano gratuito.
- **Benchmark US (S&P 500):** sem fonte gratuita oficial. Duas opções restam: (a) `yfinance`
  `^GSPC` como fallback não-oficial (mesma ressalva de sempre — sem quota garantida), ou (b)
  declarar como **gap explícito** (mesmo padrão do gap de dados de mercado BR no catálogo) e
  deixar de fora do v1 desta feature. Fica como Open Question `[SE]` pro PRD decidir.

Isso desbloqueia a feature de histórico de NAV/benchmark: BR pode seguir o mesmo padrão de
implementação direta (brapi.dev) já usado no resto do projeto; US precisa de uma decisão explícita
sobre aceitar yfinance não-oficial ou declarar gap.
