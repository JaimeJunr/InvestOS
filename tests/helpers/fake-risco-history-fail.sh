#!/usr/bin/env bash
# Fake nomeado de serie historica que simula os tres modos de falha do
# provider injetado (RISCO_HISTORY): exit!=0, stdout nao-JSON com exit 0, e
# stdout vazio com exit 0. Usado para provar que achados.sh nao propaga a
# falha do enriquecimento opcional (US-003 AC4) - nunca faz I/O de rede.
set -euo pipefail

slug="${1:-}"
ticker="${2:-}"
mercado="${3:-}"

if [ -z "$slug" ] || [ -z "$ticker" ] || [ -z "$mercado" ]; then
  echo "fake-risco-history-fail: recebido slug='$slug' ticker='$ticker' mercado='$mercado', esperado <slug> <ticker> <mercado>." >&2
  exit 1
fi

modo="${RISCO_HISTORY_FAIL_MODE:-}"
if [ -z "$modo" ]; then
  echo "fake-risco-history-fail: recebido RISCO_HISTORY_FAIL_MODE='$modo', esperado exit1|nonjson|empty." >&2
  exit 1
fi

case "$modo" in
  exit1)
    echo "fake-risco-history-fail: falha simulada (exit1) buscando serie de $ticker" >&2
    exit 1
    ;;
  nonjson)
    echo "fake-risco-history-fail: falha simulada (nonjson) buscando serie de $ticker" >&2
    printf '<html>erro</html>\n'
    exit 0
    ;;
  empty)
    echo "fake-risco-history-fail: falha simulada (empty) buscando serie de $ticker" >&2
    printf ''
    exit 0
    ;;
  *)
    echo "fake-risco-history-fail: recebido RISCO_HISTORY_FAIL_MODE='$modo', esperado exit1|nonjson|empty." >&2
    exit 1
    ;;
esac
