#!/usr/bin/env python3
"""Motor de achados: gera fatos medidos + severidade a partir da carteira.

Nunca produz texto de recomendacao de compra/venda - isso e proposito do
InvestOS (ferramenta antes de agente, nunca decide pela pessoa). "licao" e
um slug conceitual, nao prosa: uma story futura calibra a explicacao em tres
niveis de conhecimento do investidor a partir dele.

Cada tipo de achado vira uma funcao find_<tipo>() que devolve uma lista de
achados; build_report() so as encadeia. Quatro tipos: concentracao e desvio
dependem do total da carteira (ticker sem cotacao derruba o tipo inteiro pra
naoMedido); reserva e liquidez nao dependem do total e sempre rodam.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib_report import as_decimal, die, load_holdings, load_json, print_report

# Limiares por tipo de achado e perfil de risco - unico lugar pra trocar um
# valor. Perfil ausente ou nao reconhecido cai em DEFAULT_PERFIL. Indexado por
# tipo (nao so "concentracao") porque a proxima folha adiciona desvio/reserva/
# liquidez com a mesma mecanica de override, sem duplicar resolve/validacao.
LIMIARES_POR_TIPO: dict[str, dict[str, float]] = {
    "concentracao": {
        "conservador": 0.15,
        "moderado": 0.25,
        "arrojado": 0.40,
    },
}
DEFAULT_PERFIL = "moderado"
# Decimal desde a definicao (nao float convertido): sao constantes de
# codigo, nao dado externo, e entram direto em multiplicacao na fronteira de
# severidade (ver severidade_concentracao/severidade_desvio). Multiplicar
# dois float ja arredondados (ex.: limiar=0.40 (arrojado) * 1.5) dobra o
# arredondamento e desloca a fronteira - confirmado empiricamente:
# 0.40 * 1.5 == 0.6000000000000001 (float) != 0.6, entao uma posicao
# exatamente em 1,5x o limiar (40%) deixava de disparar "alta". Em Decimal
# a multiplicacao e exata.
SEVERIDADE_ALTA_MULTIPLICADOR = Decimal("1.5")

# "desvio" nao entra em LIMIARES_POR_TIPO: o threshold vem do proprio
# alocacao-alvo.json (decisao junto com os pesos daquela carteira), nao de
# um dial generico por perfil de risco - por isso nao aceita override via
# perfil-investidor.json.limiares.desvio (ver find_desvio).
DESVIO_SEVERIDADE_ALTA_MULTIPLICADOR = Decimal("2.0")
LIQUIDEZ_PRAZO_CURTO_LIMITE = 1  # n > 1 e descasado; D+0/D+1 sao liquidez imediata.


def decimal_exato(value: float) -> Decimal:
    """Converte um float ja validado (limiar, peso-alvo, threshold - todos
    vieram de as_limiar/as_peso/as_threshold_alvo, que ja rejeitaram o que
    nao e numero) para Decimal preservando o valor decimal original, nao o
    binario.

    Decimal(0.05) direto do float carregaria o erro de representacao binaria
    do proprio float (Decimal(0.05) == Decimal('0.05000000000000000277...')).
    Decimal(str(0.05)) reconstroi a partir do repr mais curto que arredonda
    de volta pro mesmo float (garantia do algoritmo de repr do Python desde
    3.1) - mesmo caminho ja usado por as_decimal() para quantidade/preco.
    Nao trocamos load_perfil/load_alvo/validate_pesos para
    json.load(parse_float=Decimal) porque o float continua sendo o tipo de
    saida serializavel (json.dump nao aceita Decimal) e essas funcoes
    tambem retornam o valor pra uso fora de comparacao (validacao de faixa,
    "medidas" no achado); a conversao pontual aqui, so onde a comparacao de
    fronteira acontece, e mais cirurgica do que threadar Decimal pelo
    parsing inteiro.
    """
    return Decimal(str(value))


def load_quotes(path: str) -> dict[str, Decimal]:
    expected = 'JSON {"TICKER": preco}'
    payload = load_json(path, expected)
    if not isinstance(payload, dict):
        die(f"Cotacoes invalidas: recebido {payload!r} em '{path}', esperado {expected}.")
    quotes: dict[str, Decimal] = {}
    for ticker, preco in payload.items():
        valor = as_decimal(preco, str(ticker), payload)
        if valor <= 0:
            # Preco 0 ou negativo (ticker suspenso na brapi, por exemplo) e
            # tao "sem cotacao usavel" quanto null - mesmo caminho de
            # naoMedido, nunca mata o relatorio inteiro por um unico ticker.
            continue
        quotes[str(ticker).upper()] = valor
    return quotes


def load_sem_provider(path: str) -> set[str]:
    expected = 'JSON ["TICKER", ...]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Sem-provider invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    return {str(ticker).upper() for ticker in payload}


def validate_limiares_keys(perfil: dict[str, Any]) -> None:
    """Chave nao reconhecida em "limiares" (typo ou tipo sem override, como
    "desvio" - ver comentario acima de find_desvio) nao pode ser ignorada
    silenciosamente: o investidor jura que mudou o limiar e o motor segue
    usando o default, sem avisar. Rejeita citando a chave recebida e as
    chaves validas."""
    limiares = perfil.get("limiares")
    if not isinstance(limiares, dict):
        return
    validas = set(LIMIARES_POR_TIPO)
    invalidas = sorted(set(limiares) - validas)
    if invalidas:
        die(
            f"Limiar invalido: recebido(s) chave(s) desconhecida(s) {invalidas!r} em "
            f"limiares, esperado uma de: {sorted(validas)!r}."
        )


def load_perfil(path: str) -> dict[str, Any]:
    expected = (
        'JSON {"perfilRisco": "conservador|moderado|arrojado"?, "limiares": {...}?, '
        '"reservaEmergenciaOk": bool?, "objetivos": [{"prazo": "curto|medio|longo", ...}, ...]?}'
    )
    payload = load_json(path, expected)
    if not isinstance(payload, dict):
        die(f"Perfil invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    validate_limiares_keys(payload)
    return payload


def as_peso(value: Any, field: str, received: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        die(f"Alvo invalido: recebido {field}={value!r} em {received!r}, esperado numero >= 0.")
    if number < 0:
        die(f"Alvo invalido: recebido {field}={value!r} em {received!r}, esperado numero >= 0.")
    return number


def validate_pesos(pesos: Any, label: str, received: Any) -> dict[str, float]:
    if not isinstance(pesos, dict) or not pesos:
        die(
            f"Alvo invalido: recebido {label}={pesos!r} em {received!r}, "
            "esperado objeto {<chave>: peso} com pelo menos 1 chave."
        )
    return {str(key): as_peso(value, label, received) for key, value in pesos.items()}


def as_threshold_alvo(value: Any, received: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        die(f"Alvo invalido: recebido threshold={value!r} em {received!r}, esperado numero em (0, 1].")
    if not (0 < number <= 1):
        die(f"Alvo invalido: recebido threshold={value!r} em {received!r}, esperado numero em (0, 1].")
    return number


def load_alvo(path: str) -> dict[str, Any] | None:
    """Carrega alocacao-alvo.json para o tipo "desvio". None = arquivo
    ausente (bin/achados.sh grava 0 bytes nesse caso) - vira naoMedido
    com motivo "alvo-ausente" em find_desvio, nunca mata o script."""
    with open(path, encoding="utf-8") as handle:
        raw = handle.read()
    if not raw.strip():
        return None
    expected = 'JSON {"porClasse": {<classe>: peso}, "porMercado": {br|us: peso}, "threshold": numero em (0, 1]}'
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Arquivo invalido: recebido JSON invalido em '{path}' ({exc}), esperado {expected}.")
    if not isinstance(payload, dict):
        die(f"Alvo invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    threshold = as_threshold_alvo(payload.get("threshold"), payload)
    return {
        "porClasse": validate_pesos(payload.get("porClasse"), "porClasse", payload),
        "porMercado": validate_pesos(payload.get("porMercado"), "porMercado", payload),
        "threshold": threshold,
    }


def as_limiar(value: Any, tipo: str, received: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        die(
            f"Limiar invalido: recebido limiares.{tipo}={value!r} em {received!r}, "
            "esperado numero em (0, 1]."
        )
    if not (0 < number <= 1):
        die(
            f"Limiar invalido: recebido limiares.{tipo}={value!r} em {received!r}, "
            "esperado numero em (0, 1]."
        )
    return number


def resolve_limiar(perfil: dict[str, Any], tipo: str) -> tuple[float, bool]:
    """Devolve o limiar como float (formato de saida em "medidas" - json.dump
    nao serializa Decimal). Quem for comparar contra fronteira deve converter
    com decimal_exato() antes, nao comparar o float direto (ver
    find_concentracao)."""
    limiares = perfil.get("limiares")
    if isinstance(limiares, dict) and tipo in limiares:
        return as_limiar(limiares[tipo], tipo, perfil), True
    risco = str(perfil.get("perfilRisco") or "").strip().lower()
    tabela = LIMIARES_POR_TIPO[tipo]
    if risco not in tabela:
        risco = DEFAULT_PERFIL
    return tabela[risco], False


def ticker_values(
    positions: list[dict[str, Any]], quotes: dict[str, Decimal]
) -> tuple[dict[str, Decimal], Decimal, list[str]]:
    # Ticker sem cotacao volta separado (ausentes), nunca some do denominador
    # silenciosamente: misturar isso no total faria os demais tickers
    # parecerem uma fatia maior do que realmente sao (base parcial vira
    # achado inventado - decisao de produto, ver find_concentracao).
    totals: dict[str, Decimal] = {}
    ausentes: list[str] = []
    for item in positions:
        ticker = item["ticker"]
        if ticker not in quotes:
            if ticker not in ausentes:
                ausentes.append(ticker)
            continue
        valor = item["quantidade"] * quotes[ticker]
        totals[ticker] = totals.get(ticker, Decimal("0")) + valor
    total = sum(totals.values(), Decimal("0"))
    return totals, total, sorted(ausentes)


def severidade_concentracao(percentual: Decimal, limiar: Decimal) -> str:
    return "alta" if percentual >= limiar * SEVERIDADE_ALTA_MULTIPLICADOR else "media"


def nao_medido_por_ausencia(
    tipo: str, ausentes: list[str], sem_provider: set[str]
) -> list[dict[str, Any]]:
    """Motivo compartilhado entre "concentracao" e "desvio" - os dois dependem
    do total da carteira, entao um ticker sem cotacao derruba o tipo inteiro
    pra naoMedido (nunca mede sobre base parcial). Dois motivos distintos:
    "provider-nao-configurado" (mercado sem ALOCACAO_QUOTE injetado - falha de
    configuracao do usuario) e "cotacao-ausente" (provider falhou ou devolveu
    preco invalido - falha de rede ou do dado)."""
    nao_medido: list[dict[str, Any]] = []
    sem_provider_tickers = [t for t in ausentes if t in sem_provider]
    cotacao_ausente_tickers = [t for t in ausentes if t not in sem_provider]
    if sem_provider_tickers:
        nao_medido.append(
            {"tipo": tipo, "motivo": "provider-nao-configurado", "tickers": sem_provider_tickers}
        )
    if cotacao_ausente_tickers:
        nao_medido.append(
            {"tipo": tipo, "motivo": "cotacao-ausente", "tickers": cotacao_ausente_tickers}
        )
    return nao_medido


def find_concentracao(
    positions: list[dict[str, Any]],
    quotes: dict[str, Decimal],
    perfil: dict[str, Any],
    sem_provider: set[str],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Devolve (achados, naoMedido). Com qualquer ticker sem cotacao, o total
    real da carteira e desconhecido - todo percentual seria chute, entao o
    tipo inteiro fica naoMedido nesta rodada em vez de medir sobre uma base
    parcial (AC2/AC8: o motor nunca inventa achado)."""
    limiar, sobrescrito = resolve_limiar(perfil, "concentracao")
    limiar_decimal = decimal_exato(limiar)
    values, total, ausentes = ticker_values(positions, quotes)
    if ausentes:
        return [], nao_medido_por_ausencia("concentracao", ausentes, sem_provider)
    if total <= 0:
        return [], []
    achados: list[dict[str, Any]] = []
    for ticker in sorted(values):
        # Comparacao de fronteira em Decimal (valores ja exatos): percentual
        # e razao entre dois Decimal derivados de quantidade*preco, sem
        # passar por float ate a serializacao final em "medidas".
        percentual_decimal = values[ticker] / total
        if percentual_decimal < limiar_decimal:
            continue
        achado: dict[str, Any] = {
            "tipo": "concentracao",
            "severidade": severidade_concentracao(percentual_decimal, limiar_decimal),
            "medidas": {
                "ticker": ticker,
                "valor": float(values[ticker]),
                "percentual": float(percentual_decimal),
                "limiar": limiar,
            },
            "licao": "concentracao-por-ativo",
        }
        if sobrescrito:
            achado["limiarSobrescrito"] = True
        achados.append(achado)
    return achados, []


