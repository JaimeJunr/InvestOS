#!/usr/bin/env bash
# Relatorio de proventos recebidos: totais, por ticker/classe/tipo, DY realizado 12m.
# Opcionalmente inclui proventos provisionados (anunciados, ainda nao pagos).
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
suficiente). Se <slug>/proventos-provisionados.json existir, inclui tambem
provisionadoProximos12m e dyProjetado12m (liquido realizado 12m + bruto
provisionado dos proximos 12m / NAV medio). Informativo apenas - nao calcula
Imposto de Renda devido.
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
PROVISIONADOS="$SLUG/proventos-provisionados.json"

args=("$PROVENTOS")
if [ -f "$NAV" ]; then
  args+=("$NAV")
fi
if [ -f "$PROVISIONADOS" ]; then
  args+=("$PROVISIONADOS")
fi
python3 "$SCRIPT_DIR/proventos-relatorio-report.py" "${args[@]}"
