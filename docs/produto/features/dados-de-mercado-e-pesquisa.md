[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Dados de Mercado e Pesquisa

**Prioridade:** P1.

## Mercado BR — implementação própria

Como nenhum plugin de terceiro cobre dados de mercado brasileiro (ver o
[gap registrado no catálogo](catalogo-de-plugins.md#o-gap-de-dados-br)), esta feature resolve isso
diretamente, sobre duas fontes públicas e gratuitas — validadas por um spike técnico antes de
qualquer linha de código (ver
[`.ralph/investos/spikes/dados-mercado-br.md`](../../../.ralph/investos/spikes/dados-mercado-br.md)
para a investigação completa, incluindo por que a API oficial da B3 e a ANBIMA Feed API foram
descartadas):

- **Ações, ETFs e FIIs:** [`bin/brapi-quote.sh`](../../../bin/brapi-quote.sh), via
  [brapi.dev](https://brapi.dev) (free tier, 15.000 requisições/mês). `PETR4`, `VALE3`, `MGLU3` e
  `ITUB4` funcionam sem token; qualquer outro ticker exige `BRAPI_TOKEN` no `.env` do portfólio
  (cadastro gratuito).
- **Fundos:** [`bin/cvm-informe.sh`](../../../bin/cvm-informe.sh), via o Informe Diário de Fundos
  da [CVM Dados Abertos](https://dados.cvm.gov.br) (CSV/ZIP público, atualização diária, sem
  login). O ticker de um fundo é o CNPJ de 14 dígitos.

## Mercado US/global — MCP declarativo

Segue o [mecanismo declarativo](../decisao-mecanismo-mcp-e-enum-mercado.md) estabelecido para toda
integração externa: quando o domínio `dados-mercado` está habilitado com mercado `us` ou `ambos`,
o setup escreve um MCP server do Alpha Vantage em `.mcp.json` e um placeholder `ALPHA_VANTAGE_API_KEY=`
no `.env`. Não há client HTTP first-party para esse mercado — quem de fato consulta a API é o
Claude Code, através do MCP, quando a credencial real é preenchida.

## Research

Duas skills (`templates/skills/research-br`, `templates/skills/research-us`) são copiadas para
`.claude/skills/` do portfólio conforme domínio `research` + mercado escolhidos. Cada uma instrui
o agente a montar um relatório de fundamentals **a partir dos dados já disponíveis** (via os
scripts acima) — nunca inventar número, nunca calcular no chute quando um campo não vier na
resposta.