def eixo_values(positions: list[dict[str, Any]], quotes: dict[str, Decimal], key: str) -> dict[str, Decimal]:
    """Soma valor de mercado por classe/mercado. So e chamada quando ja se
    sabe que toda posicao tem cotacao (find_desvio baila pra naoMedido antes
    disso), entao nunca precisa lidar com ticker ausente aqui."""
    totals: dict[str, Decimal] = {}
    for item in positions:
        chave = item[key]
        totals[chave] = totals.get(chave, Decimal("0")) + item["quantidade"] * quotes[item["ticker"]]
    return totals


def severidade_desvio(desvio_absoluto: Decimal, threshold: Decimal) -> str:
    return "alta" if desvio_absoluto >= threshold * DESVIO_SEVERIDADE_ALTA_MULTIPLICADOR else "media"


def desvio_achados_do_eixo(
    eixo: str, values: dict[str, Decimal], alvo_pesos: dict[str, float], total: Decimal, threshold: float
) -> list[dict[str, Any]]:
    # Bug de producao confirmado: "atual - meta" em float (dois floats ja
    # arredondados independentemente, ex.: 0.6 e 0.5) nao devolve a mesma
    # coisa que a subtracao decimal exata (0.6 - 0.5 == 0.09999999999999998
    # em float, == 0.1 em Decimal). Tudo aqui fica em Decimal ate a
    # comparacao de fronteira; so vira float na hora de montar "medidas"
    # (json.dump nao serializa Decimal).
    threshold_decimal = decimal_exato(threshold)
    achados: list[dict[str, Any]] = []
    for chave in sorted(set(values) | set(alvo_pesos)):
        atual_decimal = values.get(chave, Decimal("0")) / total
        meta_decimal = decimal_exato(alvo_pesos.get(chave, 0.0))
        desvio_decimal = atual_decimal - meta_decimal
        if abs(desvio_decimal) < threshold_decimal:
            continue
        achados.append(
            {
                "tipo": "desvio",
                "severidade": severidade_desvio(abs(desvio_decimal), threshold_decimal),
                "medidas": {
                    "eixo": eixo,
                    "chave": chave,
                    "atual": float(atual_decimal),
                    "alvo": float(meta_decimal),
                    "desvio": float(desvio_decimal),
                    "threshold": threshold,
                },
                "licao": "desvio-da-alocacao-alvo",
            }
        )
    return achados


