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
de novo só pra revisar o diagnóstico (perfil, objetivos, `ultimaRevisao`, `implicacoes[]`), deixe
claro que dá pra atualizar só o Passo 0 (`perfil-investidor.json`) sem mexer em
`holdings.json`/`alocacao-alvo.json`.

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
  "ultimaRevisao": "2026-08-30",
  "implicacoes": [
    {
      "pergunta": "Essa posição em PETR4 é a maior da carteira e você marcou aposentadoria como objetivo de mais longo prazo — como você enxerga essa posição dentro desse objetivo?",
      "respostaDoInvestidor": "acho que ta ok, é uma empresa solida",
      "quedaEstimadaPeloInvestidor": null,
      "ticker": "PETR4",
      "data": "2026-08-30"
    },
    {
      "pergunta": "Se sua carteira como um todo caísse pela metade num ano ruim, o que você acha que aconteceria?",
      "respostaDoInvestidor": "ia doer mas eu seguraria",
      "quedaEstimadaPeloInvestidor": 0.5,
      "ticker": null,
      "data": "2026-08-30"
    }
  ]
}
```

`perfilRiscoFatores` guarda os fatores brutos que geraram `perfilRisco` (horizonte e situação
financeira já vêm de `objetivos`/`reservaEmergenciaOk`, não precisam repetir aqui) —
`confirmadoPeloInvestidor: false` significa que o investidor corrigiu a classificação derivada.
`implicacoes` guarda o registro bruto do Passo 2 (implicação) — a entrevista de suitability em si
não muda por causa dele, é um array que só cresce conforme o investidor responde às perguntas
daquele passo. `ticker` é o símbolo exato de `holdings.json` (ex.: `"PETR4"`, nunca o nome da
empresa) quando a pergunta foi sobre uma posição concreta, ou `null` quando foi sobre a carteira
como um todo ou sobre um objetivo — existe pra que `bin/achados.sh` confronte automaticamente a
queda que o investidor estimou com o drawdown histórico daquele mesmo ativo (US-006), sem depender
de extrair o ticker da prosa da `pergunta`; não é redundante com o texto da pergunta por isso,
mesmo que pareça à primeira vista. Item gravado antes desse campo existir continua válido — é
aditivo, ausência não invalida a implicação.

`ultimaRevisao` é a data de hoje (formato `AAAA-MM-DD`) — o `/status` usa esse campo pra lembrar de
rodar `/instalar` de novo (revisão do diagnóstico, não do zero) quando passar muito tempo, ou
quando um `anoAlvo` estiver se aproximando.

Use o perfil de risco registrado aqui para **sugerir** um ponto de partida de alocação-alvo no
Passo 3 (ex.: perfil conservador tende a mais peso em renda fixa, arrojado tende a mais peso em
ações) — nunca imponha o peso sugerido; a decisão final de alocação é sempre do usuário.

## Passo 1 — Posições (`holdings.json`)

Pergunte quais posições o usuário já tem hoje: ticker, quantidade, classe (ex.: `acoes`,
`renda-fixa`, `fundos`) e mercado (`br` ou `us`, deve bater com o enum de `portfolio.json`). Aceite
uma lista em texto livre (ex.: "100 PETR4 acoes br, 50 IVVB11 acoes br") em vez de perguntar campo
por campo pra cada posição. Se o usuário não tiver nenhuma posição ainda, grave uma lista vazia —
não invente posição.

Se alguma posição **não tiver ticker cotável** (Tesouro Direto, CDB, debênture, qualquer renda
fixa direta — mesmo que o usuário mencione um nome/código que não é símbolo de B3/bolsa), pergunte
o valor unitário atual (do extrato) e grave como `precoManual`. Não tente inventar ou adivinhar um
ticker de mercado pra esses — mesmo que a brapi tenha símbolos de Tesouro Direto reais, eles
exigem plano pago; `precoManual` é o caminho que funciona sem custo. Deixe claro que o valor
precisa ser atualizado manualmente (não é cotação ao vivo).

Nesse mesmo ponto (posição sem ticker cotável), pergunte também o **prazo de resgate** e grave
como `liquidez`, no formato `"D+<n>"` (`n` dias, inteiro >= 0 — `"D+0"` resgate no mesmo dia,
`"D+1"` no dia seguinte, `"D+30"`, `"D+180"` etc.). Este passo é o único lugar do sistema que
produz esse dado — sem gravar aqui, o campo nunca é preenchido por ninguém. Se o investidor não
souber o prazo, não grave o campo (ausente é diferente de ilíquido — não invente `"D+0"` só pra
preencher).

Grave em `holdings.json`:

```json
{"posicoes": [
  {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
  {"ticker": "NTN-B mai/2055", "quantidade": 4, "classe": "renda-fixa", "mercado": "br", "precoManual": 1005.74, "liquidez": "D+1"}
]}
```

## Passo 2 — Implicação (registrado em `perfil-investidor.json`)

Se `holdings.json` ainda estiver vazio (nenhuma posição registrada no Passo 1), pule este passo —
não há posição concreta pra conversar a respeito.

Este passo é **só perguntas**. Você não afirma número, não afirma risco, não afirma consequência
e não responde a própria pergunta — se o investidor devolver "sei lá, você acha que é muito?",
devolva a pergunta a ele, nunca dê o veredito. A superfície de entrevista é socrática pura; afirmar
consequência é trabalho do relatório, não deste comando.

Calibre o vocabulário por `perfilRiscoFatores.conhecimentoMercado` (já coletado no Passo 0): para
`basico`, use termos concretos do dia a dia ("cair pela metade"); para `intermediario` — o caso mais
comum — use o termo técnico mas explique o mecanismo na mesma frase ("uma queda forte, um drawdown
de uns 40%"); para `avancado`, pode usar o termo direto (volatilidade, drawdown). Nunca
condescendência, nunca jargão gratuito.

Pelo menos uma pergunta deve amarrar uma posição concreta a um objetivo concreto já declarado no
Passo 0 — por exemplo, a maior posição da carteira e o objetivo de maior prazo. Pelo menos uma
pergunta deve pedir ao investidor que nomeie um cenário de queda pra alguma posição — o número é
dele, não do sistema. Exemplos de pergunta boa, no tom deste comando:

- "Essa posição em PETR4 é a maior da sua carteira, e aposentadoria é o objetivo de prazo mais
  longo que você registrou — como você enxerga essa posição dentro desse objetivo?"
- "E se esse ativo caísse pela metade num ano ruim, o que você acha que aconteceria com o seu
  plano?" (pra `conhecimentoMercado: basico`) ou "qual drawdown você toleraria nessa posição num
  ano ruim?" (pra `avancado`)
- "Você tem uma posição relevante em renda variável dentro de um objetivo de curto prazo — o que
  te faz sentir confortável com isso?"
- "Se essa posição não existisse hoje, você compraria ela de novo com o dinheiro que teria em
  mãos?"

O investidor pode recusar responder qualquer uma delas: siga sem gravar aquele item, sem insistir
e sem reformular a mesma pergunta de outro jeito pra tentar forçar uma resposta.

Grave cada resposta em `perfil-investidor.json`, no array `implicacoes[]` (ver exemplo no Passo
0) — `respostaDoInvestidor` é a frase do investidor **verbatim**, nunca reescrita ou resumida:
é essa frase que o relatório vai citar de volta pra ele depois, e reescrita perde o valor.
`quedaEstimadaPeloInvestidor` é uma fração (ex.: `0.5` pra "metade") só quando ele nomeou um
cenário; deixe `null` quando ele não nomeou nenhum número. Grave também `ticker`: o símbolo exato
como está em `holdings.json` (ex.: `"PETR4"`) quando a pergunta amarrou uma posição concreta, ou
`null` quando a pergunta foi sobre a carteira como um todo ou sobre um objetivo — nunca invente um
ticker pra preencher o campo.

## Passo 3 — Alocação-alvo (`alocacao-alvo.json`)

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

## Passo 4 — Watchlist de fundos (`watchlist-fundos.json`, opcional)

Só pergunte se `holdings.json` tiver alguma posição com `classe` de fundo ou se o domínio
`dados-mercado` estiver habilitado para o mercado `br`. Peça o(s) CNPJ(s) (14 dígitos) dos fundos
de interesse.

Grave em `watchlist-fundos.json`:

```json
{"cnpjs": ["00.000.000/0001-00"]}
```

Pule este passo (não crie o arquivo) se não houver fundo nenhum.

## Passo 5 — Histórico real, se o investidor já tiver (opcional)

Se em qualquer momento da entrevista o investidor mencionar ou colar dados reais de extrato da
corretora (patrimônio em uma data, rentabilidade acumulada, valor inicial vs. atual) — **não
descarte isso**. Não é "dado de memória" não-confiável: é extrato real, mais preciso que os
snapshots automáticos que a série ainda não teve tempo de acumular. Ofereça registrar os pontos
que o investidor tiver como histórico real:

```bash
bin/nav-snapshot.sh <slug> --valor <valor-inicial> --data <data-inicio>
bin/nav-snapshot.sh <slug> --valor <valor-atual> --data <data-de-hoje>
```

Isso não é backfill por estimativa/chute — é o investidor informando um dado que ele já tem em
mãos. Quanto mais pontos reais ele tiver (extratos mensais, por exemplo), melhor a base pra
`bin/contra-benchmark.sh`/`bin/retorno.sh`/`bin/eficiencia.sh` mais adiante. Se ele só tiver
"lembro mais ou menos que valia X há alguns meses" (sem extrato, por memória), aí sim não registre
— avise que a série vai começar a acumular a partir de agora.

## Ao final

Resuma o que foi gravado (diagnóstico, posições, implicação registrada se houver, alocação-alvo,
watchlist se houver) e sugira o próximo comando: `bin/alocacao.sh <slug>` para ver a alocação
atual, ou `/status` pra um briefing rápido.
