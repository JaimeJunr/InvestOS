#!/usr/bin/env bats
# Testes do motor de achados: os quatro tipos (concentracao, desvio, reserva,
# liquidez) e a chave "naoMedido" que reporta quando um tipo nao pode ser
# calculado na rodada.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/achados.sh"
  FAKE_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export ALOCACAO_QUOTE="$FAKE_QUOTE"
  export ALOCACAO_QUOTE_PRICES="$WORKDIR/prices.json"
  export ALOCACAO_QUOTE_LOG="$WORKDIR/quote.log"
  : > "$ALOCACAO_QUOTE_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  local slug="$1"
  mkdir -p "$slug"
  : > "$slug/.env"
}

write_holdings() {
  local slug="$1" positions_json="$2"
  python3 - "$slug" "$positions_json" <<'PY'
import json, sys
slug, positions_json = sys.argv[1], sys.argv[2]
payload = {"posicoes": json.loads(positions_json)}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

write_prices() {
  local prices_json="$1"
  python3 - "$ALOCACAO_QUOTE_PRICES" "$prices_json" <<'PY'
import json, sys
path, prices_json = sys.argv[1], sys.argv[2]
with open(path, "w", encoding="utf-8") as fh:
    json.dump(json.loads(prices_json), fh)
PY
}

write_perfil() {
  local slug="$1" perfil_json="$2"
  python3 - "$slug" "$perfil_json" <<'PY'
import json, sys
slug, perfil_json = sys.argv[1], sys.argv[2]
with open(f"{slug}/perfil-investidor.json", "w", encoding="utf-8") as fh:
    json.dump(json.loads(perfil_json), fh)
PY
}

write_alvo() {
  local slug="$1" alvo_json="$2"
  python3 - "$slug" "$alvo_json" <<'PY'
import json, sys
slug, alvo_json = sys.argv[1], sys.argv[2]
with open(f"{slug}/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump(json.loads(alvo_json), fh)
PY
}

@test "uso sem args: falha com mensagem de uso citando holdings.json" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"holdings.json"* ]]
}

@test "carteira com 3 posicoes acima do limiar moderado (default): um achado por posicao, nao so a maior" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "C", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"A": 3000, "B": 3000, "C": 4000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
# So concentracao e afirmada aqui: alocacao-alvo.json nao foi escrito neste
# teste, entao o tipo "desvio" cai em naoMedido (motivo alvo-ausente) por
# desenho - nao e regressao, e o novo tipo entrando na rodada.
assert not [n for n in report["naoMedido"] if n["tipo"] == "concentracao"], report
achados = report["achados"]
assert len(achados) == 3, achados
tickers = {a["medidas"]["ticker"] for a in achados}
assert tickers == {"A", "B", "C"}, tickers
for a in achados:
    assert a["tipo"] == "concentracao", a
    assert a["licao"] == "concentracao-por-ativo", a
    assert "limiarSobrescrito" not in a, a
' "$output"
  [ "$status" -eq 0 ]
}

@test "carteira exatamente no limiar (todas as 4 posicoes em 25%): AC4 manda disparar no limiar, nao so acima" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "C", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "D", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"A": 2500, "B": 2500, "C": 2500, "D": 2500}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
# Idem: sem alocacao-alvo.json, "desvio" cai em naoMedido por desenho.
assert not [n for n in report["naoMedido"] if n["tipo"] == "concentracao"], report
achados = report["achados"]
assert len(achados) == 4, achados
for a in achados:
    assert a["severidade"] == "media", a
' "$output"
  [ "$status" -eq 0 ]
}

@test "boundary do limiar moderado: abaixo nao dispara, exatamente no limiar dispara media, exatamente em 1,5x dispara alta" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "LOW", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "AT", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "HIGH", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "REST", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  # total = 10000; limiar moderado = 0.25 -> AT = 2500 (25%, no limiar);
  # 1,5x limiar = 0.375 -> HIGH = 3750 (37,5%, exatamente na fronteira alta);
  # LOW = 2000 (20%, abaixo do limiar); REST fecha o total, tambem abaixo.
  write_prices '{"LOW": 2000, "AT": 2500, "HIGH": 3750, "REST": 1750}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achados = {a["medidas"]["ticker"]: a for a in report["achados"]}
