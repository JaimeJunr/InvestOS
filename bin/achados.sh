#!/usr/bin/env bash
# Motor de achados: varre a carteira em busca de gatilhos objetivos (fato medido +
# severidade), sem nunca recomendar compra/venda - quem veste em narrativa e uma skill.
#
# Uso:
#   bin/achados.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/achados.sh <slug>

Varre <slug>/holdings.json em busca de achados objetivos: "concentracao"
(uma posicao no limiar da carteira ou acima, um achado por posicao - nao so
a maior), "desvio" (classe/mercado fora do threshold de
alocacao-alvo.json), "reserva" (reservaEmergenciaOk false) e "liquidez"
(posicao iliquida descasada de objetivo de prazo curto). A chave
"naoMedido" reporta o motivo quando um tipo nao pode ser calculado nesta
rodada (cotacao ausente, provider nao configurado, alvo ausente). Limiar de
concentracao deriva do perfilRisco em
<slug>/perfil-investidor.json (conservador 15%, moderado 25%, arrojado 40%;
ausente ou nao reconhecido usa moderado) e pode ser sobrescrito por um objeto
"limiares" no mesmo arquivo. Severidade "media" no limiar, "alta" a partir de
1,5x o limiar (ambas as fronteiras disparam no ponto). Cada achado traz so
fato medido, nunca recomendacao de compra/venda. Valoriza BR via
brapi-quote.sh; US/global exige ALOCACAO_QUOTE injetado. Ticker sem cotacao
torna o total da carteira desconhecido: o motor nao inventa percentual sobre
base parcial, entao o tipo "concentracao" inteiro sai da chave "naoMedido"
(com o(s) ticker(s) faltantes) em vez de "achados" nessa rodada. Dois motivos
distintos: "provider-nao-configurado" (mercado sem ALOCACAO_QUOTE injetado -
falha de configuracao, o usuario resolve) e "cotacao-ausente" (provider
falhou ou devolveu preco ausente/null/<=0 - falha de rede ou do dado).

Tipo "desvio" compara a alocacao atual contra <slug>/alocacao-alvo.json
(porClasse/porMercado/threshold); ausente vira naoMedido com motivo
"alvo-ausente" sem matar o script. Tipo "reserva" dispara alta quando
perfil-investidor.json.reservaEmergenciaOk e false (ausente nao dispara).
Tipo "liquidez" dispara alta quando ha objetivo de prazo "curto" em
perfil-investidor.json.objetivos[] e alguma posicao com liquidez D+<n>, n > 1.
"reserva" e "liquidez" nao dependem do total da carteira - saem mesmo quando
concentracao/desvio caem em naoMedido por falta de cotacao.
EOF
}

require_file() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo invalido: recebido path inexistente '$file', esperado $expected." >&2
    exit 1
  fi
}

source "$SCRIPT_DIR/lib-cotacao.sh"

collect_quotes() {
  local slug="$1" holdings="$2" dest="$3" sem_provider_dest="$4"
  local tickers ticker mercado preco_manual payload preco quotes sem_provider
  quotes="{}"
  sem_provider="[]"
  tickers=$(jq -c '.posicoes[] | {ticker: (.ticker|ascii_upcase), mercado: (.mercado|ascii_downcase), precoManual: (.precoManual // null)}' "$holdings")
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    ticker=$(jq -r '.ticker' <<<"$row")
    mercado=$(jq -r '.mercado' <<<"$row")
    if jq -e --arg t "$ticker" 'has($t)' <<<"$quotes" >/dev/null; then
      continue
    fi
    if jq -e --arg t "$ticker" 'index($t)' <<<"$sem_provider" >/dev/null; then
      continue
    fi
    preco_manual=$(jq -r '.precoManual // empty' <<<"$row")
    if [ -n "$preco_manual" ]; then
      quotes=$(jq --arg t "$ticker" --argjson p "$preco_manual" '.[$t] = $p' <<<"$quotes")
      continue
    fi
    # Mercado sem cotacao direta (so BR tem fallback via brapi-quote.sh) e
    # sem ALOCACAO_QUOTE injetado: falha de CONFIGURACAO do usuario, nao de
    # provider - motivo proprio rio abaixo (provider-nao-configurado), pra
    # nao ficar mudo atras do "cotacao-ausente" generico. Nao chama
    # quote_payload aqui: a mensagem dela ja e sabida, so precisamos do slug.
    if [ "$mercado" != "br" ] && [ -z "${ALOCACAO_QUOTE:-}" ]; then
      sem_provider=$(jq --arg t "$ticker" '. + [$t]' <<<"$sem_provider")
      continue
    fi
    # Falha de cotacao aqui (provider com status != 0, OU status 0 com
    # ".preco" ausente/null - caso real: brapi sem regularMarketPrice) deixa
    # o ticker fora de "quotes": vira achado naoMedido rio abaixo, nunca mata
    # o script (set -e so protege o que esta dentro do "if").
    if payload=$(quote_payload "$slug" "$ticker" "$mercado" 2>/dev/null); then
      if preco=$(jq -er '.preco | select(type == "number")' <<<"$payload" 2>/dev/null); then
        quotes=$(jq --arg t "$ticker" --argjson p "$preco" '.[$t] = $p' <<<"$quotes")
      fi
    fi
  done <<<"$tickers"
  printf '%s\n' "$quotes" > "$dest"
  printf '%s\n' "$sem_provider" > "$sem_provider_dest"
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

HOLDINGS="$SLUG/holdings.json"
PERFIL="$SLUG/perfil-investidor.json"
ALVO="$SLUG/alocacao-alvo.json"
require_file "$HOLDINGS" 'JSON {"posicoes": [{ticker, quantidade, classe, mercado}, ...]}'

QUOTES=$(mktemp)
SEM_PROVIDER=$(mktemp)
PERFIL_INPUT=$(mktemp)
ALVO_INPUT=$(mktemp)
trap 'rm -f "$QUOTES" "$SEM_PROVIDER" "$PERFIL_INPUT" "$ALVO_INPUT"' EXIT

if [ -f "$PERFIL" ]; then
  cat "$PERFIL" > "$PERFIL_INPUT"
else
  # perfil-investidor.json e opcional - ausencia cai no limiar de moderado.
  printf '%s\n' '{}' > "$PERFIL_INPUT"
fi

if [ -f "$ALVO" ]; then
  cat "$ALVO" > "$ALVO_INPUT"
else
  # alocacao-alvo.json e opcional aqui (ao contrario de alocacao.sh, que
  # exige e morre) - ausencia so tira o tipo "desvio" da rodada (naoMedido),
  # os outros tipos continuam. Arquivo vazio e o sinal de "ausente" pro
  # achados-report.py (nao ha JSON valido que seja 0 bytes).
  : > "$ALVO_INPUT"
fi

collect_quotes "$SLUG" "$HOLDINGS" "$QUOTES" "$SEM_PROVIDER"
python3 "$SCRIPT_DIR/achados-report.py" "$HOLDINGS" "$QUOTES" "$PERFIL_INPUT" "$SEM_PROVIDER" "$ALVO_INPUT"
