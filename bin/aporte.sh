#!/usr/bin/env bash
# Sugere como distribuir um aporte novo entre classes/mercados underweight,
# sem precisar vender nada.
#
# Uso:
#   bin/aporte.sh <slug> <valor>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/aporte.sh <slug> <valor>

Sugere como distribuir um novo aporte (valor em BRL) entre as classes e
mercados mais abaixo do peso-alvo em <slug>/alocacao-alvo.json, priorizando
o que esta mais underweight primeiro (rateio proporcional ao gap). Se nada
estiver underweight, distribui o aporte pelos pesos-alvo diretamente. Nunca
sugere vender - so onde colocar dinheiro novo. Nao executa ordem, nao altera
holdings.json.
EOF
}

SLUG="${1:-}"
VALOR="${2:-}"

if [ -z "$SLUG" ] || [ -z "$VALOR" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

REPORT=$("$REPO_ROOT/bin/alocacao.sh" "$SLUG")
printf '%s' "$REPORT" | python3 "$SCRIPT_DIR/aporte-report.py" "$VALOR"