assert "LOW" not in achados, achados
assert "REST" not in achados, achados
assert achados["AT"]["severidade"] == "media", achados["AT"]
assert achados["HIGH"]["severidade"] == "alta", achados["HIGH"]
' "$output"
  [ "$status" -eq 0 ]
}

@test "boundary da concentracao com valores decimais comuns (perfil arrojado, limiar 0.40): exatamente 1,5x o limiar dispara alta" {
  # Mesma familia de bug do "desvio": severidade_concentracao compara
  # "percentual >= limiar * 1.5" - em float, 0.40 * 1.5 == 0.6000000000000001
  # (nao 0.6), entao uma posicao com EXATAMENTE 60% da carteira (o proprio
  # ponto de fronteira 1,5x) deixava de disparar "alta" e caia em "media".
  # 6000/10000 e 4000/10000 sao valores decimais comuns, nao fracoes binarias
  # escolhidas a dedo - equivalente ao caso realista do "desvio" acima.
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 6000, "Y": 4000}'
  write_perfil acme '{"perfilRisco": "arrojado"}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado_x = next(a for a in report["achados"] if a["medidas"]["ticker"] == "X")
assert achado_x["medidas"]["percentual"] == 0.6, achado_x
assert achado_x["severidade"] == "alta", achado_x
' "$output"
  [ "$status" -eq 0 ]
}

@test "mesmo percentual gera severidade diferente conforme o perfil (conservador vs arrojado)" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 4500, "Y": 5500}'

  write_perfil acme '{"perfilRisco": "conservador"}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado_x = next(a for a in report["achados"] if a["medidas"]["ticker"] == "X")
assert achado_x["severidade"] == "alta", achado_x
' "$output"
  [ "$status" -eq 0 ]

  write_perfil acme '{"perfilRisco": "arrojado"}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado_x = next(a for a in report["achados"] if a["medidas"]["ticker"] == "X")
assert achado_x["severidade"] == "media", achado_x
' "$output"
  [ "$status" -eq 0 ]
}

@test "perfil-investidor.json ausente: usa limiar de moderado, nao quebra" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 3000, "Y": 7000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado_x = next(a for a in report["achados"] if a["medidas"]["ticker"] == "X")
assert achado_x["severidade"] == "media", achado_x
assert abs(achado_x["medidas"]["limiar"] - 0.25) < 1e-9, achado_x
assert "limiarSobrescrito" not in achado_x, achado_x
' "$output"
  [ "$status" -eq 0 ]
}

@test "override de limiares.concentracao e aplicado e marcado com limiarSobrescrito" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 2000, "Y": 8000}'
  write_perfil acme '{"limiares": {"concentracao": 0.1}}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado_x = next(a for a in report["achados"] if a["medidas"]["ticker"] == "X")
assert achado_x["limiarSobrescrito"] is True, achado_x
assert abs(achado_x["medidas"]["limiar"] - 0.1) < 1e-9, achado_x
assert achado_x["severidade"] == "alta", achado_x
' "$output"
  [ "$status" -eq 0 ]
}

@test "override de limiares.concentracao invalido (fora de (0,1]) e rejeitado citando o valor" {
  seed_portfolio acme
  write_holdings acme '[{"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"}]'
  write_prices '{"X": 1000}'
  write_perfil acme '{"limiares": {"concentracao": 1.5}}'

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"1.5"* ]]
  [[ "$output" == *"esperado"* ]]

  write_perfil acme '{"limiares": {"concentracao": 0}}'
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"Limiar invalido"* ]]
  [[ "$output" == *"esperado"* ]]
}

@test "chave desconhecida em limiares e rejeitada citando a chave recebida e as chaves validas" {
  seed_portfolio acme
  write_holdings acme '[{"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"}]'
  write_prices '{"X": 1000}'

  # Chave que nunca vai ter override (ver comentario em find_desvio): erro
  # explicito em vez de silenciosamente ignorada.
  write_perfil acme '{"limiares": {"desvio": 99}}'
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"desvio"* ]]
  [[ "$output" == *"concentracao"* ]]

  # Erro de digitacao na chave: mesmo tratamento.
  write_perfil acme '{"limiares": {"concentracaoo": 0.1}}'
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"concentracaoo"* ]]
  [[ "$output" == *"concentracao"* ]]
}

