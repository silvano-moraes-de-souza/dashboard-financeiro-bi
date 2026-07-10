--========================================
-- rpc_functions_v2.sql
-- Descrição:
-- Criado por: Silvano Moraes de Souza
--========================================

-- Drop old overloaded functions to avoid PGRST203 ambiguity
DROP FUNCTION IF EXISTS public.get_dashboard_completo(text,text,text,text,text,text,text,text,text,text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_dashboard_completo(text,text,text,text,text,text,text,text,text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_uf(text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_uf(text,text,text,text,text,text,text,text,text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_volume(text,text,text,text,text,text,text,text,text,text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_volume(text,text,text,text,text,text,text,text,text,text,text) CASCADE;

-- ============================================================
-- FUNCAO 1: get_dashboard_completo
-- Retorna JSON do financeiro (identico ao /api/dados)
-- ============================================================
CREATE OR REPLACE FUNCTION get_dashboard_completo(
    p_empresa TEXT DEFAULT NULL,
    p_natureza TEXT DEFAULT NULL,
    p_tipo_pessoa TEXT DEFAULT NULL,
    p_ano TEXT DEFAULT NULL,
    p_mes TEXT DEFAULT NULL,
    p_produto TEXT DEFAULT NULL,
    p_cliente TEXT DEFAULT NULL,
    p_uf TEXT DEFAULT NULL,
    p_categoria TEXT DEFAULT NULL,
    p_dia TEXT DEFAULT NULL,
    p_dia_semana TEXT DEFAULT NULL,
    p_params TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
AS $func$
DECLARE
    v_ano INT;
    v_mes INT;
    v_dia INT;
    v_dia_semana INT;
    v_ref_year INT;
    v_cliente_array TEXT[];
    v_has_cliente_filter BOOLEAN;
    -- Resultados
    v_faturamento NUMERIC;
    v_custo_total NUMERIC;
    v_total_notas INT;
    v_total_caixas NUMERIC;
    v_evol_atual JSONB;
    v_evol_anterior JSONB;
    v_evol_dia JSONB;
    v_rank_semana JSONB;
    v_top10 JSONB;
    v_market_share JSONB;
    v_vendas_uf JSONB;
    v_rank_cat JSONB;
    v_pm JSONB;
    v_transacoes JSONB;
    v_top20 JSONB;
    v_mix JSONB;
    v_rentabilidade JSONB;
    v_margem_mensal JSONB;
    v_todos_produtos JSONB;
    v_filtros JSONB;
    v_top20_nomes TEXT[];
BEGIN
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;
    v_dia := NULLIF(p_dia, '')::INT;
    v_dia_semana := NULLIF(p_dia_semana, '')::INT;

    IF p_cliente IS NOT NULL AND p_cliente != '' AND p_cliente != '__NONE__' THEN
        v_cliente_array := string_to_array(p_cliente, ',');
        v_has_cliente_filter := TRUE;
    ELSE
        v_cliente_array := NULL;
        v_has_cliente_filter := FALSE;
    END IF;

    IF v_ano IS NOT NULL THEN v_ref_year := v_ano;
    ELSE SELECT MAX(ano) INTO v_ref_year FROM vendas_geral; END IF;

    -- ============================================================
    -- Q1: KPIs
    -- ============================================================
    SELECT
        ROUND(COALESCE(SUM(v.val_item::numeric), 0), 2),
        ROUND(COALESCE(SUM(v.qtd_caixas::numeric * v.uni_cx_produto::numeric * COALESCE(
            (SELECT p.custo::numeric FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto) LIMIT 1), 0
        )), 0), 2),
        COUNT(DISTINCT v.numero_nota || '_' || v.empresa)::INT,
        ROUND(COALESCE(SUM(v.qtd_caixas), 0))
    INTO v_faturamento, v_custo_total, v_total_notas, v_total_caixas
    FROM vendas_geral v
    WHERE 1=1
        AND (p_empresa IS NULL OR v.empresa = p_empresa)
        AND (p_natureza IS NULL OR v.natureza_operacao LIKE '%' || p_natureza || '%')
        AND (p_tipo_pessoa IS NULL OR v.tipo_pessoa = p_tipo_pessoa)
        AND (v_ano IS NULL OR v.ano = v_ano)
        AND (v_mes IS NULL OR v.mes = v_mes)
        AND (p_produto IS NULL OR v.produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
        AND (NOT v_has_cliente_filter OR v.cliente = ANY(v_cliente_array))
        AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
        AND (p_uf IS NULL OR v.uf = p_uf)
        AND (p_categoria IS NULL OR v.categoria_produto = p_categoria)
        AND (v_dia IS NULL OR v.dia = v_dia)
        AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM v.data_emissao)::INT = v_dia_semana)
        AND v.cliente != 'EMPRESA DEMO LTDA';

    -- ============================================================
    -- Q2: Evolucao Mensal
    -- ============================================================
    WITH evol AS (
        SELECT mes,
            SUM(val_item::numeric) FILTER (WHERE ano = v_ref_year) AS valor_atual,
            SUM(val_item::numeric) FILTER (WHERE ano = v_ref_year - 1) AS valor_anterior
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
            AND ano IN (v_ref_year, v_ref_year - 1)
        GROUP BY mes
    )
    SELECT jsonb_build_object(
        'data', COALESCE(
            (SELECT jsonb_agg(COALESCE(e.valor_atual, 0) ORDER BY m.mes)
             FROM generate_series(1, 12) m(mes) LEFT JOIN evol e ON m.mes = e.mes),
            '[]'::jsonb
        ),
        'data_anterior', COALESCE(
            (SELECT jsonb_agg(COALESCE(e.valor_anterior, 0) ORDER BY m.mes)
             FROM generate_series(1, 12) m(mes) LEFT JOIN evol e ON m.mes = e.mes),
            '[]'::jsonb
        )
    ) INTO v_evol_atual;

    -- ============================================================
    -- Q3: Evolucao Diaria
    -- ============================================================
    WITH evol_dia AS (
        SELECT d.dia, COALESCE(sub.valor, 0) AS valor
        FROM generate_series(1, 31) d(dia)
        LEFT JOIN (
            SELECT dia, SUM(val_item::numeric) AS valor
            FROM vendas_geral
            WHERE 1=1
                AND (p_empresa IS NULL OR empresa = p_empresa)
                AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
                AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
                AND (v_ano IS NULL OR ano = v_ano)
                AND (v_mes IS NULL OR mes = v_mes)
                AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
                AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
                AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
                AND (p_uf IS NULL OR uf = p_uf)
                AND (p_categoria IS NULL OR categoria_produto = p_categoria)
                AND (v_dia IS NULL OR dia = v_dia)
                AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
                AND cliente != 'EMPRESA DEMO LTDA'
            GROUP BY dia
        ) sub ON d.dia = sub.dia
    )
    SELECT jsonb_agg(valor ORDER BY dia) INTO v_evol_dia FROM evol_dia;

    -- ============================================================
    -- Q4: Rank Dia da Semana
    -- ============================================================
    WITH rank_dia AS (
        SELECT d.dia_semana, COALESCE(sub.valor, 0) AS valor
        FROM generate_series(0, 6) d(dia_semana)
        LEFT JOIN (
            SELECT EXTRACT(DOW FROM data_emissao)::INT AS dia_semana, SUM(val_item::numeric) AS valor
            FROM vendas_geral
            WHERE 1=1
                AND (p_empresa IS NULL OR empresa = p_empresa)
                AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
                AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
                AND (v_ano IS NULL OR ano = v_ano)
                AND (v_mes IS NULL OR mes = v_mes)
                AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
                AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
                AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
                AND (p_uf IS NULL OR uf = p_uf)
                AND (p_categoria IS NULL OR categoria_produto = p_categoria)
                AND (v_dia IS NULL OR dia = v_dia)
                AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
                AND cliente != 'EMPRESA DEMO LTDA'
            GROUP BY EXTRACT(DOW FROM data_emissao)::INT
        ) sub ON d.dia_semana = sub.dia_semana
    )
    SELECT jsonb_agg(valor ORDER BY dia_semana) INTO v_rank_semana FROM rank_dia;

    -- ============================================================
    -- Q5: Top 10 Produtos
    -- ============================================================
    WITH top_prod AS (
        SELECT COALESCE(produto, 'N/A') AS label, SUM(val_item::numeric) AS valor
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY produto
        ORDER BY valor DESC
        LIMIT 10
    )
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(label ORDER BY valor DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(valor ORDER BY valor DESC), '[]'::jsonb)
    ) INTO v_top10 FROM top_prod;

    -- ============================================================
    -- Q6: Market Share
    -- ============================================================
    WITH ms AS (
        SELECT empresa, SUM(val_item::numeric) AS valor
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY empresa
        ORDER BY valor DESC
    )
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(empresa ORDER BY valor DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(valor ORDER BY valor DESC), '[]'::jsonb)
    ) INTO v_market_share FROM ms;

    -- ============================================================
    -- Q7: Vendas por UF
    -- ============================================================
    WITH vendas_uf AS (
        SELECT uf, SUM(val_item::numeric) AS valor
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
            AND uf != '' AND uf IS NOT NULL
        GROUP BY uf
        ORDER BY valor DESC
    )
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(uf ORDER BY valor DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(valor ORDER BY valor DESC), '[]'::jsonb)
    ) INTO v_vendas_uf FROM vendas_uf;

    -- ============================================================
    -- Q8: Rank Categoria
    -- ============================================================
    WITH cat AS (
        SELECT categoria_produto AS label, SUM(val_item::numeric) AS valor
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY categoria_produto
        ORDER BY valor DESC
    )
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(label ORDER BY valor DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(valor ORDER BY valor DESC), '[]'::jsonb)
    ) INTO v_rank_cat FROM cat;

    -- ============================================================
    -- Q9: PM por Empresa (12 meses)
    -- ============================================================
    WITH pm_data AS (
        SELECT empresa, SUM(val_item::numeric) AS valor, SUM(qtd_caixas) AS qtd_caixas
        FROM vendas_geral
        WHERE data_emissao >= CURRENT_DATE - INTERVAL '12 months'
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY empresa
    ),
    total_fat AS (SELECT SUM(valor) AS total FROM pm_data)
    SELECT jsonb_build_object(
        'ponderado', COALESCE((SELECT SUM((valor / NULLIF(qtd_caixas::numeric, 0)) * (valor / NULLIF((SELECT total FROM total_fat), 0))) FROM pm_data WHERE qtd_caixas > 0), 0),
        'por_empresa', COALESCE(
            (SELECT jsonb_object_agg(empresa, jsonb_build_object(
                'preco_medio', ROUND(COALESCE(valor::numeric / NULLIF(qtd_caixas::numeric, 0), 0), 2),
                'faturamento_12m', ROUND(valor, 2),
                'qtd_caixas_12m', qtd_caixas,
                'share_12m', ROUND(COALESCE(valor * 100.0 / NULLIF((SELECT total FROM total_fat), 0), 0), 2)
            )) FROM pm_data),
            '{}'::jsonb
        )
    ) INTO v_pm;

    -- ============================================================
    -- Q10: Transacoes Recentes
    -- ============================================================
    WITH trans AS (
        SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
               val_item, empresa, nomenclatura, categoria_produto, ano, mes
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        ORDER BY data_emissao DESC, numero_nota DESC
        LIMIT 100
    )
    SELECT COALESCE(jsonb_agg(row_to_json(trans)::jsonb ORDER BY data_emissao DESC, numero_nota DESC), '[]'::jsonb)
    INTO v_transacoes FROM trans;

    -- ============================================================
    -- Q11: Top 30 Clientes
    -- ============================================================
    WITH total_geral AS (
        SELECT SUM(val_item::numeric) AS total FROM vendas_geral
        WHERE cliente != '' AND cliente IS NOT NULL
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
    ),
    top_clientes AS (
        SELECT
            cliente,
            ROUND(SUM(val_item::numeric), 2) AS valor,
            COUNT(DISTINCT numero_nota || '_' || empresa) AS notas,
            ROUND(SUM(qtd_caixas))::INT AS caixas,
            ROUND(SUM(val_item::numeric) * 100.0 / NULLIF((SELECT total FROM total_geral), 0), 2) AS porcentagem
        FROM vendas_geral
        WHERE cliente != '' AND cliente IS NOT NULL
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY cliente
        ORDER BY valor DESC
        LIMIT 30
    )
    SELECT
        COALESCE(jsonb_agg(row_to_json(top_clientes)::jsonb ORDER BY valor DESC), '[]'::jsonb),
        COALESCE(array_agg(cliente ORDER BY valor DESC), ARRAY[]::TEXT[])
    INTO v_top20, v_top20_nomes
    FROM top_clientes;

    -- ============================================================
    -- Q12: Mix de Produtos por Cliente
    -- ============================================================
    IF v_top20_nomes IS NOT NULL AND array_length(v_top20_nomes, 1) IS NOT NULL AND array_length(v_top20_nomes, 1) > 0 THEN
        WITH mix AS (
            SELECT cliente, produto, COALESCE(categoria_produto, '') AS categoria,
                   ROUND(SUM(val_item::numeric), 2) AS valor,
                   ROUND(SUM(qtd_caixas::numeric))::INT AS caixas,
                   ROUND(SUM(quantidade::numeric))::INT AS unidades
            FROM vendas_geral
            WHERE cliente = ANY(v_top20_nomes)
                AND (p_empresa IS NULL OR empresa = p_empresa)
                AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
                AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
                AND (v_ano IS NULL OR ano = v_ano)
                AND (v_mes IS NULL OR mes = v_mes)
                AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
                AND (p_uf IS NULL OR uf = p_uf)
                AND (p_categoria IS NULL OR categoria_produto = p_categoria)
                AND (v_dia IS NULL OR dia = v_dia)
                AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
                AND cliente != 'EMPRESA DEMO LTDA'
            GROUP BY cliente, produto, categoria_produto
        )
        SELECT COALESCE(jsonb_object_agg(cliente, produtos), '{}'::jsonb)
        INTO v_mix
        FROM (
            SELECT cliente, jsonb_agg(jsonb_build_object(
                'produto', produto, 'categoria', categoria,
                'valor', valor, 'caixas', caixas, 'unidades', unidades
            ) ORDER BY valor DESC) AS produtos
            FROM mix
            GROUP BY cliente
        ) sub;
    ELSE
        v_mix := '{}'::jsonb;
    END IF;

    -- ============================================================
    -- Q13: Todos os Produtos
    -- ============================================================
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'produto', produto,
        'categoria', COALESCE(categoria, ''),
        'nomenclatura', COALESCE(nomenclatura, produto)
    ) ORDER BY produto), '[]'::jsonb)
    INTO v_todos_produtos
    FROM produtos WHERE produto != '';

    -- ============================================================
    -- Q14-17: Filtros Disponiveis
    -- ============================================================
    WITH f_emp AS (
        SELECT jsonb_agg(DISTINCT empresa ORDER BY empresa) AS val FROM vendas_geral
    ),
    f_anos AS (
        SELECT jsonb_agg(DISTINCT ano ORDER BY ano DESC) AS val FROM vendas_geral
    ),
    f_prod AS (
        SELECT jsonb_agg(DISTINCT COALESCE(nomenclatura, produto) ORDER BY COALESCE(nomenclatura, produto)) AS val
        FROM produtos WHERE produto != ''
    ),
    f_clientes AS (
        SELECT jsonb_agg(DISTINCT cliente ORDER BY cliente) AS val
        FROM vendas_geral WHERE cliente != '' AND cliente != 'EMPRESA DEMO LTDA'
    )
    SELECT jsonb_build_object(
        'empresas', COALESCE((SELECT val FROM f_emp), '[]'::jsonb),
        'anos', COALESCE((SELECT val FROM f_anos), '[]'::jsonb),
        'produtos', COALESCE((SELECT val FROM f_prod), '[]'::jsonb),
        'clientes', COALESCE((SELECT val FROM f_clientes), '[]'::jsonb)
    ) INTO v_filtros;

    -- ============================================================
    -- Q18: Rentabilidade por Cliente (top 400)
    -- ============================================================
    WITH rent AS (
        SELECT
            v.cliente,
            ROUND(SUM(v.val_item::numeric), 2) AS receita,
            ROUND(SUM(v.qtd_caixas::numeric * v.uni_cx_produto::numeric * COALESCE(
                (SELECT p.custo::numeric FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto) LIMIT 1), 0
            )), 2) AS custo,
            COUNT(DISTINCT v.numero_nota || '_' || v.empresa) AS pedidos
        FROM vendas_geral v
        WHERE 1=1
            AND (p_empresa IS NULL OR v.empresa = p_empresa)
            AND (p_natureza IS NULL OR v.natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR v.tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR v.ano = v_ano)
            AND (v_mes IS NULL OR v.mes = v_mes)
            AND (p_produto IS NULL OR v.produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR v.cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR v.uf = p_uf)
            AND (p_categoria IS NULL OR v.categoria_produto = p_categoria)
            AND (v_dia IS NULL OR v.dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM v.data_emissao)::INT = v_dia_semana)
            AND v.cliente != 'EMPRESA DEMO LTDA'
        GROUP BY v.cliente
        ORDER BY receita DESC
        LIMIT 400
    ),
    rent_medians AS (
        SELECT
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY receita) AS med_receita,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
                CASE WHEN receita > 0 THEN (receita - custo) / receita * 100 ELSE 0 END
            ) AS med_margem
        FROM rent
    ),
    rent_classified AS (
        SELECT
            r.cliente,
            r.receita,
            r.custo,
            ROUND((r.receita - r.custo)::numeric, 2) AS lucro,
            CASE WHEN r.receita > 0 THEN ROUND(((r.receita - r.custo)::numeric / r.receita * 100), 1) ELSE 0 END AS margem,
            r.pedidos,
            ROUND(r.receita::numeric / NULLIF(r.pedidos, 0), 2) AS ticket_medio,
            CASE
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) >= m.med_margem
                     AND r.receita >= m.med_receita THEN 2
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) >= m.med_margem
                     AND r.receita < m.med_receita THEN 1
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) < m.med_margem
                     AND r.receita >= m.med_receita THEN 4
                ELSE 3
            END AS quadrante,
            CASE
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) >= m.med_margem
                     AND r.receita >= m.med_receita THEN 'Cliente Ideal'
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) >= m.med_margem
                     AND r.receita < m.med_receita THEN 'Potencial de Expansao'
                WHEN (CASE WHEN r.receita > 0 THEN (r.receita - r.custo) / r.receita * 100 ELSE 0 END) < m.med_margem
                     AND r.receita >= m.med_receita THEN 'Risco de Margem'
                ELSE 'Baixo Impacto'
            END AS status
        FROM rent r
        CROSS JOIN rent_medians m
    )
    SELECT jsonb_build_object(
        'clientes', COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'cliente', cliente,
                'receita', receita,
                'custo', custo,
                'lucro', lucro,
                'margem', margem,
                'pedidos', pedidos,
                'ticket_medio', ticket_medio,
                'quadrante', quadrante,
                'status', status
            ) ORDER BY receita DESC) FROM rent_classified),
            '[]'::jsonb
        ),
        'mediana_receita', COALESCE((SELECT med_receita FROM rent_medians), 0),
        'mediana_margem', COALESCE((SELECT med_margem FROM rent_medians), 0)
    ) INTO v_rentabilidade;

    -- ============================================================
    -- Q19: Margem Mensal
    -- ============================================================
    WITH margem AS (
        SELECT mes,
            ROUND(SUM(val_item::numeric), 2) AS receita,
            ROUND(SUM(qtd_caixas::numeric * uni_cx_produto::numeric * COALESCE(
                (SELECT p.custo::numeric FROM produtos p WHERE TRIM(p.produto) = TRIM(produto) LIMIT 1), 0
            )), 2) AS custo
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (NOT v_has_cliente_filter OR cliente = ANY(v_cliente_array))
            AND (p_cliente IS NULL OR p_cliente != '__NONE__' OR 1=0)
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY mes
        ORDER BY mes
    )
    SELECT COALESCE(jsonb_agg(
        CASE WHEN receita > 0 THEN ROUND(((receita - custo)::numeric / receita * 100), 1) ELSE NULL END
        ORDER BY mes
    ), '[]'::jsonb)
    INTO v_margem_mensal FROM margem;

    -- ============================================================
    -- RESPOSTA FINAL
    -- ============================================================
    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'faturamento', v_faturamento,
            'lucro_estimado', ROUND(v_faturamento * 0.15, 2),
            'custo_total', v_custo_total,
            'custo_percentual', CASE WHEN v_faturamento > 0 THEN ROUND((v_custo_total / v_faturamento * 100)::numeric, 2) ELSE 0 END,
            'ticket_medio', CASE WHEN v_total_caixas > 0 THEN ROUND(v_faturamento / 12 / v_total_caixas::numeric, 2) ELSE 0 END,
            'total_notas', v_total_notas,
            'total_caixas', ROUND(v_total_caixas)
        ),
        'pm', COALESCE(v_pm, '{"ponderado":0,"por_empresa":{}}'::jsonb),
        'evolucao_mensal', jsonb_build_object(
            'labels', '["Jan","Fev","Mar","Abr","Mai","Jun","Jul","Ago","Set","Out","Nov","Dez"]'::jsonb,
            'data', COALESCE(v_evol_atual->'data', '[]'::jsonb),
            'data_anterior', COALESCE(v_evol_atual->'data_anterior', '[]'::jsonb),
            'ano_atual', v_ref_year
        ),
        'evolucao_diaria', jsonb_build_object(
            'labels', (SELECT jsonb_agg('D' || g) FROM generate_series(1, 31) g),
            'dias_reais', (SELECT jsonb_agg(g) FROM generate_series(1, 31) g),
            'data', COALESCE(v_evol_dia, '[]'::jsonb)
        ),
        'rank_semana', jsonb_build_object(
            'labels', '["Dom","Seg","Ter","Qua","Qui","Sex","Sab"]'::jsonb,
            'data', COALESCE(v_rank_semana, '[]'::jsonb)
        ),
        'top10', COALESCE(v_top10, '{"labels":[],"data":[]}'::jsonb),
        'market_share', COALESCE(v_market_share, '{"labels":[],"data":[]}'::jsonb),
        'vendas_uf', COALESCE(v_vendas_uf, '{"labels":[],"data":[]}'::jsonb),
        'rank_categoria', COALESCE(v_rank_cat, '{"labels":[],"data":[]}'::jsonb),
        'top20_clientes', COALESCE(v_top20, '[]'::jsonb),
        'mix_por_cliente', COALESCE(v_mix, '{}'::jsonb),
        'rentabilidade', COALESCE(v_rentabilidade, '{"clientes":[],"mediana_receita":0,"mediana_margem":0}'::jsonb),
        'margem_mensal', COALESCE(v_margem_mensal, '[]'::jsonb),
        'todos_produtos', COALESCE(v_todos_produtos, '[]'::jsonb),
        'filtros', COALESCE(v_filtros, '{"empresas":[],"anos":[],"produtos":[],"clientes":[]}'::jsonb),
        'transacoes_recentes', COALESCE(v_transacoes, '[]'::jsonb)
    );
