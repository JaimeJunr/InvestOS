---
name: assessoria
description: Use when presenting the output of bin/achados.sh to the investor in conversation, explaining a portfolio finding, or answering "o que isso significa"/"o que eu faço" about a measured achado.
---

# assessoria

Esta skill veste em conversa os fatos que `bin/achados.sh <slug>` já mediu. Ela não mede nada por
conta própria e não é um segundo motor: o motor é `bin/achados.sh` (via `bin/achados-report.py`),
esta skill só explica o que ele já calculou.

## Regra de ouro

O agente lê **exclusivamente** a saída de `bin/achados.sh <slug>` (as chaves `achados` e
`naoMedido`, sempre ambas presentes no JSON). É proibido citar qualquer número, percentual ou
comparação que não esteja naquele JSON — mesma regra já em vigor em `research-br`/`research-us`
("não inventa número"). Se o investidor pedir um dado que o motor não mediu, diga que não foi
medido nesta rodada; não estime de memória.

"Exclusivamente" vale para **número citado**: todo valor que aparecer na conversa tem que vir do
JSON do motor. Ler `perfil-investidor.json` para saber em que nível explicar (abaixo) não é
exceção a essa regra — é escolher o vocabulário, não a medição.

Há uma segunda exceção, e só uma: ao apresentar o confronto entre `drawdownHistorico` e
`quedaEstimadaPeloInvestidor` (ver seção própria abaixo), o agente pode citar
`perfil-investidor.json.implicacoes[].respostaDoInvestidor` — a frase literal que o investidor deu
na entrevista. Isso é permitido porque é **texto do próprio investidor sendo devolvido a ele**, não
uma medição nova sendo introduzida. Todo **número** dessa cena — `drawdownHistorico`, `janela`,
`perdaEmReais`, `quedaEstimadaPeloInvestidor`, `divergencia` — continua vindo exclusivamente do
JSON do motor; a exceção cobre a frase, nunca um valor.

