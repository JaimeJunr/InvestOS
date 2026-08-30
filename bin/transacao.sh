#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Uso: bin/transacao.sh <slug> registrar <tipo> <valor> [data]" >&2
}

SLUG="${1:-}"
COMANDO="${2:-}"
TIPO="${3:-}"
VALOR="${4:-}"
DATA="${5:-}"

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  usage
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

if [ "$COMANDO" != "registrar" ]; then
  echo "Comando invalido: recebido '$COMANDO', esperado registrar." >&2
  exit 1
fi

case "$TIPO" in
  aporte | resgate | compra | venda) ;;
  *)
    echo "Tipo invalido: recebido '$TIPO', esperado um de: aporte, resgate, compra ou venda." >&2
    exit 1
    ;;
esac

if ! VALOR_JSON=$(jq -cen --arg valor "$VALOR" '$valor | tonumber | select(. > 0)' 2>/dev/null); then
  echo "Valor invalido: recebido '$VALOR', esperado numero maior que zero." >&2
  exit 1
fi

if [ "$#" -eq 4 ]; then
  DATA=$(date +%Y-%m-%d)
fi

TRANSACOES="$SLUG/transacoes.json"
TEMPORARIO=$(mktemp "$SLUG/.transacoes.json.tmp.XXXXXX")
trap 'rm -f "$TEMPORARIO"' EXIT

if [ -f "$TRANSACOES" ]; then
  jq -e --arg data "$DATA" --arg tipo "$TIPO" --argjson valor "$VALOR_JSON" \
    'if type == "array" then . + [{data: $data, tipo: $tipo, valor: $valor}] else error("transacoes.json deve ser um array") end' \
    "$TRANSACOES" > "$TEMPORARIO"
else
  jq -n --arg data "$DATA" --arg tipo "$TIPO" --argjson valor "$VALOR_JSON" \
    '[{data: $data, tipo: $tipo, valor: $valor}]' > "$TEMPORARIO"
fi

mv "$TEMPORARIO" "$TRANSACOES"
trap - EXIT