END;
$func$;

-- ============================================================
-- FUNCAO 3: get_vendas_uf (Mapa)
-- Retorna dados agregados por UF para o mapa do Brasil
-- ============================================================
DROP FUNCTION IF EXISTS public.get_vendas_uf(text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_uf(text,text,text,text,text,text,text,text,text,text,text) CASCADE;

CREATE OR REPLACE FUNCTION get_vendas_uf(
    p_empresa TEXT DEFAULT NULL,
    p_natureza TEXT DEFAULT NULL,
    p_tipo_pessoa TEXT DEFAULT NULL,
    p_ano TEXT DEFAULT NULL,
    p_mes TEXT DEFAULT NULL,
    p_produto TEXT DEFAULT NULL,
    p_cliente TEXT DEFAULT NULL,
    p_uf TEXT DEFAULT NULL,
    p_categoria TEXT DEFAULT NULL,
    p_dia TEXT DEFAULT NULL,
    p_dia_semana TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
AS $func$
DECLARE
    v_ano INT;
    v_mes INT;
    v_dia INT;
    v_dia_semana INT;
    v_result JSONB;
BEGIN
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;
    v_dia := NULLIF(p_dia, '')::INT;
    v_dia_semana := NULLIF(p_dia_semana, '')::INT;

    WITH total_nacional AS (
        SELECT SUM(val_item::numeric) AS total
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND cliente != 'EMPRESA DEMO LTDA'
    ),
    uf_agg AS (
        SELECT
            uf,
            ROUND(SUM(val_item::numeric), 2) AS valor,
            ROUND(COALESCE(SUM(val_item::numeric) * 100.0 / NULLIF((SELECT total FROM total_nacional), 0), 0), 2) AS porcentagem,
            COUNT(DISTINCT numero_nota || '_' || empresa)::INT AS notas
        FROM vendas_geral
        WHERE 1=1
            AND (p_empresa IS NULL OR empresa = p_empresa)
            AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
            AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
            AND (v_ano IS NULL OR ano = v_ano)
            AND (v_mes IS NULL OR mes = v_mes)
            AND (p_produto IS NULL OR produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = p_produto))
            AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
            AND (p_uf IS NULL OR uf = p_uf)
            AND (p_categoria IS NULL OR categoria_produto = p_categoria)
            AND (v_dia IS NULL OR dia = v_dia)
            AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
            AND uf != '' AND uf IS NOT NULL
            AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY uf
    )
    SELECT jsonb_build_object(
        'dados_por_uf', COALESCE(
            (SELECT jsonb_object_agg(uf, jsonb_build_object(
                'nome', CASE uf
                    WHEN 'AC' THEN 'Acre' WHEN 'AL' THEN 'Alagoas' WHEN 'AP' THEN 'Amapa' WHEN 'AM' THEN 'Amazonas'
                    WHEN 'BA' THEN 'Bahia' WHEN 'CE' THEN 'Ceara' WHEN 'DF' THEN 'Distrito Federal' WHEN 'ES' THEN 'Espirito Santo'
                    WHEN 'GO' THEN 'Goias' WHEN 'MA' THEN 'Maranhao' WHEN 'MT' THEN 'Mato Grosso' WHEN 'MS' THEN 'Mato Grosso do Sul'
                    WHEN 'MG' THEN 'Minas Gerais' WHEN 'PA' THEN 'Para' WHEN 'PB' THEN 'Paraiba' WHEN 'PR' THEN 'Parana'
                    WHEN 'PE' THEN 'Pernambuco' WHEN 'PI' THEN 'Piaui' WHEN 'RJ' THEN 'Rio de Janeiro' WHEN 'RN' THEN 'Rio Grande do Norte'
                    WHEN 'RS' THEN 'Rio Grande do Sul' WHEN 'RO' THEN 'Rondonia' WHEN 'RR' THEN 'Roraima' WHEN 'SC' THEN 'Santa Catarina'
                    WHEN 'SP' THEN 'Sao Paulo' WHEN 'SE' THEN 'Sergipe' WHEN 'TO' THEN 'Tocantins' ELSE uf
                END,
                'valor', valor,
                'porcentagem', porcentagem,
                'notas', notas
            ) ORDER BY uf)
            FROM uf_agg),
            '{}'::jsonb
        ),
        'max_valor', COALESCE(
            (SELECT valor FROM uf_agg ORDER BY valor DESC LIMIT 1),
            0
        ),
        'total_geral', COALESCE((SELECT total FROM total_nacional), 0),
        'total_estados', (SELECT COUNT(*) FROM uf_agg)
    ) INTO v_result;

    RETURN v_result;
END;
$func$;

-- ============================================================
-- FUNCAO 2: get_vendas_volume (Vendas)
-- generate_series(1,12) com FILTER para evolucao mensal correta
-- ============================================================
DROP FUNCTION IF EXISTS public.get_vendas_volume(text,text,text,text,text,text,text,text,text,text,text,text) CASCADE;
DROP FUNCTION IF EXISTS public.get_vendas_volume(text,text,text,text,text,text,text,text,text,text,text) CASCADE;

CREATE OR REPLACE FUNCTION get_vendas_volume(
    p_empresa TEXT DEFAULT NULL,
    p_natureza TEXT DEFAULT NULL,
    p_tipo_pessoa TEXT DEFAULT NULL,
    p_ano TEXT DEFAULT NULL,
    p_mes TEXT DEFAULT NULL,
    p_produto TEXT DEFAULT NULL,
    p_cliente TEXT DEFAULT NULL,
    p_uf TEXT DEFAULT NULL,
    p_categoria TEXT DEFAULT NULL,
    p_dia TEXT DEFAULT NULL,
    p_dia_semana TEXT DEFAULT NULL,
    p_params TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
AS $func$
DECLARE
    v_ano INT;
    v_mes INT;
    v_dia INT;
    v_dia_semana INT;
    v_ref_year INT;
    v_total_caixas INT;
    v_total_litros NUMERIC;
    v_total_unidades INT;
    v_total_notas INT;
    v_media_cx_nota NUMERIC;
    v_evol_atual JSONB;
    v_evol_dia JSONB;
    v_rank_semana JSONB;
    v_top10 JSONB;
    v_market_share JSONB;
    v_vendas_uf JSONB;
    v_rank_cat JSONB;
    v_volume_empresa JSONB;
    v_transacoes JSONB;
    v_top20 JSONB;
    v_mix JSONB;
    v_todos_produtos JSONB;
    v_filtros JSONB;
    v_mapa_caixas JSONB;
    v_top_nomes TEXT[];
BEGIN
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;
    v_dia := NULLIF(p_dia, '')::INT;
    v_dia_semana := NULLIF(p_dia_semana, '')::INT;
    v_ref_year := COALESCE(v_ano, (SELECT MAX(ano) FROM vendas_geral));

    -- Q1: KPIs Volume
    SELECT
        COALESCE(ROUND(SUM(qtd_caixas::numeric))::INT, 0),
        COALESCE(ROUND(SUM(litros_produto::numeric), 0), 0),
        COALESCE(ROUND(SUM(quantidade::numeric))::INT, 0),
        COALESCE(COUNT(DISTINCT numero_nota || '_' || empresa)::INT, 0)
    INTO v_total_caixas, v_total_litros, v_total_unidades, v_total_notas
    FROM vendas_geral
    WHERE (p_empresa IS NULL OR empresa = p_empresa)
      AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
      AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
      AND (v_ano IS NULL OR ano = v_ano)
      AND (v_mes IS NULL OR mes = v_mes)
      AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
      AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
      AND (p_uf IS NULL OR uf = p_uf)
      AND (p_categoria IS NULL OR categoria_produto = p_categoria)
      AND (v_dia IS NULL OR dia = v_dia)
      AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
      AND cliente != 'EMPRESA DEMO LTDA';

    v_media_cx_nota := CASE WHEN v_total_notas > 0 THEN ROUND(v_total_caixas::NUMERIC / v_total_notas, 1) ELSE 0 END;

    -- Q2: Evolucao Mensal Caixas — generate_series(1,12) com FILTER
    WITH evol AS (
        SELECT mes,
            ROUND(SUM(qtd_caixas::numeric) FILTER (WHERE ano = v_ref_year))::INT AS caixas_atual,
            ROUND(SUM(qtd_caixas::numeric) FILTER (WHERE ano = v_ref_year - 1))::INT AS caixas_anterior
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
          AND ano IN (v_ref_year, v_ref_year - 1)
        GROUP BY mes
    )
    SELECT jsonb_build_object(
        'data', COALESCE(
            (SELECT jsonb_agg(COALESCE(e.caixas_atual, 0) ORDER BY m.mes)
             FROM generate_series(1, 12) m(mes) LEFT JOIN evol e ON m.mes = e.mes),
            '[]'::jsonb
        ),
        'data_anterior', COALESCE(
            (SELECT jsonb_agg(COALESCE(e.caixas_anterior, 0) ORDER BY m.mes)
             FROM generate_series(1, 12) m(mes) LEFT JOIN evol e ON m.mes = e.mes),
            '[]'::jsonb
        )
    ) INTO v_evol_atual;

    -- Q3: Evolucao Diaria Caixas
    SELECT COALESCE(jsonb_agg(COALESCE(sub.caixas, 0) ORDER BY d.dia), '[]'::jsonb)
    INTO v_evol_dia
    FROM generate_series(1, 31) d(dia)
    LEFT JOIN (
        SELECT dia, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY dia
    ) sub ON d.dia = sub.dia;

    -- Q4: Rank Semana Caixas
    SELECT COALESCE(jsonb_agg(COALESCE(sub.caixas, 0) ORDER BY d.dia_semana), '[]'::jsonb)
    INTO v_rank_semana
    FROM generate_series(0, 6) d(dia_semana)
    LEFT JOIN (
        SELECT EXTRACT(DOW FROM data_emissao)::INT AS dia_semana, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY EXTRACT(DOW FROM data_emissao)::INT
    ) sub ON d.dia_semana = sub.dia_semana;

    -- Q5: Top 10 Produtos (Caixas)
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(produto ORDER BY caixas DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), '[]'::jsonb)
    )
    INTO v_top10
    FROM (
        SELECT COALESCE(produto, 'N/A') AS produto, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY produto
        ORDER BY caixas DESC
        LIMIT 10
    ) sub;

    -- Q6: Market Share (Caixas)
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(empresa ORDER BY caixas DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), '[]'::jsonb)
    )
    INTO v_market_share
    FROM (
        SELECT empresa, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY empresa
        ORDER BY caixas DESC
    ) sub;

    -- Q7: Caixas por UF
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(uf ORDER BY caixas DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), '[]'::jsonb)
    )
    INTO v_vendas_uf
    FROM (
        SELECT uf, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND uf != '' AND uf IS NOT NULL
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY uf
        ORDER BY caixas DESC
    ) sub;

    -- Q8: Rank Categoria (Caixas)
    SELECT jsonb_build_object(
        'labels', COALESCE(jsonb_agg(categoria ORDER BY caixas DESC), '[]'::jsonb),
        'data', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), '[]'::jsonb)
    )
    INTO v_rank_cat
    FROM (
        SELECT categoria_produto AS categoria, ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY categoria_produto
        ORDER BY caixas DESC
    ) sub;

    -- Q9: Volume por Empresa (12m)
    WITH vol_data AS (
        SELECT empresa,
            ROUND(SUM(litros_produto::numeric), 1) AS litros,
            ROUND(SUM(qtd_caixas::numeric))::INT AS caixas
        FROM vendas_geral
        WHERE data_emissao >= CURRENT_DATE - INTERVAL '12 months'
          AND (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY empresa
    ),
    total_vol AS (SELECT SUM(caixas) AS total_caixas, SUM(litros) AS total_litros FROM vol_data)
    SELECT jsonb_build_object(
        'por_empresa', COALESCE(
            (SELECT jsonb_object_agg(empresa, jsonb_build_object(
                'caixas_12m', caixas,
                'litros_12m', litros,
                'share_12m', ROUND(COALESCE(caixas::numeric * 100.0 / NULLIF((SELECT total_caixas FROM total_vol), 0), 0), 2)
            )) FROM vol_data),
            '{}'::jsonb
        )
    ) INTO v_volume_empresa;

    -- Q10: Transacoes Recentes
    WITH trans AS (
        SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
               val_item, empresa, nomenclatura, categoria_produto, ano, mes,
               qtd_caixas, litros_produto, quantidade, uni_cx_produto
        FROM vendas_geral
        WHERE (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        ORDER BY data_emissao DESC, numero_nota DESC
        LIMIT 100
    )
    SELECT COALESCE(jsonb_agg(row_to_json(trans)::jsonb ORDER BY data_emissao DESC, numero_nota DESC), '[]'::jsonb)
    INTO v_transacoes FROM trans;

    -- Q11: Top 30 Clientes por Caixas
    WITH top_clientes AS (
        SELECT cliente,
            ROUND(SUM(qtd_caixas::numeric))::INT AS caixas,
            COUNT(DISTINCT numero_nota || '_' || empresa)::INT AS notas,
            ROUND(SUM(val_item::numeric), 2) AS valor
        FROM vendas_geral
        WHERE cliente != '' AND cliente IS NOT NULL
          AND (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY cliente
        ORDER BY caixas DESC
        LIMIT 30
    )
    SELECT
        COALESCE(jsonb_agg(row_to_json(top_clientes)::jsonb ORDER BY caixas DESC), '[]'::jsonb),
        COALESCE(array_agg(cliente ORDER BY caixas DESC), ARRAY[]::TEXT[])
    INTO v_top20, v_top_nomes
    FROM top_clientes;

    -- Q12: Mix de Produtos por Cliente
    IF v_top_nomes IS NOT NULL AND array_length(v_top_nomes, 1) IS NOT NULL AND array_length(v_top_nomes, 1) > 0 THEN
        WITH mix AS (
            SELECT cliente, produto, COALESCE(categoria_produto, '') AS categoria,
                   ROUND(SUM(val_item::numeric), 2) AS valor,
                   ROUND(SUM(qtd_caixas::numeric))::INT AS caixas,
                   ROUND(SUM(quantidade::numeric))::INT AS unidades
            FROM vendas_geral
            WHERE cliente = ANY(v_top_nomes)
              AND (p_empresa IS NULL OR empresa = p_empresa)
              AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
              AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
              AND (v_ano IS NULL OR ano = v_ano)
              AND (v_mes IS NULL OR mes = v_mes)
              AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
              AND (p_uf IS NULL OR uf = p_uf)
              AND (p_categoria IS NULL OR categoria_produto = p_categoria)
              AND (v_dia IS NULL OR dia = v_dia)
              AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
              AND cliente != 'EMPRESA DEMO LTDA'
            GROUP BY cliente, produto, categoria_produto
        )
        SELECT COALESCE(jsonb_object_agg(cliente, produtos), '{}'::jsonb)
        INTO v_mix
        FROM (
            SELECT cliente, jsonb_agg(jsonb_build_object(
                'produto', produto, 'categoria', categoria,
                'valor', valor, 'caixas', caixas, 'unidades', unidades
            ) ORDER BY caixas DESC) AS produtos
            FROM mix GROUP BY cliente
        ) sub;
    ELSE
        v_mix := '{}'::jsonb;
    END IF;

    -- Q13: Todos os Produtos
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'produto', produto, 'categoria', COALESCE(categoria, '')
    ) ORDER BY produto), '[]'::jsonb)
    INTO v_todos_produtos
    FROM produtos WHERE produto != '';

    -- Q14: Filtros
    WITH f_emp AS (
        SELECT jsonb_agg(DISTINCT empresa ORDER BY empresa) AS val FROM vendas_geral
    ),
    f_anos AS (
        SELECT jsonb_agg(DISTINCT ano ORDER BY ano DESC) AS val FROM vendas_geral
    ),
    f_prod AS (
        SELECT jsonb_agg(DISTINCT COALESCE(nomenclatura, produto) ORDER BY COALESCE(nomenclatura, produto)) AS val
        FROM produtos WHERE produto != ''
    ),
    f_clientes AS (
        SELECT jsonb_agg(DISTINCT cliente ORDER BY cliente) AS val
        FROM vendas_geral WHERE cliente != '' AND cliente != 'EMPRESA DEMO LTDA'
    )
    SELECT jsonb_build_object(
        'empresas', COALESCE((SELECT val FROM f_emp), '[]'::jsonb),
        'anos', COALESCE((SELECT val FROM f_anos), '[]'::jsonb),
        'produtos', COALESCE((SELECT val FROM f_prod), '[]'::jsonb),
        'clientes', COALESCE((SELECT val FROM f_clientes), '[]'::jsonb)
    ) INTO v_filtros;

    -- Q15: Caixas por UF para Mapa
    WITH total_nacional AS (
        SELECT ROUND(SUM(qtd_caixas::numeric))::INT AS total
        FROM vendas_geral WHERE 1=1
          AND (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND cliente != 'EMPRESA DEMO LTDA'
    ),
    uf_agg AS (
        SELECT uf,
            ROUND(SUM(qtd_caixas::numeric))::INT AS caixas,
            COUNT(DISTINCT numero_nota || '_' || empresa)::INT AS notas,
            ROUND(SUM(qtd_caixas::numeric) * 100.0 / NULLIF((SELECT total FROM total_nacional), 0), 2) AS porcentagem
        FROM vendas_geral
        WHERE 1=1
          AND (p_empresa IS NULL OR empresa = p_empresa)
          AND (p_natureza IS NULL OR natureza_operacao LIKE '%' || p_natureza || '%')
          AND (p_tipo_pessoa IS NULL OR tipo_pessoa = p_tipo_pessoa)
          AND (v_ano IS NULL OR ano = v_ano)
          AND (v_mes IS NULL OR mes = v_mes)
          AND (p_produto IS NULL OR produto IN (SELECT produto FROM produtos WHERE nomenclatura = p_produto))
          AND (p_cliente IS NULL OR p_cliente = '' OR cliente = ANY(string_to_array(p_cliente, ',')))
          AND (p_uf IS NULL OR uf = p_uf)
          AND (p_categoria IS NULL OR categoria_produto = p_categoria)
          AND (v_dia IS NULL OR dia = v_dia)
          AND (v_dia_semana IS NULL OR EXTRACT(DOW FROM data_emissao)::INT = v_dia_semana)
          AND uf != '' AND uf IS NOT NULL
          AND cliente != 'EMPRESA DEMO LTDA'
        GROUP BY uf
    )
    SELECT jsonb_build_object(
        'dados_por_uf', COALESCE(
            (SELECT jsonb_object_agg(uf, jsonb_build_object(
                'nome', CASE uf
                    WHEN 'AC' THEN 'Acre' WHEN 'AL' THEN 'Alagoas' WHEN 'AP' THEN 'Amapa'
                    WHEN 'AM' THEN 'Amazonas' WHEN 'BA' THEN 'Bahia' WHEN 'CE' THEN 'Ceara'
                    WHEN 'DF' THEN 'Distrito Federal' WHEN 'ES' THEN 'Espirito Santo'
                    WHEN 'GO' THEN 'Goias' WHEN 'MA' THEN 'Maranhao' WHEN 'MT' THEN 'Mato Grosso'
                    WHEN 'MS' THEN 'Mato Grosso do Sul' WHEN 'MG' THEN 'Minas Gerais'
                    WHEN 'PA' THEN 'Para' WHEN 'PB' THEN 'Paraiba' WHEN 'PR' THEN 'Parana'
                    WHEN 'PE' THEN 'Pernambuco' WHEN 'PI' THEN 'Piaui' WHEN 'RJ' THEN 'Rio de Janeiro'
                    WHEN 'RN' THEN 'Rio Grande do Norte' WHEN 'RS' THEN 'Rio Grande do Sul'
                    WHEN 'RO' THEN 'Rondonia' WHEN 'RR' THEN 'Roraima' WHEN 'SC' THEN 'Santa Catarina'
                    WHEN 'SP' THEN 'Sao Paulo' WHEN 'SE' THEN 'Sergipe' WHEN 'TO' THEN 'Tocantins'
                    ELSE uf
                END,
                'caixas', caixas,
                'porcentagem', porcentagem,
                'notas', notas
            ) ORDER BY uf) FROM uf_agg),
            '{}'::jsonb
        ),
        'max_valor', COALESCE((SELECT caixas FROM uf_agg ORDER BY caixas DESC LIMIT 1), 0)
    ) INTO v_mapa_caixas;

    -- RESPOSTA FINAL
    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'total_caixas', v_total_caixas,
            'total_litros', v_total_litros,
            'total_unidades', v_total_unidades,
            'total_notas', v_total_notas,
            'media_cx_nota', v_media_cx_nota
        ),
        'volume', COALESCE(v_volume_empresa, '{"por_empresa":{}}'::jsonb),
        'evolucao_mensal', jsonb_build_object(
            'labels', '["Jan","Fev","Mar","Abr","Mai","Jun","Jul","Ago","Set","Out","Nov","Dez"]'::jsonb,
            'data', COALESCE(v_evol_atual->'data', '[]'::jsonb),
            'data_anterior', COALESCE(v_evol_atual->'data_anterior', '[]'::jsonb),
            'ano_atual', v_ref_year
        ),
        'evolucao_diaria', jsonb_build_object(
            'labels', (SELECT jsonb_agg('D' || g) FROM generate_series(1, 31) g),
            'dias_reais', (SELECT jsonb_agg(g) FROM generate_series(1, 31) g),
            'data', COALESCE(v_evol_dia, '[]'::jsonb)
        ),
        'rank_semana', jsonb_build_object(
            'labels', '["Dom","Seg","Ter","Qua","Qui","Sex","Sab"]'::jsonb,
            'data', COALESCE(v_rank_semana, '[]'::jsonb)
        ),
        'top10', COALESCE(v_top10, '{"labels":[],"data":[]}'::jsonb),
        'market_share', COALESCE(v_market_share, '{"labels":[],"data":[]}'::jsonb),
        'vendas_uf', COALESCE(v_vendas_uf, '{"labels":[],"data":[]}'::jsonb),
        'rank_categoria', COALESCE(v_rank_cat, '{"labels":[],"data":[]}'::jsonb),
        'top20_clientes', COALESCE(v_top20, '[]'::jsonb),
        'mix_por_cliente', COALESCE(v_mix, '{}'::jsonb),
        'todos_produtos', COALESCE(v_todos_produtos, '[]'::jsonb),
        'filtros', COALESCE(v_filtros, '{"empresas":[],"anos":[],"produtos":[],"clientes":[]}'::jsonb),
        'transacoes_recentes', COALESCE(v_transacoes, '[]'::jsonb),
        'mapa_caixas', COALESCE(v_mapa_caixas, '{"dados_por_uf":{},"max_valor":0}'::jsonb)
    );
END;
$func$;
