--============================================
-- security_emergency_fix.sql
-- CORRECAO COMPLETA DE SEGURANCA - Dashboard Financeiro BI
-- v3.0 - 2026-06-08
-- EXECUTAR NO SUPABASE SQL EDITOR
--============================================

-- =====================================================================
-- SECAO 1: CORRIGIR VIEW -> SECURITY INVOKER
-- ANTES: SECURITY DEFINER (bypassava RLS)
-- DEPOIS: SECURITY INVOKER (respeita permissoes do usuario)
-- =====================================================================
CREATE OR REPLACE VIEW public.view_vendas_geral
WITH (security_invoker = on)
AS
SELECT
    v.id, v.data_emissao, v.numero_nota, v.natureza_operacao,
    v.sku_ref, v.produto,
    v.nome_cliente AS cliente, v.tipo_pessoa,
    v.cidade, v.uf,
    v.quantidade, v.valor_unitario, v.frete, v.valor_total AS val_item,
    v.empresa,
    COALESCE(n.nomenclatura, 'NAO MAPEADA') AS nomenclatura,
    COALESCE(p.categoria, 'SEM CATEGORIA') AS categoria_produto,
    COALESCE(p.litros, 0) AS litros_produto,
    COALESCE(p.uni_cx, 0) AS uni_cx_produto,
    CASE
        WHEN v.empresa = 'FILIAL_B' AND TO_CHAR(v.data_emissao, 'YYYY-MM') = '2025-01'
            THEN v.quantidade / COALESCE(NULLIF(p.uni_cx, 0), 1)
        WHEN v.empresa = 'FILIAL_B' THEN v.quantidade
        WHEN v.empresa = 'FILIAL' THEN v.quantidade / COALESCE(NULLIF(p.uni_cx, 0), 1)
        ELSE v.quantidade
    END AS qtd_caixas,
    EXTRACT(YEAR FROM v.data_emissao)::INTEGER AS ano,
    EXTRACT(MONTH FROM v.data_emissao)::INTEGER AS mes,
    EXTRACT(DAY FROM v.data_emissao)::INTEGER AS dia,
    TO_CHAR(v.data_emissao, 'YYYY-MM') AS ano_mes
FROM vendas_filial_b v
LEFT JOIN natureza n ON TRIM(v.natureza_operacao) = TRIM(n.natureza_operacao)
LEFT JOIN produtos p ON TRIM(v.produto) = TRIM(p.produto)
WHERE COALESCE(n.nomenclatura, 'NAO MAPEADA') = 'VENDA'
  AND COALESCE(n.nomenclatura, 'NAO MAPEADA') != 'FILIAL'
  AND p.categoria IS NOT NULL AND p.categoria != ''

UNION ALL

SELECT
    v.id, v.data_emissao, v.numero_nota, v.natureza_operacao,
    v.sku_ref, v.produto,
    v.nome_cliente AS cliente, v.tipo_pessoa,
    v.cidade, v.uf,
    v.quantidade, v.valor_unitario, v.frete, v.valor_total AS val_item,
    v.empresa,
    COALESCE(n.nomenclatura, 'NAO MAPEADA') AS nomenclatura,
    COALESCE(p.categoria, 'SEM CATEGORIA') AS categoria_produto,
    COALESCE(p.litros, 0) AS litros_produto,
    COALESCE(p.uni_cx, 0) AS uni_cx_produto,
    CASE
        WHEN v.empresa = 'FILIAL_B' AND TO_CHAR(v.data_emissao, 'YYYY-MM') = '2025-01'
            THEN v.quantidade / COALESCE(NULLIF(p.uni_cx, 0), 1)
        WHEN v.empresa = 'FILIAL_B' THEN v.quantidade
        WHEN v.empresa = 'FILIAL' THEN v.quantidade / COALESCE(NULLIF(p.uni_cx, 0), 1)
        ELSE v.quantidade
    END AS qtd_caixas,
    EXTRACT(YEAR FROM v.data_emissao)::INTEGER AS ano,
    EXTRACT(MONTH FROM v.data_emissao)::INTEGER AS mes,
    EXTRACT(DAY FROM v.data_emissao)::INTEGER AS dia,
    TO_CHAR(v.data_emissao, 'YYYY-MM') AS ano_mes
