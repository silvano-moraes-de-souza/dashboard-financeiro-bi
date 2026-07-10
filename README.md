# Dashboard Financeiro BI

Sistema full-stack de gestão financeira e de vendas desenvolvido para uma indústria do setor de cosméticos e produtos de limpeza. Centraliza dados de duas empresas do grupo em um único painel, substituindo o fechamento manual em planilhas.

**Resultados em produção:** redução de ~60% no tempo de fechamento financeiro mensal e automação de ~80% dos relatórios recorrentes.

> Esta é a versão de demonstração/estudo do projeto. Dados, credenciais e identificadores da empresa foram removidos ou substituídos por valores fictícios.

## O problema

O fechamento financeiro consolidava manualmente vendas de duas empresas a partir do ERP, com retrabalho diário de exportação, tratamento e conferência em planilhas. Divergências entre relatórios eram comuns e a diretoria não tinha visão consolidada em tempo hábil.

## A solução

Pipeline ETL automatizado que coleta dados do ERP (API do Tiny ERP), trata e normaliza em SQLite local, sincroniza com PostgreSQL (Supabase) e serve dashboards interativos via API Flask.

```
ERP (API REST) → ETL Python → SQLite (staging) → Supabase/PostgreSQL → API Flask → SPA (JS)
```

## Stack

| Camada | Tecnologia |
|---|---|
| ETL | Python (requests, retry com backoff, deduplicação por período/empresa) |
| Banco local | SQLite (staging e operação offline) |
| Banco produção | PostgreSQL no Supabase, com RLS e funções RPC |
| API | Flask + CORS, headers de segurança, endpoints REST |
| Frontend | SPA em JavaScript puro (router próprio, autenticação, páginas de Financeiro, Vendas e Admin) |
| Segurança | Row Level Security, views com `security_invoker`, revogação de acesso `anon` |

## Destaques técnicos

- **ETL resiliente**: requisições com retry/timeout, normalização de datas e documentos (PF/PJ), verificação de idempotência antes de recarregar períodos.
- **Modelagem SQL**: views consolidadas multi-empresa com conversão de unidades (caixa/unidade), categorização de produtos e mapeamento de nomenclaturas.
- **Funções RPC no PostgreSQL**: agregações de vendas, ranking de clientes e filtros dinâmicos executados no banco, reduzindo tráfego para o frontend.
- **Hardening de segurança**: correção de views `SECURITY DEFINER` → `SECURITY INVOKER`, políticas RLS por tabela e revogação de privilégios do papel anônimo (ver `sql/security_emergency_fix.sql`).

## Como rodar

```bash
pip install -r requirements.txt
cp .env.example .env   # configure caminho do banco e credenciais
python scripts/db/init_sqlite_schema.py
python scripts/etl/coleta_tiny.py      # carga a partir do ERP
python api/server.py                   # sobe API + frontend em http://localhost:5000
```

## Estrutura

```
api/          API Flask (endpoints /api/dados, /api/status, /api/mapa ...)
frontend/     SPA (HTML/CSS/JS, autenticação e páginas)
scripts/etl/  Coletas do ERP e sincronização com Supabase
scripts/db/   Schema e manutenção do SQLite
sql/          Migrações, funções RPC e correções de segurança (Supabase)
```

## Autor

Silvano Moraes de Souza — Analista de Dados | Python, SQL, ETL, automação de processos
[LinkedIn](https://linkedin.com/in/silvano-moraes) · [Portfólio](https://silvanomsouza.vercel.app/)
