# Biblioteca compartilhada: cotacao de ticker (BR via brapi-quote.sh, US/global via override).
# Usada por alocacao.sh e diagnostico.sh - nao e um comando standalone.
#
# Requer $REPO_ROOT resolvido pelo script que faz source deste arquivo
# (usado para localizar bin/brapi-quote.sh a partir da raiz do repo).

quote_payload() {
  local slug="$1" ticker="$2" mercado="$3" raw
  if [ -n "${ALOCACAO_QUOTE:-}" ]; then
    "$ALOCACAO_QUOTE" "$slug" "$ticker" "$mercado"
    return
  fi
  if [ "$mercado" = "br" ]; then
    raw=$("$REPO_ROOT/bin/brapi-quote.sh" "$slug" "$ticker")
    jq -ce '{preco: .results[0].data.regularMarketPrice}' <<<"$raw"
    return
  fi
  echo "Cotacao indisponivel: recebido mercado '$mercado' ticker '$ticker', esperado mercado 'br' (brapi.dev) ou ALOCACAO_QUOTE injetado (MCP US e config declarativa, sem client HTTP)." >&2
  exit 1
}