FROM vendas_filial v
LEFT JOIN natureza n ON TRIM(v.natureza_operacao) = TRIM(n.natureza_operacao)
LEFT JOIN produtos p ON TRIM(v.produto) = TRIM(p.produto)
WHERE COALESCE(n.nomenclatura, 'NAO MAPEADA') = 'VENDA'
  AND COALESCE(n.nomenclatura, 'NAO MAPEADA') != 'FILIAL'
  AND p.categoria IS NOT NULL AND p.categoria != '';

-- =====================================================================
-- SECAO 2: REMOVER COLUNA CPF/CNPJ DAS TABELAS
-- Dados sensiveis nao devem ficar em tabelas expostas via API
-- =====================================================================
ALTER TABLE vendas_filial_b DROP COLUMN IF EXISTS cpf_cnpj;
ALTER TABLE vendas_filial DROP COLUMN IF EXISTS cpf_cnpj;
ALTER TABLE vendas_filial_b DROP COLUMN IF EXISTS endereco;
ALTER TABLE vendas_filial DROP COLUMN IF EXISTS endereco;
ALTER TABLE vendas_filial_b DROP COLUMN IF EXISTS cep;
ALTER TABLE vendas_filial DROP COLUMN IF EXISTS cep;
ALTER TABLE vendas_filial_b DROP COLUMN IF EXISTS numero;
ALTER TABLE vendas_filial DROP COLUMN IF EXISTS numero;

-- =====================================================================
-- SECAO 3: REFRESH FUNCTION -> SECURITY INVOKER
-- =====================================================================
CREATE OR REPLACE FUNCTION refresh_vendas_geral()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    DELETE FROM vendas_geral;
    INSERT INTO vendas_geral SELECT * FROM view_vendas_geral;
END;
$$;

-- =====================================================================
-- SECAO 4: CORRIGIR RLS EM TODAS AS TABELAS
-- ANTES: USING (true) -> QUALQUER autenticado le TUDO
-- DEPOIS: so usuarios na tabela usuarios podem ler
-- =====================================================================

-- Remover politicas antigas e perigosas
DROP POLICY IF EXISTS "Leitura vendas_geral" ON vendas_geral;
DROP POLICY IF EXISTS "Leitura vendas_filial_b" ON vendas_filial_b;
DROP POLICY IF EXISTS "Leitura vendas_filial" ON vendas_filial;
DROP POLICY IF EXISTS "Leitura natureza" ON natureza;
DROP POLICY IF EXISTS "Leitura produtos" ON produtos;
DROP POLICY IF EXISTS "Leitura proprios dados" ON usuarios;
DROP POLICY IF EXISTS "Admin gerencia usuarios" ON usuarios;

-- Garantir RLS ativo
ALTER TABLE IF EXISTS vendas_geral ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS vendas_filial_b ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS vendas_filial ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS natureza ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS usuarios ENABLE ROW LEVEL SECURITY;

-- NOVAS politicas restritivas
CREATE POLICY "RLS vendas_geral" ON vendas_geral
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "RLS vendas_filial_b" ON vendas_filial_b
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "RLS vendas_filial" ON vendas_filial
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "RLS natureza" ON natureza
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "RLS produtos" ON produtos
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "RLS usuarios leitura" ON usuarios
    FOR SELECT TO authenticated USING (
        id = auth.uid()
        OR EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin')
    );

CREATE POLICY "RLS usuarios admin" ON usuarios
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin'));

-- =====================================================================
-- SECAO 5: RPCs SEGURAS (SECURITY INVOKER + REMOVER DADOS SENSIVEIS)
-- ANTES: SECURITY DEFINER -> ignorava RLS
-- DEPOIS: SECURITY INVOKER -> respeita RLS
-- =====================================================================

