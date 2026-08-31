#!/usr/bin/env bash
# Fake nomeado do GET HTTP do BCB SGS. Nao faz I/O de rede.
set -euo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "fake-bcb-sgs: recebido URL vazia, esperado https://api.bcb.gov.br/dados/serie/bcdata.sgs.<codigo>/dados/ultimos/1?formato=json" >&2
  exit 1
fi

if [ -n "${MACRO_FETCH_LOG:-}" ]; then
  printf '%s\n' "$url" >> "$MACRO_FETCH_LOG"
fi

if [ "${MACRO_FAKE_FAIL:-0}" = "1" ]; then
  echo "fake-bcb-sgs: falha de rede simulada" >&2
  exit 1
fi

case "$url" in
  "https://api.bcb.gov.br/dados/serie/bcdata.sgs.432/dados/ultimos/1?formato=json")
    printf '%s\n' '[{"data":"29/08/2026","valor":"15.00"}]'
    ;;
  "https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados/ultimos/1?formato=json")
    printf '%s\n' '[{"data":"30/08/2026","valor":"0.05"}]'
    ;;
  *)
    echo "fake-bcb-sgs: URL fora do contrato BCB SGS: recebido '$url', esperado serie 432 ou 12 com ultimos/1?formato=json" >&2
    exit 1
    ;;
esac
