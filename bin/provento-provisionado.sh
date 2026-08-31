#!/usr/bin/env bash
# Registra proventos provisionados (anunciados, ainda nao pagos) em
# proventos-provisionados.json. Sem valorLiquido: retencao so e conhecida
# no pagamento real. dataPrevisao e obrigatoria (sem default de hoje).
#
# Uso:
#   bin/provento-provisionado.sh <slug> registrar <ticker> <tipo> <classe> <valorBruto> <dataPrevisao>
#   bin/provento-provisionado.sh <slug> importar <arquivo.json>

set -euo pipefail

TIPOS_VALIDOS="dividendo jcp rendimento"

usage() {
  cat <<EOF
Uso: bin/provento-provisionado.sh <slug> registrar <ticker> <tipo> <classe> <valorBruto> <dataPrevisao>
     bin/provento-provisionado.sh <slug> importar <arquivo.json>

Grava proventos provisionados (dividendo, jcp ou rendimento ja anunciados
pela empresa, com pagamento futuro) em <slug>/proventos-provisionados.json.
Nao tem valorLiquido — retencao na fonte so e conhecida no pagamento real.
valorBruto deve ser maior que zero. dataPrevisao e obrigatoria, formato
AAAA-MM-DD (sem default de hoje: e sempre uma data futura anunciada).

Nao misturar com proventos.json (eventos ja pagos, usados no DY realizado).

"importar" le um array JSON de eventos no mesmo formato
({ticker, tipo, classe, valorBruto, dataPrevisao}) e grava todos de uma
vez - all-or-nothing (um item invalido rejeita o arquivo inteiro, nada e
gravado). Reimportar o mesmo arquivo nao duplica eventos ja identicos.
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

PROVISIONADOS="$SLUG/proventos-provisionados.json"

if [ "$COMANDO" = "registrar" ]; then
  TICKER="${3:-}"
  TIPO="${4:-}"
  CLASSE="${5:-}"
  VALOR_BRUTO="${6:-}"
  DATA_PREVISAO="${7:-}"

  if [ "$#" -ne 7 ]; then
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

  if ! is_valid_date "$DATA_PREVISAO"; then
    echo "Data invalida: recebido '$DATA_PREVISAO', esperado formato AAAA-MM-DD." >&2
    exit 1
  fi

  TEMPORARIO=$(mktemp "$SLUG/.proventos-provisionados.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  if [ -f "$PROVISIONADOS" ]; then
    jq -e --arg data "$DATA_PREVISAO" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg classe "$CLASSE" \
      --argjson bruto "$BRUTO_JSON" \
      'if type == "array" then . + [{ticker: $ticker, tipo: $tipo, classe: $classe, valorBruto: $bruto, dataPrevisao: $data}] else error("proventos-provisionados.json deve ser um array") end' \
      "$PROVISIONADOS" > "$TEMPORARIO"
  else
    jq -n --arg data "$DATA_PREVISAO" --arg ticker "$TICKER" --arg tipo "$TIPO" --arg classe "$CLASSE" \
      --argjson bruto "$BRUTO_JSON" \
      '[{ticker: $ticker, tipo: $tipo, classe: $classe, valorBruto: $bruto, dataPrevisao: $data}]' > "$TEMPORARIO"
  fi

  mv "$TEMPORARIO" "$PROVISIONADOS"
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
    echo "Arquivo invalido: recebido path inexistente '$ARQUIVO', esperado JSON com array de proventos provisionados." >&2
    exit 1
  fi

  NORMALIZADO=$(python3 - "$ARQUIVO" <<'PY'
import json, re, sys
from datetime import date

TIPOS_VALIDOS = {"dividendo", "jcp", "rendimento"}
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
path = sys.argv[1]

try:
    payload = json.load(open(path, encoding="utf-8"))
except Exception as exc:
    sys.exit(f"Arquivo invalido: recebido erro '{exc}' em '{path}', esperado JSON valido.")

if not isinstance(payload, list):
    sys.exit(f"Arquivo invalido: recebido {payload!r}, esperado array de proventos provisionados.")

out = []
for index, item in enumerate(payload):
    expected = "{ticker, tipo, classe, valorBruto, dataPrevisao}"
    if not isinstance(item, dict):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip()
    tipo = str(item.get("tipo") or "").strip()
    classe = str(item.get("classe") or "").strip()
    data_raw = str(item.get("dataPrevisao") or "").strip()
    try:
        bruto = float(item.get("valorBruto"))
    except (TypeError, ValueError):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado valorBruto numerico.")
    if not ticker or tipo not in TIPOS_VALIDOS or not classe:
        sys.exit(
            f"Item invalido: recebido {item!r} no indice {index}, "
            f"esperado ticker/classe nao-vazios e tipo um de: {sorted(TIPOS_VALIDOS)}."
        )
    if bruto <= 0:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado valorBruto > 0.")
    if not DATE_RE.match(data_raw):
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado dataPrevisao AAAA-MM-DD.")
    try:
        date.fromisoformat(data_raw)
    except ValueError:
        sys.exit(f"Item invalido: recebido {item!r} no indice {index}, esperado dataPrevisao AAAA-MM-DD.")
    out.append({"ticker": ticker, "tipo": tipo, "classe": classe, "valorBruto": bruto, "dataPrevisao": data_raw})

json.dump(out, sys.stdout)
PY
) || { echo "$NORMALIZADO" >&2; exit 1; }

  TEMPORARIO=$(mktemp "$SLUG/.proventos-provisionados.json.tmp.XXXXXX")
  trap 'rm -f "$TEMPORARIO"' EXIT

  EXISTENTE='[]'
  if [ -f "$PROVISIONADOS" ]; then
    EXISTENTE=$(cat "$PROVISIONADOS")
  fi

  jq -n --argjson existente "$EXISTENTE" --argjson novos "$NORMALIZADO" \
    '$existente + ($novos - $existente)' \
    > "$TEMPORARIO"

  mv "$TEMPORARIO" "$PROVISIONADOS"
  trap - EXIT
  exit 0
fi

echo "Comando invalido: recebido '$COMANDO', esperado registrar ou importar." >&2
exit 1
