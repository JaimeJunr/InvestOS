[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Integração com Corretora/Banco

**Prioridade:** P2 — a mais sensível das 5 áreas, por lidar com credenciais de conta real.

## Read-only, sempre

Quando o domínio `corretora-banco` é habilitado, o setup escreve um MCP server do Plaid em
`.mcp.json` marcado `"readOnly": true`, e placeholders `PLAID_CLIENT_ID=` / `PLAID_SECRET=` no
`.env` do portfólio. Segue o mesmo
[mecanismo declarativo](../decisao-mecanismo-mcp-e-enum-mercado.md) do resto do sistema — nenhum
client HTTP first-party, nenhuma chamada de API dentro do InvestOS.

## Credenciais isoladas (`bin/credencial.sh`)

O único código autorizado a checar se uma credencial existe. Lê apenas do `.env` do próprio
portfólio — nunca do ambiente do processo, nunca dá `source` no arquivo, e **nunca imprime o
valor**. Toda outra parte do sistema que precisa saber "a corretora está conectada?" passa por
aqui em vez de ler o `.env` diretamente.

```bash
bin/credencial.sh minha-carteira has PLAID_CLIENT_ID   # exit 0 se presente, 1 se ausente
```

## Sincronização com fallback seguro (`bin/holdings-sync.sh`)

Quando há credencial, tenta atualizar `holdings.json` via o override injetável `HOLDINGS_FETCH`
(o MCP Plaid é config declarativa; este script não chama API real). Se a conexão falhar ou o token
tiver expirado, **o portfólio não é zerado**: o último `holdings.json` conhecido é mantido, com um
aviso da idade do dado (rastreada em `_cache/plaid/meta.json`).

## Desconectar sem quebrar nada

Remover a credencial do `.env` volta o portfólio a usar `holdings.json` manual — as demais áreas
(alocação, risco, rebalanceamento) continuam funcionando normalmente, sem depender da integração
de corretora estar ativa.
