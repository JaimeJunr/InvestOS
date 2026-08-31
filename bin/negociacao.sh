#!/usr/bin/env bash
# Registra negociacoes (compra/venda, inclusive ofertas publicas) em negociacoes.json.
#
# Uso:
#   bin/negociacao.sh <slug> registrar <ticker> <tipo> <quantidade> <precoUnitario> <data> [oferta]
#   bin/negociacao.sh <slug> importar <arquivo.json>

set -euo pipefail

TIPOS_VALIDOS="compra venda"

usage() {
  cat <<EOF
Uso: bin/negociacao.sh <slug> registrar <ticker> <tipo> <quantidade> <precoUnitario> <data> [oferta]
     bin/negociacao.sh <slug> importar <arquivo.json>

Grava negociacoes (compra ou venda) em <slug>/negociacoes.json.
quantidade e precoUnitario devem ser maiores que zero. data no formato AAAA-MM-DD.
oferta e opcional: quando presente, marca participacao em Oferta Publica
(IPO/follow-on/subscricao).

"importar" le um array JSON de eventos no mesmo formato
({ticker, tipo, quantidade, precoUnitario, data, oferta?}) e grava todos de
uma vez - all-or-nothing (um item invalido rejeita o arquivo inteiro, nada
e gravado). Reimportar o mesmo arquivo nao duplica eventos ja identicos.
EOF
}

is_valid_tipo() {
  [[ " $TIPOS_VALIDOS " == *" $1 "* ]]
}

is_valid_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
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

NEGOCIACOES="$SLUG/negociacoes.json"

if [ "$COMANDO" = "registrar" ]; then
  TICKER="${3:-}"
  TIPO="${4:-}"
  QUANTIDADE="${5:-}"
  PRECO="${6:-}"
  DATA="${7:-}"
  OFERTA="${8:-}"

  if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
    usage >&2
    exit 1
  fi

  if [ -z "$TICKER" ]; then
    echo "Ticker invalido: recebido ticker vazio, esperado ticker nao-vazio (ex.: PETR4)." >&2
    exit 1
  fi
  if ! is_valid_tipo "$TIPO"; then
    echo "Tipo invalido: recebido '$TIPO', esperado um de: $TIPOS_VALIDOS." >&2
    exit 1
  fi
  if ! QTD_JSON=$(jq -cen --arg v "$QUANTIDADE" '$v | tonumber | select(. > 0)' 2>/dev/null); then
    echo "Valor invalido: recebido quantidade='$QUANTIDADE', esperado numero maior que zero." >&2
    exit 1
  fi
  if ! PRECO_JSON=$(jq -cen --arg v "$PRECO" '$v | tonumber | select(. > 0)' 2>/dev/null); then
    echo "Valor invalido: recebido precoUnitario='$PRECO', esperado numero maior que zero." >&2
    exit 1
  fi
  if ! is_valid_date "$DATA"; then
    echo "Data invalida: recebido '$DATA', esperado formato AAAA-MM-DD." >&2
    exit 1
  fi

  TEMPORARIO=$(mktemp "$SLUG/.negociacoes.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  if [ -f "$NEGOCIACOES" ]; then
    jq -e --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg oferta "$OFERTA" \
      --argjson quantidade "$QTD_JSON" --argjson preco "$PRECO_JSON" \
      'if type == "array" then . + [{ticker: $ticker, tipo: $tipo, quantidade: $quantidade, precoUnitario: $preco, data: $data, oferta: (if $oferta == "" then null else $oferta end)}] else error("negociacoes.json deve ser um array") end' \
      "$NEGOCIACOES" > "$TEMPORARIO"
  else
    jq -n --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg oferta "$OFERTA" \
      --argjson quantidade "$QTD_JSON" --argjson preco "$PRECO_JSON" \
      '[{ticker: $ticker, tipo: $tipo, quantidade: $quantidade, precoUnitario: $preco, data: $data, oferta: (if $oferta == "" then null else $oferta end)}]' > "$TEMPORARIO"
  fi

  mv "$TEMPORARIO" "$NEGOCIACOES"
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
    echo "Arquivo invalido: recebido path inexistente '$ARQUIVO', esperado JSON com array de negociacoes." >&2
    exit 1
  fi

  NORMALIZADO=$(python3 - "$ARQUIVO" <<'PY'
import json, re, sys
from datetime import date

TIPOS_VALIDOS = {"compra", "venda"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
path = sys.argv[1]

try:
    payload = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    sys.exit(f"Arquivo invalido: recebido erro '{exc}' em '{path}', esperado JSON valido.")

if not isinstance(payload, list):
    sys.exit(f"Arquivo invalido: recebido {payload!r}, esperado array de negociacoes.")


def to_num(value):
    n = float(value)
    if n.is_integer():
        return int(n)
    return n


out = []
for index, item in enumerate(payload):
    expected = "{ticker, tipo, quantidade, precoUnitario, data, oferta?}"
    if not isinstance(item, dict):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip()
    tipo = str(item.get("tipo") or "").strip()
    data_raw = str(item.get("data") or "").strip()
    try:
        quantidade = to_num(item.get("quantidade"))
        preco = to_num(item.get("precoUnitario"))
    except (TypeError, ValueError):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado quantidade/precoUnitario numericos.")
    if not ticker or tipo not in TIPOS_VALIDOS:
        sys.exit(
            f"Item invalido: recebido {item!r} no indice {index}, "
            f"esperado ticker nao-vazio e tipo um de: {sorted(TIPOS_VALIDOS)}."
        )
    if quantidade <= 0 or preco <= 0:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado quantidade/precoUnitario > 0.")
    if not DATE_RE.match(data_raw):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado data AAAA-MM-DD.")
    try:
        date.fromisoformat(data_raw)
    except ValueError:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado data AAAA-MM-DD.")
    oferta_raw = item.get("oferta")
    if oferta_raw is None or str(oferta_raw).strip() == "":
        oferta = None
    else:
        oferta = str(oferta_raw).strip()
    out.append({
        "ticker": ticker,
        "tipo": tipo,
        "quantidade": quantidade,
        "precoUnitario": preco,
        "data": data_raw,
        "oferta": oferta,
    })

json.dump(out, sys.stdout)
PY
) || { echo "$NORMALIZADO" >&2; exit 1; }

  TEMPORARIO=$(mktemp "$SLUG/.negociacoes.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  EXISTENTE='[]'
  if [ -f "$NEGOCIACOES" ]; then
    EXISTENTE=$(cat "$NEGOCIACOES")
  fi

  jq -n --argjson existente "$EXISTENTE" --argjson novos "$NORMALIZADO" \
    '$existente + ($novos - $existente)' \
    > "$TEMPORARIO"

  mv "$TEMPORARIO" "$NEGOCIACOES"
  trap - EXIT
  exit 0
fi

echo "Comando invalido: recebido '$COMANDO', esperado registrar ou importar." >&2
exit 1
