---
name: research-us
description: Use when researching US/global stocks or ETFs (fundamentals) in an InvestOS portfolio with market us or ambos enabled.
---

# research-us — fundamentals US/global

Monta um relatorio de fundamentals via MCP Alpha Vantage ja configurado no portfolio. Nao inventa numero e nao monta planilha manual.

## Dados

- MCP: `alpha-vantage` em `<slug>/.mcp.json` (URL `https://mcp.alphavantage.co/mcp?apikey=${ALPHA_VANTAGE_API_KEY}`).
- Credencial: placeholder `ALPHA_VANTAGE_API_KEY` em `<slug>/.env`. Sem chave preenchida, pare e peca o valor — nao chame a API.
- Ferramentas tipicas: OVERVIEW (fundamentals) e GLOBAL_QUOTE (preco). Nao faca chamada HTTP fora do MCP.

## Relatorio

Para cada ticker pedido, extraia (quando o MCP devolver): preco, market cap, P/E, EPS, profit margin, 52-week range. Campo ausente = declare ausente.

## Falha

Se `.mcp.json` nao existir, o server `alpha-vantage` nao estiver declarado, ou o MCP recusar a chamada, deixe o erro visivel. Nunca preencha fundamentals com yfinance "no jeito" — esta skill e so Alpha Vantage.
