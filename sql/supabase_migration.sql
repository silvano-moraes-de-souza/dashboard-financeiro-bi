--========================================
-- supabase_migration.sql
-- PROTEÇÃO MÁXIMA - Dashboard Financeiro BI Dashboard
-- v3.0 - 2026-06-08
--========================================

-- 1. TABELAS BASE
CREATE TABLE IF NOT EXISTS vendas_filial_b (
    id              BIGSERIAL PRIMARY KEY,
    data_emissao    DATE NOT NULL,
    numero_nota     TEXT NOT NULL,
    natureza_operacao TEXT,
    sku_ref         TEXT,
    produto         TEXT,
    nome_cliente    TEXT,
    cpf_cnpj        TEXT,
    tipo_pessoa     TEXT,
    cidade          TEXT,
    uf              TEXT,
    cep             TEXT,
    endereco        TEXT,
    numero          TEXT,
    quantidade      REAL DEFAULT 0,
    valor_unitario  REAL DEFAULT 0,
    frete           REAL DEFAULT 0,
    valor_total     REAL DEFAULT 0,
    empresa         TEXT DEFAULT 'FILIAL_B' NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS vendas_filial (
    id              BIGSERIAL PRIMARY KEY,
    data_emissao    DATE NOT NULL,
    numero_nota     TEXT NOT NULL,
    natureza_operacao TEXT,
    sku_ref         TEXT,
    produto         TEXT,
    nome_cliente    TEXT,
    cpf_cnpj        TEXT,
    tipo_pessoa     TEXT,
    cidade          TEXT,
    uf              TEXT,
    cep             TEXT,
    endereco        TEXT,
    numero          TEXT,
    quantidade      REAL DEFAULT 0,
    valor_unitario  REAL DEFAULT 0,
    frete           REAL DEFAULT 0,
    valor_total     REAL DEFAULT 0,
    empresa         TEXT DEFAULT 'FILIAL' NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS natureza (
    id                  BIGSERIAL PRIMARY KEY,
    natureza_operacao   TEXT NOT NULL,
    nomenclatura        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS produtos (
    id          BIGSERIAL PRIMARY KEY,
    sku         TEXT,
    produto     TEXT NOT NULL,
    categoria   TEXT,
    litros      REAL,
    uni_cx      INTEGER,
    custo       REAL DEFAULT 0,
    nomenclatura TEXT
);

-- 2. VIEW COM SECURITY INVOKER (respeita RLS do usuario logado)
-- ANTES: SECURITY DEFINER (bypassava RLS) -> AGORA: SECURITY INVOKER
CREATE OR REPLACE VIEW view_vendas_geral
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

-- 3. TABELA MATERIALIZADA vendas_geral (recebe os dados da VIEW)
CREATE TABLE IF NOT EXISTS vendas_geral AS SELECT * FROM view_vendas_geral WHERE 1=0;

-- 4. INDICES
CREATE INDEX IF NOT EXISTS idx_vb_empresa ON vendas_filial_b(empresa);
CREATE INDEX IF NOT EXISTS idx_vb_data ON vendas_filial_b(data_emissao);
CREATE INDEX IF NOT EXISTS idx_vb_produto ON vendas_filial_b(produto);
CREATE INDEX IF NOT EXISTS idx_vb_cliente ON vendas_filial_b(nome_cliente);

CREATE INDEX IF NOT EXISTS idx_vf_empresa ON vendas_filial(empresa);
CREATE INDEX IF NOT EXISTS idx_vf_data ON vendas_filial(data_emissao);
CREATE INDEX IF NOT EXISTS idx_vf_produto ON vendas_filial(produto);
CREATE INDEX IF NOT EXISTS idx_vf_cliente ON vendas_filial(nome_cliente);

CREATE INDEX IF NOT EXISTS idx_vg_empresa ON vendas_geral(empresa);
CREATE INDEX IF NOT EXISTS idx_vg_ano_mes ON vendas_geral(ano, mes);
CREATE INDEX IF NOT EXISTS idx_vg_uf ON vendas_geral(uf);
CREATE INDEX IF NOT EXISTS idx_vg_produto ON vendas_geral(produto);
CREATE INDEX IF NOT EXISTS idx_vg_categoria ON vendas_geral(categoria_produto);
CREATE INDEX IF NOT EXISTS idx_vg_data ON vendas_geral(data_emissao);
CREATE INDEX IF NOT EXISTS idx_vg_cliente ON vendas_geral(cliente);

CREATE INDEX IF NOT EXISTS idx_nat_natureza ON natureza(natureza_operacao);
CREATE INDEX IF NOT EXISTS idx_prod_produto ON produtos(produto);
CREATE INDEX IF NOT EXISTS idx_prod_sku ON produtos(sku);

-- 5. FUNCAO PARA ATUALIZAR vendas_geral (segura - SECURITY INVOKER)
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

-- 6. RLS (Row Level Security)
ALTER TABLE vendas_geral ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendas_filial_b ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendas_filial ENABLE ROW LEVEL SECURITY;
ALTER TABLE natureza ENABLE ROW LEVEL SECURITY;
ALTER TABLE produtos ENABLE ROW LEVEL SECURITY;

-- REMOVER politicas antigas (permissivas)
DROP POLICY IF EXISTS "Leitura vendas_geral" ON vendas_geral;
DROP POLICY IF EXISTS "Leitura vendas_filial_b" ON vendas_filial_b;
DROP POLICY IF EXISTS "Leitura vendas_filial" ON vendas_filial;
DROP POLICY IF EXISTS "Leitura natureza" ON natureza;
DROP POLICY IF EXISTS "Leitura produtos" ON produtos;

-- NOVAS politicas: apenas usuarios CADASTRADOS na tabela usuarios podem ler
CREATE POLICY "Leitura vendas_geral segura" ON vendas_geral
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "Leitura vendas_filial_b segura" ON vendas_filial_b
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "Leitura vendas_filial segura" ON vendas_filial
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "Leitura natureza segura" ON natureza
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

CREATE POLICY "Leitura produtos segura" ON produtos
    FOR SELECT TO authenticated USING (
        EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid())
    );

-- Escrita permitida apenas para service_role (ETL)
CREATE POLICY "Escrita vendas_filial_b" ON vendas_filial_b
    FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Escrita vendas_filial" ON vendas_filial
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 7. TABELA DE USUARIOS (para controle de roles)
CREATE TABLE IF NOT EXISTS usuarios (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       TEXT NOT NULL,
    role        TEXT NOT NULL DEFAULT 'vendas' CHECK (role IN ('admin', 'financeiro', 'vendas')),
    nome        TEXT DEFAULT '',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

-- Remover politicas antigas
DROP POLICY IF EXISTS "Leitura proprios dados" ON usuarios;
DROP POLICY IF EXISTS "Admin gerencia usuarios" ON usuarios;

-- Admin ve tudo, outros usuarios veem apenas o proprio registro
CREATE POLICY "Leitura usuarios" ON usuarios
    FOR SELECT TO authenticated USING (
        id = auth.uid()
        OR EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin')
    );

CREATE POLICY "Admin gerencia usuarios" ON usuarios
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM usuarios WHERE id = auth.uid() AND role = 'admin'));

-- 8. TRIGGER: auto-inserir na usuarios quando criar em auth.users
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

-- 9. REVOGAR ACESSO DIRETO AS TABELAS BASE (opcional, forca uso das views/RPCs)
-- Apenas service_role pode escrever, usuarios autenticados leem via RLS
REVOKE ALL ON vendas_filial_b FROM anon;
REVOKE ALL ON vendas_filial FROM anon;
REVOKE ALL ON natureza FROM anon;
REVOKE ALL ON produtos FROM anon;
REVOKE ALL ON vendas_geral FROM anon;
REVOKE ALL ON usuarios FROM anon;

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
