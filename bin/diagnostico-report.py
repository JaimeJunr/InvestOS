#!/usr/bin/env python3
"""Monta o relatorio de diagnostico da carteira atual."""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

MERCADOS = {"br", "us"}
LIQUIDEZ_KEYS = ("D+0", "D+1")
INDISPONIVEL = "indisponivel"


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


def optional_liquidez(item: dict[str, Any]) -> str | None:
    raw = item.get("liquidez")
    if raw is None:
        return None
    text = str(raw).strip().upper()
    return text or None


def validate_holding(item: Any, index: int) -> dict[str, Any]:
    expected = "{ticker, quantidade, classe, mercado, liquidez?}"
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
    entry = {"ticker": ticker, "quantidade": quantidade, "classe": classe, "mercado": mercado}
    liquidez = optional_liquidez(item)
    if liquidez is not None:
        entry["liquidez"] = liquidez
    return entry


def load_holdings(path: str) -> list[dict[str, Any]]:
    expected = 'JSON {"posicoes": [{ticker, quantidade, classe, mercado, liquidez?}, ...]}'
    payload = load_json(path, expected)
    rows = payload.get("posicoes") if isinstance(payload, dict) else None
    if not isinstance(rows, list) or not rows:
        die(
            f"Holdings invalido: recebido {payload!r} em '{path}', "
            'esperado JSON {"posicoes": [...]} com pelo menos 1 posicao.'
        )
    return [validate_holding(item, index) for index, item in enumerate(rows)]


def load_quote_entry(ticker: str, info: Any, payload: Any) -> dict[str, Any]:
    if not isinstance(info, dict) or "preco" not in info:
        die(f"Cotacao invalida: recebido {ticker}={info!r} em {payload!r}, esperado objeto {{preco, dividendYield?}}.")
    preco = as_decimal(info.get("preco"), ticker, info)
    if preco <= 0:
        die(f"Cotacao invalida: recebido {ticker}={info!r}, esperado preco > 0.")
    entry: dict[str, Any] = {"preco": preco}
    if info.get("dividendYield") is not None:
        entry["dividendYield"] = as_decimal(info["dividendYield"], "dividendYield", info)
    return entry


def load_quotes(path: str) -> dict[str, dict[str, Any]]:
    payload = load_json(path, 'JSON {"TICKER": {preco, dividendYield?}}')
    if not isinstance(payload, dict) or not payload:
        die(f"Cotacoes invalidas: recebido {payload!r} em '{path}', esperado objeto {{TICKER: {{preco}}}}.")
    quotes = {}
    for ticker, info in payload.items():
        quotes[str(ticker).upper()] = load_quote_entry(str(ticker), info, payload)
    return quotes


def position_value(item: dict[str, Any], quotes: dict[str, dict[str, Any]]) -> Decimal:
    ticker = item["ticker"]
    if ticker not in quotes:
        die(f"Cotacao ausente: recebido ticker '{ticker}' sem preco, esperado mapa de cotacoes com a chave do ticker.")
    return item["quantidade"] * quotes[ticker]["preco"]


def values_by_ticker(positions: list[dict[str, Any]], quotes: dict[str, dict[str, Any]]) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = {}
    for item in positions:
        ticker = item["ticker"]
        totals[ticker] = totals.get(ticker, Decimal("0")) + position_value(item, quotes)
    return totals


def grouped_values(
    positions: list[dict[str, Any]], quotes: dict[str, dict[str, Any]], key: str
) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = {}
    for item in positions:
        if key not in item:
            continue
        bucket = item[key]
        totals[bucket] = totals.get(bucket, Decimal("0")) + position_value(item, quotes)
    return totals


def share(valor: Decimal, total: Decimal) -> float:
    if total <= 0:
        return 0.0
    return float(valor / total)


def slice_report(values: dict[str, Decimal], total: Decimal, keys: tuple[str, ...]) -> dict[str, dict[str, float]]:
    report: dict[str, dict[str, float]] = {}
    for key in keys:
        valor = values.get(key, Decimal("0"))
        report[key] = {"valor": float(valor), "percentual": share(valor, total)}
    return report


def concentration_report(values: dict[str, Decimal], total: Decimal) -> dict[str, Any]:
    ticker = max(values, key=lambda name: (values[name], name))
    valor = values[ticker]
    return {"ticker": ticker, "valor": float(valor), "percentual": share(valor, total)}


def dividend_yield_value(quote: dict[str, Any]) -> Any:
    if "dividendYield" not in quote:
        return INDISPONIVEL
    return float(quote["dividendYield"])


def dividend_yield_rows(
    positions: list[dict[str, Any]], quotes: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in positions:
        ticker = item["ticker"]
        if ticker in seen:
            continue
        seen.add(ticker)
        rows.append({"ticker": ticker, "dividendYield": dividend_yield_value(quotes[ticker])})
    return rows


def build_report(positions: list[dict[str, Any]], quotes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    total = sum((position_value(item, quotes) for item in positions), Decimal("0"))
    if total <= 0:
        die(f"Diagnostico invalido: recebido total {total} a partir das posicoes, esperado valor de mercado > 0.")
    return {
        "total": float(total),
        "concentracao": concentration_report(values_by_ticker(positions, quotes), total),
        "porMercado": slice_report(grouped_values(positions, quotes, "mercado"), total, ("br", "us")),
        "porLiquidez": slice_report(grouped_values(positions, quotes, "liquidez"), total, LIQUIDEZ_KEYS),
        "dividendYield12m": dividend_yield_rows(positions, quotes),
    }


def main() -> None:
    if len(sys.argv) != 3:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado diagnostico-report.py <holdings.json> <quotes.json>")
    report = build_report(load_holdings(sys.argv[1]), load_quotes(sys.argv[2]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
