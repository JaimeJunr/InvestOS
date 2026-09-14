#!/usr/bin/env bash
# Fake de cotacao que devolve payload malformado (status 0) para um ticker
# especifico - reproduz casos reais de provider "respondeu, mas sem preco
# usavel": null (brapi sem regularMarketPrice), tipo errado (string) e chave
# ausente ({}). Sao os tres formatos que a protecao select(type == "number")
# em bin/achados.sh precisa filtrar antes de --argjson (removida, "abc" quebra
# o script com "invalid JSON text"). Demais tickers usam o mesmo arquivo de
# precos do fake-alocacao-quote.sh.
set -euo pipefail

slug="${1:-}"
ticker="${2:-}"
mercado="${3:-}"

if [ -z "$slug" ] || [ -z "$ticker" ] || [ -z "$mercado" ]; then
  echo "fake-alocacao-quote-null-preco: recebido slug='$slug' ticker='$ticker' mercado='$mercado', esperado <slug> <ticker> <mercado>." >&2
  exit 1
fi

if [ -n "${ALOCACAO_QUOTE_LOG:-}" ]; then
  printf '%s %s %s\n' "$slug" "$ticker" "$mercado" >> "$ALOCACAO_QUOTE_LOG"
fi

if [ "$ticker" = "${ALOCACAO_QUOTE_NULL_TICKER:-}" ]; then
  jq -nc '{preco: null}'
  exit 0
fi

if [ "$ticker" = "${ALOCACAO_QUOTE_BAD_TYPE_TICKER:-}" ]; then
  jq -nc '{preco: "abc"}'
  exit 0
fi

if [ "$ticker" = "${ALOCACAO_QUOTE_MISSING_KEY_TICKER:-}" ]; then
  jq -nc '{}'
  exit 0
fi

prices="${ALOCACAO_QUOTE_PRICES:-}"
if [ -z "$prices" ] || [ ! -f "$prices" ]; then
  echo "fake-alocacao-quote-null-preco: recebido ALOCACAO_QUOTE_PRICES='$prices', esperado arquivo JSON {\"TICKER\": preco}." >&2
  exit 1
fi

preco=$(jq -er --arg t "$ticker" '.[$t] // empty' "$prices")
if [ -z "$preco" ]; then
  echo "fake-alocacao-quote-null-preco: ticker '$ticker' ausente em $prices, esperado chave com preco." >&2
  exit 1
fi

jq -nc --argjson preco "$preco" '{preco: $preco}'
