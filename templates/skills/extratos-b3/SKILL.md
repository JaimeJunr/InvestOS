---
name: extratos-b3
description: Use when the user pastes, uploads or mentions a B3 Área do Investidor statement/extract (Movimentação, Negociação, Eventos, Ofertas Públicas — any format: XLSX, PDF, CSV, plain text) and wants it registered persistently in InvestOS, or asks for a negociacoes/eventos-corporativos summary report.
---

# extratos-b3

Ler o extrato é trabalho seu, não de código bash — o InvestOS não tem (nem deveria ter) um parser
amarrado ao layout da B3. Você já sabe ler planilhas/PDFs; use isso.

Os quatro extratos oficiais da Área do Investidor (Movimentação, Negociação, Eventos, Ofertas
Públicas) entram pelos comandos abaixo. **Nunca classifique silenciosamente um tipo de movimento
ambíguo** — pergunte ao usuário antes de assumir a categoria.

## Negociação

1. Leia o arquivo. Procure ticker, lado (compra/venda), quantidade, preço unitário e data.
2. Monte um array JSON no formato exato:
   ```json
   [{"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10", "oferta": null}]
   ```
   `tipo` ∈ `compra | venda`. `oferta` só entra preenchido se a linha for de Oferta Pública (veja
   abaixo); senão omita ou deixe `null`. Grave o array num arquivo temporário e rode:
   ```bash
   bin/negociacao.sh <slug> importar <arquivo-temporario>.json
   ```
3. `importar` é idempotente (reimportar o mesmo extrato não duplica) e all-or-nothing (um item
   inválido rejeita o arquivo inteiro). Para um evento avulso:
   `bin/negociacao.sh <slug> registrar <ticker> <tipo> <quantidade> <precoUnitario> <data> [oferta]`.

## Ofertas Públicas

Mesmo fluxo de Negociação. Preencha `oferta` com o código/nome da oferta (IPO, follow-on,
subscrição) que estiver no extrato:

```json
[{"ticker": "VALE3", "tipo": "compra", "quantidade": 50, "precoUnitario": 60.00, "data": "2026-03-12", "oferta": "follow-on-vale"}]
```

Não existe arquivo/schema separado para ofertas — o campo `oferta` em `negociacoes.json` é a
cobertura. Nunca invente o nome da oferta; se o extrato não disser, pergunte.

## Eventos

1. Leia o extrato de Eventos (desdobramento, grupamento, bonificação, incorporação, outro).
2. Monte um array JSON no formato exato:
   ```json
   [{"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2, "quantidadeRecebida": null, "observacao": null}]
   ```
   `tipo` ∈ `desdobramento | grupamento | bonificacao | incorporacao | outro`. `fator`,
   `quantidadeRecebida` e `observacao` são todos opcionais (pode ser só um registro informativo).
   Ex.: desdobro 1:2 → `fator=2`; grupamento 10:1 → `fator=0.1`; bonificação em quantidade nova →
   `quantidadeRecebida` em vez de fator.
3. Grave o array num arquivo temporário e rode:
   ```bash
   bin/evento-corporativo.sh <slug> importar <arquivo-temporario>.json
   ```
   Este é um **log puramente informativo** — **não** ajuste `holdings.json` automaticamente. A
   matemática de ajuste por tipo de evento está fora do v1.

## Movimentação

O extrato de Movimentação é um ledger genérico que mistura tudo. Classifique **cada linha** pelo
tipo de movimento e roteie para o comando certo:

| Tipo de movimento no extrato | Destino |
|---|---|
| Dividendo / JCP / Rendimento | mesma lógica da skill `proventos` → `bin/provento.sh <slug> importar <arquivo>` |
| Transferência (depósito/retirada de custódia, ~aporte/resgate) | `bin/transacao.sh <slug> registrar aporte\|resgate <valor> [data]` — **não tem `importar`**, só um registro por chamada; se forem várias linhas, chame em loop |
| Desdobramento / Grupamento / Bonificação / Incorporação | `bin/evento-corporativo.sh <slug> importar <arquivo>` |
| Compra / Venda | `bin/negociacao.sh <slug> importar <arquivo>` |

Se a linha for ambígua (não dá para dizer se é rendimento, transferência, evento ou negócio),
**pare e pergunte** — não chute a categoria.

Para proventos, o array canônico é o da skill `proventos` (`ticker`, `tipo`, `classe`,
`valorBruto`, `valorLiquido`, `data`). Nunca invente bruto vs líquido; se o extrato só tiver um
valor, pergunte.

## Relatórios

- `bin/negociacoes-relatorio.sh <slug>` — totais comprado/vendido, quantidade líquida por ticker,
  volume por ticker e por tipo, e seção de ofertas públicas (itens com `oferta` preenchido).
  **Não calcula ganho/perda de capital** (não é objetivo do InvestOS calcular IR).
- `bin/eventos-corporativos-relatorio.sh <slug>` — listagem ordenada por data, agrupada por ticker
  e por tipo. Sem cálculo de retorno/valor.
