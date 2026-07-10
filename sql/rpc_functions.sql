--========================================
-- rpc_functions.sql
-- Descrição:
-- Criado por: Silvano Moraes de Souza
--========================================
--   supabase.rpc('get_vendas_uf', { empresa, tipo_pessoa, ano, mes })
-- ============================================================

-- ============================================================
-- FUNCAO 1: get_dashboard_completo (Financeiro)
-- Retorna JSON identico ao /api/dados do Flask
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
AS $$
DECLARE
    v_ano INT;
    v_mes INT;
    v_dia INT;
    v_dia_semana INT;
    v_ref_year INT;
    v_where_parts TEXT[];
    v_filter TEXT;
    -- KPIs
    v_faturamento NUMERIC;
    v_custo_total NUMERIC;
    v_total_notas INT;
    v_total_caixas NUMERIC;
    -- Evolucao Mensal
    v_evol_mes JSONB;
    v_evol_atual JSONB;
    v_evol_anterior JSONB;
    -- Evolucao Diaria
    v_evol_dia JSONB;
    -- Rank Semana
    v_rank_semana JSONB;
    -- Top 10
    v_top10 JSONB;
    -- Market Share
    v_market_share JSONB;
    -- Vendas UF
    v_vendas_uf JSONB;
    -- Rank Categoria
    v_rank_cat JSONB;
    -- PM
    v_pm JSONB;
    -- Transacoes
    v_transacoes JSONB;
    -- Top 20 Clientes
    v_top20 JSONB;
    -- Mix por Cliente
    v_mix JSONB;
    -- Rentabilidade
    v_rentabilidade JSONB;
    -- Margem Mensal
    v_margem_mensal JSONB;
    -- Produtos
    v_todos_produtos JSONB;
    -- Filtros disponiveis
    v_filtros JSONB;
    -- ano maximo fallback
    v_temp RECORD;