@test "ausencia de cotacao de uma posicao torna o total da carteira desconhecido: suprime TODOS os achados de concentracao e reporta naoMedido" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  # So Y tem cotacao no fake - X fica sem preco. Y sozinho pareceria 100% da
  # base precificada, mas o total real da carteira e desconhecido: o motor
  # nao inventa o percentual, reporta naoMedido em vez de medir errado.
  write_prices '{"Y": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "posicao com precoManual conta como precificada - nao entra em naoMedido nem chama o provider de cotacao" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br", "precoManual": 3000},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"Y": 7000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
# Idem: sem alocacao-alvo.json, "desvio" cai em naoMedido por desenho.
assert not [n for n in report["naoMedido"] if n["tipo"] == "concentracao"], report
' "$output"
  [ "$status" -eq 0 ]
  ! grep -q '^acme X br$' "$ALOCACAO_QUOTE_LOG"
}

@test "cotacao com preco null (status 0) nao mata o script - vira naoMedido, exit continua 0" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  export ALOCACAO_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote-null-preco.sh"
  export ALOCACAO_QUOTE_NULL_TICKER="X"
  write_prices '{"Y": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "cotacao com preco de tipo errado (string) nao mata o script - vira naoMedido, exit continua 0" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  # Prova da lacuna: mutacao removendo select(type == "number") de
  # bin/achados.sh deixa esse payload chegar em --argjson como string "abc" -
  # jq quebra com "invalid JSON text passed to --argjson" e o script morre.
  export ALOCACAO_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote-null-preco.sh"
  export ALOCACAO_QUOTE_BAD_TYPE_TICKER="X"
  write_prices '{"Y": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "cotacao com chave .preco ausente no payload (status 0) nao mata o script - vira naoMedido" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  export ALOCACAO_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote-null-preco.sh"
  export ALOCACAO_QUOTE_MISSING_KEY_TICKER="X"
  write_prices '{"Y": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "cotacao 0 ou negativa e tratada como ausente, nao mata o relatorio" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 0, "Y": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]

  write_prices '{"X": -100, "Y": 5000}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["X"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "mercado sem provider configurado (US sem ALOCACAO_QUOTE) reporta motivo proprio, distinto de cotacao-ausente" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "AAPL", "quantidade": 1, "classe": "acoes", "mercado": "us"}
  ]'
  # Simula carteira US sem ALOCACAO_QUOTE injetado (nao ha client HTTP direto
  # pra US neste repo - so BR tem fallback via brapi-quote.sh).
  unset ALOCACAO_QUOTE

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "provider-nao-configurado", "tickers": ["AAPL"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "provider configurado mas falhando (ticker sem preco no fake) continua usando o motivo cotacao-ausente" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "AAPL", "quantidade": 1, "classe": "acoes", "mercado": "us"},
    {"ticker": "MSFT", "quantidade": 1, "classe": "acoes", "mercado": "us"}
  ]'
  # ALOCACAO_QUOTE esta configurado (herdado do setup), mas o fake falha
  # porque AAPL nao esta no arquivo de precos - falha de provider, nao de
  # configuracao ausente.
  write_prices '{"MSFT": 5000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "concentracao", "motivo": "cotacao-ausente", "tickers": ["AAPL"]}, {"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

@test "carteira totalmente precificada e sem achados: achados e naoMedido saem [] simultaneamente" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  # 50/50, abaixo do limiar moderado (25%)... na verdade 50% ultrapassa - usar
  # split que fique abaixo do limiar (perfil moderado, 0.25): 4 posicoes iguais.
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Z", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "W", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "V", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"X": 2000, "Y": 2000, "Z": 2000, "W": 2000, "V": 2000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"achados": [], "naoMedido": [{"tipo": "desvio", "motivo": "alvo-ausente"}]}' ]
}

# --- tipo "desvio" ---------------------------------------------------------

