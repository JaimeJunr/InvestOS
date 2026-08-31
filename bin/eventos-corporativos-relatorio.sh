#!/usr/bin/env bash
# Relatorio de eventos corporativos: listagem ordenada e agrupada. Sem calculo.
#
# Uso:
#   bin/eventos-corporativos-relatorio.sh <slug>

set -euo pipefail

usage() {
  cat <<EOF
Uso: bin/eventos-corporativos-relatorio.sh <slug>

Lista os eventos corporativos de <slug>/eventos-corporativos.json ordenados
por data, agrupados por ticker e por tipo. Log informativo apenas - nao
calcula retorno nem ajusta holdings.
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

EVENTOS="$SLUG/eventos-corporativos.json"
require_file "$EVENTOS" '[{"ticker","tipo","data"}, ...]'

jq -e '
  if type != "array" then error("eventos-corporativos.json deve ser um array") else . end
  | sort_by(.data)
  | . as $ordenado
  | {
      eventos: $ordenado,
      porTicker: ($ordenado | group_by(.ticker) | map({(.[0].ticker): .}) | add // {}),
      porTipo: ($ordenado | group_by(.tipo) | map({(.[0].tipo): .}) | add // {})
    }
' "$EVENTOS"
