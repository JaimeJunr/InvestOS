#!/usr/bin/env bash
# Consulta Selic/CDI no BCB SGS, com cache local por portfolio.
# O dado e informativo; este script nunca recomenda investimento.
#
# Uso:
#   bin/macro-brasil.sh <slug>

set -euo pipefail

CACHE_TTL="${MACRO_CACHE_TTL_SECONDS:-86400}"
BCB_SGS_BASE_URL="https://api.bcb.gov.br/dados/serie/bcdata.sgs"

usage() {
  cat <<EOF
Uso: bin/macro-brasil.sh <slug>

Consulta Selic e CDI diarios no BCB SGS e devolve dados macroeconomicos
informativos em JSON. Cache local em <slug>/_cache/macro/ (TTL ${CACHE_TTL}s).
EOF
}

now_epoch() {
  if [ -n "${MACRO_NOW:-}" ]; then
    printf '%s' "$MACRO_NOW"
  else
    date +%s
  fi
}

http_get() {
  local url="$1"
  if [ -n "${MACRO_HTTP_GET:-}" ]; then
    "$MACRO_HTTP_GET" "$url"
  else
    curl -fsS --connect-timeout 10 --max-time 30 "$url"
  fi
}

read_fresh_cache() {
  local file="$1" now="$2"
  if [ ! -f "$file" ]; then
    return 1
  fi
  jq -ce --argjson now "$now" --argjson ttl "$CACHE_TTL" \
    'select((.fetchedAt | type == "number") and ($now - .fetchedAt < $ttl)) | .payload' "$file"
}

write_cache() {
  local file="$1" payload="$2" now="$3"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$payload" | jq -c --argjson fetched "$now" \
    '{fetchedAt: $fetched, payload: .}' > "$file"
}

normalize_date() {
  local raw_date="$1" iso parsed

  if [[ "$raw_date" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{4})$ ]]; then
    iso="${BASH_REMATCH[3]}-${BASH_REMATCH[2]}-${BASH_REMATCH[1]}"
  elif [[ "$raw_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    iso="$raw_date"
  else
    return 1
  fi

  if ! parsed=$(date -u -d "$iso" +%F 2>/dev/null) || [ "$parsed" != "$iso" ]; then
    return 1
  fi
  printf '%s' "$iso"
}

parse_series() {
  local code="$1" url raw record raw_value raw_date value_number iso_date normalized_value
  url="$BCB_SGS_BASE_URL.$code/dados/ultimos/1?formato=json"

  if ! raw=$(http_get "$url"); then
    echo "Falha ao consultar BCB SGS: recebido erro ao buscar serie '$code' (URL '$url'), esperado HTTP 200 com JSON da serie." >&2
    return 1
  fi

  if ! record=$(printf '%s' "$raw" | jq -ce \
    'if (type == "array" and length > 0 and (.[0] | type == "object")) then .[0] else error("formato") end' \
    2>/dev/null); then
    echo "Resposta BCB SGS invalida: recebido '$raw', esperado array JSON com objeto contendo data e valor." >&2
    return 1
  fi

  raw_value=$(printf '%s' "$record" | jq -r 'if .valor == null then empty else (.valor | tostring) end')
  raw_date=$(printf '%s' "$record" | jq -r 'if .data == null then empty else (.data | tostring) end')

  normalized_value="${raw_value//,/.}"
  if [ -z "$normalized_value" ] || [[ ! "$normalized_value" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]]; then
    echo "Valor BCB SGS invalido: recebido '$raw_value', esperado numero na serie '$code'." >&2
    return 1
  fi
  if ! value_number=$(jq -cn --arg value "$normalized_value" '$value | tonumber' 2>/dev/null); then
    echo "Valor BCB SGS invalido: recebido '$raw_value', esperado numero na serie '$code'." >&2
    return 1
  fi

  if ! iso_date=$(normalize_date "$raw_date"); then
    echo "Data BCB SGS invalida: recebido '$raw_date', esperado data no formato AAAA-MM-DD ou DD/MM/AAAA na serie '$code'." >&2
    return 1
  fi

  printf '%s\t%s\n' "$value_number" "$iso_date"
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

NOW=$(now_epoch)
CACHE="$SLUG/_cache/macro/selic-cdi.json"

if payload=$(read_fresh_cache "$CACHE" "$NOW"); then
  printf '%s\n' "$payload"
  exit 0
fi

if ! selic=$(parse_series 432); then
  exit 1
fi
if ! cdi=$(parse_series 12); then
  exit 1
fi

IFS=$'\t' read -r SELIC_VALUE SELIC_DATE <<< "$selic"
IFS=$'\t' read -r CDI_VALUE CDI_DATE <<< "$cdi"

PAYLOAD=$(jq -cn \
  --argjson selic "$SELIC_VALUE" \
  --arg selic_date "$SELIC_DATE" \
  --argjson cdi "$CDI_VALUE" \
  --arg cdi_date "$CDI_DATE" \
  '{metaSelicAnual: $selic, metaSelicData: $selic_date, cdiDiario: $cdi, cdiData: $cdi_date, fonte: "BCB SGS", aviso: "Dado informativo, nao e recomendacao de investimento."}')

write_cache "$CACHE" "$PAYLOAD" "$NOW"
printf '%s\n' "$PAYLOAD"
