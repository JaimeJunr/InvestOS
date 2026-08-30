#!/usr/bin/env bash
# Fake nomeado de cotacao para o relatorio de alocacao. Nao faz I/O de rede.
set -euo pipefail

slug="${1:-}"
ticker="${2:-}"
mercado="${3:-}"

if [ -z "$slug" ] || [ -z "$ticker" ] || [ -z "$mercado" ]; then
  echo "fake-alocacao-quote: recebido slug='$slug' ticker='$ticker' mercado='$mercado', esperado <slug> <ticker> <mercado>." >&2
  exit 1
fi

if [ -n "${ALOCACAO_QUOTE_LOG:-}" ]; then
  printf '%s %s %s\n' "$slug" "$ticker" "$mercado" >> "$ALOCACAO_QUOTE_LOG"
fi

prices="${ALOCACAO_QUOTE_PRICES:-}"
if [ -z "$prices" ] || [ ! -f "$prices" ]; then
  echo "fake-alocacao-quote: recebido ALOCACAO_QUOTE_PRICES='$prices', esperado arquivo JSON {\"TICKER\": preco}." >&2
  exit 1
fi

preco=$(jq -er --arg t "$ticker" '.[$t] // empty' "$prices")
if [ -z "$preco" ]; then
  echo "fake-alocacao-quote: ticker '$ticker' ausente em $prices, esperado chave com preco." >&2
  exit 1
fi

jq -nc --argjson preco "$preco" '{preco: $preco}'