BEGIN
    -- Converte parametros para tipos corretos
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;
    v_dia := NULLIF(p_dia, '')::INT;
    v_dia_semana := NULLIF(p_dia_semana, '')::INT;

    -- Ano de referencia (max ou informado)
    IF v_ano IS NOT NULL THEN
        v_ref_year := v_ano;
    ELSE
        SELECT MAX(ano) INTO v_ref_year FROM vendas_geral;
    END IF;

    -- ============================================================
    -- BUILD WHERE CLAUSE
    -- ============================================================
    v_where_parts := ARRAY['1=1'];
    v_where_parts := array_append(v_where_parts, 'cliente != ''EMPRESA DEMO LTDA''');

    IF p_empresa IS NOT NULL AND p_empresa != '' THEN
        v_where_parts := array_append(v_where_parts, format('empresa = %L', p_empresa));
    END IF;
    IF p_natureza IS NOT NULL AND p_natureza != '' THEN
        v_where_parts := array_append(v_where_parts, format('natureza_operacao LIKE ''%%%s%%''', replace(p_natureza, '''', '''''')) );
    END IF;
    IF p_tipo_pessoa IS NOT NULL AND p_tipo_pessoa != '' THEN
        v_where_parts := array_append(v_where_parts, format('tipo_pessoa = %L', p_tipo_pessoa));
    END IF;
    IF v_ano IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('ano = %s', v_ano));
    END IF;
    IF v_mes IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('mes = %s', v_mes));
    END IF;
    IF p_produto IS NOT NULL AND p_produto != '' THEN
        v_where_parts := array_append(v_where_parts, format('produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = %L)', p_produto));
    END IF;
    IF p_cliente IS NOT NULL AND p_cliente != '' THEN
        IF p_cliente = '__NONE__' THEN
            v_where_parts := array_append(v_where_parts, '1=0');
        ELSE
            v_where_parts := array_append(v_where_parts, format('cliente = ANY(ARRAY[%s])', 
                (SELECT string_agg(format('%L', trim(c)), ',') FROM unnest(string_to_array(p_cliente, ',')) c WHERE trim(c) != '')));
        END IF;
    END IF;
    IF p_uf IS NOT NULL AND p_uf != '' THEN
        v_where_parts := array_append(v_where_parts, format('uf = %L', p_uf));
    END IF;
    IF p_categoria IS NOT NULL AND p_categoria != '' THEN
        v_where_parts := array_append(v_where_parts, format('categoria_produto = %L', p_categoria));
    END IF;
    IF v_dia IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('dia = %s', v_dia));
    END IF;
    IF v_dia_semana IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('dia_semana = %s', v_dia_semana));
    END IF;

    v_filter := array_to_string(v_where_parts, ' AND ');

    -- ============================================================
    -- Q1: KPIs
    -- ============================================================
    EXECUTE format('
        SELECT
            COALESCE(SUM(val_item), 0) AS faturamento,
            COALESCE(ROUND(SUM(qtd_caixas * uni_cx_produto * COALESCE(
                (SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto)), 0
            )), 2), 0) AS custo_total,
            COUNT(DISTINCT numero_nota || ''_'' || empresa) AS total_notas,
            COALESCE(SUM(qtd_caixas), 0) AS total_caixas
        FROM vendas_geral v
        WHERE %s', v_filter)
    INTO v_faturamento, v_custo_total, v_total_notas, v_total_caixas;

    -- ============================================================
    -- Q2: Evolucao Mensal (ano atual vs anterior)
    -- ============================================================
    -- Remove o filtro de ano
    DECLARE
        v_no_year TEXT[];
        v_evol JSONB;
    BEGIN
        v_no_year := (SELECT array_agg(p) FROM unnest(v_where_parts) p WHERE p NOT LIKE 'ano =%');
        IF v_no_year IS NULL THEN
            v_no_year := ARRAY['1=1'];
        END IF;

        EXECUTE format('
            SELECT jsonb_build_object(
                ''ano_atual'', %s,
                ''labels'', ''[%s]''::TEXT,
                ''data'', COALESCE(jsonb_agg(CASE WHEN ano = %s THEN valor ELSE 0 END ORDER BY mes), ''[]''::jsonb),
                ''data_anterior'', COALESCE(jsonb_agg(CASE WHEN ano = %s THEN valor ELSE 0 END ORDER BY mes), ''[]''::jsonb)
            )
            FROM (
                SELECT ano, mes, SUM(val_item) AS valor
                FROM vendas_geral
                WHERE %s AND ano IN (%s, %s)
                GROUP BY ano, mes
            ) sub',
            v_ref_year,
            'Jan,Fev,Mar,Abr,Mai,Jun,Jul,Ago,Set,Out,Nov,Dez',
            v_ref_year,
            v_ref_year - 1,
            array_to_string(v_no_year, ' AND '),
            v_ref_year,
            v_ref_year - 1
        ) INTO v_evol;
        v_evol_atual := COALESCE(v_evol->'data', '[]'::jsonb);
        v_evol_anterior := COALESCE(v_evol->'data_anterior', '[]'::jsonb);
    END;

    -- ============================================================
    -- Q3: Evolucao Diaria
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(COALESCE(d.valor, 0) ORDER BY d.dia), ''[]''::jsonb)
        FROM generate_series(1, 31) d(dia)
        LEFT JOIN (
            SELECT dia, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s
            GROUP BY dia
        ) sub ON d.dia = sub.dia',
        v_filter
    ) INTO v_evol_dia;

    -- ============================================================
    -- Q4: Rank Dia da Semana
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(COALESCE(d.valor, 0) ORDER BY d.dia_semana), ''[]''::jsonb)
        FROM generate_series(0, 6) d(dia_semana)
        LEFT JOIN (
            SELECT EXTRACT(DOW FROM data_emissao)::INT AS dia_semana, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s
            GROUP BY EXTRACT(DOW FROM data_emissao)::INT
        ) sub ON d.dia_semana = sub.dia_semana',
        v_filter
    ) INTO v_rank_semana;

    -- ============================================================
    -- Q5: Top 10 Produtos
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(produto ORDER BY valor DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(valor ORDER BY valor DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT COALESCE(produto, ''N/A'') AS produto, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s
            GROUP BY produto
            ORDER BY valor DESC
            LIMIT 10
        ) sub',
        v_filter
    ) INTO v_top10;

    -- ============================================================
    -- Q6: Market Share
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(empresa ORDER BY valor DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(valor ORDER BY valor DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT empresa, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s
            GROUP BY empresa
            ORDER BY valor DESC
        ) sub',
        v_filter
    ) INTO v_market_share;

    -- ============================================================
    -- Q7: Vendas por UF
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(uf ORDER BY valor DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(valor ORDER BY valor DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT uf, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s AND uf != '''' AND uf IS NOT NULL
            GROUP BY uf
            ORDER BY valor DESC
        ) sub',
        v_filter
    ) INTO v_vendas_uf;

    -- ============================================================
    -- Q8: Rank Categoria
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(categoria ORDER BY valor DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(valor ORDER BY valor DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT categoria_produto AS categoria, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE %s
            GROUP BY categoria_produto
            ORDER BY valor DESC
        ) sub',
        v_filter
    ) INTO v_rank_cat;

    -- ============================================================
    -- Q9: PM por Empresa (ultimos 12 meses)
    -- ============================================================
    EXECUTE format('
        WITH pm_data AS (
            SELECT empresa,
                SUM(val_item) AS valor,
                SUM(qtd_caixas) AS qtd_caixas
            FROM vendas_geral
            WHERE data_emissao >= CURRENT_DATE - INTERVAL ''12 months''
                AND %s
            GROUP BY empresa
        ),
        total_fat AS (
            SELECT SUM(valor) AS total FROM pm_data
        )
        SELECT jsonb_build_object(
            ''ponderado'', COALESCE((SELECT
                SUM((valor / NULLIF(qtd_caixas, 0)) * (valor / NULLIF((SELECT total FROM total_fat), 0)))
                FROM pm_data WHERE qtd_caixas > 0), 0),
            ''por_empresa'', COALESCE(
                (SELECT jsonb_object_agg(empresa, jsonb_build_object(
                    ''preco_medio'', ROUND(COALESCE(valor / NULLIF(qtd_caixas, 0), 0), 2),
                    ''faturamento_12m'', ROUND(valor, 2),
                    ''qtd_caixas_12m'', qtd_caixas,
                    ''share_12m'', ROUND(COALESCE(valor * 100.0 / NULLIF((SELECT total FROM total_fat), 0), 0), 2)
                ))
                FROM pm_data),
                ''{}''::jsonb
            )
        )',
        v_filter
    ) INTO v_pm;

    -- ============================================================
    -- Q10: Transacoes Recentes
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(sub ORDER BY sub.data_emissao DESC, sub.numero_nota DESC), ''[]''::jsonb)
        FROM (
            SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
                   val_item, empresa, nomenclatura, categoria_produto, ano, mes
            FROM vendas_geral
            WHERE %s
            ORDER BY data_emissao DESC, numero_nota DESC
            LIMIT 100
        ) sub',
        v_filter
    ) INTO v_transacoes;

    -- ============================================================
    -- Q11: Top 30 Clientes
    -- ============================================================
    EXECUTE format('
        WITH total_geral AS (
            SELECT SUM(val_item) AS total FROM vendas_geral WHERE %s AND cliente != '''' AND cliente IS NOT NULL
        )
        SELECT COALESCE(jsonb_agg(sub ORDER BY sub.valor DESC), ''[]''::jsonb)
        FROM (
            SELECT
                cliente,
                ROUND(SUM(val_item), 2) AS valor,
                COUNT(DISTINCT numero_nota || ''_'' || empresa) AS notas,
                SUM(qtd_caixas) AS caixas,
                ROUND(SUM(val_item) * 100.0 / NULLIF((SELECT total FROM total_geral), 0), 2) AS porcentagem
            FROM vendas_geral
            WHERE %s AND cliente != '''' AND cliente IS NOT NULL
            GROUP BY cliente
            ORDER BY valor DESC
            LIMIT 30
        ) sub',
        v_filter, v_filter
    ) INTO v_top20;

    -- ============================================================
    -- Q12: Mix de Produtos por Cliente (top 20)
    -- ============================================================
    DECLARE
        v_top_nomes TEXT[];
    BEGIN
        SELECT ARRAY(SELECT cliente FROM (
            SELECT cliente
            FROM vendas_geral WHERE %s AND cliente != '''' AND cliente IS NOT NULL
            GROUP BY cliente ORDER BY SUM(val_item) DESC LIMIT 30
        ) t) INTO v_top_nomes;

        IF v_top_nomes IS NOT NULL AND array_length(v_top_nomes, 1) > 0 THEN
            EXECUTE format('
                SELECT COALESCE(jsonb_object_agg(cliente, produtos), ''{}''::jsonb)
                FROM (
                    SELECT cliente, jsonb_agg(jsonb_build_object(
                        ''produto'', produto,
                        ''categoria'', COALESCE(categoria_produto, ''''),
                        ''valor'', ROUND(SUM(val_item), 2),
                        ''caixas'', ROUND(SUM(qtd_caixas))::INT,
                        ''unidades'', ROUND(SUM(quantidade))::INT
                    ) ORDER BY SUM(val_item) DESC) AS produtos
                    FROM vendas_geral
                    WHERE %s AND cliente = ANY(%L::TEXT[])
                    GROUP BY cliente
                ) sub',
                v_filter, v_filter, v_top_nomes
            ) INTO v_mix;
        ELSE
            v_mix := '{}'::jsonb;
        END IF;
    END;

    -- ============================================================
    -- Q13: Todos os Produtos
    -- ============================================================
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'produto', produto,
        'categoria', COALESCE(categoria, ''),
        'nomenclatura', COALESCE(nomenclatura, produto)
    ) ORDER BY produto), '[]'::jsonb)
    INTO v_todos_produtos
    FROM produtos
    WHERE produto != '';

    -- ============================================================
    -- Q14-17: Filtros Disponiveis
    -- ============================================================
    WITH filtros_empresas AS (
        SELECT jsonb_agg(DISTINCT empresa ORDER BY empresa) AS val FROM vendas_geral
    ),
    filtros_anos AS (
        SELECT jsonb_agg(DISTINCT ano ORDER BY ano DESC) AS val FROM vendas_geral
    ),
    filtros_produtos AS (
        SELECT jsonb_agg(DISTINCT COALESCE(nomenclatura, produto) ORDER BY COALESCE(nomenclatura, produto)) AS val
        FROM produtos WHERE produto != ''
    ),
    filtros_clientes AS (
        SELECT jsonb_agg(DISTINCT cliente ORDER BY cliente) AS val
        FROM vendas_geral WHERE cliente != '' AND cliente != 'EMPRESA DEMO LTDA'
    )
    SELECT jsonb_build_object(
        'empresas', COALESCE((SELECT val FROM filtros_empresas), '[]'::jsonb),
        'anos', COALESCE((SELECT val FROM filtros_anos), '[]'::jsonb),
        'produtos', COALESCE((SELECT val FROM filtros_produtos), '[]'::jsonb),
        'clientes', COALESCE((SELECT val FROM filtros_clientes), '[]'::jsonb)
    ) INTO v_filtros;

    -- ============================================================
    -- Q18: Rentabilidade por Cliente (top 400)
    -- ============================================================
    EXECUTE format('
        WITH rent AS (
            SELECT
                v.cliente,
                ROUND(SUM(v.val_item), 2) AS receita,
                ROUND(SUM(v.qtd_caixas * v.uni_cx_produto * COALESCE(
                    (SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto)), 0
                )), 2) AS custo,
                COUNT(DISTINCT v.numero_nota || ''_'' || v.empresa) AS pedidos
            FROM vendas_geral v
            WHERE %s
            GROUP BY v.cliente
            ORDER BY receita DESC
            LIMIT 400
        )
        SELECT jsonb_build_object(
            ''clientes'', COALESCE(
                (SELECT jsonb_agg(jsonb_build_object(
                    ''cliente'', cliente,
                    ''receita'', receita,
                    ''custo'', custo,
                    ''lucro'', ROUND(receita - custo, 2),
                    ''margem'', CASE WHEN receita > 0 THEN ROUND((receita - custo) / receita * 100, 1) ELSE 0 END,
                    ''pedidos'', pedidos,
                    ''ticket_medio'', ROUND(receita / NULLIF(pedidos, 0), 2)
                ) ORDER BY receita DESC)
                FROM rent),
                ''[]''::jsonb
            ),
            ''mediana_receita'', COALESCE((SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY receita) FROM rent), 0),
            ''mediana_margem'', COALESCE((SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY
                CASE WHEN receita > 0 THEN (receita - custo) / receita * 100 ELSE 0 END
            ) FROM rent), 0)
        )',
        v_filter
    ) INTO v_rentabilidade;

    -- ============================================================
    -- Q19: Margem Mensal
    -- ============================================================
    DECLARE
        v_margem_where TEXT;
    BEGIN
        v_margem_where := v_filter;
        -- Se tiver cliente com nome longo, ignore (nao temos parametro cliente_margem separado)

        EXECUTE format('
            SELECT COALESCE(jsonb_agg(
                CASE WHEN receita > 0 THEN ROUND((receita - custo) / receita * 100, 1) ELSE NULL END
                ORDER BY mes
            ), ''[]''::jsonb)
            FROM (
                SELECT mes,
                    ROUND(SUM(val_item), 2) AS receita,
                    ROUND(SUM(qtd_caixas * uni_cx_produto * COALESCE(
                        (SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(produto)), 0
                    )), 2) AS custo
                FROM vendas_geral
                WHERE %s
                GROUP BY mes
                ORDER BY mes
            ) sub',
            v_margem_where
        ) INTO v_margem_mensal;
    END;

    -- ============================================================
    -- MONTA RESPOSTA FINAL
    -- ============================================================
    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'faturamento', ROUND(v_faturamento, 2),
            'lucro_estimado', ROUND(v_faturamento * 0.15, 2),
            'custo_total', ROUND(v_custo_total, 2),
            'custo_percentual', CASE WHEN v_faturamento > 0 THEN ROUND(v_custo_total / v_faturamento * 100, 2) ELSE 0 END,
            'ticket_medio', CASE WHEN v_total_caixas > 0 THEN ROUND(v_faturamento / 12 / v_total_caixas, 2) ELSE 0 END,
            'total_notas', v_total_notas,
            'total_caixas', ROUND(v_total_caixas)
        ),
        'pm', COALESCE(v_pm, '{"ponderado":0,"por_empresa":{}}'::jsonb),
        'evolucao_mensal', jsonb_build_object(
            'labels', '["Jan","Fev","Mar","Abr","Mai","Jun","Jul","Ago","Set","Out","Nov","Dez"]',
            'data', COALESCE(v_evol_atual, '[]'::jsonb),
            'data_anterior', COALESCE(v_evol_anterior, '[]'::jsonb),
            'ano_atual', v_ref_year
        ),
        'evolucao_diaria', jsonb_build_object(
            'labels', COALESCE((SELECT jsonb_agg('D' || g) FROM generate_series(1, 31) g), '[]'::jsonb),
            'dias_reais', COALESCE((SELECT jsonb_agg(g) FROM generate_series(1, 31) g), '[]'::jsonb),
            'data', COALESCE(v_evol_dia, '[]'::jsonb)
        ),
        'rank_semana', jsonb_build_object(
            'labels', '["Dom","Seg","Ter","Qua","Qui","Sex","Sab"]',
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
$$;

-- ============================================================
-- FUNCAO 2: get_vendas_volume (Vendas)
-- Retorna JSON identico ao /api/vendas do Flask
-- ============================================================
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
AS $$
DECLARE
    v_ano INT;
    v_mes INT;
    v_dia INT;
    v_dia_semana INT;
    v_ref_year INT;
    v_where_parts TEXT[];
    v_filter TEXT;
    -- KPIs
    v_total_caixas INT;
    v_total_litros NUMERIC;
    v_total_unidades INT;
    v_total_notas INT;
    v_media_cx_nota NUMERIC;
    -- Evolucao
    v_evol_atual JSONB;
    v_evol_anterior JSONB;
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
BEGIN
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;
    v_dia := NULLIF(p_dia, '')::INT;
    v_dia_semana := NULLIF(p_dia_semana, '')::INT;

    IF v_ano IS NOT NULL THEN
        v_ref_year := v_ano;
    ELSE
        SELECT MAX(ano) INTO v_ref_year FROM vendas_geral;
    END IF;

    -- Build WHERE
    v_where_parts := ARRAY['1=1'];
    v_where_parts := array_append(v_where_parts, 'cliente != ''EMPRESA DEMO LTDA''');

    IF p_empresa IS NOT NULL AND p_empresa != '' THEN
        v_where_parts := array_append(v_where_parts, format('empresa = %L', p_empresa));
    END IF;
    IF p_natureza IS NOT NULL AND p_natureza != '' THEN
        v_where_parts := array_append(v_where_parts, format('natureza_operacao LIKE ''%%%s%%''', replace(p_natureza, '''', '''''')) );
    END IF;
    IF p_tipo_pessoa IS NOT NULL AND p_tipo_pessoa != '' THEN
        v_where_parts := array_append(v_where_parts, format('tipo_pessoa = %L', p_tipo_pessoa));
    END IF;
    IF v_ano IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('ano = %s', v_ano));
    END IF;
    IF v_mes IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('mes = %s', v_mes));
    END IF;
    IF p_produto IS NOT NULL AND p_produto != '' THEN
        v_where_parts := array_append(v_where_parts, format('produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = %L)', p_produto));
    END IF;
    IF p_cliente IS NOT NULL AND p_cliente != '' THEN
        IF p_cliente = '__NONE__' THEN
            v_where_parts := array_append(v_where_parts, '1=0');
        ELSE
            v_where_parts := array_append(v_where_parts, format('cliente = ANY(ARRAY[%s])',
                (SELECT string_agg(format('%L', trim(c)), ',') FROM unnest(string_to_array(p_cliente, ',')) c WHERE trim(c) != '')));
        END IF;
    END IF;
    IF p_uf IS NOT NULL AND p_uf != '' THEN
        v_where_parts := array_append(v_where_parts, format('uf = %L', p_uf));
    END IF;
    IF p_categoria IS NOT NULL AND p_categoria != '' THEN
        v_where_parts := array_append(v_where_parts, format('categoria_produto = %L', p_categoria));
    END IF;
    IF v_dia IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('dia = %s', v_dia));
    END IF;
    IF v_dia_semana IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('dia_semana = %s', v_dia_semana));
    END IF;

    v_filter := array_to_string(v_where_parts, ' AND ');

    -- ============================================================
    -- Q1: KPIs Volume
    -- ============================================================
    EXECUTE format('
        SELECT
            COALESCE(ROUND(SUM(qtd_caixas))::INT, 0),
            COALESCE(ROUND(SUM(litros_produto)), 0),
            COALESCE(ROUND(SUM(quantidade))::INT, 0),
            COALESCE(COUNT(DISTINCT numero_nota || ''_'' || empresa)::INT, 0)
        FROM vendas_geral
        WHERE %s', v_filter)
    INTO v_total_caixas, v_total_litros, v_total_unidades, v_total_notas;

    v_media_cx_nota := CASE WHEN v_total_notas > 0 THEN ROUND(v_total_caixas::NUMERIC / v_total_notas, 1) ELSE 0 END;

    -- ============================================================
    -- Q2: Evolucao Mensal Caixas
    -- ============================================================
    DECLARE
        v_no_year TEXT[];
    BEGIN
        v_no_year := (SELECT array_agg(p) FROM unnest(v_where_parts) p WHERE p NOT LIKE 'ano =%');
        IF v_no_year IS NULL THEN v_no_year := ARRAY['1=1']; END IF;

        EXECUTE format('
            SELECT jsonb_build_object(
                ''data'', COALESCE(jsonb_agg(CASE WHEN ano = %s THEN caixas ELSE 0 END ORDER BY mes), ''[]''::jsonb),
                ''data_anterior'', COALESCE(jsonb_agg(CASE WHEN ano = %s THEN caixas ELSE 0 END ORDER BY mes), ''[]''::jsonb)
            )
            FROM (
                SELECT ano, mes, ROUND(SUM(qtd_caixas))::INT AS caixas
                FROM vendas_geral
                WHERE %s AND ano IN (%s, %s)
                GROUP BY ano, mes
            ) sub',
            v_ref_year, v_ref_year - 1,
            array_to_string(v_no_year, ' AND '),
            v_ref_year, v_ref_year - 1
        ) INTO v_evol_atual; -- this is actually both
    END;

    -- ============================================================
    -- Q3: Evolucao Diaria Caixas
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(COALESCE(d.caixas, 0) ORDER BY d.dia), ''[]''::jsonb)
        FROM generate_series(1, 31) d(dia)
        LEFT JOIN (
            SELECT dia, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s
            GROUP BY dia
        ) sub ON d.dia = sub.dia', v_filter
    ) INTO v_evol_dia;

    -- ============================================================
    -- Q4: Rank Semana Caixas
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(COALESCE(d.caixas, 0) ORDER BY d.dia_semana), ''[]''::jsonb)
        FROM generate_series(0, 6) d(dia_semana)
        LEFT JOIN (
            SELECT EXTRACT(DOW FROM data_emissao)::INT AS dia_semana, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s
            GROUP BY EXTRACT(DOW FROM data_emissao)::INT
        ) sub ON d.dia_semana = sub.dia_semana', v_filter
    ) INTO v_rank_semana;

    -- ============================================================
    -- Q5: Top 10 Produtos (Caixas)
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(produto ORDER BY caixas DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT COALESCE(produto, ''N/A'') AS produto, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s
            GROUP BY produto ORDER BY caixas DESC LIMIT 10
        ) sub', v_filter
    ) INTO v_top10;

    -- ============================================================
    -- Q6: Market Share (Caixas)
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(empresa ORDER BY caixas DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT empresa, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s
            GROUP BY empresa ORDER BY caixas DESC
        ) sub', v_filter
    ) INTO v_market_share;

    -- ============================================================
    -- Q7: Caixas por UF
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(uf ORDER BY caixas DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT uf, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s AND uf != '''' AND uf IS NOT NULL
            GROUP BY uf ORDER BY caixas DESC
        ) sub', v_filter
    ) INTO v_vendas_uf;

    -- ============================================================
    -- Q8: Rank Categoria (Caixas)
    -- ============================================================
    EXECUTE format('
        SELECT jsonb_build_object(
            ''labels'', COALESCE(jsonb_agg(categoria ORDER BY caixas DESC), ''[]''::jsonb),
            ''data'', COALESCE(jsonb_agg(caixas ORDER BY caixas DESC), ''[]''::jsonb)
        )
        FROM (
            SELECT categoria_produto AS categoria, ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral WHERE %s
            GROUP BY categoria_produto ORDER BY caixas DESC
        ) sub', v_filter
    ) INTO v_rank_cat;

    -- ============================================================
    -- Q9: Volume por Empresa (12m)
    -- ============================================================
    EXECUTE format('
        WITH vol_data AS (
            SELECT empresa,
                ROUND(SUM(litros_produto), 1) AS litros,
                ROUND(SUM(qtd_caixas))::INT AS caixas
            FROM vendas_geral
            WHERE data_emissao >= CURRENT_DATE - INTERVAL ''12 months'' AND %s
            GROUP BY empresa
        ),
        total_cx AS (SELECT SUM(caixas) AS total FROM vol_data)
        SELECT COALESCE(
            (SELECT jsonb_object_agg(empresa, jsonb_build_object(
                ''caixas_12m'', caixas,
                ''litros_12m'', litros,
                ''share_12m'', ROUND(COALESCE(caixas * 100.0 / NULLIF((SELECT total FROM total_cx), 0), 0), 2)
            )) FROM vol_data),
            ''{}''::jsonb
        )', v_filter
    ) INTO v_volume_empresa;

    -- ============================================================
    -- Q10: Transacoes Recentes
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(sub ORDER BY sub.data_emissao DESC, sub.numero_nota DESC), ''[]''::jsonb)
        FROM (
            SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
                   val_item, empresa, nomenclatura, categoria_produto, ano, mes,
                   ROUND(qtd_caixas)::INT AS qtd_caixas,
                   ROUND(litros_produto, 1) AS litros_produto,
                   ROUND(quantidade)::INT AS quantidade,
                   uni_cx_produto::INT
            FROM vendas_geral
            WHERE %s
            ORDER BY data_emissao DESC, numero_nota DESC
            LIMIT 100
        ) sub', v_filter
    ) INTO v_transacoes;

    -- ============================================================
    -- Q11: Top 30 Clientes por Caixas
    -- ============================================================
    EXECUTE format('
        SELECT COALESCE(jsonb_agg(sub ORDER BY sub.caixas DESC), ''[]''::jsonb)
        FROM (
            SELECT
                cliente,
                ROUND(SUM(qtd_caixas))::INT AS caixas,
                COUNT(DISTINCT numero_nota || ''_'' || empresa)::INT AS notas,
                ROUND(SUM(val_item), 2) AS valor
            FROM vendas_geral
            WHERE %s AND cliente != '''' AND cliente IS NOT NULL
            GROUP BY cliente
            ORDER BY caixas DESC
            LIMIT 30
        ) sub', v_filter
    ) INTO v_top20;

    -- ============================================================
    -- Q12: Mix de Produtos por Cliente
    -- ============================================================
    DECLARE
        v_top_nomes TEXT[];
    BEGIN
        SELECT ARRAY(SELECT cliente FROM (
            SELECT cliente
            FROM vendas_geral WHERE %s AND cliente != '''' AND cliente IS NOT NULL
            GROUP BY cliente ORDER BY ROUND(SUM(qtd_caixas))::INT DESC LIMIT 30
        ) t) INTO v_top_nomes;

        IF v_top_nomes IS NOT NULL AND array_length(v_top_nomes, 1) > 0 THEN
            EXECUTE format('
                SELECT COALESCE(jsonb_object_agg(cliente, produtos), ''{}''::jsonb)
                FROM (
                    SELECT cliente, jsonb_agg(jsonb_build_object(
                        ''produto'', produto,
                        ''categoria'', COALESCE(categoria_produto, ''''),
                        ''valor'', ROUND(SUM(val_item), 2),
                        ''caixas'', ROUND(SUM(qtd_caixas))::INT,
                        ''unidades'', ROUND(SUM(quantidade))::INT
                    ) ORDER BY SUM(qtd_caixas) DESC) AS produtos
                    FROM vendas_geral
                    WHERE %s AND cliente = ANY(%L::TEXT[])
                    GROUP BY cliente
                ) sub',
                v_filter, v_filter, v_top_nomes
            ) INTO v_mix;
        ELSE
            v_mix := '{}'::jsonb;
        END IF;
    END;

    -- ============================================================
    -- Q13: Produtos (sem nomenclatura)
    -- ============================================================
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'produto', produto,
        'categoria', COALESCE(categoria, '')
    ) ORDER BY produto), '[]'::jsonb)
    INTO v_todos_produtos
    FROM produtos WHERE produto != '';

    -- ============================================================
    -- Filtros
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
    -- Mapa Caixas por UF
    -- ============================================================
    EXECUTE format('
        WITH total_nacional AS (
            SELECT ROUND(SUM(qtd_caixas))::INT AS total
            FROM vendas_geral WHERE %s
        )
        SELECT jsonb_build_object(
            ''dados_por_uf'', COALESCE(
                (SELECT jsonb_object_agg(uf, jsonb_build_object(
                    ''nome'', CASE uf
                        WHEN ''AC'' THEN ''Acre'' WHEN ''AL'' THEN ''Alagoas'' WHEN ''AP'' THEN ''Amapa'' WHEN ''AM'' THEN ''Amazonas''
                        WHEN ''BA'' THEN ''Bahia'' WHEN ''CE'' THEN ''Ceara'' WHEN ''DF'' THEN ''Distrito Federal'' WHEN ''ES'' THEN ''Espirito Santo''
                        WHEN ''GO'' THEN ''Goias'' WHEN ''MA'' THEN ''Maranhao'' WHEN ''MT'' THEN ''Mato Grosso'' WHEN ''MS'' THEN ''Mato Grosso do Sul''
                        WHEN ''MG'' THEN ''Minas Gerais'' WHEN ''PA'' THEN ''Para'' WHEN ''PB'' THEN ''Paraiba'' WHEN ''PR'' THEN ''Parana''
                        WHEN ''PE'' THEN ''Pernambuco'' WHEN ''PI'' THEN ''Piaui'' WHEN ''RJ'' THEN ''Rio de Janeiro'' WHEN ''RN'' THEN ''Rio Grande do Norte''
                        WHEN ''RS'' THEN ''Rio Grande do Sul'' WHEN ''RO'' THEN ''Rondonia'' WHEN ''RR'' THEN ''Roraima'' WHEN ''SC'' THEN ''Santa Catarina''
                        WHEN ''SP'' THEN ''Sao Paulo'' WHEN ''SE'' THEN ''Sergipe'' WHEN ''TO'' THEN ''Tocantins'' ELSE uf
                    END,
                    ''caixas'', ROUND(SUM(qtd_caixas))::INT,
                    ''notas'', COUNT(DISTINCT numero_nota || ''_'' || empresa)::INT,
                    ''porcentagem'', ROUND(COALESCE(SUM(qtd_caixas) * 100.0 / NULLIF((SELECT total FROM total_nacional), 0), 0), 2)
                ) ORDER BY uf)
                FROM vendas_geral
                WHERE %s AND uf != '''' AND uf IS NOT NULL
                GROUP BY uf),
                ''{}''::jsonb
            ),
            ''max_valor'', COALESCE(
                (SELECT ROUND(SUM(qtd_caixas))::INT FROM vendas_geral WHERE %s AND uf != '''' AND uf IS NOT NULL
                 GROUP BY uf ORDER BY SUM(qtd_caixas) DESC LIMIT 1),
                0
            )
        )', v_filter, v_filter, v_filter
    ) INTO v_mapa_caixas;

    -- ============================================================
    -- MONTA RESPOSTA
    -- ============================================================
    RETURN jsonb_build_object(
        'kpis', jsonb_build_object(
            'total_caixas', v_total_caixas,
            'total_litros', v_total_litros,
            'total_unidades', v_total_unidades,
            'total_notas', v_total_notas,
            'media_cx_nota', v_media_cx_nota
        ),
        'volume', jsonb_build_object(
            'por_empresa', COALESCE(v_volume_empresa, '{}'::jsonb)
        ),
        'evolucao_mensal', jsonb_build_object(
            'labels', '["Jan","Fev","Mar","Abr","Mai","Jun","Jul","Ago","Set","Out","Nov","Dez"]',
            'data', COALESCE(v_evol_atual->'data', '[]'::jsonb),
            'data_anterior', COALESCE(v_evol_atual->'data_anterior', '[]'::jsonb),
            'ano_atual', v_ref_year
        ),
        'evolucao_diaria', jsonb_build_object(
            'labels', COALESCE((SELECT jsonb_agg('D' || g) FROM generate_series(1, 31) g), '[]'::jsonb),
            'dias_reais', COALESCE((SELECT jsonb_agg(g) FROM generate_series(1, 31) g), '[]'::jsonb),
            'data', COALESCE(v_evol_dia, '[]'::jsonb)
        ),
        'rank_semana', jsonb_build_object(
            'labels', '["Dom","Seg","Ter","Qua","Qui","Sex","Sab"]',
            'data', COALESCE(v_rank_semana, '[]'::jsonb)
        ),
        'top10', COALESCE(v_top10, '{"labels":[],"data":[]}'::jsonb),
        'market_share', COALESCE(v_market_share, '{"labels":[],"data":[]}'::jsonb),
        'vendas_uf', COALESCE(v_vendas_uf, '{"labels":[],"data":[]}'::jsonb),
        'rank_categoria', COALESCE(v_rank_cat, '{"labels":[],"data":[]}'::jsonb),
        'filtros', COALESCE(v_filtros, '{"empresas":[],"anos":[],"produtos":[],"clientes":[]}'::jsonb),
        'top20_clientes', COALESCE(v_top20, '[]'::jsonb),
        'mix_por_cliente', COALESCE(v_mix, '{}'::jsonb),
        'todos_produtos', COALESCE(v_todos_produtos, '[]'::jsonb),
        'transacoes_recentes', COALESCE(v_transacoes, '[]'::jsonb),
        'mapa_caixas', COALESCE(v_mapa_caixas, '{"dados_por_uf":{},"max_valor":0}'::jsonb)
    );
END;
$$;

-- ============================================================
-- FUNCAO 3: get_vendas_uf (Mapa)
-- Aceita apenas 4 filtros (empresa, tipo_pessoa, ano, mes)
-- ============================================================
CREATE OR REPLACE FUNCTION get_vendas_uf(
    p_empresa TEXT DEFAULT NULL,
    p_tipo_pessoa TEXT DEFAULT NULL,
    p_ano TEXT DEFAULT NULL,
    p_mes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_ano INT;
    v_mes INT;
    v_filter TEXT;
    v_where_parts TEXT[];
    v_result JSONB;
BEGIN
    v_ano := NULLIF(p_ano, '')::INT;
    v_mes := NULLIF(p_mes, '')::INT;

    v_where_parts := ARRAY['1=1'];
    IF p_empresa IS NOT NULL AND p_empresa != '' THEN
        v_where_parts := array_append(v_where_parts, format('empresa = %L', p_empresa));
    END IF;
    IF p_tipo_pessoa IS NOT NULL AND p_tipo_pessoa != '' THEN
        v_where_parts := array_append(v_where_parts, format('tipo_pessoa = %L', p_tipo_pessoa));
    END IF;
    IF v_ano IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('ano = %s', v_ano));
    END IF;
    IF v_mes IS NOT NULL THEN
        v_where_parts := array_append(v_where_parts, format('mes = %s', v_mes));
    END IF;
    v_filter := array_to_string(v_where_parts, ' AND ');

    EXECUTE format('
        WITH total_nacional AS (
            SELECT SUM(val_item) AS total
            FROM vendas_geral WHERE %s
        )
        SELECT jsonb_build_object(
            ''dados_por_uf'', COALESCE(
                (SELECT jsonb_object_agg(uf, jsonb_build_object(
                    ''nome'', CASE uf
                        WHEN ''AC'' THEN ''Acre'' WHEN ''AL'' THEN ''Alagoas'' WHEN ''AP'' THEN ''Amapa'' WHEN ''AM'' THEN ''Amazonas''
                        WHEN ''BA'' THEN ''Bahia'' WHEN ''CE'' THEN ''Ceara'' WHEN ''DF'' THEN ''Distrito Federal'' WHEN ''ES'' THEN ''Espirito Santo''
                        WHEN ''GO'' THEN ''Goias'' WHEN ''MA'' THEN ''Maranhao'' WHEN ''MT'' THEN ''Mato Grosso'' WHEN ''MS'' THEN ''Mato Grosso do Sul''
                        WHEN ''MG'' THEN ''Minas Gerais'' WHEN ''PA'' THEN ''Para'' WHEN ''PB'' THEN ''Paraiba'' WHEN ''PR'' THEN ''Parana''
                        WHEN ''PE'' THEN ''Pernambuco'' WHEN ''PI'' THEN ''Piaui'' WHEN ''RJ'' THEN ''Rio de Janeiro'' WHEN ''RN'' THEN ''Rio Grande do Norte''
                        WHEN ''RS'' THEN ''Rio Grande do Sul'' WHEN ''RO'' THEN ''Rondonia'' WHEN ''RR'' THEN ''Roraima'' WHEN ''SC'' THEN ''Santa Catarina''
                        WHEN ''SP'' THEN ''Sao Paulo'' WHEN ''SE'' THEN ''Sergipe'' WHEN ''TO'' THEN ''Tocantins'' ELSE uf
                    END,
                    ''valor'', ROUND(SUM(val_item), 2),
                    ''porcentagem'', ROUND(COALESCE(SUM(val_item) * 100.0 / NULLIF((SELECT total FROM total_nacional), 0), 0), 2),
                    ''notas'', COUNT(DISTINCT numero_nota || ''_'' || empresa)::INT
                ) ORDER BY uf)
                FROM vendas_geral
                WHERE %s AND uf != '''' AND uf IS NOT NULL
                GROUP BY uf),
                ''{}''::jsonb
            ),
            ''max_valor'', COALESCE(
                (SELECT ROUND(SUM(val_item), 2) FROM vendas_geral
                 WHERE %s AND uf != '''' AND uf IS NOT NULL
                 GROUP BY uf ORDER BY SUM(val_item) DESC LIMIT 1),
                0
            ),
            ''total_geral'', COALESCE((SELECT total FROM total_nacional), 0),
            ''total_estados'', (SELECT COUNT(*) FROM (
                SELECT DISTINCT uf FROM vendas_geral WHERE %s AND uf != '''' AND uf IS NOT NULL
            ) u)
        )', v_filter, v_filter, v_filter, v_filter
    ) INTO v_result;

    RETURN v_result;
END;
$$;
