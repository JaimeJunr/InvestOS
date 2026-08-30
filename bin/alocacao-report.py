#!/usr/bin/env python3
"""Monta o relatorio de alocacao atual vs. alocacao-alvo."""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

WEIGHT_TOLERANCE = Decimal("0.000001")
MERCADOS = {"br", "us"}


def die(message: str) -> None:
    raise SystemExit(message)


def load_json(path: str, expected: str) -> Any:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        die(f"Arquivo invalido: recebido path inexistente '{path}', esperado {expected}.")
    except json.JSONDecodeError as exc:
        die(f"Arquivo invalido: recebido JSON invalido em '{path}' ({exc}), esperado {expected}.")


def as_decimal(value: Any, field: str, received: Any) -> Decimal:
    try:
        number = Decimal(str(value))
    except Exception:
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")
    return number


def validate_holding(item: Any, index: int) -> dict[str, Any]:
    expected = "{ticker, quantidade, classe, mercado}"
    if not isinstance(item, dict):
        die(f"Posicao invalida: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip().upper()
    classe = str(item.get("classe") or "").strip()
    mercado = str(item.get("mercado") or "").strip().lower()
    quantidade = as_decimal(item.get("quantidade"), "quantidade", item)
    if not ticker or not classe or mercado not in MERCADOS or quantidade <= 0:
        die(
            f"Posicao invalida: recebido {item!r}, esperado ticker nao-vazio, "
            f"quantidade > 0, classe nao-vazia e mercado um de: br, us."
        )
    return {"ticker": ticker, "quantidade": quantidade, "classe": classe, "mercado": mercado}


def load_holdings(path: str) -> list[dict[str, Any]]:
    payload = load_json(path, 'JSON {"posicoes": [{ticker, quantidade, classe, mercado}, ...]}')
    rows = payload.get("posicoes") if isinstance(payload, dict) else None
    if not isinstance(rows, list) or not rows:
        die(
            f"Holdings invalido: recebido {payload!r} em '{path}', "
            'esperado JSON {"posicoes": [...]} com pelo menos 1 posicao.'
        )
    return [validate_holding(item, index) for index, item in enumerate(rows)]


def validate_weights(weights: Any, label: str) -> dict[str, Decimal]:
    if not isinstance(weights, dict) or not weights:
        die(f"Alvo invalido: recebido {label}={weights!r}, esperado objeto {{<chave>: peso}} com pelo menos 1 chave.")
    parsed = {str(key): as_decimal(value, label, weights) for key, value in weights.items()}
    if any(value < 0 for value in parsed.values()):
        die(f"Alvo invalido: recebido {label}={weights!r}, esperado pesos >= 0.")
    total = sum(parsed.values(), Decimal("0"))
    if abs(total - Decimal("1")) > WEIGHT_TOLERANCE:
        die(f"Alvo invalido: recebido {label} soma {total} a partir de {weights!r}, esperado soma 1.")
    return parsed


def load_alvo(path: str) -> dict[str, dict[str, Decimal]]:
    expected = 'JSON {"porClasse": {<classe>: peso}, "porMercado": {br|us: peso}} com pesos somando 1'
    payload = load_json(path, expected)
    if not isinstance(payload, dict):
        die(f"Alvo invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    return {
        "porClasse": validate_weights(payload.get("porClasse"), "porClasse"),
        "porMercado": validate_weights(payload.get("porMercado"), "porMercado"),
    }


def load_quotes(path: str) -> dict[str, Decimal]:
    payload = load_json(path, 'JSON {"TICKER": preco}')
    if not isinstance(payload, dict) or not payload:
        die(f"Cotacoes invalidas: recebido {payload!r} em '{path}', esperado objeto {{TICKER: preco}}.")
    quotes = {}
    for ticker, price in payload.items():
        number = as_decimal(price, ticker, payload)
        if number <= 0:
            die(f"Cotacao invalida: recebido {ticker}={price!r}, esperado preco > 0.")
        quotes[str(ticker).upper()] = number
    return quotes


def position_value(item: dict[str, Any], quotes: dict[str, Decimal]) -> Decimal:
    ticker = item["ticker"]
    if ticker not in quotes:
        die(f"Cotacao ausente: recebido ticker '{ticker}' sem preco, esperado mapa de cotacoes com a chave do ticker.")
    return item["quantidade"] * quotes[ticker]


def grouped_values(
    positions: list[dict[str, Any]], quotes: dict[str, Decimal], key: str
) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = {}
    for item in positions:
        bucket = item[key]
        totals[bucket] = totals.get(bucket, Decimal("0")) + position_value(item, quotes)
    return totals


def slice_report(
    values: dict[str, Decimal], alvo: dict[str, Decimal], total: Decimal
) -> dict[str, dict[str, float]]:
    report: dict[str, dict[str, float]] = {}
    for key in sorted(set(values) | set(alvo)):
        valor = values.get(key, Decimal("0"))
        atual = (valor / total) if total else Decimal("0")
        meta = alvo.get(key, Decimal("0"))
        report[key] = {
            "valor": float(valor),
            "atual": float(atual),
            "alvo": float(meta),
            "desvio": float(atual - meta),
        }
    return report


def build_report(
    positions: list[dict[str, Any]],
    quotes: dict[str, Decimal],
    alvo: dict[str, dict[str, Decimal]],
) -> dict[str, Any]:
    total = sum((position_value(item, quotes) for item in positions), Decimal("0"))
    if total <= 0:
        die(f"Alocacao invalida: recebido total {total} a partir das posicoes, esperado valor de mercado > 0.")
    return {
        "total": float(total),
        "porClasse": slice_report(grouped_values(positions, quotes, "classe"), alvo["porClasse"], total),
        "porMercado": slice_report(grouped_values(positions, quotes, "mercado"), alvo["porMercado"], total),
    }


def main() -> None:
    if len(sys.argv) != 4:
        die(
            f"Uso invalido: recebido {sys.argv!r}, "
            "esperado alocacao-report.py <holdings.json> <alocacao-alvo.json> <quotes.json>"
        )
    report = build_report(load_holdings(sys.argv[1]), load_quotes(sys.argv[3]), load_alvo(sys.argv[2]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
