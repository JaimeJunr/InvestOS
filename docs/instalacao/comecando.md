# Começando

## Requisitos

- Bash
- [`jq`](https://jqlang.github.io/jq/)
- Python 3
- [Claude Code](https://claude.com/claude-code), para de fato usar os MCPs/skills gerados
- [Bats](https://github.com/bats-core/bats-core), só se for rodar os testes

Nada disso precisa de instalação/build própria do InvestOS — é um conjunto de scripts, clone e
use.

## Criando o primeiro portfólio

```bash
git clone https://github.com/JaimeJunr/InvestOS.git
cd InvestOS
bin/setup.sh minha-carteira
```

O portfólio **não** é criado dentro da pasta do InvestOS — mesmo padrão do
[BizOS](https://github.com/JaimeJunr/BizOS). Um nome puro (sem `/`) vira
`~/Documents/investos-minha-carteira` (override via
`INVESTOS_PORTFOLIOS_DIR=/outro/lugar bin/setup.sh minha-carteira`). Se preferir escolher o
caminho exato, passe um caminho em vez de um nome — qualquer argumento que comece com `.`, `~` ou
contenha `/` é respeitado literalmente:

```bash
bin/setup.sh ~/carteiras/pessoal       # cria em ~/carteiras/pessoal
bin/setup.sh ./aqui-mesmo              # cria ./aqui-mesmo, relativo ao cwd atual
```

O setup pergunta, um por um:

1. Habilitar cada domínio (`research`, `risco`, `dados-mercado`, `corretora-banco`) — `y`/`N`.
2. Mercado: `br`, `us` ou `ambos` (case-insensitive, sem outra variação aceita).

Ao final, o portfólio existe com a estrutura descrita em
[`arquitetura/visao-geral.md`](../arquitetura/visao-geral.md), e o comando imprime o `cd` exato pra
abrir o Claude Code lá dentro.

## Sendo guiado (`/instalar` e `/status`)

O `setup.sh` só cria o esqueleto — `holdings.json` e `alocacao-alvo.json` ainda não existem, e os
scripts de relatório exigem os dois. Em vez de escrever esses arquivos à mão, abra o Claude Code
dentro do portfólio recém-criado e rode a entrevista guiada:

```bash
cd minha-carteira
claude
```

Dentro da sessão:

- **`/instalar`** — entrevista guiada que começa por um diagnóstico rápido (perfil de risco,
  objetivos e prazo, reserva de emergência, custos/impostos, alinhamento de expectativa — o mesmo
  processo que um profissional de finanças segue antes de montar uma carteira), depois pergunta
  suas posições atuais, sua alocação-alvo (com uma sugestão de partida baseada no seu perfil de
  risco) e, se fizer sentido, os fundos de interesse — e grava os 4 arquivos por você.
- **`/status`** — depois de instalado, um briefing rápido e somente leitura (alocação atual,
  risco, sugestão de rebalanceamento se houver desvio). Roda `/instalar` primeiro se ainda não
  tiver dados.

## Preenchendo credenciais (opcional)

Se você habilitou `dados-mercado` com mercado diferente de `br`, ou `corretora-banco`, o
`.env` do portfólio terá placeholders vazios:

```
ALPHA_VANTAGE_API_KEY=
BRAPI_TOKEN=
PLAID_CLIENT_ID=
PLAID_SECRET=
```

Preencha só o que for usar. `BRAPI_TOKEN` é opcional para os 4 tickers gratuitos (`PETR4`,
`VALE3`, `MGLU3`, `ITUB4`); os demais tickers BR exigem um token gratuito em
[brapi.dev](https://brapi.dev).

## Primeiros comandos

```bash
# Cotação de uma ação BR (sem token, tickers gratuitos)
bin/brapi-quote.sh minha-carteira PETR4

# Relatório de risco (exige holdings.json preenchido)
bin/risco.sh minha-carteira

# Relatório de alocação vs. alvo (exige holdings.json + alocacao-alvo.json)
bin/alocacao.sh minha-carteira

# Sugestão de rebalanceamento
bin/rebalanceamento.sh minha-carteira
```

`holdings.json` e `alocacao-alvo.json` normalmente já existem nesse ponto, gravados pelo
`/instalar` (ver acima). Os formatos exatos estão documentados em
[`produto/features/gestao-de-portfolio-e-risco.md`](../produto/features/gestao-de-portfolio-e-risco.md)
caso prefira editar à mão. A integração de corretora, quando conectada, substitui a necessidade de
manter `holdings.json` manualmente.

## Acumulando histórico (opcional)

Métricas como Beta, TWR e Sortino precisam de uma série de dados que só existe se você alimentar
com o tempo — não há atalho nem backfill retroativo:

```bash
bin/nav-snapshot.sh minha-carteira              # roda periodicamente (ex.: sempre que checar /status)
bin/transacao.sh minha-carteira registrar aporte 1000
```

Detalhes de cada métrica e o que fazer enquanto o histórico ainda é curto em
[`produto/features/historico-metricas.md`](../produto/features/historico-metricas.md).
