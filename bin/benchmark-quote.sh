#!/usr/bin/env bash
# Consulta o benchmark Ibovespa via brapi.dev.
#
# Uso:
#   bin/benchmark-quote.sh <slug> br

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/benchmark-quote.sh <slug> br

Consulta o historico do Ibovespa (^BVSP) via brapi.dev por ate 3 meses,
com intervalo diario, preservando o cache e o token do cliente brapi.
EOF
}

if [ "$#" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  usage >&2
  exit 1
fi

SLUG="$1"
MARKET="$2"

if [ "$MARKET" != "br" ]; then
  echo "Mercado invalido: recebido '$MARKET', esperado 'br' (Ibovespa via brapi.dev)." >&2
  exit 1
fi

BRAPI_RANGE=3mo BRAPI_INTERVAL=1d exec "$SCRIPT_DIR/brapi-quote.sh" "$SLUG" "^BVSP"