@test "desvio: classe acima de 2x o threshold da carteira dispara severidade alta" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "renda-fixa", "mercado": "br"}
  ]'
  write_prices '{"A": 9000, "B": 1000}'
  write_alvo acme '{"porClasse": {"acoes": 0.5, "renda-fixa": 0.5}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.05}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achados = [a for a in report["achados"] if a["tipo"] == "desvio"]
acoes = next(a for a in achados if a["medidas"]["eixo"] == "porClasse" and a["medidas"]["chave"] == "acoes")
assert acoes["severidade"] == "alta", acoes
assert abs(acoes["medidas"]["atual"] - 0.9) < 1e-9, acoes
assert abs(acoes["medidas"]["alvo"] - 0.5) < 1e-9, acoes
assert abs(acoes["medidas"]["threshold"] - 0.05) < 1e-9, acoes
assert acoes["licao"] == "desvio-da-alocacao-alvo", acoes
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: dentro do threshold nao dispara achado" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "renda-fixa", "mercado": "br"}
  ]'
  write_prices '{"A": 5100, "B": 4900}'
  write_alvo acme '{"porClasse": {"acoes": 0.5, "renda-fixa": 0.5}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.05}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "desvio"], report
assert not [n for n in report["naoMedido"] if n["tipo"] == "desvio"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: alocacao-alvo.json ausente nao mata o script, vai para naoMedido com motivo proprio, e concentracao continua saindo" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  # 60/40, ambas acima do limiar moderado (25%) - prova que "concentracao"
  # continua saindo normalmente mesmo com "desvio" em naoMedido.
  write_prices '{"A": 6000, "B": 4000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
desvio_nao_medido = next(n for n in report["naoMedido"] if n["tipo"] == "desvio")
assert desvio_nao_medido["motivo"] == "alvo-ausente", desvio_nao_medido
concentracao = [a for a in report["achados"] if a["tipo"] == "concentracao"]
assert len(concentracao) == 2, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: ticker sem cotacao torna o tipo desvio inteiro naoMedido (mesma regra da concentracao)" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"Y": 5000}'
  write_alvo acme '{"porClasse": {"acoes": 1}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.05}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
desvio_nao_medido = next(n for n in report["naoMedido"] if n["tipo"] == "desvio")
assert desvio_nao_medido["motivo"] == "cotacao-ausente", desvio_nao_medido
assert desvio_nao_medido["tickers"] == ["X"], desvio_nao_medido
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: boundary do threshold com valores realistas (60/40 vs 50/50, threshold 0.05) - carteira mais banal que existe, e o default sugerido pelo /instalar" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "renda-fixa", "mercado": "br"}
  ]'
  # Bug de producao confirmado: em float, (0.6 - 0.5) == 0.09999999999999998,
  # que fica ABAIXO de 0.05*2 (0.1). Isso fazia uma carteira 60/40 contra
  # alvo 50/50 com threshold 0.05 (o default que o /instalar sugere) reportar
  # severidade "media" onde o AC6 pede "alta" (exatamente 2x o threshold).
  # Fracoes binarias exatas (oitavos, teste seguinte) nao pegam esse bug -
  # por isso este teste com valores decimais comuns e o que importa.
  write_alvo acme '{"porClasse": {"acoes": 0.5, "renda-fixa": 0.5}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.05}'

  # abaixo do threshold: 52/48 (desvio 0.02).
  write_prices '{"A": 5200, "B": 4800}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "desvio"], report
' "$output"
  [ "$status" -eq 0 ]

  # exatamente no threshold (0.05 de desvio): 55/45 -> media.
  write_prices '{"A": 5500, "B": 4500}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
acoes = next(a for a in report["achados"] if a["tipo"] == "desvio" and a["medidas"]["chave"] == "acoes")
assert acoes["severidade"] == "media", acoes
' "$output"
  [ "$status" -eq 0 ]

  # exatamente em 2x o threshold (0.10 de desvio): 60/40 -> alta.
  write_prices '{"A": 6000, "B": 4000}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
