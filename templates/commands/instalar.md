---
description: Entrevista guiada que popula os arquivos de dados deste portfolio (holdings.json, alocacao-alvo.json, watchlist-fundos.json).
---

# /instalar

Este portfolio foi gerado por `bin/setup.sh`, mas ainda não tem dados — os scripts de
`bin/alocacao.sh`, `bin/risco.sh` e `bin/rebalanceamento.sh` exigem `holdings.json` e
`alocacao-alvo.json`, que ainda não existem. Este comando conduz uma entrevista curta pra criar
esses arquivos, um de cada vez, usando `AskUserQuestion` quando fizer sentido.

## Antes de perguntar

Rode a partir da raiz do InvestOS (não de dentro desta pasta). Se `holdings.json` ou
`alocacao-alvo.json` já existirem neste portfolio, avise e pergunte se quer sobrescrever antes de
continuar — nunca sobrescreva sem confirmação explícita. Se o `/status` sugeriu rodar `/instalar`
de novo só pra revisar o diagnóstico (perfil, objetivos, `ultimaRevisao`), deixe claro que dá pra
atualizar só o Passo 0 (`perfil-investidor.json`) sem mexer em `holdings.json`/`alocacao-alvo.json`.

## Passo 0 — Diagnóstico do investidor (`perfil-investidor.json`)

Antes de perguntar sobre posições, faça o mesmo diagnóstico que um profissional de finanças faz
antes de montar uma carteira. Não pule este passo mesmo que o usuário queira ir direto pras
posições — pergunte pelo menos uma vez, e registre a resposta.

1. **Perfil de risco (suitability) — derivado, nunca perguntado direto.** Não pergunte "qual
   perfil você se identifica" — isso é autoavaliação enviesada (quase todo mundo se acha "moderado"
   ou superestima a própria tolerância). Em vez disso, pergunte os 4 fatores que uma análise de
   suitability de verdade usa, e **derive** o perfil da combinação das respostas:
   - **Tolerância a perda:** se o valor investido caísse, digamos, 20% em pouco tempo, o
     investidor venderia tudo (baixa tolerância), ficaria preocupado mas manteria a posição
     (tolerância média) ou veria como oportunidade de aportar mais (alta tolerância)?
   - **Horizonte de tempo predominante:** reaproveite o Passo 0.2 (objetivos e prazos) — se a
     maioria dos objetivos é curto prazo, horizonte é curto; se é longo prazo (aposentadoria etc.),
     horizonte é longo.
   - **Conhecimento de mercado financeiro:** o investidor já usa só produtos básicos (poupança,
     CDB, Tesouro Direto), já entende fundos de investimento e renda variável leve (FIIs), ou já
     domina ações, derivativos, mercado internacional?
   - **Situação financeira atual:** reaproveite o Passo 0.3 (capacidade de aporte, reserva de
     emergência já formada ou não).

   Combine as 4 respostas numa classificação **conservador** (baixa tolerância + horizonte curto +
   conhecimento básico), **moderado** (fatores mistos, tolerância/horizonte médios) ou **arrojado**
   (alta tolerância + horizonte longo + conhecimento avançado + situação financeira consolidada) —
   sem fórmula rígida de peso, é julgamento sobre o conjunto. Sempre **apresente a classificação
   derivada de volta pro investidor e peça confirmação** antes de gravar — se ele discordar (ex.:
   "acho que sou mais conservador do que isso"), respeite a correção dele, mas registre os 4
   fatores originais mesmo assim (não apague o dado bruto).
2. **Objetivos e prazos:** para cada objetivo que o investidor mencionar, pergunte o prazo —
   **curto prazo** (até 1 ano: foco em liquidez e segurança, ex. reserva de emergência),
   **médio prazo** (1 a 5 anos: ganho real acima da inflação com risco controlado) ou
   **longo prazo** (acima de 5 anos: acumulação de patrimônio, aposentadoria). Para objetivos de
   médio/longo prazo, pergunte também um **ano-alvo aproximado** (ex.: "2030") — usado só pra
   lembrar de revisar a estratégia conforme a data se aproxima, não é compromisso rígido.
3. **Situação financeira atual (visão rápida, não um balanço completo):** capacidade de aporte
   mensal recorrente, e se já existe uma **reserva de emergência** de 3 a 12 meses de custo de vida
   em liquidez diária. Se a reserva ainda não existir, avise antes de seguir — normalmente ela vem
   antes de qualquer alocação de risco.
