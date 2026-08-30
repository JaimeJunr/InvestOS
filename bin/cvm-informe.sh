#!/usr/bin/env bash
# Parser do Informe Diario de Fundos da CVM (CSV/ZIP), filtrado pela watchlist.
#
# Uso:
#   bin/cvm-informe.sh <slug> [YYYYMM]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CVM_BASE_URL="${CVM_BASE_URL:-https://dados.cvm.gov.br/dados/FI/DOC/INF_DIARIO/DADOS}"

usage() {
  cat <<EOF
Uso: bin/cvm-informe.sh <slug> [YYYYMM]

Parser do Informe Diario de Fundos da CVM (dados.cvm.gov.br, CSV/ZIP).
Atualizacao batch diaria do ZIP do mes corrente (M e M-1 republicam todo dia util).
Filtra so os fundos da watchlist em <slug>/watchlist-fundos.json
({"cnpjs": ["12.345.678/0001-90"]}). CNPJ casa com ou sem pontuacao.
EOF
}

now_epoch() {
  if [ -n "${CVM_NOW:-}" ]; then
    printf '%s' "$CVM_NOW"
  else
    date +%s
  fi
}

ymd_utc() {
  date -u -d "@$1" +%F
}

ym_utc() {
  date -u -d "@$1" +%Y%m
}

http_get_file() {
  local url="$1" dest="$2"
  if [ -n "${CVM_HTTP_GET:-}" ]; then
    "$CVM_HTTP_GET" "$url" > "$dest"
  else
    curl -fsS "$url" -o "$dest"
  fi
}

require_watchlist() {
  local file="$1" received
  if [ ! -f "$file" ]; then
    echo "Watchlist invalida: recebido arquivo inexistente '$file', esperado JSON {\"cnpjs\": [\"<CNPJ>\"]} com pelo menos 1 CNPJ." >&2
    exit 1
  fi
  received=$(jq -c '.' "$file" 2>/dev/null || printf '%s' "")
  if ! jq -e '.cnpjs | type == "array" and length > 0' "$file" >/dev/null 2>&1; then
    echo "Watchlist invalida: recebido '$received', esperado JSON {\"cnpjs\": [\"<CNPJ>\"]} com pelo menos 1 CNPJ em $file." >&2
    exit 1
  fi
}

cache_fresh_today() {
  local meta="$1" zip="$2" now="$3" fetched
  [ -f "$meta" ] && [ -f "$zip" ] || return 1
  fetched=$(jq -r '.fetchedAt' "$meta")
  [ "$(ymd_utc "$fetched")" = "$(ymd_utc "$now")" ]
}

write_fetch_meta() {
  local meta="$1" now="$2"
  jq -n --argjson fetched "$now" '{fetchedAt: $fetched}' > "$meta"
}

parse_informe_csv() {
  local watchlist="$1"
  python3 "$SCRIPT_DIR/cvm-informe-parse.py" "$watchlist"
}

SLUG="${1:-}"
MONTH="${2:-}"

if [ -z "$SLUG" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

WATCHLIST="$SLUG/watchlist-fundos.json"
require_watchlist "$WATCHLIST"

NOW=$(now_epoch)
if [ -z "$MONTH" ]; then
  MONTH=$(ym_utc "$NOW")
fi
if [[ ! "$MONTH" =~ ^[0-9]{6}$ ]]; then
  echo "Mes invalido: recebido '$MONTH', esperado YYYYMM com 6 digitos." >&2
  exit 1
fi

CACHE_DIR="$SLUG/_cache/cvm"
ZIP="$CACHE_DIR/inf_diario_fi_${MONTH}.zip"
META="$CACHE_DIR/inf_diario_fi_${MONTH}.meta.json"
URL="$CVM_BASE_URL/inf_diario_fi_${MONTH}.zip"

mkdir -p "$CACHE_DIR"
if ! cache_fresh_today "$META" "$ZIP" "$NOW"; then
  http_get_file "$URL" "$ZIP"
  write_fetch_meta "$META" "$NOW"
fi

unzip -p "$ZIP" | parse_informe_csv "$WATCHLIST"
