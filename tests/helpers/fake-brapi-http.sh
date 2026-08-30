#!/usr/bin/env bash
# Fake nomeado do GET HTTP da brapi.dev. Nao faz I/O de rede.
set -euo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "fake-brapi-http: recebido URL vazia, esperado https://brapi.dev/api/quote/<ticker>" >&2
  exit 1
fi

if [ -n "${BRAPI_FETCH_LOG:-}" ]; then
  printf '%s\n' "$url" >> "$BRAPI_FETCH_LOG"
fi

ticker=$(printf '%s' "$url" | sed -E 's|.*/quote/([^?]+).*|\1|')
if [ -z "$ticker" ] || [ "$ticker" = "$url" ]; then
  echo "fake-brapi-http: nao extraiu ticker de URL '$url', esperado .../quote/<ticker>" >&2
  exit 1
fi

printf '{"results":[{"symbol":"%s","regularMarketPrice":10.5}]}\n' "$ticker"
