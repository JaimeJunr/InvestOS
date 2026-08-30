#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/transacao.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  mkdir -p acme
}

teardown() {
  rm -rf "$WORKDIR"
}

@test "registra os quatro tipos validos e preserva o append com valor numerico" {
  run "$SCRIPT" acme registrar aporte 100.50 2026-08-30
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme registrar resgate 40 2026-08-30
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme registrar compra 12.75 2026-08-30
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme registrar venda 8.25 2026-08-30
  [ "$status" -eq 0 ]

  run jq -e '
    type == "array"
    and length == 4
    and all(.[];
      type == "object"
      and (keys | sort) == ["data", "tipo", "valor"]
      and ((.valor | type) == "number")
    )
    and . == [
      {"data": "2026-08-30", "tipo": "aporte", "valor": 100.50},
      {"data": "2026-08-30", "tipo": "resgate", "valor": 40},
      {"data": "2026-08-30", "tipo": "compra", "valor": 12.75},
      {"data": "2026-08-30", "tipo": "venda", "valor": 8.25}
    ]
  ' acme/transacoes.json
  [ "$status" -eq 0 ]
}

@test "data omitida usa a data de hoje" {
  hoje="$(date +%Y-%m-%d)"

  run "$SCRIPT" acme registrar aporte 123.45
  [ "$status" -eq 0 ]

  run jq -e --arg hoje "$hoje" '
    type == "array"
    and length == 1
    and .[0] == {"data": $hoje, "tipo": "aporte", "valor": 123.45}
    and ((.[0].valor | type) == "number")
  ' acme/transacoes.json
  [ "$status" -eq 0 ]
}

@test "tipo invalido falha com recebido, esperado e enum sem criar arquivo" {
  run "$SCRIPT" acme registrar dividendo 100 2026-08-30
  [ "$status" -eq 1 ]
  [[ "$output" == *"dividendo"* ]]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]
  [[ "$output" == *"aporte"* ]]
  [[ "$output" == *"resgate"* ]]
  [[ "$output" == *"compra"* ]]
  [[ "$output" == *"venda"* ]]
  [ ! -e acme/transacoes.json ]
}

@test "valor zero, negativo ou texto falha com recebido e esperado sem criar arquivo" {
  for valor in 0 -10 abacate; do
    run "$SCRIPT" acme registrar aporte "$valor" 2026-08-30
    [ "$status" -eq 1 ]
    [[ "$output" == *"$valor"* ]]
    [[ "$output" == *"recebido"* ]]
    [[ "$output" == *"esperado"* ]]
    [ ! -e acme/transacoes.json ]
  done
}
