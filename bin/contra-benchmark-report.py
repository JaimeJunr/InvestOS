#!/usr/bin/env python3
"""Monta o relatorio de Beta, Alfa, R-quadrado e Tracking Error vs. benchmark."""

from __future__ import annotations

import json
import statistics
import sys
from typing import Any

MERCADOS = ("br", "us")
INSUFFICIENT = "historico insuficiente"
# 2 pontos de retorno deixam R² sempre 1 (AC: numero instavel). 4 NAVs = 3 retornos.
MIN_ALIGNED = 4


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


def as_float(value: Any, field: str, received: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")
    return number


def load_nav(path: str) -> list[dict[str, Any]]:
    expected = 'JSON [{"data": "AAAA-MM-DD", "valorTotal": ...}]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"NAV invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    points = []
    for item in payload:
        if not isinstance(item, dict):
            die(f"Snapshot invalido: recebido {item!r}, esperado objeto {{data, valorTotal}}.")
        day = str(item.get("data") or "").strip()[:10]
        value = as_float(item.get("valorTotal"), "valorTotal", item)
        if not day or value <= 0:
            die(f"Snapshot invalido: recebido {item!r}, esperado data nao-vazia e valorTotal > 0.")
        points.append({"date": day, "close": value})
    return sorted(points, key=lambda point: point["date"])


def load_points(label: str, rows: Any) -> list[dict[str, Any]]:
    if not isinstance(rows, list):
        die(f"Historico invalido: recebido {label}={rows!r}, esperado lista de {{date, close}}.")
    points = []
    for item in rows:
        if not isinstance(item, dict):
            die(f"Ponto invalido: recebido {item!r} em {label}, esperado objeto {{date, close}}.")
        day = str(item.get("date") or "").strip()[:10]
        close = as_float(item.get("close"), "close", item)
        if not day or close <= 0:
            die(f"Ponto invalido: recebido {item!r} em {label}, esperado date nao-vazio e close > 0.")
        points.append({"date": day, "close": close})
    return sorted(points, key=lambda point: point["date"])


def load_bundle(path: str, markets: tuple[str, ...]) -> dict[str, dict[str, Any]]:
    expected = 'JSON {"br"|"us": {"ticker", "pontos": [{"date","close"}]}}'
    payload = load_json(path, expected)
    if not isinstance(payload, dict):
        die(f"Benchmark invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    bundle = {}
    for market in markets:
        entry = payload.get(market)
        if not isinstance(entry, dict) or "ticker" not in entry:
            die(f"Benchmark invalido: recebido {market}={entry!r}, esperado objeto {{ticker, pontos}}.")
        ticker = str(entry.get("ticker") or "").strip()
        if not ticker:
            die(f"Benchmark invalido: recebido ticker {entry.get('ticker')!r} em {market}, esperado ticker nao-vazio.")
        bundle[market] = {"ticker": ticker, "pontos": load_points(ticker, entry.get("pontos"))}
    return bundle


def markets_for(mercado: str) -> tuple[str, ...]:
    if mercado in MERCADOS:
        return (mercado,)
    if mercado == "ambos":
        return MERCADOS
    die(f"Mercado invalido: recebido {mercado!r}, esperado um de: br, us, ambos.")
    return MERCADOS


def series_by_date(points: list[dict[str, Any]]) -> dict[str, float]:
    return {point["date"]: float(point["close"]) for point in points}


def aligned_values(
    nav: list[dict[str, Any]], bench: list[dict[str, Any]]
) -> tuple[list[float], list[float]]:
    nav_map = series_by_date(nav)
    bench_map = series_by_date(bench)
    days = sorted(set(nav_map) & set(bench_map))
    return [nav_map[day] for day in days], [bench_map[day] for day in days]


def period_returns(values: list[float]) -> list[float]:
    return [values[index] / values[index - 1] - 1.0 for index in range(1, len(values))]


def insufficient_payload(mercado: str, ticker: str) -> dict[str, Any]:
    return {
        "mercado": mercado,
        "benchmark": ticker,
        "beta": INSUFFICIENT,
        "alfa": INSUFFICIENT,
        "rQuadrado": INSUFFICIENT,
        "trackingError": INSUFFICIENT,
    }


def regression_metrics(portfolio: list[float], benchmark: list[float]) -> dict[str, float]:
    # Snapshots de NAV nao sao diarios; nao anualiza com 252.
    fit = statistics.linear_regression(benchmark, portfolio)
    excess = [left - right for left, right in zip(portfolio, benchmark)]
    return {
        "beta": fit.slope,
        "alfa": fit.intercept,
        "rQuadrado": statistics.correlation(portfolio, benchmark) ** 2,
        "trackingError": statistics.stdev(excess),
    }


def metrics_or_insufficient(mercado: str, ticker: str, nav: list[dict[str, Any]], bench: list[dict[str, Any]]) -> dict[str, Any]:
    nav_values, bench_values = aligned_values(nav, bench)
    if len(nav_values) < MIN_ALIGNED:
        return insufficient_payload(mercado, ticker)
    portfolio = period_returns(nav_values)
    market = period_returns(bench_values)
    if len(portfolio) < 2 or statistics.pstdev(market) == 0:
        return insufficient_payload(mercado, ticker)
    payload = insufficient_payload(mercado, ticker)
    payload.update(regression_metrics(portfolio, market))
    return payload


def build_report(
    nav: list[dict[str, Any]], bundle: dict[str, dict[str, Any]], mercado: str
) -> dict[str, Any]:
    markets = markets_for(mercado)
    rows = [
        metrics_or_insufficient(market, bundle[market]["ticker"], nav, bundle[market]["pontos"])
        for market in markets
    ]
    if len(rows) == 1:
        return rows[0]
    return {"mercado": mercado, "porMercado": {row["mercado"]: row for row in rows}}


def main() -> None:
    if len(sys.argv) != 4:
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "contra-benchmark-report.py <nav-historico.json> <benchmark.json> <mercado>"
        )
    mercado = str(sys.argv[3]).strip().lower()
    markets = markets_for(mercado)
    report = build_report(load_nav(sys.argv[1]), load_bundle(sys.argv[2], markets), mercado)
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
