#!/usr/bin/env bash
# Relatorio de negociacoes: totais, quantidade liquida, volume, ofertas publicas.
#
# Uso:
#   bin/negociacoes-relatorio.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/negociacoes-relatorio.sh <slug>

Resume as negociacoes registradas em <slug>/negociacoes.json: total comprado,
total vendido, quantidade liquida por ticker, volume por ticker e por tipo,
e participacao em ofertas publicas (itens com campo oferta preenchido).
Nao calcula ganho/perda de capital em vendas.
EOF
}

require_file() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo invalido: recebido path inexistente '$file', esperado $expected." >&2
    exit 1
  fi
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

NEGOCIACOES="$SLUG/negociacoes.json"
require_file "$NEGOCIACOES" '[{"ticker","tipo","quantidade","precoUnitario","data","oferta?"}, ...]'

python3 "$SCRIPT_DIR/negociacoes-relatorio-report.py" "$NEGOCIACOES"