acoes = next(a for a in report["achados"] if a["tipo"] == "desvio" and a["medidas"]["chave"] == "acoes")
assert acoes["severidade"] == "alta", acoes
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: boundary do threshold com fracoes binarias exatas (teste adicional - nao substitui o caso realista acima)" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "renda-fixa", "mercado": "br"}
  ]'
  # Threshold e percentuais escolhidos como fracoes binarias exatas (oitavos):
  # esta variante NAO expoe o bug de arredondamento (ver teste acima com
  # valores realistas), mas continua util como boundary test independente.
  write_alvo acme '{"porClasse": {"acoes": 0.5, "renda-fixa": 0.5}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.125}'

  # total = 8000; abaixo do threshold (0.05 de desvio): 4400/3600.
  write_prices '{"A": 4400, "B": 3600}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "desvio"], report
' "$output"
  [ "$status" -eq 0 ]

  # exatamente no threshold (0.125 de desvio): 5000/3000 (62,5%/37,5%) ->
  # media (AC6: dispara NO ponto, mesma semantica de boundary do "concentracao").
  write_prices '{"A": 5000, "B": 3000}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
acoes = next(a for a in report["achados"] if a["tipo"] == "desvio" and a["medidas"]["chave"] == "acoes")
assert acoes["severidade"] == "media", acoes
' "$output"
  [ "$status" -eq 0 ]

  # exatamente em 2x o threshold (0.25 de desvio): 6000/2000 (75%/25%) -> alta.
  write_prices '{"A": 6000, "B": 2000}'
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
acoes = next(a for a in report["achados"] if a["tipo"] == "desvio" and a["medidas"]["chave"] == "acoes")
assert acoes["severidade"] == "alta", acoes
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio: eixo porMercado tambem dispara achado (nao so porClasse)" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "B", "quantidade": 1, "classe": "acoes", "mercado": "us"}
  ]'
  # porClasse balanceado (100% acoes = alvo 1.0, desvio 0) - so o eixo
  # porMercado fica desbalanceado (90% br contra alvo de 50%), pra provar que
  # o eixo e de fato avaliado (mutacao que faz find_desvio ignorar
  # porMercado nao quebraria nenhum teste anterior, so este).
  write_prices '{"A": 9000, "B": 1000}'
  write_alvo acme '{"porClasse": {"acoes": 1}, "porMercado": {"br": 0.5, "us": 0.5}, "threshold": 0.05}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achados = [a for a in report["achados"] if a["tipo"] == "desvio" and a["medidas"]["eixo"] == "porMercado"]
br = next(a for a in achados if a["medidas"]["chave"] == "br")
assert br["severidade"] == "alta", br
assert abs(br["medidas"]["atual"] - 0.9) < 1e-9, br
assert abs(br["medidas"]["alvo"] - 0.5) < 1e-9, br
' "$output"
  [ "$status" -eq 0 ]
}

# --- tipo "reserva" ----------------------------------------------------------

@test "reserva: reservaEmergenciaOk false dispara achado de severidade alta" {
  seed_portfolio acme
  write_holdings acme '[{"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"}]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"reservaEmergenciaOk": false}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado = next(a for a in report["achados"] if a["tipo"] == "reserva")
assert achado["severidade"] == "alta", achado
assert achado["licao"] == "reserva-emergencia-ausente", achado
' "$output"
  [ "$status" -eq 0 ]
}

@test "reserva: reservaEmergenciaOk true nao dispara achado" {
  seed_portfolio acme
  write_holdings acme '[{"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"}]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"reservaEmergenciaOk": true}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "reserva"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "reserva: campo ausente (perfil-investidor.json inexistente) nao dispara - ausente != falso" {
  seed_portfolio acme
  write_holdings acme '[{"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br"}]'
  write_prices '{"A": 1000}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "reserva"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "reserva: continua saindo mesmo quando concentracao/desvio caem em naoMedido por falta de cotacao" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"Y": 5000}'
  write_perfil acme '{"reservaEmergenciaOk": false}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert [n for n in report["naoMedido"] if n["tipo"] == "concentracao"], report
achado = next(a for a in report["achados"] if a["tipo"] == "reserva")
assert achado["severidade"] == "alta", achado
' "$output"
  [ "$status" -eq 0 ]
}

