#!/usr/bin/env bash
# Relatorio de TWR e MWR a partir de nav-historico.json e transacoes.json.
#
# Uso:
#   bin/retorno.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/retorno.sh <slug>

Calcula o retorno ponderado pelo tempo (TWR) encadeando geometricamente
os sub-periodos entre snapshots de <slug>/nav-historico.json, isolando
aportes/resgates de <slug>/transacoes.json, e o retorno ponderado pelo
dinheiro (MWR) como taxa interna de retorno dos fluxos + valor final.
Sem transacoes.json ou historico de NAV insuficiente reporta a string
"dado insuficiente" em vez de calcular.
EOF
}

SLUG="${1:-}"

if [ -z "$SLUG" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

NAV="$SLUG/nav-historico.json"
TRANSACOES="$SLUG/transacoes.json"
NAV_INPUT=$(mktemp)
TX_INPUT=$(mktemp)
trap 'rm -f "$NAV_INPUT" "$TX_INPUT"' EXIT

if [ -f "$NAV" ]; then
  cat "$NAV" > "$NAV_INPUT"
else
  printf '%s\n' '[]' > "$NAV_INPUT"
fi

if [ -f "$TRANSACOES" ]; then
  cat "$TRANSACOES" > "$TX_INPUT"
else
  printf '%s\n' '[]' > "$TX_INPUT"
fi

python3 "$SCRIPT_DIR/retorno-report.py" "$NAV_INPUT" "$TX_INPUT"
