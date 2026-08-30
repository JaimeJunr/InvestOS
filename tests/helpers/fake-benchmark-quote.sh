#!/usr/bin/env bash
# Fake nomeado do benchmark US. Nao faz I/O de rede.
set -euo pipefail

slug="${1:-}"
ticker="${2:-}"
mercado="${3:-}"

if [ -z "$slug" ] || [ -z "$ticker" ] || [ -z "$mercado" ]; then
  echo "fake-benchmark-quote: recebido slug='$slug' ticker='$ticker' mercado='$mercado', esperado <slug> <ticker> <mercado>." >&2
  exit 1
fi

if [ -n "${BENCHMARK_QUOTE_LOG:-}" ]; then
  printf '%s %s %s\n' "$slug" "$ticker" "$mercado" >> "$BENCHMARK_QUOTE_LOG"
fi

payload="${BENCHMARK_QUOTE_PAYLOAD:-}"
if [ -z "$payload" ] || [ ! -f "$payload" ]; then
  echo "fake-benchmark-quote: recebido BENCHMARK_QUOTE_PAYLOAD='$payload', esperado arquivo JSON com historico de ^GSPC." >&2
  exit 1
fi

cat "$payload"
