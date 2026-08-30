#!/usr/bin/env python3
"""Relatorio informativo de ganho/perda nao realizada (tax-loss harvesting).

Nunca recomenda vender. Nunca calcula Imposto de Renda devido - so aponta,
por posicao com precoMedio conhecido, se ha perda nao realizada hoje.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

AVISO_LEGAL = (
    "Informativo apenas - nao e recomendacao de venda nem calculo de Imposto de Renda "
    "devido. Consulte um contador antes de realizar qualquer perda para fins fiscais."
)


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
        return Decimal(str(value))
    except Exception:
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")


def load_holdings(path: str) -> list[dict[str, Any]]:
    expected = 'JSON {"posicoes": [{ticker, quantidade, classe, mercado, precoMedio?}, ...]}'
    payload = load_json(path, expected)
    rows = payload.get("posicoes") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        die(f"Holdings invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    positions = []
    for index, item in enumerate(rows):
        if not isinstance(item, dict):
            die(f"Posicao invalida: recebido {item!r} no indice {index}, esperado objeto {expected}.")
        ticker = str(item.get("ticker") or "").strip().upper()
        quantidade = as_decimal(item.get("quantidade"), "quantidade", item)
        if not ticker or quantidade <= 0:
            die(f"Posicao invalida: recebido {item!r}, esperado ticker nao-vazio e quantidade > 0.")
        entry: dict[str, Any] = {"ticker": ticker, "quantidade": quantidade}
        if "precoMedio" in item:
            entry["precoMedio"] = as_decimal(item["precoMedio"], "precoMedio", item)
        positions.append(entry)
    return positions


def load_quotes(path: str) -> dict[str, Decimal]:
    payload = load_json(path, 'JSON {"TICKER": preco}')
    if not isinstance(payload, dict):
        die(f"Cotacoes invalidas: recebido {payload!r} em '{path}', esperado objeto {{TICKER: preco}}.")
    quotes: dict[str, Decimal] = {}
    for ticker, price in payload.items():
        number = as_decimal(price, ticker, payload)
        if number <= 0:
            die(f"Cotacao invalida: recebido {ticker}={price!r}, esperado preco > 0.")
        quotes[str(ticker).upper()] = number
    return quotes


def build_report(positions: list[dict[str, Any]], quotes: dict[str, Decimal]) -> dict[str, Any]:
    posicoes: list[dict[str, Any]] = []
    sem_preco_medio: list[str] = []
    candidatos: list[str] = []

    for item in positions:
        ticker = item["ticker"]
        if "precoMedio" not in item:
            sem_preco_medio.append(ticker)
            continue
        if ticker not in quotes:
            die(f"Cotacao ausente: recebido ticker '{ticker}' sem preco, esperado mapa de cotacoes com a chave do ticker.")
        preco_medio = item["precoMedio"]
        preco_atual = quotes[ticker]
        ganho_valor = (preco_atual - preco_medio) * item["quantidade"]
        perda = ganho_valor < 0
        if perda:
            candidatos.append(ticker)
        posicoes.append(
            {
                "ticker": ticker,
                "precoMedio": float(preco_medio),
                "precoAtual": float(preco_atual),
                "ganhoValor": float(ganho_valor),
                "perdaNaoRealizada": perda,
            }
        )

    return {
        "posicoes": posicoes,
        "posicoesSemPrecoMedio": sorted(sem_preco_medio),
        "candidatosTaxLossHarvesting": sorted(candidatos),
        "avisoLegal": AVISO_LEGAL,
    }


def main() -> None:
    if len(sys.argv) != 3:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado perdas-report.py <holdings.json> <quotes.json>")
    report = build_report(load_holdings(sys.argv[1]), load_quotes(sys.argv[2]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
