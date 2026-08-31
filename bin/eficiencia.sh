#!/usr/bin/env bash
# Relatorio de Sortino, giro de carteira e aliquota efetiva de IR.
#
# Uso:
#   bin/eficiencia.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/eficiencia.sh <slug>

Calcula o indice de Sortino a partir de <slug>/nav-historico.json
(penaliza so o desvio negativo, sem anualizar), o giro de carteira
(soma de compra+venda em <slug>/transacoes.json / valor medio do NAV)
e a aliquota efetiva de IR (impostoPago / ganhoRealizado, campos
opcionais). Sem transacoes registradas ou historico insuficiente
reporta a string "dado insuficiente" no campo correspondente.
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

python3 "$SCRIPT_DIR/eficiencia-report.py" "$NAV_INPUT" "$TX_INPUT"
