#!/usr/bin/env bash
# Relatorio de proventos recebidos: totais, por ticker/classe/tipo, DY realizado 12m.
#
# Uso:
#   bin/proventos-relatorio.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/proventos-relatorio.sh <slug>

Resume os proventos registrados em <slug>/proventos.json: total bruto/liquido,
retido na fonte, agrupado por ticker/classe/tipo, e dividend yield realizado
nos ultimos 12 meses (proventos liquidos do periodo / NAV medio do periodo,
via <slug>/nav-historico.json - "dado insuficiente" sem historico
suficiente). Informativo apenas - nao calcula Imposto de Renda devido.
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

PROVENTOS="$SLUG/proventos.json"
require_file "$PROVENTOS" '[{"ticker","tipo","classe","valorBruto","valorLiquido","data"}, ...]'

NAV="$SLUG/nav-historico.json"
if [ -f "$NAV" ]; then
  python3 "$SCRIPT_DIR/proventos-relatorio-report.py" "$PROVENTOS" "$NAV"
else
  python3 "$SCRIPT_DIR/proventos-relatorio-report.py" "$PROVENTOS"
fi