# --- tipo "liquidez" ---------------------------------------------------------

@test "liquidez: objetivo de prazo curto + posicao com liquidez D+30 dispara achado de severidade alta" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "fiis", "mercado": "br", "liquidez": "D+30"}
  ]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"objetivos": [{"nome": "reforma", "prazo": "curto"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
achado = next(a for a in report["achados"] if a["tipo"] == "liquidez")
assert achado["severidade"] == "alta", achado
assert achado["medidas"]["ticker"] == "A", achado
assert achado["medidas"]["liquidez"] == "D+30", achado
assert achado["licao"] == "liquidez-descasada-do-prazo", achado
' "$output"
  [ "$status" -eq 0 ]
}

@test "liquidez: sem objetivo de prazo curto nao dispara, mesmo com posicao D+30" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "fiis", "mercado": "br", "liquidez": "D+30"}
  ]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"objetivos": [{"nome": "aposentadoria", "prazo": "longo"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "liquidez"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "liquidez: objetivo curto porem posicao sem campo liquidez nao dispara - ausente != ilíquido" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "fiis", "mercado": "br"}
  ]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"objetivos": [{"nome": "reforma", "prazo": "curto"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "liquidez"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "liquidez: D+0 e D+1 nao contam como descasados (n > 1), so D+2 em diante" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br", "liquidez": "D+1"}
  ]'
  write_prices '{"A": 1000}'
  write_perfil acme '{"objetivos": [{"nome": "reforma", "prazo": "curto"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert not [a for a in report["achados"] if a["tipo"] == "liquidez"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "liquidez: continua saindo mesmo quando concentracao/desvio caem em naoMedido por falta de cotacao" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "X", "quantidade": 1, "classe": "fiis", "mercado": "br", "liquidez": "D+30"},
    {"ticker": "Y", "quantidade": 1, "classe": "acoes", "mercado": "br"}
  ]'
  write_prices '{"Y": 5000}'
  write_perfil acme '{"objetivos": [{"nome": "reforma", "prazo": "curto"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert [n for n in report["naoMedido"] if n["tipo"] == "concentracao"], report
achado = next(a for a in report["achados"] if a["tipo"] == "liquidez")
assert achado["medidas"]["ticker"] == "X", achado
' "$output"
  [ "$status" -eq 0 ]
}

# --- multiplos tipos simultaneos ---------------------------------------------

@test "multiplos tipos disparam juntos na mesma carteira" {
  seed_portfolio acme
  write_holdings acme '[
    {"ticker": "A", "quantidade": 1, "classe": "acoes", "mercado": "br", "liquidez": "D+30"},
    {"ticker": "B", "quantidade": 1, "classe": "renda-fixa", "mercado": "br"}
  ]'
  write_prices '{"A": 9000, "B": 1000}'
  write_alvo acme '{"porClasse": {"acoes": 0.5, "renda-fixa": 0.5}, "porMercado": {"br": 1, "us": 0}, "threshold": 0.05}'
  write_perfil acme '{"reservaEmergenciaOk": false, "objetivos": [{"nome": "reforma", "prazo": "curto"}]}'

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  # Captura o relatorio ANTES de qualquer run aninhado - "run python3 -c"
  # abaixo sobrescreve $output com o stdout do proprio python (vazio), entao
  # qualquer assercao sobre $output feita depois dele testaria string errada.
  report="$output"
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
tipos = {a["tipo"] for a in report["achados"]}
assert "concentracao" in tipos, report
assert "desvio" in tipos, report
assert "reserva" in tipos, report
assert "liquidez" in tipos, report
' "$report"
  [ "$status" -eq 0 ]
  # Nenhum achado recomenda compra/venda - o motor so mede fato (AC12). Guarda
  # roda contra carteira que dispara os 4 tipos simultaneamente (o lugar mais
  # exigente pra essa afirmacao), usando $report - nao $output, que aqui ja
  # foi sobrescrito pelo run aninhado acima.
  lowered="$(echo "$report" | tr "[:upper:]" "[:lower:]")"
  [[ "$lowered" != *"compr"* ]]
  [[ "$lowered" != *"vend"* ]]
}
