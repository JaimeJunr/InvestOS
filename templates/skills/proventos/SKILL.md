---
name: proventos
description: Use when the user pastes, uploads or mentions a brokerage statement/extract with dividends, JCP or rendimentos (any broker, any format — XLSX, PDF text, CSV, plain text) and wants it registered persistently in InvestOS, or asks for a proventos/dividend summary report.
---

# proventos

Ler o extrato é trabalho seu, não de código bash — o InvestOS não tem (nem deveria ter) um parser
amarrado ao layout de uma corretora específica. Você já sabe ler planilhas/PDFs; use isso.

## Registrando proventos de um extrato

1. Leia o arquivo que o usuário deu (XLSX, PDF, CSV, o que for). Procure a seção de
   dividendos/proventos/distribuições — geralmente tem ticker, tipo (dividendo, JCP, rendimento),
   valor bruto, valor líquido (ou só um dos dois — se só tiver um valor, pergunte ao usuário se é
   bruto ou líquido antes de assumir) e data.
2. Nunca invente ou estime um valor que não está no extrato. Se um evento não tiver classe
   associada, pergunte ou infira de `holdings.json` pelo ticker (nunca "chute" silenciosamente).
3. Monte um array JSON no formato exato:
   ```json
   [{"ticker": "PETR4", "tipo": "dividendo", "classe": "acoes", "valorBruto": 6.13, "valorLiquido": 6.13, "data": "2026-12-21"}]
   ```
   `tipo` ∈ `dividendo | jcp | rendimento`. Grave esse array num arquivo temporário e rode:
   ```bash
   bin/provento.sh <slug> importar <arquivo-temporario>.json
   ```
4. `importar` é idempotente (reimportar o mesmo extrato não duplica) e all-or-nothing (um evento
   inválido rejeita o arquivo inteiro, com mensagem dizendo qual). Para um evento avulso, use
   `bin/provento.sh <slug> registrar <ticker> <tipo> <classe> <valorBruto> <valorLiquido> [data]`.

## Relatório

Rode `bin/proventos-relatorio.sh <slug>` pra ver totais (bruto/líquido/retido na fonte), por
ticker/classe/tipo, e dividend yield realizado dos últimos 12 meses (precisa de
`nav-historico.json` com histórico suficiente — sem isso, marca "dado insuficiente").

**Nunca apresente isso como cálculo de Imposto de Renda devido** — o relatório já carrega o aviso
legal explícito; retenção na fonte varia por tipo de provento e situação do investidor.
