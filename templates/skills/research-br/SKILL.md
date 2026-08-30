---
name: research-br
description: Use when researching Brazilian stocks, ETFs, FIIs or funds (fundamentals) in an InvestOS portfolio with market br or ambos enabled.
---

# research-br — fundamentals BR

Monta um relatorio de fundamentals a partir dos dados ja disponiveis no portfolio. Nao inventa numero e nao monta planilha manual.

## Dados

- Acoes/ETFs/FIIs: `bin/brapi-quote.sh <slug> <ticker>` (PETR4, VALE3, MGLU3, ITUB4 sem token; demais exigem `BRAPI_TOKEN` em `<slug>/.env`).
- Fundos: `bin/cvm-informe.sh <slug>` filtrado por `<slug>/watchlist-fundos.json`.

Rode os comandos a partir da raiz do InvestOS, nao de dentro da pasta do portfolio.

## Relatorio

Para cada ticker/fundo pedido, extraia do JSON (quando existir): preco/cota, PL, earnings/priceEarnings, variacao, data do dado. Se o campo nao vier na resposta, diga que esta ausente — nao calcule no chute.

## Falha e cache

Se o client falhar (API fora, token ausente, watchlist vazia), deixe a mensagem de erro visivel. Dado de cache so entra no relatorio com a idade avisada; nunca apresente cache velho como cotacao ao vivo.