def find_desvio(
    positions: list[dict[str, Any]],
    quotes: dict[str, Decimal],
    alvo: dict[str, Any] | None,
    sem_provider: set[str],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Devolve (achados, naoMedido). Mesma logica de "concentracao": sem
    alocacao-alvo.json nao ha alvo pra comparar (naoMedido, motivo
    "alvo-ausente"); com ticker sem cotacao o total e desconhecido
    (naoMedido, mesmos dois motivos de "concentracao"). Threshold vem do
    proprio alocacao-alvo.json, nunca de limiares.desvio no perfil - o
    threshold e uma decisao tomada junto com os pesos daquela carteira
    especifica, nao um dial generico por perfil de risco."""
    if alvo is None:
        return [], [{"tipo": "desvio", "motivo": "alvo-ausente"}]
    _, total, ausentes = ticker_values(positions, quotes)
    if ausentes:
        return [], nao_medido_por_ausencia("desvio", ausentes, sem_provider)
    if total <= 0:
        return [], []
    threshold = alvo["threshold"]
    achados = desvio_achados_do_eixo(
        "porClasse", eixo_values(positions, quotes, "classe"), alvo["porClasse"], total, threshold
    ) + desvio_achados_do_eixo(
        "porMercado", eixo_values(positions, quotes, "mercado"), alvo["porMercado"], total, threshold
    )
    return achados, []


def find_reserva(perfil: dict[str, Any]) -> list[dict[str, Any]]:
    """Nao depende do total da carteira - sempre roda, mesmo com
    concentracao/desvio em naoMedido. Ausente != false: so dispara quando o
    campo esta explicitamente presente e vale False."""
    if perfil.get("reservaEmergenciaOk") is False:
        return [
            {
                "tipo": "reserva",
                "severidade": "alta",
                "medidas": {},
                "licao": "reserva-emergencia-ausente",
            }
        ]
    return []


def tem_objetivo_prazo_curto(perfil: dict[str, Any]) -> bool:
    objetivos = perfil.get("objetivos")
    if not isinstance(objetivos, list):
        return False
    return any(isinstance(obj, dict) and obj.get("prazo") == "curto" for obj in objetivos)


def find_liquidez(positions: list[dict[str, Any]], perfil: dict[str, Any]) -> list[dict[str, Any]]:
    """Nao depende do total da carteira - sempre roda, mesmo com
    concentracao/desvio em naoMedido. Um achado por posicao descasada
    (mesmo padrao de find_concentracao: nao so a pior posicao)."""
    if not tem_objetivo_prazo_curto(perfil):
        return []
    achados: list[dict[str, Any]] = []
    for item in positions:
        liquidez = item.get("liquidez")
        if liquidez is None:
            continue
        prazo = int(liquidez[2:])
        if prazo <= LIQUIDEZ_PRAZO_CURTO_LIMITE:
            continue
        achados.append(
            {
                "tipo": "liquidez",
                "severidade": "alta",
                "medidas": {"ticker": item["ticker"], "liquidez": liquidez, "objetivoPrazo": "curto"},
                "licao": "liquidez-descasada-do-prazo",
            }
        )
    return achados


def build_report(
    positions: list[dict[str, Any]],
    quotes: dict[str, Decimal],
    perfil: dict[str, Any],
    sem_provider: set[str],
    alvo: dict[str, Any] | None,
) -> dict[str, Any]:
    achados: list[dict[str, Any]] = []
    nao_medido: list[dict[str, Any]] = []
    concentracao_achados, concentracao_nao_medido = find_concentracao(
        positions, quotes, perfil, sem_provider
    )
    achados.extend(concentracao_achados)
    nao_medido.extend(concentracao_nao_medido)
    desvio_achados, desvio_nao_medido = find_desvio(positions, quotes, alvo, sem_provider)
    achados.extend(desvio_achados)
    nao_medido.extend(desvio_nao_medido)
    achados.extend(find_reserva(perfil))
    achados.extend(find_liquidez(positions, perfil))
    return {"achados": achados, "naoMedido": nao_medido}


def main() -> None:
    if len(sys.argv) != 6:
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "achados-report.py <holdings.json> <quotes.json> <perfil-investidor.json> "
            "<sem-provider.json> <alocacao-alvo.json>"
        )
    # expected de validate_holding cita precoManual?/liquidez?; o de
    # load_holdings (die de path/JSON) omite ambos — mensagens historicas,
    # preservadas byte a byte.
    positions = load_holdings(
        sys.argv[1],
        expected_holdings='JSON {"posicoes": [{ticker, quantidade, classe, mercado}, ...]}',
        expected_item="{ticker, quantidade, classe, mercado, precoManual?, liquidez?}",
        suporta_liquidez=True,
    )
    quotes = load_quotes(sys.argv[2])
    perfil = load_perfil(sys.argv[3])
    sem_provider = load_sem_provider(sys.argv[4])
    alvo = load_alvo(sys.argv[5])
    report = build_report(positions, quotes, perfil, sem_provider, alvo)
    print_report(report)


if __name__ == "__main__":
    main()
