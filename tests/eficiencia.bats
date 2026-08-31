#!/usr/bin/env bats
# Testes de fh-US-008: Sortino, giro de carteira e aliquota efetiva de IR.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/eficiencia.sh"
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
            {"data": "2026-01-16", "valorTotal": 120},
            {"data": "2026-01-23", "valorTotal": 132},
            {"data": "2026-01-30", "valorTotal": 118.8},
        ],
        fh,
    )
PY
}

write_transacoes() {
  python3 - "$1" <<'PY'
import json, sys

with open(f"{sys.argv[1]}/transacoes.json", "w", encoding="utf-8") as fh:
    json.dump(
        [
            {"data": "2026-01-02", "tipo": "aporte", "valor": 100},
            {"data": "2026-01-10", "tipo": "compra", "valor": 40},
            {"data": "2026-01-20", "tipo": "venda", "valor": 15, "impostoPago": 2, "ganhoRealizado": 10},
            {"data": "2026-01-25", "tipo": "resgate", "valor": 20},
        ],
        fh,
    )
PY
}

assert_known_metrics() {
  python3 -c '
import json, math, statistics, sys

report = json.loads(sys.argv[1])
returns = [0.20, 0.10, -0.10]
mean = statistics.fmean(returns)
downside = math.sqrt(sum(min(item, 0.0) ** 2 for item in returns) / len(returns))
stdev = statistics.pstdev(returns)
expected_sortino = mean / downside
expected_giro = 55.0 / 117.7
assert abs(report["sortino"] - expected_sortino) < 1e-9, report
assert abs(report["giro"] - expected_giro) < 1e-9, report
assert abs(report["aliquotaEfetiva"] - 0.2) < 1e-9, report
assert abs(report["sortino"] - mean / stdev) > 1e-6, report
' "$1"
}

assert_insuficiente() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
key = sys.argv[2]
assert report[key] == "dado insuficiente", (key, report)
assert not isinstance(report[key], (int, float)), (key, report)
' "$1" "$2"
}

@test "uso sem args: falha com mensagem de uso citando nav-historico e transacoes" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"nav-historico.json"* ]]
  [[ "$output" == *"transacoes.json"* ]]
}

@test "Sortino penaliza so desvio negativo a partir do nav-historico" {
  write_nav acme
  write_transacoes acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_known_metrics "$output"
  [ "$status" -eq 0 ]
}

@test "giro soma compra e venda e divide pelo valor medio do NAV; aporte e resgate nao entram" {
  write_nav acme
  write_transacoes acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["giro"] - (55.0 / 117.7)) < 1e-9, report
assert abs(report["giro"] - (175.0 / 117.7)) > 1e-6, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "aliquota efetiva e impostoPago sobre ganhoRealizado nos campos opcionais" {
  write_nav acme
  write_transacoes acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["aliquotaEfetiva"] - 0.2) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "transacoes.json ausente reporta dado insuficiente em giro e aliquota; Sortino segue do NAV" {
  write_nav acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run python3 -c '
import json, math, statistics, sys
report = json.loads(sys.argv[1])
returns = [0.20, 0.10, -0.10]
mean = statistics.fmean(returns)
downside = math.sqrt(sum(min(item, 0.0) ** 2 for item in returns) / len(returns))
assert abs(report["sortino"] - mean / downside) < 1e-9, report
' "$report"
  [ "$status" -eq 0 ]
  run assert_insuficiente "$report" giro
  [ "$status" -eq 0 ]
  run assert_insuficiente "$report" aliquotaEfetiva
  [ "$status" -eq 0 ]
}

@test "nav-historico insuficiente reporta dado insuficiente no Sortino em vez de numero" {
  write_transacoes acme
  python3 - <<'PY'
import json
with open("acme/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump([{"data": "2026-01-02", "valorTotal": 100}], fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report" sortino
  [ "$status" -eq 0 ]
  [[ "$report" == *"dado insuficiente"* ]]
}

@test "campos de IR ausentes reportam dado insuficiente sem inventar aliquota" {
  write_nav acme
  python3 - <<'PY'
import json
with open("acme/transacoes.json", "w", encoding="utf-8") as fh:
    json.dump(
        [
            {"data": "2026-01-10", "tipo": "compra", "valor": 40},
            {"data": "2026-01-20", "tipo": "venda", "valor": 15},
        ],
        fh,
    )
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report" aliquotaEfetiva
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["giro"] - (55.0 / 117.7)) < 1e-9, report
assert isinstance(report["sortino"], float), report
' "$report"
  [ "$status" -eq 0 ]
}
