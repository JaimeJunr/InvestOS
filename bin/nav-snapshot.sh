#!/usr/bin/env bash
# Registra o valor total atual da carteira no historico diario de NAV.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLUG="${1:-}"

RELATORIO=$("$SCRIPT_DIR/alocacao.sh" "$SLUG")
VALOR_TOTAL=$(jq -er '.total' <<<"$RELATORIO")
DATA_ATUAL=$(date +%Y-%m-%d)
HISTORICO="$SLUG/nav-historico.json"
TEMPORARIO=$(mktemp "$SLUG/.nav-historico.json.tmp.XXXXXX")
trap 'rm -f "$TEMPORARIO"' EXIT

if [ -f "$HISTORICO" ]; then
  jq --arg data "$DATA_ATUAL" --argjson valorTotal "$VALOR_TOTAL" \
    'map(select(.data != $data)) + [{data: $data, valorTotal: $valorTotal}]' \
    "$HISTORICO" > "$TEMPORARIO"
else
  jq -n --arg data "$DATA_ATUAL" --argjson valorTotal "$VALOR_TOTAL" \
    '[{data: $data, valorTotal: $valorTotal}]' > "$TEMPORARIO"
fi

mv "$TEMPORARIO" "$HISTORICO"
trap - EXIT
