#!/usr/bin/env python3
"""Monta o relatorio de diagnostico da carteira atual."""

from __future__ import annotations

import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib_report import as_decimal, die, load_holdings, load_json, print_report

LIQUIDEZ_KEYS = ("D+0", "D+1")
INDISPONIVEL = "indisponivel"


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


def liquidez_keys(values: dict[str, Decimal]) -> tuple[str, ...]:
    # Piso D+0/D+1 sempre presente (invariante de porLiquidez), mais qualquer
    # prazo observado nas posicoes, ordenado numericamente (lexicografico erra:
    # "D+1" < "D+30" < "D+0" como texto).
    observed = set(values) | set(LIQUIDEZ_KEYS)
    return tuple(sorted(observed, key=lambda key: int(key[2:])))


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
    valores_liquidez = grouped_values(positions, quotes, "liquidez")
    return {
        "total": float(total),
        "concentracao": concentration_report(values_by_ticker(positions, quotes), total),
        "porMercado": slice_report(grouped_values(positions, quotes, "mercado"), total, ("br", "us")),
        "porLiquidez": slice_report(valores_liquidez, total, liquidez_keys(valores_liquidez)),
        "dividendYield12m": dividend_yield_rows(positions, quotes),
    }


def main() -> None:
    if len(sys.argv) != 3:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado diagnostico-report.py <holdings.json> <quotes.json>")
    report = build_report(
        load_holdings(
            sys.argv[1],
            expected_holdings='JSON {"posicoes": [{ticker, quantidade, classe, mercado, liquidez?}, ...]}',
            expected_item="{ticker, quantidade, classe, mercado, liquidez?}",
            suporta_liquidez=True,
        ),
        load_quotes(sys.argv[2]),
    )
    print_report(report)


if __name__ == "__main__":
    main()
