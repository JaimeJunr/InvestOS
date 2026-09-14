#!/usr/bin/env bash
# Resolve holdings do portfolio: Plaid quando houver credencial, senao holdings.json manual.
#
# Uso:
#   bin/holdings-sync.sh <slug>
#
# MCP Plaid e config declarativa (bi-US-001); este CLI nao chama API real.
# Fetch injetavel via HOLDINGS_FETCH. Sem credencial, nao busca e nao altera
# <slug>/holdings.json. Falha de token/conexao mantem o ultimo arquivo conhecido
# e avisa a idade do dado — nunca zera a carteira nem trava as outras features.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/holdings-sync.sh <slug>

Atualiza <slug>/holdings.json a partir da corretora quando PLAID_CLIENT_ID e
PLAID_SECRET estiverem preenchidos no <slug>/.env. Sem credencial, usa o
holdings.json manual. Fetch via HOLDINGS_FETCH (MCP Plaid e config declarativa,
sem client HTTP first-party). Falha de conexao/token nao zera a carteira:
mantem o ultimo holdings.json conhecido e avisa a idade do dado.
Campos manuais (precoManual, liquidez) sao casados por ticker+mercado e
preservados do local ao aplicar o payload da corretora - a corretora nunca
os produz. Local sempre vence em conflito, e posicao ausente do payload
novo e mantida, nunca removida silenciosamente; ambos os casos emitem
aviso em stderr.
EOF
}

now_epoch() {
  if [ -n "${HOLDINGS_NOW:-}" ]; then
    printf '%s' "$HOLDINGS_NOW"
  else
    date +%s
  fi
}

plaid_connected() {
  local slug="$1"
  "$REPO_ROOT/bin/credencial.sh" "$slug" has PLAID_CLIENT_ID >/dev/null 2>&1 \
    && "$REPO_ROOT/bin/credencial.sh" "$slug" has PLAID_SECRET >/dev/null 2>&1
}

meta_path() {
  printf '%s/_cache/plaid/meta.json' "$1"
}

age_seconds() {
  local meta="$1" fetched
  if [ ! -f "$meta" ]; then
    return 0
  fi
  fetched=$(jq -er '.fetchedAt' "$meta" 2>/dev/null || true)
  if [ -z "$fetched" ]; then
    return 0
  fi
  echo $(($(now_epoch) - fetched))
}

warn_stale() {
  local holdings="$1" meta="$2" reason="$3" age
  age=$(age_seconds "$meta")
  if [ -n "$age" ]; then
    echo "aviso: $reason; mantendo ultimo holdings.json conhecido em '$holdings' (idade ${age}s)." >&2
  else
    echo "aviso: $reason; mantendo ultimo holdings.json conhecido em '$holdings' (idade desconhecida)." >&2
  fi
}

write_meta() {
  local meta="$1"
  mkdir -p "$(dirname "$meta")"
  jq -nc --argjson fetched "$(now_epoch)" '{fetchedAt: $fetched}' > "$meta"
}

payload_tem_posicoes() {
  jq -e '.posicoes | type == "array" and length > 0' >/dev/null 2>&1 <<<"$1"
}

# Campos manuais: so o /instalar produz (posicao sem ticker cotavel, ex. Tesouro
# Direto). Casamento por ticker+mercado (evita colisao de ticker repetido entre
# mercados). Local sempre vence em conflito e posicao ausente do payload da
# corretora e preservada, nunca removida silenciosamente - o script roda
# nao-interativo (cron/CLI), entao a "pergunta ao usuario" vira aviso explicito
# em stderr em vez de bloquear em stdin.
CAMPOS_MANUAIS='["precoManual","liquidez"]'

merge_posicoes() {
  local local_json="$1" payload="$2"
  jq -c -n --argjson broker "$payload" --argjson local "$local_json" --argjson campos "$CAMPOS_MANUAIS" '
    def chave(p): (p.ticker | ascii_upcase) + "|" + (p.mercado | ascii_downcase);
    ($local.posicoes // []) as $lp
    | ($lp | map({(chave(.)): .}) | add // {}) as $lidx
    | ($broker.posicoes // []) as $bp
    | ($bp | map(chave(.))) as $bkeys
    | ($bp | map(
        . as $b
        | (chave($b)) as $k
        | ($lidx[$k]) as $l
        | if $l == null then $b
          else reduce $campos[] as $campo ($b;
              if ($l | has($campo)) then . + {($campo): $l[$campo]} else . end
            )
          end
      )) as $merged
    | ($lp | map(select((chave(.)) as $k | ($bkeys | index($k)) == null))) as $orfaos
    | {posicoes: ($merged + $orfaos)}
  '
}

merge_warnings() {
  local local_json="$1" payload="$2"
  jq -r -n --argjson broker "$payload" --argjson local "$local_json" --argjson campos "$CAMPOS_MANUAIS" '
    def chave(p): (p.ticker | ascii_upcase) + "|" + (p.mercado | ascii_downcase);
    ($local.posicoes // []) as $lp
    | ($lp | map({(chave(.)): .}) | add // {}) as $lidx
    | ($broker.posicoes // []) as $bp
    | ($bp | map(chave(.))) as $bkeys
    | (
        $bp[] | . as $b | (chave($b)) as $k | ($lidx[$k]) as $l
        | select($l != null)
        | ($campos[] as $campo
            | select(($l | has($campo)) and ($b | has($campo)) and ($l[$campo] != $b[$campo]))
            | "conflito em \($k): campo \($campo) local=\($l[$campo]) corretora=\($b[$campo]) - mantendo valor local"
          )
      ),
      (
        $lp[] | select((chave(.)) as $k | ($bkeys | index($k)) == null)
        | "posicao \(.ticker)/\(.mercado) ausente no payload da corretora - mantendo posicao local"
      )
  '
}

fetch_holdings() {
  local slug="$1"
  if [ -z "${HOLDINGS_FETCH:-}" ]; then
    echo "conexao indisponivel: recebido HOLDINGS_FETCH vazio, esperado comando injetado (MCP Plaid e config declarativa, sem client HTTP)"
    return 1
  fi
  "$HOLDINGS_FETCH" "$slug"
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
META=$(meta_path "$SLUG")

if ! plaid_connected "$SLUG"; then
  exit 0
fi

set +e
PAYLOAD=$(fetch_holdings "$SLUG" 2>/dev/null)
FETCH_STATUS=$?
set -e

if [ "$FETCH_STATUS" -ne 0 ] || ! payload_tem_posicoes "$PAYLOAD"; then
  warn_stale "$HOLDINGS" "$META" "token expirado ou conexao falhou"
  exit 0
fi

BROKER_JSON=$(jq -c '{posicoes: .posicoes}' <<<"$PAYLOAD")
if [ -f "$HOLDINGS" ]; then
  LOCAL_JSON=$(jq -c '.' "$HOLDINGS")
else
  LOCAL_JSON='{"posicoes":[]}'
fi

WARNINGS=$(merge_warnings "$LOCAL_JSON" "$BROKER_JSON")
if [ -n "$WARNINGS" ]; then
  while IFS= read -r linha; do
    echo "aviso: $linha" >&2
  done <<<"$WARNINGS"
fi

merge_posicoes "$LOCAL_JSON" "$BROKER_JSON" > "$HOLDINGS"
write_meta "$META"
