#!/usr/bin/env bash
# Registra eventos corporativos (log informativo) em eventos-corporativos.json.
#
# Uso:
#   bin/evento-corporativo.sh <slug> registrar <ticker> <tipo> <data> [fator] [quantidadeRecebida] [observacao]
#   bin/evento-corporativo.sh <slug> importar <arquivo.json>

set -euo pipefail

TIPOS_VALIDOS="desdobramento grupamento bonificacao incorporacao outro"

usage() {
  cat <<EOF
Uso: bin/evento-corporativo.sh <slug> registrar <ticker> <tipo> <data> [fator] [quantidadeRecebida] [observacao]
     bin/evento-corporativo.sh <slug> importar <arquivo.json>

Grava eventos corporativos em <slug>/eventos-corporativos.json.
tipo um de: desdobramento, grupamento, bonificacao, incorporacao, outro.
data no formato AAAA-MM-DD. fator, quantidadeRecebida e observacao sao
opcionais (log puramente informativo - nao ajusta holdings.json).

"importar" le um array JSON de eventos no mesmo formato
({ticker, tipo, data, fator?, quantidadeRecebida?, observacao?}) e grava
todos de uma vez - all-or-nothing (um item invalido rejeita o arquivo
inteiro, nada e gravado). Reimportar o mesmo arquivo nao duplica eventos
ja identicos.
EOF
}

is_valid_tipo() {
  [[ " $TIPOS_VALIDOS " == *" $1 "* ]]
}

is_valid_date() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

optional_positive_json() {
  local field="$1" valor="$2"
  if [ -z "$valor" ]; then
    echo null
    return 0
  fi
  local parsed
  if ! parsed=$(jq -cen --arg v "$valor" '$v | tonumber | select(. > 0)' 2>/dev/null); then
    echo "Valor invalido: recebido $field='$valor', esperado numero maior que zero (ou vazio)." >&2
    return 1
  fi
  echo "$parsed"
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

EVENTOS="$SLUG/eventos-corporativos.json"

if [ "$COMANDO" = "registrar" ]; then
  TICKER="${3:-}"
  TIPO="${4:-}"
  DATA="${5:-}"
  FATOR="${6:-}"
  QTD_REC="${7:-}"
  OBSERVACAO="${8:-}"

  if [ "$#" -lt 5 ] || [ "$#" -gt 8 ]; then
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
  if ! is_valid_date "$DATA"; then
    echo "Data invalida: recebido '$DATA', esperado formato AAAA-MM-DD." >&2
    exit 1
  fi
  if ! FATOR_JSON=$(optional_positive_json fator "$FATOR"); then
    exit 1
  fi
  if ! QTD_JSON=$(optional_positive_json quantidadeRecebida "$QTD_REC"); then
    exit 1
  fi

  TEMPORARIO=$(mktemp "$SLUG/.eventos-corporativos.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  if [ -f "$EVENTOS" ]; then
    jq -e --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg obs "$OBSERVACAO" \
      --argjson fator "$FATOR_JSON" --argjson qtd "$QTD_JSON" \
      'if type == "array" then . + [{ticker: $ticker, tipo: $tipo, data: $data, fator: $fator, quantidadeRecebida: $qtd, observacao: (if $obs == "" then null else $obs end)}] else error("eventos-corporativos.json deve ser um array") end' \
      "$EVENTOS" > "$TEMPORARIO"
  else
    jq -n --arg data "$DATA" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg obs "$OBSERVACAO" \
      --argjson fator "$FATOR_JSON" --argjson qtd "$QTD_JSON" \
      '[{ticker: $ticker, tipo: $tipo, data: $data, fator: $fator, quantidadeRecebida: $qtd, observacao: (if $obs == "" then null else $obs end)}]' > "$TEMPORARIO"
  fi

  mv "$TEMPORARIO" "$EVENTOS"
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
    echo "Arquivo invalido: recebido path inexistente '$ARQUIVO', esperado JSON com array de eventos corporativos." >&2
    exit 1
  fi

  NORMALIZADO=$(python3 - "$ARQUIVO" <<'PY'
import json, re, sys
from datetime import date

TIPOS_VALIDOS = {"desdobramento", "grupamento", "bonificacao", "incorporacao", "outro"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
path = sys.argv[1]

try:
    payload = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    sys.exit(f"Arquivo invalido: recebido erro '{exc}' em '{path}', esperado JSON valido.")

if not isinstance(payload, list):
    sys.exit(f"Arquivo invalido: recebido {payload!r}, esperado array de eventos corporativos.")


def to_num(value):
    n = float(value)
    if n.is_integer():
        return int(n)
    return n


def optional_positive(item, key, index):
    if key not in item or item[key] is None or item[key] == "":
        return None
    try:
        val = to_num(item[key])
    except (TypeError, ValueError):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado {key} numerico > 0.")
    if val <= 0:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado {key} > 0.")
    return val


out = []
for index, item in enumerate(payload):
    expected = "{ticker, tipo, data, fator?, quantidadeRecebida?, observacao?}"
    if not isinstance(item, dict):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip()
    tipo = str(item.get("tipo") or "").strip()
    data_raw = str(item.get("data") or "").strip()
    if not ticker or tipo not in TIPOS_VALIDOS:
        sys.exit(
            f"Item invalido: recebido {item!r} no indice {index}, "
            f"esperado ticker nao-vazio e tipo um de: {sorted(TIPOS_VALIDOS)}."
        )
    if not DATE_RE.match(data_raw):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado data AAAA-MM-DD.")
    try:
        date.fromisoformat(data_raw)
    except ValueError:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado data AAAA-MM-DD.")
    obs_raw = item.get("observacao")
    if obs_raw is None or str(obs_raw).strip() == "":
        observacao = None
    else:
        observacao = str(obs_raw)
    out.append({
        "ticker": ticker,
        "tipo": tipo,
        "data": data_raw,
        "fator": optional_positive(item, "fator", index),
        "quantidadeRecebida": optional_positive(item, "quantidadeRecebida", index),
        "observacao": observacao,
    })

json.dump(out, sys.stdout)
PY
) || { echo "$NORMALIZADO" >&2; exit 1; }

  TEMPORARIO=$(mktemp "$SLUG/.eventos-corporativos.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  EXISTENTE='[]'
  if [ -f "$EVENTOS" ]; then
    EXISTENTE=$(cat "$EVENTOS")
  fi

  jq -n --argjson existente "$EXISTENTE" --argjson novos "$NORMALIZADO" \
    '$existente + ($novos - $existente)' \
    > "$TEMPORARIO"

  mv "$TEMPORARIO" "$EVENTOS"
  trap - EXIT
  exit 0
fi

echo "Comando invalido: recebido '$COMANDO', esperado registrar ou importar." >&2
exit 1
