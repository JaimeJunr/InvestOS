#!/usr/bin/env bash
# Fake nomeado do GET HTTP da brapi.dev v2 (quote/statistics). Nao faz I/O de rede.
set -euo pipefail

url="${1:-}"
token="${2:-}"
if [ -z "$url" ]; then
  echo "fake-brapi-http: recebido URL vazia, esperado .../v2/stocks/quote?symbols=<ticker>" >&2
  exit 1
fi

if [ -n "${BRAPI_FETCH_LOG:-}" ]; then
  printf '%s\n' "$url" >> "$BRAPI_FETCH_LOG"
  if [ -n "$token" ]; then
    printf 'Authorization: Bearer %s\n' "$token" >> "$BRAPI_FETCH_LOG"
  fi
fi

ticker=$(printf '%s' "$url" | sed -E 's/.*[?&]symbols=([^&]+).*/\1/')
if [ -z "$ticker" ] || [ "$ticker" = "$url" ]; then
  echo "fake-brapi-http: nao extraiu ticker de URL '$url', esperado .../v2/stocks/quote?symbols=<ticker>" >&2
  exit 1
fi

if [[ "$url" == *"/statistics"* ]]; then
  dy=""
  if [ -n "${BRAPI_DIVIDEND_YIELDS:-}" ] && [ -f "${BRAPI_DIVIDEND_YIELDS}" ]; then
    dy=$(jq -r --arg t "$ticker" '.[$t] // empty' "$BRAPI_DIVIDEND_YIELDS")
  fi
  if [ -n "$dy" ]; then
    printf '{"results":[{"symbol":"%s","data":{"dividendYield":%s}}]}\n' "$ticker" "$dy"
  else
    printf '{"results":[{"symbol":"%s","data":{}}]}\n' "$ticker"
  fi
  exit 0
fi

printf '{"results":[{"symbol":"%s","data":{"regularMarketPrice":10.5}}]}\n' "$ticker"