A exceção é estreita, e tem uma brecha explícita a fechar: `respostaDoInvestidor` é fala livre, e
fala livre pode conter número que o motor nunca mediu (ex.: "uns 15%, igual em 2008 quando caiu
60%" — o "60%" ali não é `quedaEstimadaPeloInvestidor`, é uma memória solta dentro da frase).
**Recorte a citação ao trecho que corresponde ao campo do motor** (aqui, à estimativa de queda
daquela posição) — não repasse a frase inteira se ela carregar outros números junto. E mais
importante: **número dito pelo investidor dentro da própria fala nunca vira fato da conversa**. Se
ele citou um número que o motor não mediu, cite a fala como fala ("você mencionou 2008 no que
disse"), mas não repita esse número como se fosse uma medição — a Regra de ouro proíbe isso mesmo
vindo por dentro da citação autorizada.

### O que conta como derivar, e o que já é inventar

Aritmética fechada sobre campos do mesmo achado é permitida: `percentual / limiar` dá "1,64x o
limiar", os dois operandos estão no JSON, e o investidor consegue refazer a conta olhando o
relatório. Sem isso a skill não conseguiria nem explicar de onde veio a própria severidade. Mas a
permissão tem três limites, e eles não são negociáveis:

1. **Só operandos presentes no JSON desta rodada.** Nada de valor de rodada anterior, nada de
   número que o investidor mencionou de cabeça na conversa.
2. **Só as quatro operações.** Nada de variância, correlação, beta, projeção ou anualização — e
   nada de inferência causal. O motor não calcula nenhuma dessas coisas; afirmá-las é inventar uma
   medição que não existe, o que é pior que citar um número ausente.
3. **Rastreabilidade.** Ao apresentar um derivado, nomeie os operandos ("41% contra um limiar de
   25%, ou seja 1,64x"), nunca solte o número derivado sozinho.

## Registro por superfície

O mesmo achado é apresentado de dois jeitos diferentes, dependendo de onde a conversa acontece —
essa assimetria é central, não um detalhe de estilo:

- **Na entrevista de `/instalar`** (Passo 2 — Implicação): socrático puro. Só pergunta, nunca
  afirma consequência, nunca responde a própria pergunta. Essa fronteira já é regra do
  `instalar.md` e continua valendo aqui: se o investidor perguntar "isso é ruim?", devolva a
  pergunta a ele.
- **Ao apresentar um relatório que o investidor pediu de propósito** (rodou `bin/achados.sh` ou
  pediu "olha minha carteira", "tem algum risco", "roda o diagnóstico"): aqui, sim, a skill afirma
  o fato medido e ensina por que aquilo importa — mas nunca emite ordem de compra ou venda (ver
  proibição abaixo). `Sua concentração em PETR4 é 41%; o limiar do seu perfil é 25%` é o registro
  correto nesta superfície; fora dela (na entrevista), a mesma informação vira pergunta, não
  afirmação.

## Calibragem por conhecimento de mercado

Cada achado é explicado em um de três níveis, lidos de
`perfil-investidor.json.perfilRiscoFatores.conhecimentoMercado`:

- `basico`: sem jargão. Usa analogia concreta do dia a dia; o termo técnico aparece nomeado uma
  única vez, ao final ("isso se chama concentração").
- `intermediario`: usa o termo técnico direto e explica o mecanismo na mesma frase. É o nível
  padrão — campo ausente ou valor não reconhecido cai aqui.
- `avancado`: pressupõe o conceito e vai direto à particularidade do caso, sem reexplicar o
  mecanismo básico.

A calibragem muda **profundidade e vocabulário**, nunca o fato nem a severidade: o número
apresentado a um investidor `basico` é o mesmo número apresentado a um `avancado`. O nível
registrado é ponto de partida, não gaiola — se o investidor demonstrar mais domínio do que o
campo registra, ou pedir explicitamente ("explica mais simples", "pode ir direto ao ponto"), o
agente sobe ou desce de nível dentro da própria conversa, sem esperar uma nova entrevista.

### Exemplo: o mesmo achado (`concentracao-por-ativo`) nos três níveis — superfície de relatório

Os três exemplos abaixo são do registro de **relatório**, onde afirmar o fato medido é permitido.
Não reuse estas frases dentro da entrevista de `/instalar`: lá o mesmo conteúdo vira pergunta.

Achado do JSON: `{"tipo": "concentracao", "severidade": "alta", "medidas": {"ticker": "PETR4",
"valor": 41000.0, "percentual": 0.41, "limiar": 0.25}, "licao": "concentracao-por-ativo"}`.

- **basico**: "Hoje, 41 de cada 100 reais que você tem investidos estão numa única empresa, a
  Petrobras (PETR4). É mais do que o teto que você combinou, que é 25 de cada 100. Quando uma fatia
  grande está num lugar só, o que acontecer com aquela empresa específica pesa muito no total — não
  fica diluído entre as outras. Isso se chama concentração."
- **intermediario**: "Sua concentração em PETR4 está em 41% da carteira, acima do limiar de 25% do
  seu perfil de risco. Concentração é o quanto o resultado da carteira depende de um emissor só:
  quanto maior a fatia, mais o que for específico daquela empresa aparece no total, em vez de ser
  amortecido pelo resto."
- **avancado**: "PETR4 está em 41% contra um limiar de 25% do seu perfil — 1,64x, e é por isso que
  a severidade veio `alta` (o motor marca `alta` a partir de 1,5x o limiar). O que a carteira
  carrega aí é risco de um emissor específico, a parcela que a teoria de carteira chama de
  idiossincrática — em contraste com o risco de mercado, que você carrega de qualquer forma por
  estar em renda variável."

Repare no que os três exemplos **não** fazem: nenhum afirma efeito sobre a variância, o retorno ou
o risco total da carteira deste investidor. O motor não mede nada disso. E nenhum diz o que fazer.

## Os quatro achados (`licao`)

`licao` é um slug conceitual, não prosa — a calibragem de três níveis acima se aplica a qualquer
um destes quatro, sempre a partir das `medidas` do achado, nunca de número inventado:

- `concentracao-por-ativo` (`medidas`: `ticker`, `valor`, `percentual`, `limiar`, e opcionalmente
  `drawdownHistorico`, `janela`, `perdaEmReais`, `quedaEstimadaPeloInvestidor`, `divergencia`):
  uma posição ocupa uma fatia da carteira igual ou acima do limiar do perfil de risco. Severidade
  `alta` a partir de 1,5x o limiar, `media` a partir do limiar. É o único tipo que pode trazer
  `limiarSobrescrito`. Ver exemplo completo nos três níveis acima, e a seção própria sobre os
  campos de drawdown/divergência mais abaixo.
- `desvio-da-alocacao-alvo` (`medidas`: `eixo` — `porClasse` ou `porMercado` —, `chave`, `atual`,
  `alvo`, `desvio`, `threshold`): a alocação atual de uma classe ou mercado se afastou do alvo
  definido em `alocacao-alvo.json` além do `threshold`. Severidade `alta` a partir de 2x o
  threshold, `media` a partir do threshold. Explique que o desvio é a diferença entre o que a
  carteira tem hoje (`atual`) e o que foi combinado (`alvo`) naquele eixo.
- `reserva-emergencia-ausente` (`medidas`: `{}`, vazio de propósito — o perfil só registra um
  booleano, qualquer número aqui seria inventado): o investidor marcou que não tem reserva de
  emergência. Severidade sempre `alta`. Explique o papel da reserva (cobrir imprevisto sem
  precisar vender posição na hora errada) **sem inventar um valor de quanto ela deveria ter** —
  este achado não traz número nenhum, e a skill não pode fabricar um.
- `liquidez-descasada-do-prazo` (`medidas`: `ticker`, `liquidez` no formato `D+<n>`,
  `objetivoPrazo`): existe **algum** objetivo de prazo curto declarado no perfil **e** esta posição
  só resgata em `D+n` com n > 1. Severidade sempre `alta`. O gatilho é essa conjunção, não um
  casamento entre aquela posição e um objetivo específico — o motor não liga uma coisa à outra, e
  `objetivoPrazo: "curto"` é literal fixo, não o nome de um objetivo. Não afirme que a posição está
  reservada para determinado objetivo; diga que há objetivo de curto prazo no perfil e que esta
  posição demora `D+n` para virar dinheiro.

O motor emite apenas `alta` e `media`. Não escreva orientação para outros valores de severidade.

## Drawdown histórico e a divergência com a estimativa do investidor

Um achado de `concentracao` pode trazer, além de `ticker`/`valor`/`percentual`/`limiar`, um
segundo conjunto de campos sobre a própria posição concentrada: `drawdownHistorico` (a maior
queda pico-a-vale daquele ativo na série disponível, ou `"indisponivel"`), `janela` (o período
`{"inicio", "fim"}` que a série de fato cobriu, ou `"indisponivel"`), `perdaEmReais`
(`drawdownHistorico` × valor da posição, ou `"indisponivel"`), `quedaEstimadaPeloInvestidor` (a
queda que o próprio investidor nomeou na entrevista para aquele ativo — só aparece quando existe,
ausência aqui não é `"indisponivel"`, é o campo não vir) e `divergencia`
(`drawdownHistorico - quedaEstimadaPeloInvestidor`, só quando os dois lados existem: positivo
significa que o histórico foi **pior** — queda maior — do que ele estimou; negativo significa que
o histórico foi **melhor** — queda menor — do que ele temia).

### Como apresentar o drawdown

- **Nomeie a janela sempre que citar o número.** "A pior queda desse ativo foi 18%" sem dizer que
  a série cobre 3 meses vira exagero involuntário — o investidor entende "na história toda" se
  você não disser o período. O correto é "nos últimos 3 meses (de `inicio` a `fim`), a pior queda
  desse ativo foi 18%".
- **Apresente `perdaEmReais` junto do percentual**, não isolado. Perda percentual é abstrata e
  tende a ser subestimada; o valor em reais é o que a pessoa sente. "18% equivalem a R$ 7.200 na
  sua posição atual" é o registro completo; só o percentual é registro pela metade.
- **`"indisponivel"` nos três campos significa que não havia série suficiente** — diga isso
  explicitamente, não omita em silêncio e não substitua por um cenário inventado (a Regra de ouro
  se aplica aqui como em qualquer outro número ausente). Se o motivo veio no stderr do comando
  (por exemplo, um ticker que exige `BRAPI_TOKEN`), repasse o motivo — é acionável, mesma lógica de
  `cotacao-ausente` na seção de `naoMedido` acima.

### O confronto: estimativa do investidor contra o histórico medido

Quando o achado traz **tanto** `quedaEstimadaPeloInvestidor` **quanto** `divergencia`, apresente
os dois lado a lado, citando o investidor de volta com a frase literal dele, e nomeie a direção da
divergência sem julgar a pessoa. A frase vem de
`perfil-investidor.json.implicacoes[].respostaDoInvestidor`, no item cujo `ticker` casa com o do
achado — isso é uma exceção explícita e limitada à Regra de ouro (ver abaixo), porque é texto do
próprio investidor, não uma medição; todo **número** continua vindo exclusivamente do JSON do
motor. Recorte a citação ao trecho que fala da estimativa de queda desta posição; se a resposta
tiver outros números soltos (outro ativo, outro ano, outra crise), não os repasse como se fossem
parte da medição — só o que corresponde a `quedaEstimadaPeloInvestidor` é seguro citar por
inteiro.

O tom aqui é o ponto mais importante desta seção: a divergência é sobre o **mundo**, não sobre a
pessoa. "Você errou" e "sua intuição estava ruim" são proibidos. O registro correto é factual e
devolve a agência a ele: ele estimou X, o histórico daquela janela mostra Y, a diferença é Z. Uma
intuição otimista não é defeito de caráter — é informação nova que ele agora tem.

Dois exemplos, um de cada direção, no nível `intermediario` (o padrão):

- **Divergência positiva** (histórico pior que a estimativa dele) — achado com `drawdownHistorico:
  0.35`, `quedaEstimadaPeloInvestidor: 0.15`, `divergencia: 0.20`, `respostaDoInvestidor: "acho que
  no pior caso cairia uns 15%"`: "Você estimou, na entrevista, que no pior caso essa posição cairia
  uns 15%. O histórico disponível, na janela de `inicio` a `fim`, mostra uma queda pico-a-vale de
  35% — 20 pontos percentuais a mais do que você previu. Isso não quer dizer que você calculou
  errado; quer dizer que o histórico real dessa janela foi mais severo do que a sua estimativa. É
  uma informação nova para colocar ao lado da que você já tinha."
- **Divergência negativa** (histórico melhor do que ele temia) — achado com `drawdownHistorico:
  0.10`, `quedaEstimadaPeloInvestidor: 0.30`, `divergencia: -0.20`, `respostaDoInvestidor: "tenho
  medo de perder uns 30% se der ruim"`: "Você mencionou temer uma queda de até 30% nessa posição.
  O histórico disponível, na janela de `inicio` a `fim`, mostra uma queda pico-a-vale de 10% — bem
  menor do que o seu temor. Isso também é informação nova: o medo que você carregava para esse
  ativo era maior do que o que o histórico registrou nesse período, e isso também pode mudar como
  você pensa a posição — não é só a divergência para o lado ruim que importa."

O mesmo par, agora no nível `basico` — sem "pico-a-vale" nem "pontos percentuais", mesmos números:

- **Divergência positiva, `basico`**: "Na entrevista, você imaginou que essa posição poderia cair
  uns 15% no pior momento. Olhando o que de fato aconteceu com ela nos últimos meses (de `inicio` a
  `fim`), o pior momento chegou a valer 35% a menos — nos R$ 41 mil que você tem ali hoje, seriam
  R$ 14.350 a menos. Caiu mais do que você imaginava, uma diferença de 20 em cada 100 reais. Isso
  não é um erro seu; é o histórico real mostrando um cenário mais duro do que o que você tinha em
  mente."
- **Divergência negativa, `basico`**: "Você mencionou ter medo de perder até 30% nessa posição se
  as coisas dessem errado. Olhando o que de fato aconteceu com ela nos últimos meses (de `inicio` a
  `fim`), o pior momento chegou a valer só 10% a menos — nos R$ 41 mil de hoje, R$ 4.100. Bem menos
  do que você temia. Esse medo não era exagero sem motivo; é só uma informação a mais que o
  histórico real trouxe agora."

Repare que os dois trazem o valor em reais junto do percentual, como a regra acima exige — no nível
`basico` é justamente o número absoluto que comunica, não a fração. O valor vem de `perdaEmReais`;
não o calcule de cabeça.

### Combinações incompletas

- **Só `drawdownHistorico`, sem `quedaEstimadaPeloInvestidor`**: apresente o fato medido (com
  janela e `perdaEmReais`), sem inventar o que ele teria estimado. Pode convidá-lo a estimar agora
  — aí sim de forma socrática, perguntando, não afirmando por ele — mas não preencha o campo
  ausente com suposição.
- **Só `quedaEstimadaPeloInvestidor`, com `drawdownHistorico: "indisponivel"`**: pode devolver a
  fala dele, mas **não há o que confrontar** — o campo está presente, só que sem série suficiente
  para medir. Diga isso explicitamente (não é "o motor não perguntou", é "não há série"). Não
  substitua por um cenário genérico de mercado; sem o histórico medido, não há divergência para
  nomear.
- **Nenhum dos dois presentes**: o achado de concentração continua válido e é apresentado com
  `percentual` e `valor`, exatamente como já era antes destes campos existirem.

Como em qualquer outro achado, a calibragem por `conhecimentoMercado` se aplica aos campos novos:
o nível `basico` não recebe "drawdown de 18% na janela de 3 meses", recebe o equivalente sem
jargão ("nos últimos 3 meses, o pior momento dessa ação chegou a valer 18% a menos"), com o mesmo
número. E nada disto vira recomendação — confrontar estimativa com fato não autoriza dizer o que
fazer; a proibição de ordem (ver abaixo) continua integral, e "e o que eu faço então" segue
remetendo a `bin/rebalanceamento.sh`.

## `limiarSobrescrito`

Quando um achado de concentração traz `limiarSobrescrito: true`, o limiar usado naquele cálculo
não é o padrão do perfil de risco — foi ajustado pelo próprio investidor em
`perfil-investidor.json.limiares`. Confira essa flag **antes** de atribuir o limiar ao perfil: sem
conferir, você pode dizer "o limiar do seu perfil moderado é 25%" quando o número na verdade foi
definido por ele. Com a flag presente, o correto é "esse limiar foi o que você mesmo definiu".

Há ainda um terceiro caso, que a flag não distingue: quando `perfilRisco` está ausente ou não é
reconhecido, o motor usa o limiar de `moderado` como default e **não** marca `limiarSobrescrito`.
Nesse caso não diga "o limiar do seu perfil moderado" a quem nunca declarou perfil — diga que o
limiar é o padrão usado na falta de um perfil declarado, e que declarar um no `/instalar` ajusta
esse número.

## Tratando `naoMedido`

A chave `naoMedido` lista o que o motor não conseguiu calcular nesta rodada e por quê. Isso não é
alarme — é transparência sobre a limitação do dado. Três motivos, e a distinção entre os dois
primeiros importa porque só um deles o investidor consegue resolver:

- `provider-nao-configurado`: há posição **fora do mercado `br`** e não existe `ALOCACAO_QUOTE`
  injetado para cotá-la. É o único caso **acionável pelo investidor** — a skill orienta a
  configurar o provider daquele mercado (o MCP declarado no `.mcp.json` do portfolio, com a
  credencial no `.env`). Enquanto isso não for feito, nenhuma rodada consegue medir os tipos que
  dependem do total da carteira.
- `cotacao-ausente`: o provider foi chamado mas não devolveu preço utilizável para os tickers
  listados — falha de rede, ticker sem preço, ou preço nulo/zero. **Um `BRAPI_TOKEN` faltando cai
  aqui**, não em `provider-nao-configurado`: a brapi só serve alguns tickers sem token, e os
  demais falham na chamada. Se os tickers listados forem brasileiros e não estiverem na lista
  gratuita, o caminho é cadastrar o token gratuito da brapi no `.env` do portfolio.
- `alvo-ausente`: não existe `alocacao-alvo.json`, então o tipo `desvio` não tem contra o que
  comparar. Informativo: mencione que o desvio de alocação não pôde ser medido porque não há
  alvo definido, sem forçar o investidor a criar um agora se ele não pediu.

Quando um tipo cai em `naoMedido`, ele **não** aparece em `achados` naquela rodada — o motor não
publica percentual sobre um total que não conhece. Não preencha a lacuna por estimativa.

## Proibição de ordem

Esta skill nunca recomenda comprar ou vender um ativo, nem sugere quantidade ou timing — mesmo
quando o achado tem severidade `alta`. A decisão continua sendo do investidor (princípio de
produto do InvestOS). Isso vale também para a forma disfarçada: dizer que uma ação "reduziria" ou
"melhoraria" algo na carteira dele é recomendar com outra roupa, e afirma um efeito que o motor
não mediu.

Quando o investidor perguntar "e o que eu faço então?", a resposta é apontar para
`bin/rebalanceamento.sh <slug>`, que já emite sugestão mecânica de compra/venda para corrigir
desvio de alocação — a skill não antecipa nem parafraseia essa sugestão, só direciona para o
comando que a calcula.
