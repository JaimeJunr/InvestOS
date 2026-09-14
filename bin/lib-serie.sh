# Biblioteca compartilhada: serie historica de preco por ticker (BR via
# cvm-informe.sh para fundos ou brapi-quote.sh para acoes/ETFs/FIIs, US/global
# via override). Usada por risco.sh e achados.sh - nao e um comando standalone.
#
# Requer $REPO_ROOT resolvido pelo script que faz source deste arquivo (usado
# para localizar bin/cvm-informe.sh e bin/brapi-quote.sh a partir da raiz do
# repo) - mesma convencao de lib-cotacao.sh.

digits_only() {
  printf '%s' "$1" | tr -cd '0-9'
}

is_cnpj() {
  local digits
  digits=$(digits_only "$1")
  [ "${#digits}" -eq 14 ]
}

cvm_series() {
  local slug="$1" ticker="$2" raw digits
  digits=$(digits_only "$ticker")
  if ! raw=$("$REPO_ROOT/bin/cvm-informe.sh" "$slug"); then
    printf '%s\n' '[]'
    return
  fi
  jq -c --arg d "$digits" \
    '[.[] | select((.cnpj | gsub("[^0-9]"; "")) == $d) | {date: .dtComptc, close: .vlQuota}] | sort_by(.date)' \
    <<<"$raw"
}

brapi_series() {
  local slug="$1" ticker="$2" raw
  if ! raw=$(BRAPI_RANGE=3mo BRAPI_INTERVAL=1d "$REPO_ROOT/bin/brapi-quote.sh" "$slug" "$ticker"); then
    printf '%s\n' '[]'
    return
  fi
  jq -c \
    '(.results[0].data.historicalDataPrice // []) | map({date: ((.date | todateiso8601)[0:10]), close: (.adjustedClose // .close)}) | sort_by(.date)' \
    <<<"$raw"
}

history_payload() {
  local slug="$1" ticker="$2" mercado="$3"
  if [ -n "${RISCO_HISTORY:-}" ]; then
    "$RISCO_HISTORY" "$slug" "$ticker" "$mercado"
    return
  fi
  if [ "$mercado" = "br" ] && is_cnpj "$ticker"; then
    cvm_series "$slug" "$ticker"
    return
  fi
  if [ "$mercado" = "br" ]; then
    brapi_series "$slug" "$ticker"
    return
  fi
  printf '%s\n' '[]'
}