-- get_dashboard_completo (dados agregados, sem dados sensiveis)
CREATE OR REPLACE FUNCTION get_dashboard_completo(
    data_inicio DATE DEFAULT (CURRENT_DATE - INTERVAL '12 months')::DATE,
    data_fim    DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    total_vendas BIGINT,
    total_receita REAL,
    ticket_medio REAL,
    top_produtos JSON,
    vendas_por_mes JSON,
    vendas_por_uf JSON
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT AS total_vendas,
        COALESCE(SUM(val_item), 0) AS total_receita,
        COALESCE(AVG(val_item), 0) AS ticket_medio,
        COALESCE((
            SELECT JSON_AGG(sub)
            FROM (
                SELECT produto, COUNT(*) AS qtd, SUM(val_item) AS receita
                FROM view_vendas_geral
                WHERE data_emissao BETWEEN data_inicio AND data_fim
                GROUP BY produto
                ORDER BY qtd DESC
                LIMIT 10
            ) sub
        ), '[]'::JSON) AS top_produtos,
        COALESCE((
            SELECT JSON_AGG(sub)
            FROM (
                SELECT ano_mes, COUNT(*) AS qtd, SUM(val_item) AS receita
                FROM view_vendas_geral
                WHERE data_emissao BETWEEN data_inicio AND data_fim
                GROUP BY ano_mes
                ORDER BY ano_mes
            ) sub
        ), '[]'::JSON) AS vendas_por_mes,
        COALESCE((
            SELECT JSON_AGG(sub)
            FROM (
                SELECT uf, COUNT(*) AS qtd, SUM(val_item) AS receita
                FROM view_vendas_geral
                WHERE data_emissao BETWEEN data_inicio AND data_fim
                GROUP BY uf
                ORDER BY qtd DESC
            ) sub
        ), '[]'::JSON) AS vendas_por_uf;
END;
$$;

-- get_vendas_uf (agregado, sem dados sensiveis)
CREATE OR REPLACE FUNCTION get_vendas_uf(
    data_inicio DATE DEFAULT (CURRENT_DATE - INTERVAL '12 months')::DATE,
    data_fim    DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(uf TEXT, total_vendas BIGINT, total_receita REAL)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.uf,
        COUNT(*)::BIGINT AS total_vendas,
        SUM(v.val_item) AS total_receita
    FROM view_vendas_geral v
    WHERE v.data_emissao BETWEEN data_inicio AND data_fim
      AND v.uf IS NOT NULL
    GROUP BY v.uf
    ORDER BY total_vendas DESC;
END;
$$;

-- get_vendas_volume (agregado, sem dados sensiveis)
CREATE OR REPLACE FUNCTION get_vendas_volume(
    data_inicio DATE DEFAULT (CURRENT_DATE - INTERVAL '12 months')::DATE,
    data_fim    DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    data DATE,
    total_vendas BIGINT,
    total_receita REAL
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.data_emissao AS data,
        COUNT(*)::BIGINT AS total_vendas,
        SUM(v.val_item) AS total_receita
    FROM view_vendas_geral v
    WHERE v.data_emissao BETWEEN data_inicio AND data_fim
    GROUP BY v.data_emissao
    ORDER BY v.data_emissao;
END;
$$;

-- =====================================================================
-- SECAO 6: TRIGGER PARA AUTO-INSERIR USUARIOS
-- Garante que todo signUp crie registro na tabela usuarios
-- =====================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    -- So insere na tabela usuarios se o email for do dominio corporativo
    IF NEW.email ILIKE '%@Dashboardgreen.eco.br' THEN
        INSERT INTO public.usuarios (id, email, nome, role)
        VALUES (
            NEW.id,
            NEW.email,
            COALESCE(NEW.raw_user_meta_data ->> 'nome', ''),
            COALESCE(NEW.raw_user_meta_data ->> 'role', 'vendas')
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- =====================================================================
-- SECAO 7: REVOGAR PERMISSOES PUBLICAS
-- =====================================================================
REVOKE ALL ON vendas_filial_b FROM anon;
REVOKE ALL ON vendas_filial FROM anon;
REVOKE ALL ON natureza FROM anon;
REVOKE ALL ON produtos FROM anon;
REVOKE ALL ON vendas_geral FROM anon;
REVOKE ALL ON usuarios FROM anon;
REVOKE ALL ON view_vendas_geral FROM anon;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

-- =====================================================================
-- SECAO 8: VERIFICACAO
-- =====================================================================
SELECT 'FIX EXECUTADO COM SUCESSO' AS status;

-- Verificar RLS policies ativas
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- Verificar funcoes SECURITY INVOKER/DEFINER
SELECT
    p.proname,
    p.prosecdef,
    CASE WHEN p.prosecdef THEN 'SECURITY DEFINER (PERIGOSO)' ELSE 'SECURITY INVOKER (SEGURO)' END AS security_invoker
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('refresh_vendas_geral', 'get_dashboard_completo', 'get_vendas_uf', 'get_vendas_volume')
ORDER BY p.proname;

-- Verificar trigger
SELECT
    tgname,
    tgrelid::regclass,
    pg_get_triggerdef(oid)
FROM pg_trigger
WHERE tgname = 'on_auth_user_created';