4. **Custos e alíquotas:** avise que Imposto de Renda (tabelas regressiva/progressiva conforme o
   ativo), taxas de administração/performance de fundos e custos de corretagem/custódia afetam o
   retorno líquido. Não precisa calcular nada agora — só deixar registrado que o investidor está
   ciente.
5. **Alinhamento de expectativas:** confirme que o investidor entende a relação direta entre risco
   e retorno e que oscilação de mercado é esperada dentro do prazo combinado, antes de fechar
   qualquer alocação-alvo.

Grave em `perfil-investidor.json`:

```json
{
  "perfilRisco": "moderado",
  "perfilRiscoFatores": {
    "toleranciaPerda": "media",
    "conhecimentoMercado": "intermediario",
    "confirmadoPeloInvestidor": true
  },
  "objetivos": [{"nome": "reserva de emergencia", "prazo": "curto"}, {"nome": "aposentadoria", "prazo": "longo", "anoAlvo": 2050}],
  "reservaEmergenciaOk": true,
  "cienteDeCustosEImpostos": true,
  "expectativasAlinhadas": true,
  "ultimaRevisao": "2026-08-30"
}
```

`perfilRiscoFatores` guarda os fatores brutos que geraram `perfilRisco` (horizonte e situação
financeira já vêm de `objetivos`/`reservaEmergenciaOk`, não precisam repetir aqui) —
`confirmadoPeloInvestidor: false` significa que o investidor corrigiu a classificação derivada.

`ultimaRevisao` é a data de hoje (formato `AAAA-MM-DD`) — o `/status` usa esse campo pra lembrar de
rodar `/instalar` de novo (revisão do diagnóstico, não do zero) quando passar muito tempo, ou
quando um `anoAlvo` estiver se aproximando.

Use o perfil de risco registrado aqui para **sugerir** um ponto de partida de alocação-alvo no
Passo 2 (ex.: perfil conservador tende a mais peso em renda fixa, arrojado tende a mais peso em
ações) — nunca imponha o peso sugerido; a decisão final de alocação é sempre do usuário.

## Passo 1 — Posições (`holdings.json`)

Pergunte quais posições o usuário já tem hoje: ticker, quantidade, classe (ex.: `acoes`,
`renda-fixa`, `fundos`) e mercado (`br` ou `us`, deve bater com o enum de `portfolio.json`). Aceite
uma lista em texto livre (ex.: "100 PETR4 acoes br, 50 IVVB11 acoes br") em vez de perguntar campo
por campo pra cada posição. Se o usuário não tiver nenhuma posição ainda, grave uma lista vazia —
não invente posição.

Grave em `holdings.json`:

```json
{"posicoes": [{"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"}]}
```

## Passo 2 — Alocação-alvo (`alocacao-alvo.json`)

Antes de perguntar, ofereça uma **sugestão** de ponto de partida com base no `perfilRisco` do
Passo 0 (ex.: conservador → mais peso em renda fixa; arrojado → mais peso em ações) — deixe claro
que é só sugestão e pergunte a alocação-alvo real que o usuário quer, por classe e por mercado (os
pesos de cada dimensão devem somar 1), e o threshold de desvio que deve disparar sugestão de
rebalanceamento (fração em `(0, 1]` — se o usuário não souber, sugira `0.05` como ponto de partida
e explique que é ajustável depois).

Grave em `alocacao-alvo.json`:

```json
{"porClasse": {"acoes": 0.6, "renda-fixa": 0.4}, "porMercado": {"br": 0.7, "us": 0.3}, "threshold": 0.05}
```

## Passo 3 — Watchlist de fundos (`watchlist-fundos.json`, opcional)

Só pergunte se `holdings.json` tiver alguma posição com `classe` de fundo ou se o domínio
`dados-mercado` estiver habilitado para o mercado `br`. Peça o(s) CNPJ(s) (14 dígitos) dos fundos
de interesse.

Grave em `watchlist-fundos.json`:

```json
{"cnpjs": ["00.000.000/0001-00"]}
```

Pule este passo (não crie o arquivo) se não houver fundo nenhum.

## Ao final

Resuma o que foi gravado (diagnóstico, posições, alocação-alvo, watchlist se houver) e sugira o
próximo comando: `bin/alocacao.sh <slug>` para ver a alocação atual, ou `/status` pra um briefing
rápido.
