#!/usr/bin/env bats
# Testes de registro de proventos provisionados (anunciados, ainda nao pagos)
# em proventos-provisionados.json. Sem valorLiquido: retencao so e conhecida
# no pagamento real. dataPrevisao e obrigatoria (sem default de hoje).

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/provento-provisionado.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "registrar grava um provento provisionado novo em proventos-provisionados.json" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 dividendo acoes 1.20 2026-12-15
  [ "$status" -eq 0 ]
  run jq -e '. == [{ticker: "EGIE3", tipo: "dividendo", classe: "acoes", valorBruto: 1.20, dataPrevisao: "2026-12-15"}]' acme/proventos-provisionados.json
  [ "$status" -eq 0 ]
  run jq -e '.[0] | has("valorLiquido") | not' acme/proventos-provisionados.json
  [ "$status" -eq 0 ]
}

@test "tipo invalido e rejeitado com valor recebido e esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 bonus acoes 1.20 2026-12-15
  [ "$status" -ne 0 ]
  [[ "$output" == *"bonus"* ]]
  [[ "$output" == *"dividendo"* ]]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "valorBruto invalido (zero, negativo, nao-numero) e rejeitado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 dividendo acoes 0 2026-12-15
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar EGIE3 dividendo acoes -1 2026-12-15
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar EGIE3 dividendo acoes abacate 2026-12-15
  [ "$status" -ne 0 ]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "classe vazia e rejeitada" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 dividendo "" 1.20 2026-12-15
  [ "$status" -ne 0 ]
  [[ "$output" == *"classe"* ]]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "dataPrevisao ausente e rejeitada (obrigatoria, sem default de hoje)" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 dividendo acoes 1.20
  [ "$status" -ne 0 ]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "dataPrevisao em formato errado e rejeitada (esperado AAAA-MM-DD)" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar EGIE3 dividendo acoes 1.20 15/12/2026
  [ "$status" -ne 0 ]
  [[ "$output" == *"AAAA-MM-DD"* ]]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "importar rejeita item invalido no array, nao grava nada (all-or-nothing)" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "EGIE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 1.20, "dataPrevisao": "2026-12-15"},
    {"ticker": "RUIM3", "tipo": "invalido", "classe": "acoes", "valorBruto": 1.0, "dataPrevisao": "2026-12-01"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"RUIM3"* ]] || [[ "$output" == *"invalido"* ]]
  [ ! -e "acme/proventos-provisionados.json" ]
}

@test "importar acumula sobre arquivo ja nao-vazio: segundo lote com eventos genuinamente novos nao e descartado" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "EGIE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 1.20, "dataPrevisao": "2026-12-15"}]
with open("lote1.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote1.json
  [ "$status" -eq 0 ]

  python3 - <<'PY'
import json
payload = [
    {"ticker": "VALE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 3.0, "dataPrevisao": "2026-10-01"},
    {"ticker": "HGLG11", "tipo": "rendimento", "classe": "fiis", "valorBruto": 1.5, "dataPrevisao": "2026-09-01"},
]
with open("lote2.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote2.json
  [ "$status" -eq 0 ]

  run jq -e 'length == 3' acme/proventos-provisionados.json
  [ "$status" -eq 0 ]
  run jq -e '[.[] | .ticker] | sort == ["EGIE3", "HGLG11", "VALE3"]' acme/proventos-provisionados.json
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme importar lote2.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 3' acme/proventos-provisionados.json
  [ "$status" -eq 0 ]
}
