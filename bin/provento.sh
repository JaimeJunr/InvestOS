#!/usr/bin/env bash
# Registra proventos (dividendos/JCP/rendimentos) em proventos.json.
#
# Uso:
#   bin/provento.sh <slug> registrar <ticker> <tipo> <classe> <valorBruto> <valorLiquido> [data]
#   bin/provento.sh <slug> importar <arquivo.json>

set -euo pipefail

TIPOS_VALIDOS="dividendo jcp rendimento"

usage() {
  cat <<EOF
Uso: bin/provento.sh <slug> registrar <ticker> <tipo> <classe> <valorBruto> <valorLiquido> [data]
     bin/provento.sh <slug> importar <arquivo.json>

Grava proventos (dividendo, jcp ou rendimento) em <slug>/proventos.json.
valorLiquido nunca pode ser maior que valorBruto (retencao nao pode ser
negativa). data default = hoje se omitida em "registrar".

"importar" le um array JSON de eventos no mesmo formato
({ticker, tipo, classe, valorBruto, valorLiquido, data}) e grava todos de
uma vez - all-or-nothing (um item invalido rejeita o arquivo inteiro, nada
e gravado). Reimportar o mesmo arquivo nao duplica eventos ja identicos.
EOF
}

is_valid_tipo() {
  [[ " $TIPOS_VALIDOS " == *" $1 "* ]]
}

validate_valor() {
  local field="$1" valor="$2"
  if ! jq -cen --arg v "$valor" '$v | tonumber | select(. > 0)' >/dev/null 2>&1; then
    echo "Valor invalido: recebido $field='$valor', esperado numero maior que zero." >&2
    return 1
  fi
  return 0
}

SLUG="${1:-}"
COMANDO="${2:-}"

if [ -z "$SLUG" ] || [ -z "$COMANDO" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

PROVENTOS="$SLUG/proventos.json"

if [ "$COMANDO" = "registrar" ]; then
  TICKER="${3:-}"
  TIPO="${4:-}"
  CLASSE="${5:-}"
  VALOR_BRUTO="${6:-}"
  VALOR_LIQUIDO="${7:-}"
  DATA="${8:-}"

  if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
    usage >&2
    exit 1
  fi

  if ! is_valid_tipo "$TIPO"; then
    echo "Tipo invalido: recebido '$TIPO', esperado um de: $TIPOS_VALIDOS." >&2
    exit 1
  fi
  if [ -z "$CLASSE" ]; then
    echo "Classe invalida: recebido classe vazia, esperado classe nao-vazia (ex.: acoes, fiis)." >&2
    exit 1
  fi

  if ! BRUTO_JSON=$(jq -cen --arg v "$VALOR_BRUTO" '$v | tonumber | select(. > 0)' 2>/dev/null); then
    echo "Valor invalido: recebido valorBruto='$VALOR_BRUTO', esperado numero maior que zero." >&2
    exit 1
  fi
  if ! LIQUIDO_JSON=$(jq -cen --arg v "$VALOR_LIQUIDO" '$v | tonumber | select(. > 0)' 2>/dev/null); then
    echo "Valor invalido: recebido valorLiquido='$VALOR_LIQUIDO', esperado numero maior que zero." >&2
    exit 1
  fi
  if ! jq -cen --argjson b "$BRUTO_JSON" --argjson l "$LIQUIDO_JSON" '$l <= $b' >/dev/null 2>&1; then
    echo "Valor invalido: recebido valorLiquido=$LIQUIDO_JSON > valorBruto=$BRUTO_JSON, esperado valorLiquido <= valorBruto." >&2
    exit 1
  fi

  if [ "$#" -eq 7 ]; then
    DATA=$(date +%Y-%m-%d)
  fi

  TEMPORARIO=$(mktemp "$SLUG/.proventos.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  if [ -f "$PROVENTOS" ]; then
    jq -e --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg classe "$CLASSE" \
      --argjson bruto "$BRUTO_JSON" --argjson liquido "$LIQUIDO_JSON" \
      'if type == "array" then . + [{data: $data, ticker: $ticker, tipo: $tipo, classe: $classe, valorBruto: $bruto, valorLiquido: $liquido}] else error("proventos.json deve ser um array") end' \
      "$PROVENTOS" > "$TEMPORARIO"
  else
    jq -n --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg classe "$CLASSE" \
      --argjson bruto "$BRUTO_JSON" --argjson liquido "$LIQUIDO_JSON" \
      '[{data: $data, ticker: $ticker, tipo: $tipo, classe: $classe, valorBruto: $bruto, valorLiquido: $liquido}]' > "$TEMPORARIO"
  fi

  mv "$TEMPORARIO" "$PROVENTOS"
  trap - EXIT
  exit 0
fi

if [ "$COMANDO" = "importar" ]; then
  ARQUIVO="${3:-}"
  if [ "$#" -ne 3 ] || [ -z "$ARQUIVO" ]; then
    usage >&2
    exit 1
  fi
  if [ ! -f "$ARQUIVO" ]; then
    echo "Arquivo invalido: recebido path inexistente '$ARQUIVO', esperado JSON com array de proventos." >&2
    exit 1
  fi

  NORMALIZADO=$(python3 - "$ARQUIVO" <<'PY'
import json, sys

TIPOS_VALIDOS = {"dividendo", "jcp", "rendimento"}
path = sys.argv[1]

try:
    payload = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    sys.exit(f"Arquivo invalido: recebido erro '{exc}' em '{path}', esperado JSON valido.")

if not isinstance(payload, list):
    sys.exit(f"Arquivo invalido: recebido {payload!r}, esperado array de proventos.")

out = []
for index, item in enumerate(payload):
    expected = "{ticker, tipo, classe, valorBruto, valorLiquido, data?}"
    if not isinstance(item, dict):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip()
    tipo = str(item.get("tipo") or "").strip()
    classe = str(item.get("classe") or "").strip()
    data = str(item.get("data") or "").strip()
    try:
        bruto = float(item.get("valorBruto"))
        liquido = float(item.get("valorLiquido"))
    except (TypeError, ValueError):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado valorBruto/valorLiquido numericos.")
    if not ticker or tipo not in TIPOS_VALIDOS or not classe:
        sys.exit(
            f"Item invalido: recebido {item!r} no indice {index}, "
            f"esperado ticker/classe nao-vazios e tipo um de: {sorted(TIPOS_VALIDOS)}."
        )
    if bruto <= 0 or liquido <= 0:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado valorBruto/valorLiquido > 0.")
    if liquido > bruto:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado valorLiquido <= valorBruto.")
    if not data:
        data = None
    out.append({"ticker": ticker, "tipo": tipo, "classe": classe, "valorBruto": bruto, "valorLiquido": liquido, "data": data})

json.dump(out, sys.stdout)
PY
) || { echo "$NORMALIZADO" >&2; exit 1; }

  HOJE=$(date +%Y-%m-%d)
  NORMALIZADO=$(jq --arg hoje "$HOJE" 'map(.data //= $hoje)' <<<"$NORMALIZADO")

  TEMPORARIO=$(mktemp "$SLUG/.proventos.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  EXISTENTE='[]'
  if [ -f "$PROVENTOS" ]; then
    EXISTENTE=$(cat "$PROVENTOS")
  fi

  jq -n --argjson existente "$EXISTENTE" --argjson novos "$NORMALIZADO" \
    '$existente + ($novos - $existente)' \
    > "$TEMPORARIO"

  mv "$TEMPORARIO" "$PROVENTOS"
  trap - EXIT
  exit 0
fi

echo "Comando invalido: recebido '$COMANDO', esperado registrar ou importar." >&2
exit 1
