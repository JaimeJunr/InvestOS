#!/usr/bin/env bash
# Registra o valor total da carteira no historico diario de NAV.
#
# Uso:
#   bin/nav-snapshot.sh <slug>                          # valor atual, calculado ao vivo
#   bin/nav-snapshot.sh <slug> --valor <n> --data <AAAA-MM-DD>  # ponto historico conhecido
#     (ex.: extrato da corretora) - nao consulta cotacao nenhuma.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Uso: bin/nav-snapshot.sh <slug>
     bin/nav-snapshot.sh <slug> --valor <numero> --data <AAAA-MM-DD>

Sem --valor/--data, calcula o valor total atual (bin/alocacao.sh) e grava/atualiza
a entrada do dia em <slug>/nav-historico.json - idempotente, sobrescreve a
entrada do dia se rodar de novo.

Com --valor e --data (os dois juntos, nunca so um), registra um ponto historico
conhecido (ex.: extrato da corretora) sem consultar cotacao nenhuma - util pra dar
um baseline real antes de a serie acumular organicamente. valor aceita 0 (patrimonio
comecando do zero) mas nao negativo; data no formato AAAA-MM-DD.
EOF
}

SLUG="${1:-}"
shift || true

if [ -z "$SLUG" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

VALOR=""
DATA=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --valor)
      VALOR="${2:-}"
      shift 2
      ;;
    --data)
      DATA="${2:-}"
      shift 2
      ;;
    *)
      echo "Argumento invalido: recebido '$1', esperado --valor ou --data." >&2
      exit 1
      ;;
  esac
done

if [ -n "$VALOR" ] && [ -z "$DATA" ]; then
  echo "Uso invalido: recebido --valor sem --data, esperado os dois juntos (ou nenhum, pra usar o valor atual)." >&2
  exit 1
fi
if [ -z "$VALOR" ] && [ -n "$DATA" ]; then
  echo "Uso invalido: recebido --data sem --valor, esperado os dois juntos (ou nenhum, pra usar o valor atual)." >&2
  exit 1
fi

if [ -n "$VALOR" ]; then
  if ! [[ "$VALOR" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Valor invalido: recebido '$VALOR', esperado numero >= 0." >&2
    exit 1
  fi
  if awk -v v="$VALOR" 'BEGIN { exit !(v < 0) }'; then
    echo "Valor invalido: recebido '$VALOR', esperado numero >= 0." >&2
    exit 1
  fi
  if ! [[ "$DATA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Data invalida: recebido '$DATA', esperado formato AAAA-MM-DD." >&2
    exit 1
  fi
  VALOR_TOTAL="$VALOR"
  DATA_ALVO="$DATA"
else
  RELATORIO=$("$SCRIPT_DIR/alocacao.sh" "$SLUG")
  VALOR_TOTAL=$(jq -er '.total' <<<"$RELATORIO")
  DATA_ALVO=$(date +%Y-%m-%d)
fi

HISTORICO="$SLUG/nav-historico.json"
TEMPORARIO=$(mktemp "$SLUG/.nav-historico.json.tmp.XXXXXX")
trap 'rm -f "$TEMPORARIO"' EXIT

if [ -f "$HISTORICO" ]; then
  jq --arg data "$DATA_ALVO" --argjson valorTotal "$VALOR_TOTAL" \
    '(map(select(.data != $data)) + [{data: $data, valorTotal: $valorTotal}]) | sort_by(.data)' \
    "$HISTORICO" > "$TEMPORARIO"
else
  jq -n --arg data "$DATA_ALVO" --argjson valorTotal "$VALOR_TOTAL" \
    '[{data: $data, valorTotal: $valorTotal}]' > "$TEMPORARIO"
fi

mv "$TEMPORARIO" "$HISTORICO"
trap - EXIT
