# Spike — Viabilidade de dados de mercado brasileiro (B3/ANBIMA) sem plugin/MCP pronto

## Hipóteses

- **H1:** B3 tem alguma API pública gratuita de cotação (ações/ETFs). → validar via docs oficiais B3 developers.
- **H2:** ANBIMA disponibiliza dados públicos de fundos (PL, cota) sem contrato com administrador. → validar via portal ANBIMA Data / ANBIMA Feed / alternativas de dados abertos (CVM).
- **H3:** Um provedor agregado gratuito (brapi.dev, yfinance com `.SA`) cobre cotação de ações B3 mesmo sem cobrir fundos/ANBIMA. → validar via docs de coverage/rate limit.

## Plano de execução

1. Pesquisar documentação pública da B3 para API de cotação.
2. Pesquisar dados abertos da ANBIMA/CVM para fundos.
3. Validar coverage e rate limit de brapi.dev e yfinance (`.SA`) como fallback de ações.

## Critério de conclusão

Pelo menos 1 fonte viável (sem custo, sem contrato) identificada e documentada para (a) cotação de ações/ETFs BR e (b) dados de fundos BR (PL, cota) — ou veredito explícito de inviabilidade se nenhuma existir.

## Evidências (preenchido em 2026-08-29)

**H1 — refutada como via primária.** B3 não tem API pública self-service de cotação. APIs de developer são B2B (requer relacionamento comercial); cotação real-time ou D-1 exige acordo/distribuidor autorizado. Existe um "Public Data Hub" com datasets públicos (histórico de cotação, EOD), mas não é uma API JSON de uso geral. [developers.b3.com.br/faq] [b3.com.br/en_us/data/public-data-hub]

**H2 — parcialmente confirmada, mas não pela ANBIMA diretamente.** ANBIMA Data (`data.anbima.com.br`) é gratuito mas sem API pública documentada — é plataforma de consulta manual. ANBIMA Feed API (`api.anbima.com.br/feed/v1/fundos/{codigo}/serie-historica`, retorna PL/cota/captação/resgate/cotistas) existe mas requer contrato pago (client_id + OAuth). **A alternativa genuinamente aberta é a CVM**: `dados.cvm.gov.br` publica o Informe Diário de Fundos (CSV/ZIP, sem login, com PL/cota/aplicação/resgate/cotistas) — cobre o mesmo dado que a ANBIMA Feed cobra, de graça.

**H3 — confirmada para ações/ETFs/FIIs.** brapi.dev cobre ações B3, FIIs, BDRs, ETFs, índices, histórico, dividendos — free tier 15.000 requests/mês, delay ~30min, só 4 tickers (PETR4/VALE3/MGLU3/ITUB4) sem token, demais exigem cadastro gratuito. Não é distribuidor licenciado B3 — sem SLA formal, mas adequado para uso pessoal/pesquisa. yfinance com sufixo `.SA` (ex.: `PETR4.SA`) funciona como fallback para histórico diário, mas é cliente não-oficial, sem quota garantida (rate limit errático).

## Conclusão / decisão

**Viável, com fontes concretas — sem precisar de contrato comercial:**

- **Ações/ETFs/FIIs BR:** `brapi.dev` (API principal, free tier) + `yfinance` `.SA` como fallback/histórico secundário.
- **Fundos BR (PL, cota, captação/resgate):** CVM Dados Abertos (`dados.cvm.gov.br`, CSV/ZIP diário) — não a ANBIMA Feed (paga).
- **B3 oficial:** fora de escopo do v1 — exige onboarding comercial incompatível com uso pessoal.

Isso desbloqueia a feature "Dados de Mercado e Pesquisa": a cobertura BR entra no v1 via implementação própria (parser de CSV da CVM + client de brapi.dev), não via plugin/MCP de terceiro pronto — porque nenhum existe hoje.
