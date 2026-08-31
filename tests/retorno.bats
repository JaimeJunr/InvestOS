#!/usr/bin/env bats
# Testes de fh-US-007: TWR e MWR.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/retorno.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  mkdir -p acme
}

teardown() {
  rm -rf "$WORKDIR"
}

write_nav() {
  python3 - "$1" <<'PY'
import json, sys

with open(f"{sys.argv[1]}/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump(
        [
            {"data": "2026-01-02", "valorTotal": 100},
            {"data": "2026-01-16", "valorTotal": 160},
            {"data": "2026-01-30", "valorTotal": 150},
        ],
        fh,
    )
PY
}

write_fluxos() {
  python3 - "$1" <<'PY'
import json, sys

with open(f"{sys.argv[1]}/transacoes.json", "w", encoding="utf-8") as fh:
    json.dump(
        [
            {"data": "2026-01-02", "tipo": "aporte", "valor": 100},
            {"data": "2026-01-10", "tipo": "aporte", "valor": 50},
            {"data": "2026-01-20", "tipo": "resgate", "valor": 20},
        ],
        fh,
    )
PY
}

assert_known_returns() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["twr"] - 0.16875) < 1e-9, report
assert abs(report["mwr"] - 0.15606143314773038) < 1e-9, report
assert report["twr"] != report["mwr"], report
' "$1"
}

assert_insuficiente() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
for key in ("twr", "mwr"):
    assert report[key] == "dado insuficiente", (key, report)
    assert not isinstance(report[key], (int, float)), (key, report)
' "$1"
}

@test "uso sem args: falha com mensagem de uso citando nav-historico e transacoes" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"nav-historico.json"* ]]
  [[ "$output" == *"transacoes.json"* ]]
}

@test "TWR encadeia sub-periodos isolando aporte/resgate e MWR e IRR dos fluxos + valor final" {
  write_nav acme
  write_fluxos acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_known_returns "$output"
  [ "$status" -eq 0 ]
}

@test "compra e venda internas nao entram no isolamento do TWR nem nos fluxos do MWR" {
  write_nav acme
  write_fluxos acme
  python3 - <<'PY'
import json
with open("acme/transacoes.json", encoding="utf-8") as fh:
    rows = json.load(fh)
rows.extend(
    [
        {"data": "2026-01-12", "tipo": "compra", "valor": 40},
        {"data": "2026-01-22", "tipo": "venda", "valor": 15},
    ]
)
with open("acme/transacoes.json", "w", encoding="utf-8") as fh:
    json.dump(rows, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_known_returns "$output"
  [ "$status" -eq 0 ]
}

@test "transacoes.json ausente reporta dado insuficiente sem calcular" {
  write_nav acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"dado insuficiente"* ]]
}

@test "nav-historico.json ausente reporta dado insuficiente sem calcular" {
  write_fluxos acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"dado insuficiente"* ]]
}

@test "um unico snapshot de NAV reporta dado insuficiente em vez de numero" {
  write_fluxos acme
  python3 - <<'PY'
import json
with open("acme/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump([{"data": "2026-01-02", "valorTotal": 100}], fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"dado insuficiente"* ]]
}

@test "transacoes.json vazio reporta dado insuficiente sem calcular" {
  write_nav acme
  printf '[]\n' > acme/transacoes.json

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"dado insuficiente"* ]]
}
