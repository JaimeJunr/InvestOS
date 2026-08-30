#!/usr/bin/env bash
# Fake nomeado de serie historica para o relatorio de risco. Nao faz I/O de rede.
set -euo pipefail

slug="${1:-}"
ticker="${2:-}"
mercado="${3:-}"

if [ -z "$slug" ] || [ -z "$ticker" ] || [ -z "$mercado" ]; then
  echo "fake-risco-history: recebido slug='$slug' ticker='$ticker' mercado='$mercado', esperado <slug> <ticker> <mercado>." >&2
  exit 1
fi

if [ -n "${RISCO_HISTORY_LOG:-}" ]; then
  printf '%s %s %s\n' "$slug" "$ticker" "$mercado" >> "$RISCO_HISTORY_LOG"
fi

series_file="${RISCO_HISTORY_SERIES:-}"
if [ -z "$series_file" ] || [ ! -f "$series_file" ]; then
  echo "fake-risco-history: recebido RISCO_HISTORY_SERIES='$series_file', esperado arquivo JSON {\"TICKER\": [{\"date\",\"close\"}]}." >&2
  exit 1
fi

jq -ce --arg t "$ticker" '.[$t] // []' "$series_file"
