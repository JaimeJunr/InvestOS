"""Boilerplate compartilhado pelos scripts *-report.py (I/O e validacao generica).

Os scripts tem nome hifenizado e nao sao importaveis como modulo Python; este
arquivo (identificador valido) concentra o que era duplicado byte a byte entre
eles. Mensagens de erro de holdings/posicao divergem por script — por isso
validate_holding/load_holdings recebem as strings expected como parametro.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

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
        return Decimal(str(value))
    except Exception:
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")


def optional_liquidez(item: dict[str, Any]) -> str | None:
    # D+<n>, n inteiro >= 0, normalizado - D+007 e D+7 sao o mesmo prazo.
    # Antes vivia duplicada em diagnostico-report.py e achados-report.py
    # (scripts standalone com nome hifenizado, sem modulo importavel).
    raw = item.get("liquidez")
    if raw is None:
        return None
    text = str(raw).strip().upper()
    if not text:
        return None
    prazo = text[2:] if text.startswith("D+") else ""
    # isdecimal e nao isdigit: "²".isdigit() e True, mas int("²") levanta ValueError
    # la na frente (ordenacao de liquidez_keys) — o AC exige erro explicito, nao traceback.
    if not prazo.isdecimal():
        die(
            f"Liquidez invalida: recebido liquidez={raw!r} em {item!r}, "
            "esperado formato 'D+<n>' com n inteiro >= 0."
        )
    # Normaliza o prazo pelo inteiro: D+007 e D+7 sao o mesmo balde, nao dois.
    return f"D+{int(prazo)}"


def validate_holding(
    item: Any,
    index: int,
    *,
    expected_item: str,
    suporta_liquidez: bool = False,
) -> dict[str, Any]:
    # expected_item e suporta_liquidez variam por script (mensagens de erro
    # observaveis pelos testes) — nao unificar o texto.
    if not isinstance(item, dict):
        die(f"Posicao invalida: recebido {item!r} no indice {index}, esperado objeto {expected_item}.")
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
    if suporta_liquidez:
        liquidez = optional_liquidez(item)
        if liquidez is not None:
            entry["liquidez"] = liquidez
    return entry


def load_holdings(
    path: str,
    *,
    expected_holdings: str,
    expected_item: str,
    suporta_liquidez: bool = False,
) -> list[dict[str, Any]]:
    payload = load_json(path, expected_holdings)
    rows = payload.get("posicoes") if isinstance(payload, dict) else None
    if not isinstance(rows, list) or not rows:
        die(
            f"Holdings invalido: recebido {payload!r} em '{path}', "
            'esperado JSON {"posicoes": [...]} com pelo menos 1 posicao.'
        )
    return [
        validate_holding(
            item,
            index,
            expected_item=expected_item,
            suporta_liquidez=suporta_liquidez,
        )
        for index, item in enumerate(rows)
    ]


def print_report(report: dict[str, Any]) -> None:
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
