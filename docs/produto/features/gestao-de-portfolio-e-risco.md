[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Gestão de Portfólio e Risco

**Prioridade:** P1. No v1, as posições (`holdings.json`) entram manualmente — a integração
automática com corretora/banco é a área [Integração com Corretora/Banco](integracao-corretora-banco.md),
que alimenta o mesmo arquivo quando conectada. A alocação-alvo (`alocacao-alvo.json`) é sugerida a
partir do perfil de risco levantado no diagnóstico do `/instalar` (`perfil-investidor.json`), mas a
decisão final de peso é sempre do usuário.

## Alocação (`bin/alocacao.sh`)

Compara a alocação atual do portfólio (a partir de `holdings.json`) com a alocação-alvo definida
pelo usuário em `alocacao-alvo.json`:

```json
{"posicoes": [
  {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
  {"ticker": "NTN-B mai/2055", "quantidade": 4, "classe": "renda-fixa", "mercado": "br", "precoManual": 1005.74}
]}
```

`precoManual` (opcional) é o preço unitário pra posições **sem ticker cotável** — Tesouro Direto,
CDB, debênture, qualquer renda fixa direta. Quando presente, o valor da posição é
`quantidade × precoManual`, e **nenhum script tenta consultar cotação externa** pra esse ticker
(nem brapi, nem histórico, nem dividend yield) — você atualiza o valor manualmente conforme o
extrato. Sem isso, essas posições ficam de fora do cálculo de alocação por completo (é exatamente
o gap que motivou o campo: o valor "some" da renda fixa e o desvio de alocação fica artificialmente
enorme).

```json
{"porClasse": {"acoes": 0.6, "renda-fixa": 0.4}, "porMercado": {"br": 0.7, "us": 0.3}, "threshold": 0.05}
```

Os pesos de cada dimensão somam 1. Valoriza posições BR via `brapi-quote.sh`; posições US/global
exigem o override injetável `ALOCACAO_QUOTE` (mesmo mecanismo declarativo do MCP).

## Risco (`bin/risco.sh`)

Calcula **VaR histórico 95%**, **Sharpe** (taxa livre de risco = 0, anualizado em 252 dias úteis) e
**max drawdown** a partir do histórico de preços das posições. Ações/ETFs/FIIs BR usam
`brapi-quote.sh` (janela de 3 meses); fundos BR (ticker = CNPJ) usam `cvm-informe.sh`; US/global
exige `RISCO_HISTORY` injetado. Quando um ativo não tem histórico suficiente, o relatório segue com
um aviso explícito de limitação — nunca trava nem omite o ativo em silêncio.

## Rebalanceamento (`bin/rebalanceamento.sh`)

Compara o desvio atual contra o `threshold` configurado em `alocacao-alvo.json` (fração em `(0,
1]`). Se o desvio ultrapassar o limite, sugere quantidades a comprar/vender por ticker — texto
apenas. **Nunca envia ordem, nunca chama corretora, nunca grava `holdings.json`.**
