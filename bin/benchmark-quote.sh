#!/usr/bin/env bash
# Consulta benchmarks BR e US.
#
# Uso:
#   bin/benchmark-quote.sh <slug> <br|us>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/benchmark-quote.sh <slug> <br|us>

Mercado br consulta o historico do Ibovespa (^BVSP) via brapi.dev por ate
3 meses. Mercado us exige BENCHMARK_QUOTE injetado para consultar o S&P 500
(^GSPC); o fallback documentado e yfinance, nao-oficial e sem quota garantida.
EOF
}

if [ "$#" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  usage >&2
  exit 1
fi

SLUG="$1"
MARKET="$2"

if [ "$MARKET" = "br" ]; then
  BRAPI_RANGE=3mo BRAPI_INTERVAL=1d exec "$SCRIPT_DIR/brapi-quote.sh" "$SLUG" "^BVSP"
fi

if [ "$MARKET" = "us" ]; then
  if [ -n "${BENCHMARK_QUOTE:-}" ]; then
    exec "$BENCHMARK_QUOTE" "$SLUG" "^GSPC" "us"
  fi
  echo "Benchmark US indisponivel: nao ha fonte oficial gratuita para o S&P 500; esperado BENCHMARK_QUOTE injetado. Fallback documentado: yfinance ^GSPC, nao-oficial e sem quota garantida." >&2
  exit 1
fi

echo "Mercado invalido: recebido '$MARKET', esperado 'br|us'." >&2
exit 1
