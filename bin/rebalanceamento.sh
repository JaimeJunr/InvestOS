#!/usr/bin/env bash
# Sugestao de rebalanceamento quando o desvio ultrapassa o threshold do portfolio.
#
# Uso:
#   bin/rebalanceamento.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/rebalanceamento.sh <slug>

Gera sugestao de rebalanceamento (comprar/vender) a partir da alocacao
atual vs. alvo em <slug>/alocacao-alvo.json (campo threshold em (0, 1]).
Nunca executa ordem — so sugere. Nao altera holdings.json.
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

ALVO="$SLUG/alocacao-alvo.json"
REPORT=$("$REPO_ROOT/bin/alocacao.sh" "$SLUG")
printf '%s\n' "$REPORT" | python3 "$SCRIPT_DIR/rebalanceamento-report.py" "$ALVO"
