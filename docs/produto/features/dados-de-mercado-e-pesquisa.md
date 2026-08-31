[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Dados de Mercado e Pesquisa

**Prioridade:** P1.

## Mercado BR — implementação própria

Como nenhum plugin de terceiro cobre dados de mercado brasileiro (ver o
[gap registrado no catálogo](catalogo-de-plugins.md#o-gap-de-dados-br)), esta feature resolve isso
diretamente, sobre duas fontes públicas e gratuitas — validadas por um spike técnico antes de
qualquer linha de código (a API oficial da B3 é B2B-only, e a ANBIMA Feed API é paga; ambas foram
descartadas em favor das duas fontes abaixo):

- **Ações, ETFs e FIIs:** [`bin/brapi-quote.sh`](../../../bin/brapi-quote.sh), via a
  [API v2 da brapi.dev](https://brapi.dev) (free tier, 15.000 requisições/mês; endpoints
  separados de cotação/histórico/estatísticas, token via header `Authorization: Bearer`, nunca na
  URL). `PETR4`, `VALE3`, `MGLU3` e `ITUB4` funcionam sem token; qualquer outro ticker exige
  `BRAPI_TOKEN` no `.env` do portfólio (cadastro gratuito).
- **Fundos:** [`bin/cvm-informe.sh`](../../../bin/cvm-informe.sh), via o Informe Diário de Fundos
  da [CVM Dados Abertos](https://dados.cvm.gov.br) (CSV/ZIP público, atualização diária, sem
  login). O ticker de um fundo é o CNPJ de 14 dígitos.

## Mercado US/global — MCP declarativo

Segue o [mecanismo declarativo](../decisao-mecanismo-mcp-e-enum-mercado.md) estabelecido para toda
integração externa: quando o domínio `dados-mercado` está habilitado com mercado `us` ou `ambos`,
o setup escreve um MCP server do Alpha Vantage em `.mcp.json` e um placeholder `ALPHA_VANTAGE_API_KEY=`
no `.env`. Não há client HTTP first-party para esse mercado — quem de fato consulta a API é o
Claude Code, através do MCP, quando a credencial real é preenchida.

## Limites e planos pagos da brapi.dev

O InvestOS só integra o **plano gratuito** (15.000 requisições/mês, histórico de até 3 meses) —
suficiente pra uso pessoal com poucas dezenas de tickers. Se sua carteira tiver muitas posições e
você consultar com frequência (ex.: `bin/nav-snapshot.sh` diário + relatórios), pode valer a pena
considerar um plano pago. Preços capturados em 2026-08-30 direto no checkout da brapi — **confira
o valor atual em [brapi.dev](https://brapi.dev) antes de decidir**, preço de assinatura muda:

| Plano | Preço (anual, com desconto) | Cobertura extra vs. gratuito |
|-------|------------------------------|-------------------------------|
| Gratuito (atual) | R$0 | 15.000 req/mês, ~3 meses de histórico |
| Startup | R$99,99/mês (R$1.199,90/ano, 20% off) | 150.000 req/ciclo, 1 ano de histórico, dividendos/fundamentos anuais, macro BCB e câmbio PTAX |
| Pro | R$116,66/mês (R$1.399,90/ano, 30% off) | 500.000 req/ciclo, fundamentos trimestrais e 16+ anos de histórico, FIIs/Tesouro Direto/opções/futuros, macro completo |

Nenhum desses planos muda o código do InvestOS — o `BRAPI_TOKEN` no `.env` do portfólio é o mesmo
campo independente do plano; só a quota e a profundidade de histórico disponível mudam do lado da
brapi.

## Research

Duas skills (`templates/skills/research-br`, `templates/skills/research-us`) são copiadas para
`.claude/skills/` do portfólio conforme domínio `research` + mercado escolhidos. Cada uma instrui
o agente a montar um relatório de fundamentals **a partir dos dados já disponíveis** (via os
scripts acima) — nunca inventar número, nunca calcular no chute quando um campo não vier na
resposta.
