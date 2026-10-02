#========================================
# api_server.py
# Descrição:
# Criado por: Silvano Moraes de Souza
#========================================

# -*- coding: utf-8 -*-
"""
api_server.py: API Flask para o Dashboard Financeiro Dashboard Financeiro BI
Fornece endpoint JSON com dados da tabela vendas_geral.
"""

import os
import sys
import sqlite3
import json
from datetime import datetime
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

sys.stdout.reconfigure(encoding='utf-8')

load_dotenv()

DB_PATH = os.getenv("DB_PATH", "APP_financeiro.db")
API_HOST = os.getenv("API_HOST", "127.0.0.1")
API_PORT = int(os.getenv("API_PORT", "5000"))
VENDAS_TABLE = "vendas_geral"

app = Flask(__name__, static_folder='../frontend', static_url_path='')
CORS(app, origins=[
    'http://localhost:5000',
    'http://127.0.0.1:5000',
], supports_credentials=True)


@app.after_request
def add_security_headers(resp):
    resp.headers['X-Content-Type-Options'] = 'nosniff'
    resp.headers['X-Frame-Options'] = 'DENY'
    resp.headers['X-XSS-Protection'] = '1; mode=block'
    resp.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    resp.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
    resp.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self' https://cdn.jsdelivr.net https://d3js.org https://unpkg.com https://api.iconify.design; "
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
        "img-src 'self' data: https://api.iconify.design; "
        "connect-src 'self' https://api.iconify.design https://raw.githubusercontent.com; "
        "font-src 'self' data:; "
        "object-src 'none'; "
        "frame-ancestors 'none'"
    )
    if resp.mimetype in ('text/html', 'application/javascript', 'text/javascript', 'text/css'):
        resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        resp.headers['Pragma'] = 'no-cache'
        resp.headers['Expires'] = '0'
    return resp


def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def row_to_dict(row):
    return dict(row) if row else {}


# ============================================
# ENDPOINT PRINCIPAL: dados completos para dashboard
# ============================================
@app.route('/api/dados', methods=['GET'])
def get_dados():
    conn = get_connection()
    try:
        cursor = conn.cursor()

        # Filtros opcionais via query string
        empresa = request.args.get('empresa', '').strip()
        natureza = request.args.get('natureza', '').strip()
        tipo_pessoa = request.args.get('tipo_pessoa', '').strip()
        ano = request.args.get('ano', '').strip()
        mes = request.args.get('mes', '').strip()
        produto = request.args.get('produto', '').strip()
        cliente = request.args.get('cliente', '').strip()

        where_clauses = ["1=1"]
        params = []

        # Global: excluir cliente EMPRESA DEMO LTDA
        where_clauses.append("cliente != ?")
        params.append('EMPRESA DEMO LTDA')

        if empresa:
            where_clauses.append("empresa = ?")
            params.append(empresa)
        if natureza:
            where_clauses.append("natureza_operacao LIKE '%' || ? || '%'")
            params.append(natureza)
        if tipo_pessoa:
            where_clauses.append("tipo_pessoa = ?")
            params.append(tipo_pessoa)
        if ano:
            where_clauses.append("ano = ?")
            params.append(int(ano))
        if mes:
            where_clauses.append("mes = ?")
            params.append(int(mes))
        if produto:
            where_clauses.append("produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = ?)")
            params.append(produto)
        if cliente == '__NONE__':
            where_clauses.append("1=0")
        elif cliente:
            clientes_list = [c.strip() for c in cliente.split(',') if c.strip()]
            if clientes_list:
                placeholders = ','.join('?' * len(clientes_list))
                where_clauses.append(f"cliente IN ({placeholders})")
                params.extend(clientes_list)

        uf = request.args.get('uf')
        if uf:
            where_clauses.append("uf = ?")
            params.append(uf)

        categoria = request.args.get('categoria')
        if categoria:
            where_clauses.append("categoria_produto = ?")
            params.append(categoria)

        dia = request.args.get('dia')
        if dia:
            where_clauses.append("dia = ?")
            params.append(int(dia))

        dia_semana = request.args.get('dia_semana')
        if dia_semana is not None and dia_semana != '':
            where_clauses.append("CAST(strftime('%w', data_emissao) AS INTEGER) = ?")
            params.append(int(dia_semana))

        where_sql = " AND ".join(where_clauses)

        cliente_margem = request.args.get('cliente_margem')

        # --- KPIs ---
        cursor.execute(f"""
        SELECT
        SUM(vendas_geral.val_item) AS faturamento,
        ROUND(SUM(vendas_geral.qtd_caixas * vendas_geral.uni_cx_produto * COALESCE((SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(vendas_geral.produto)), 0)), 2) AS custo_total,
        COUNT(DISTINCT vendas_geral.numero_nota || '_' || vendas_geral.empresa) AS total_notas,
        SUM(vendas_geral.qtd_caixas) AS total_caixas
        FROM vendas_geral
        WHERE {where_sql}
        """, params)
        kpi_row = cursor.fetchone()
        kpis = dict(kpi_row) if kpi_row else {}
        total_notas = kpis.get('total_notas', 0) or 0
        total_caixas = kpis.get('total_caixas', 0) or 0
        faturamento = kpis.get('faturamento', 0) or 0
        custo_total = kpis.get('custo_total', 0) or 0
        ticket_medio = (faturamento / total_caixas / 12) if total_caixas > 0 else 0

        # --- Evolução Mensal (Comparativo Ano vs Ano Anterior) ---
        if ano and ano.isdigit():
            ref_year = int(ano)
        else:
            cursor.execute("SELECT MAX(ano) FROM vendas_geral")
            row = cursor.fetchone()
            ref_year = row[0] if row and row[0] else datetime.now().year

        # Filtros sem o 'ano' para permitir buscar o anterior
        where_no_year_list = [c for c in where_clauses if "ano =" not in c]
        where_no_year = " AND ".join(where_no_year_list) if where_no_year_list else "1=1"
        
        # Reconstruir params para os filtros ativos (excluindo o ano que será passado manualmente)
        # Como where_clauses e params foram construídos em ordem, vamos reconstruir a lógica:
        p_no_year = []
        p_no_year.append('EMPRESA DEMO LTDA')
        if empresa: p_no_year.append(empresa)
        if tipo_pessoa: p_no_year.append(tipo_pessoa)
        if natureza: p_no_year.append(natureza)
        if mes: p_no_year.append(int(mes))
        if produto: p_no_year.append(produto)
        if cliente and cliente != '__NONE__':
            p_no_year.extend([c.strip() for c in cliente.split(',') if c.strip()])
        if uf: p_no_year.append(uf)
        if categoria: p_no_year.append(categoria)
        if dia: p_no_year.append(int(dia))
        if dia_semana is not None and dia_semana != '': p_no_year.append(int(dia_semana))

        cursor.execute(f"""
            SELECT ano, mes, SUM(val_item) AS valor
            FROM vendas_geral
            WHERE {where_no_year} AND ano IN (?, ?)
            GROUP BY ano, mes
        """, p_no_year + [ref_year, ref_year - 1])
        
        evol_rows = cursor.fetchall()
        data_atual = {r['mes']: r['valor'] for r in evol_rows if r['ano'] == ref_year}
        data_anterior = {r['mes']: r['valor'] for r in evol_rows if r['ano'] == ref_year - 1}
        
        evolucao_atual = [round(data_atual.get(m, 0), 2) for m in range(1, 13)]
        evolucao_anterior = [round(data_anterior.get(m, 0), 2) for m in range(1, 13)]

        # --- Evolução Diária (1-31) ---
        cursor.execute(f"""
        SELECT dia, SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql}
        GROUP BY dia
        ORDER BY dia
        """, params)
        ev_dia = {row['dia']: row['valor'] for row in cursor.fetchall()}
        evolucao_diaria = [round(ev_dia.get(d, 0), 2) for d in range(1, 32)]

        # --- Rank Dia da Semana ---
        cursor.execute(f"""
        SELECT
        CAST(strftime('%w', data_emissao) AS INTEGER) AS dia_semana,
        SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql}
        GROUP BY dia_semana
        ORDER BY dia_semana
        """, params)
        ev_sem = {row['dia_semana']: row['valor'] for row in cursor.fetchall()}
        rank_semana = [round(ev_sem.get(d, 0), 2) for d in range(7)]

        # --- TOP 10 Produtos ---
        cursor.execute(f"""
        SELECT produto, SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql}
        GROUP BY produto
        ORDER BY valor DESC
        LIMIT 10
        """, params)
        top10_rows = cursor.fetchall()
        top10_labels = [r['produto'] or 'N/A' for r in top10_rows]
        top10_data = [round(r['valor'], 2) for r in top10_rows]

        # --- Market Share por Empresa ---
        cursor.execute(f"""
        SELECT empresa, SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql}
        GROUP BY empresa
        ORDER BY valor DESC
        """, params)
        ms_rows = cursor.fetchall()
        market_labels = [r['empresa'] for r in ms_rows]
        market_data = [round(r['valor'], 2) for r in ms_rows]

        # --- Vendas por UF ---
        cursor.execute(f"""
        SELECT uf, SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql} AND uf != '' AND uf IS NOT NULL
        GROUP BY uf
        ORDER BY valor DESC
        """, params)
        uf_rows = cursor.fetchall()
        uf_labels = [r['uf'] for r in uf_rows]
        uf_data = [round(r['valor'], 2) for r in uf_rows]

        # --- Rank Categoria ---
        cursor.execute(f"""
        SELECT categoria_produto AS categoria, SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql}
        GROUP BY categoria_produto
        ORDER BY valor DESC
        """, params)
        cat_rows = cursor.fetchall()
        cat_labels = [r['categoria'] for r in cat_rows]
        cat_data = [round(r['valor'], 2) for r in cat_rows]

        # --- PM por Empresa (últimos 12 meses) ---
        cursor.execute("""
        SELECT empresa, SUM(val_item) AS valor,
        SUM(qtd_caixas) AS qtd_caixas
        FROM vendas_geral
        WHERE data_emissao >= date('now', '-12 months')
        AND """ + where_sql + """
        GROUP BY empresa
        """, params)
        pm_rows = cursor.fetchall()
        pm_por_empresa = {}
        for r in pm_rows:
            qtd_cx = r['qtd_caixas'] or 0
            valor = r['valor'] or 0
            pm_por_empresa[r['empresa']] = {
                'preco_medio': round((valor / qtd_cx) / 12, 2) if qtd_cx > 0 else 0,
                'faturamento_12m': round(valor, 2),
                'qtd_caixas_12m': round(qtd_cx, 0)
            }
        fat12 = sum(v['faturamento_12m'] for v in pm_por_empresa.values())
        pm_ponderado = 0
        for emp, v in pm_por_empresa.items():
            share = (v['faturamento_12m'] / fat12 * 100) if fat12 > 0 else 0
            pm_por_empresa[emp]['share_12m'] = round(share, 2)
            pm_ponderado += (share / 100) * v['preco_medio']
        pm_ponderado = round(pm_ponderado, 2)

        # --- Transações Recentes (últimas 100) ---
        cursor.execute(f"""
        SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
        val_item, empresa, nomenclatura, categoria_produto, ano, mes
        FROM vendas_geral
        WHERE {where_sql}
        ORDER BY data_emissao DESC, numero_nota DESC
        LIMIT 100
        """, params)
        transacoes = []
        for row in cursor.fetchall():
            r = dict(row)
            r['data_emissao'] = r.get('data_emissao', '')
            transacoes.append(r)

    # --- Top 30 Clientes por Faturamento (excluindo FILIAL) ---
        cursor.execute(f"""
        WITH total_geral AS (SELECT SUM(val_item) AS total FROM vendas_geral WHERE {where_sql} AND cliente != '' AND cliente IS NOT NULL)
        SELECT cliente, SUM(val_item) AS valor,
               COUNT(DISTINCT numero_nota || '_' || empresa) AS notas,
               SUM(qtd_caixas) AS caixas,
               ROUND(SUM(val_item) * 100.0 / (SELECT total FROM total_geral), 2) AS porcentagem
        FROM vendas_geral
        WHERE {where_sql} AND cliente != '' AND cliente IS NOT NULL
        GROUP BY cliente ORDER BY valor DESC LIMIT 30
        """, params + params)
        top20_rows = cursor.fetchall()
        top20_clientes = []
        for r in top20_rows:
            top20_clientes.append({
                'cliente': r['cliente'],
                'valor': round(r['valor'], 2),
                'notas': int(r['notas'] or 0),
                'caixas': int(r['caixas'] or 0),
                'porcentagem': round(r['porcentagem'] or 0, 2),
            })

    # --- Mix de Produtos por Cliente (top 30) ---
        top20_nomes = [c['cliente'] for c in top20_clientes]
        mix_por_cliente = {}
        if top20_nomes:
            placeholders = ','.join('?' * len(top20_nomes))
            mix_params = params + top20_nomes
            cursor.execute(f"""
                SELECT cliente, produto, categoria_produto AS categoria,
                       SUM(val_item) AS valor, ROUND(SUM(qtd_caixas)) AS caixas,
                       ROUND(SUM(quantidade)) AS unidades
                FROM vendas_geral
                WHERE {where_sql} AND cliente IN ({placeholders})
                GROUP BY cliente, produto, categoria_produto
                ORDER BY cliente, valor DESC
            """, mix_params)
            for row in cursor.fetchall():
                cl = row['cliente']
                if cl not in mix_por_cliente:
                    mix_por_cliente[cl] = []
                mix_por_cliente[cl].append({
                    'produto': row['produto'],
                    'categoria': row['categoria'] or '',
                    'valor': round(row['valor'], 2),
                    'caixas': int(row['caixas'] or 0),
                    'unidades': int(row['unidades'] or 0),
                })

            # --- Todos os Produtos (para Produtos Sugeridos no vendas) ---
            cursor.execute("SELECT produto, categoria AS categoria, COALESCE(nomenclatura, produto) AS nomenclatura FROM produtos WHERE produto != '' ORDER BY produto")
            todos_produtos = [{'produto': r['produto'], 'categoria': r['categoria'] or '', 'nomenclatura': r['nomenclatura']} for r in cursor.fetchall()]

            # --- Filtros disponíveis ---
            cursor.execute("SELECT DISTINCT empresa FROM vendas_geral ORDER BY empresa")
            empresas = [r['empresa'] for r in cursor.fetchall()]

            cursor.execute("SELECT DISTINCT ano FROM vendas_geral ORDER BY ano DESC")
            anos = [r['ano'] for r in cursor.fetchall()]

            # Filtro de produtos usando nomenclatura padronizada
            cursor.execute("SELECT DISTINCT COALESCE(nomenclatura, produto) FROM produtos WHERE produto != '' ORDER BY COALESCE(nomenclatura, produto)")
            produtos = [r[0] for r in cursor.fetchall()]

        # Filtro de clientes (excluindo FILIAL)
            cursor.execute("SELECT DISTINCT cliente FROM vendas_geral WHERE cliente != '' AND cliente != ? ORDER BY cliente", ('EMPRESA DEMO LTDA',))
            clientes = [r['cliente'] for r in cursor.fetchall()]

            # --- Rentabilidade por Cliente (Top 400 por receita) ---
            cursor.execute(f"""
                SELECT
                  v.cliente,
                  ROUND(SUM(v.val_item), 2) AS receita,
                  ROUND(SUM(v.qtd_caixas * v.uni_cx_produto * COALESCE((SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto)), 0)), 2) AS custo,
                  ROUND(SUM(v.val_item) - SUM(v.qtd_caixas * v.uni_cx_produto * COALESCE((SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto)), 0)), 2) AS lucro,
                  CASE WHEN SUM(v.val_item) > 0
                    THEN ROUND((SUM(v.val_item) - SUM(v.qtd_caixas * v.uni_cx_produto * COALESCE((SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(v.produto)), 0))) / SUM(v.val_item) * 100, 1)
                    ELSE 0 END AS margem,
                  COUNT(DISTINCT v.numero_nota || '_' || v.empresa) AS pedidos,
                  ROUND(SUM(v.val_item) / NULLIF(COUNT(DISTINCT v.numero_nota || '_' || v.empresa), 0), 2) AS ticket_medio
                FROM vendas_geral v
                WHERE {where_sql}
                GROUP BY v.cliente
                ORDER BY receita DESC
                LIMIT 400
            """, params)
            rentabilidade_rows = cursor.fetchall()

            rentabilidade_clientes = []
            todos_valores = []
            todas_margens = []
            for r in rentabilidade_rows:
                rentabilidade_clientes.append({
                    'cliente': r['cliente'],
                    'receita': r['receita'],
                    'custo': r['custo'],
                    'lucro': r['lucro'],
                    'margem': r['margem'],
                    'pedidos': r['pedidos'],
                    'ticket_medio': r['ticket_medio'],
                })
                todos_valores.append(r['receita'])
                todas_margens.append(r['margem'])

            # Medianas para corte alto/baixo na classificacao
            sorted_valores = sorted(todos_valores)
            sorted_margens = sorted(todas_margens)
            n = len(sorted_valores)
            mediana_receita = sorted_valores[n // 2] if n > 0 else 0
            mediana_margem = sorted_margens[n // 2] if n > 0 else 0

            # Classificar cada cliente
            for c in rentabilidade_clientes:
                if c['margem'] >= mediana_margem and c['receita'] >= mediana_receita:
                    c['status'] = 'Cliente Ideal'
                    c['quadrante'] = 2
                elif c['margem'] >= mediana_margem and c['receita'] < mediana_receita:
                    c['status'] = 'Potencial de Expansao'
                    c['quadrante'] = 1
                elif c['margem'] < mediana_margem and c['receita'] >= mediana_receita:
                    c['status'] = 'Risco de Margem'
                    c['quadrante'] = 4
                else:
                    c['status'] = 'Baixo Impacto'
                    c['quadrante'] = 3

        if not top20_nomes:
            rentabilidade_clientes = []
            mediana_receita = 0
            mediana_margem = 0
            todos_produtos = []
            empresas = []
            anos = []
            produtos = []
            clientes = []

        # --- Margem % Mensal (Agregada ou por Cliente) ---
        margem_params = list(params)
        if cliente_margem:
            margem_where = where_sql + " AND cliente = ?"
            margem_params.append(cliente_margem)
        else:
            margem_where = where_sql
        cursor.execute(f"""
            SELECT mes,
              ROUND(SUM(val_item), 2) AS receita,
              ROUND(SUM(qtd_caixas * uni_cx_produto * COALESCE(
                (SELECT p.custo FROM produtos p WHERE TRIM(p.produto) = TRIM(produto)), 0
              )), 2) AS custo
            FROM vendas_geral
            WHERE {margem_where}
            GROUP BY mes ORDER BY mes
        """, margem_params)
        margem_mensal = {}
        for row in cursor.fetchall():
            mes = row['mes']
            receita = row['receita'] or 0
            custo = row['custo'] or 0
            margem = round((receita - custo) / receita * 100, 1) if receita > 0 else 0
            margem_mensal[mes] = margem
        margem_mensal_array = [margem_mensal.get(m, None) for m in range(1, 13)]

        response = {
            'kpis': {
                'faturamento': round(faturamento, 2),
                'lucro_estimado': round(faturamento * 0.15, 2),
                'custo_total': round(custo_total, 2),
                'custo_percentual': round((custo_total / faturamento) * 100, 2) if faturamento > 0 else 0,
                'ticket_medio': round(ticket_medio, 2),
                'total_notas': int(total_notas),
                'total_caixas': int(kpis.get('total_caixas', 0) or 0),
            },
            'pm': {
                'ponderado': pm_ponderado,
                'por_empresa': pm_por_empresa,
            },
            'evolucao_mensal': {
                'labels': ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
                           'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
                'data': evolucao_atual,
                'data_anterior': evolucao_anterior,
                'ano_atual': ref_year
            },
            'evolucao_diaria': {
                'labels': [f'D{d}' for d in range(1, 32)],
                'dias_reais': list(range(1, 32)),
                'data': evolucao_diaria,
            },
            'rank_semana': {
                'labels': ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'],
                'data': rank_semana,
            },
            'top10': {
                'labels': top10_labels,
                'data': top10_data,
            },
            'market_share': {
                'labels': market_labels,
                'data': market_data,
            },
            'vendas_uf': {
                'labels': uf_labels,
                'data': uf_data,
            },
            'rank_categoria': {
                'labels': cat_labels,
                'data': cat_data,
            },
            'top20_clientes': top20_clientes,
            'mix_por_cliente': mix_por_cliente,
            'rentabilidade': {
                'clientes': rentabilidade_clientes,
                'mediana_receita': mediana_receita,
                'mediana_margem': mediana_margem,
            },
            'margem_mensal': margem_mensal_array,
            'todos_produtos': todos_produtos,
            'filtros': {
                'empresas': empresas,
                'anos': anos,
                'produtos': produtos,
                'clientes': clientes,
            },
            'transacoes_recentes': transacoes,
        }

        return jsonify(response)

    except Exception as e:
        return jsonify({'erro': str(e)}), 500
    finally:
        conn.close()


# ============================================
# ENDPOINT: Status / Healthcheck
# ============================================
@app.route('/api/status', methods=['GET'])
def get_status():
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) AS total FROM vendas_geral")
        total = cursor.fetchone()['total']
        cursor.execute("SELECT COUNT(DISTINCT empresa) AS empresas FROM vendas_geral")
        empresas = cursor.fetchone()['empresas']
        cursor.execute("SELECT MAX(data_emissao) AS ultima_data FROM vendas_geral")
        ultima = cursor.fetchone()['ultima_data']

        return jsonify({
            'status': 'online',
            'database': DB_PATH,
            'total_registros': total,
            'empresas': empresas,
            'ultima_atualizacao': ultima,
        })
    finally:
        conn.close()


# ============================================
# ENDPOINT: Dados do Mapa do Brasil (D3.js)
# ============================================
@app.route('/api/mapa', methods=['GET'])
def get_mapa():
    conn = get_connection()
    try:
        cursor = conn.cursor()

        # Filtros opcionais
        empresa = request.args.get('empresa', '').strip()
        tipo_pessoa = request.args.get('tipo_pessoa', '').strip()
        ano = request.args.get('ano', '').strip()
        mes = request.args.get('mes', '').strip()

        where_clauses = ["1=1"]
        params = []

        if empresa:
            where_clauses.append("empresa = ?")
            params.append(empresa)
        if tipo_pessoa:
            where_clauses.append("tipo_pessoa = ?")
            params.append(tipo_pessoa)
        if ano:
            where_clauses.append("ano = ?")
            params.append(int(ano))
        if mes:
            where_clauses.append("mes = ?")
            params.append(int(mes))

        where_sql = " AND ".join(where_clauses)

        # Query SQL: Faturamento por UF com porcentagem e total de notas
        cursor.execute(f"""
        WITH total_nacional AS (
        SELECT SUM(val_item) AS total
        FROM vendas_geral
        WHERE {where_sql}
        )
        SELECT
        uf,
        SUM(val_item) AS valor_total,
        COUNT(DISTINCT numero_nota || '_' || empresa) AS total_notas,
        ROUND((SUM(val_item) * 100.0 / (SELECT total FROM total_nacional)), 2) AS porcentagem
        FROM vendas_geral
        WHERE {where_sql}
        AND uf != '' AND uf IS NOT NULL
        GROUP BY uf
        ORDER BY valor_total DESC
        """, params + params)

        rows = cursor.fetchall()

        # Converter para dicionário Python
        dados_por_uf = {}
        total_geral = 0

        for row in rows:
            uf = row['uf']
            valor = row['valor_total'] or 0
            perc = row['porcentagem'] or 0
            notas = row['total_notas'] or 0
            dados_por_uf[uf] = {
                'valor': round(valor, 2),
                'porcentagem': round(perc, 2),
                'notas': notas
            }
            total_geral += valor

        # Encontrar valor máximo para escala de cores
        max_valor = max([d['valor'] for d in dados_por_uf.values()]) if dados_por_uf else 0

        # Nomes dos estados por UF
        nomes_estados = {
            'AC': 'Acre', 'AL': 'Alagoas', 'AP': 'Amapá', 'AM': 'Amazonas',
            'BA': 'Bahia', 'CE': 'Ceará', 'DF': 'Distrito Federal', 'ES': 'Espírito Santo',
            'GO': 'Goiás', 'MA': 'Maranhão', 'MT': 'Mato Grosso', 'MS': 'Mato Grosso do Sul',
            'MG': 'Minas Gerais', 'PA': 'Pará', 'PB': 'Paraíba', 'PR': 'Paraná',
            'PE': 'Pernambuco', 'PI': 'Piauí', 'RJ': 'Rio de Janeiro', 'RN': 'Rio Grande do Norte',
            'RS': 'Rio Grande do Sul', 'RO': 'Rondônia', 'RR': 'Roraima', 'SC': 'Santa Catarina',
            'SP': 'São Paulo', 'SE': 'Sergipe', 'TO': 'Tocantins'
        }

        # Adicionar nome do estado
        for uf, dados in dados_por_uf.items():
            dados['nome'] = nomes_estados.get(uf, uf)

        return jsonify({
            'dados_por_uf': dados_por_uf,
            'max_valor': max_valor,
            'total_geral': round(total_geral, 2),
            'total_estados': len(dados_por_uf)
        })

    except Exception as e:
        return jsonify({'erro': str(e)}), 500
    finally:
        conn.close()


@app.route('/api/vendas', methods=['GET'])
def get_vendas():
    conn = get_connection()
    try:
        cursor = conn.cursor()

        empresa = request.args.get('empresa', '').strip()
        natureza = request.args.get('natureza', '').strip()
        tipo_pessoa = request.args.get('tipo_pessoa', '').strip()
        ano = request.args.get('ano', '').strip()
        mes = request.args.get('mes', '').strip()
        produto = request.args.get('produto', '').strip()
        cliente = request.args.get('cliente', '').strip()
        uf = request.args.get('uf', '')
        categoria = request.args.get('categoria', '')
        dia = request.args.get('dia', '')
        dia_semana = request.args.get('dia_semana', '')

        where_clauses = ["1=1"]
        params = []

        # Global: excluir cliente EMPRESA DEMO LTDA
        where_clauses.append("cliente != ?")
        params.append('EMPRESA DEMO LTDA')

        if empresa:
            where_clauses.append("empresa = ?")
            params.append(empresa)
        if natureza:
            where_clauses.append("natureza_operacao LIKE '%' || ? || '%'")
            params.append(natureza)
        if tipo_pessoa:
            where_clauses.append("tipo_pessoa = ?")
            params.append(tipo_pessoa)
        if ano:
            where_clauses.append("ano = ?")
            params.append(int(ano))
        if mes:
            where_clauses.append("mes = ?")
            params.append(int(mes))
        if produto:
            where_clauses.append("produto IN (SELECT p2.produto FROM produtos p2 WHERE p2.nomenclatura = ?)")
            params.append(produto)
        if cliente == '__NONE__':
            where_clauses.append("1=0")
        elif cliente:
            clientes_list = [c.strip() for c in cliente.split(',') if c.strip()]
            if clientes_list:
                placeholders = ','.join('?' * len(clientes_list))
                where_clauses.append(f"cliente IN ({placeholders})")
                params.extend(clientes_list)
        if uf:
            where_clauses.append("uf = ?")
            params.append(uf)
        if categoria:
            where_clauses.append("categoria_produto = ?")
            params.append(categoria)
        if dia:
            where_clauses.append("dia = ?")
            params.append(int(dia))
        if dia_semana is not None and dia_semana != '':
            where_clauses.append("dia_semana = ?")
            params.append(int(dia_semana))

        where_sql = " AND ".join(where_clauses)

        # --- KPIs de Volume ---
        cursor.execute(f"""
            SELECT
                ROUND(SUM(qtd_caixas)) AS total_caixas,
                ROUND(SUM(litros_produto)) AS total_litros,
                ROUND(SUM(quantidade)) AS total_unidades,
                COUNT(DISTINCT numero_nota || '_' || empresa) AS total_notas
            FROM vendas_geral
            WHERE {where_sql}
        """, params)
        kpi_row = cursor.fetchone()
        total_caixas = int(kpi_row['total_caixas'] or 0)
        total_litros = round(kpi_row['total_litros'] or 0, 1)
        total_unidades = int(kpi_row['total_unidades'] or 0)
        total_notas = int(kpi_row['total_notas'] or 0)
        media_cx_nota = round(total_caixas / total_notas, 1) if total_notas > 0 else 0

        # --- Evolucao Mensal (Caixas) ---
        if ano and ano.isdigit():
            ref_year = int(ano)
        else:
            cursor.execute("SELECT MAX(ano) FROM vendas_geral")
            row = cursor.fetchone()
            ref_year = row[0] if row and row[0] else datetime.now().year

        where_no_year_list = [c for c in where_clauses if "ano =" not in c]
        where_no_year = " AND ".join(where_no_year_list) if where_no_year_list else "1=1"

        p_no_year = []
        p_no_year.append('EMPRESA DEMO LTDA')
        if empresa: p_no_year.append(empresa)
        if tipo_pessoa: p_no_year.append(tipo_pessoa)
        if natureza: p_no_year.append(natureza)
        if mes: p_no_year.append(int(mes))
        if produto: p_no_year.append(produto)
        if cliente and cliente != '__NONE__':
            p_no_year.extend([c.strip() for c in cliente.split(',') if c.strip()])
        if uf: p_no_year.append(uf)
        if categoria: p_no_year.append(categoria)
        if dia: p_no_year.append(int(dia))
        if dia_semana is not None and dia_semana != '': p_no_year.append(int(dia_semana))

        cursor.execute(f"""
            SELECT ano, mes, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_no_year} AND ano IN (?, ?)
            GROUP BY ano, mes
        """, p_no_year + [ref_year, ref_year - 1])
        evol_rows = cursor.fetchall()
        cx_atual = {r['mes']: r['caixas'] for r in evol_rows if r['ano'] == ref_year}
        cx_anterior = {r['mes']: r['caixas'] for r in evol_rows if r['ano'] == ref_year - 1}
        evolucao_caixas = [int(cx_atual.get(m, 0)) for m in range(1, 13)]
        evolucao_caixas_anterior = [int(cx_anterior.get(m, 0)) for m in range(1, 13)]

        # --- Evolucao Diaria (Caixas) ---
        cursor.execute(f"""
            SELECT dia, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql}
            GROUP BY dia ORDER BY dia
        """, params)
        ev_dia = {row['dia']: row['caixas'] for row in cursor.fetchall()}
        evolucao_diaria = [int(ev_dia.get(d, 0)) for d in range(1, 32)]

        # --- Rank Dia da Semana (Caixas) ---
        cursor.execute(f"""
            SELECT
                CAST(strftime('%w', data_emissao) AS INTEGER) AS dia_semana,
                ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql}
            GROUP BY dia_semana ORDER BY dia_semana
        """, params)
        ev_sem = {row['dia_semana']: row['caixas'] for row in cursor.fetchall()}
        rank_semana = [int(ev_sem.get(d, 0)) for d in range(7)]

        # --- Top 10 Produtos (Caixas) ---
        cursor.execute(f"""
            SELECT produto, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql}
            GROUP BY produto ORDER BY caixas DESC LIMIT 10
        """, params)
        top10_rows = cursor.fetchall()
        top10_labels = [r['produto'] or 'N/A' for r in top10_rows]
        top10_data = [int(r['caixas']) for r in top10_rows]

        # --- Market Share por Empresa (Caixas) ---
        cursor.execute(f"""
            SELECT empresa, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql}
            GROUP BY empresa ORDER BY caixas DESC
        """, params)
        ms_rows = cursor.fetchall()
        market_labels = [r['empresa'] for r in ms_rows]
        market_data = [int(r['caixas']) for r in ms_rows]

        # --- Caixas por UF ---
        cursor.execute(f"""
            SELECT uf, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql} AND uf != '' AND uf IS NOT NULL
            GROUP BY uf ORDER BY caixas DESC
        """, params)
        uf_rows = cursor.fetchall()
        uf_labels = [r['uf'] for r in uf_rows]
        uf_data = [int(r['caixas']) for r in uf_rows]

        # --- Rank Categoria (Caixas) ---
        cursor.execute(f"""
            SELECT categoria_produto AS categoria, ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE {where_sql}
            GROUP BY categoria_produto ORDER BY caixas DESC
        """, params)
        cat_rows = cursor.fetchall()
        cat_labels = [r['categoria'] for r in cat_rows]
        cat_data = [int(r['caixas']) for r in cat_rows]

        # --- Litros por Empresa (12m) ---
        cursor.execute(f"""
            SELECT empresa,
                ROUND(SUM(litros_produto), 1) AS litros,
                ROUND(SUM(qtd_caixas)) AS caixas
            FROM vendas_geral
            WHERE data_emissao >= date('now', '-12 months')
            AND {where_sql}
            GROUP BY empresa
        """, params)
        vol_rows = cursor.fetchall()
        vol_por_empresa = {}
        total_cx_12 = 0
        for r in vol_rows:
            cx = int(r['caixas'] or 0)
            lt = float(r['litros'] or 0)
            vol_por_empresa[r['empresa']] = {'caixas_12m': cx, 'litros_12m': lt}
            total_cx_12 += cx
        for emp in vol_por_empresa:
            vol_por_empresa[emp]['share_12m'] = round(
                (vol_por_empresa[emp]['caixas_12m'] / total_cx_12 * 100), 2
            ) if total_cx_12 > 0 else 0

        # --- Transacoes Recentes ---
        cursor.execute(f"""
            SELECT id, data_emissao, numero_nota, produto, cliente, cidade, uf,
                val_item, empresa, nomenclatura, categoria_produto, ano, mes,
                qtd_caixas, litros_produto, quantidade, uni_cx_produto
            FROM vendas_geral
            WHERE {where_sql}
            ORDER BY data_emissao DESC, numero_nota DESC LIMIT 100
        """, params)
        transacoes = []
        for row in cursor.fetchall():
            r = dict(row)
            r['qtd_caixas'] = int(round(r.get('qtd_caixas', 0) or 0))
            r['litros_produto'] = round(r.get('litros_produto', 0) or 0, 1)
            r['quantidade'] = int(round(r.get('quantidade', 0) or 0))
            r['uni_cx_produto'] = int(r.get('uni_cx_produto', 0) or 0)
            transacoes.append(r)

        # --- Top 30 Clientes por Caixas (excluindo FILIAL) ---
        cursor.execute(f"""
        SELECT cliente, ROUND(SUM(qtd_caixas)) AS caixas,
               COUNT(DISTINCT numero_nota || '_' || empresa) AS notas,
               SUM(val_item) AS valor
        FROM vendas_geral
        WHERE {where_sql} AND cliente != '' AND cliente IS NOT NULL
        GROUP BY cliente ORDER BY caixas DESC LIMIT 30
        """, params)
        top20_rows = cursor.fetchall()
        top20_clientes = []
        for r in top20_rows:
            top20_clientes.append({
                'cliente': r['cliente'],
                'caixas': int(r['caixas'] or 0),
                'notas': int(r['notas'] or 0),
                'valor': round(r['valor'], 2),
            })

        # --- Mix de Produtos por Cliente (top 30) ---
        top20_nomes = [c['cliente'] for c in top20_clientes]
        mix_por_cliente = {}
        if top20_nomes:
            placeholders = ','.join('?' * len(top20_nomes))
            mix_params = params + top20_nomes
            cursor.execute(f"""
            SELECT cliente, produto, categoria_produto AS categoria,
                   SUM(val_item) AS valor, ROUND(SUM(qtd_caixas)) AS caixas,
                   ROUND(SUM(quantidade)) AS unidades
            FROM vendas_geral
            WHERE {where_sql} AND cliente IN ({placeholders})
            GROUP BY cliente, produto, categoria_produto
            ORDER BY cliente, caixas DESC
            """, mix_params)
            for row in cursor.fetchall():
                cl = row['cliente']
                if cl not in mix_por_cliente:
                    mix_por_cliente[cl] = []
                mix_por_cliente[cl].append({
                    'produto': row['produto'],
                    'categoria': row['categoria'] or '',
                    'valor': round(row['valor'], 2),
                    'caixas': int(row['caixas'] or 0),
                    'unidades': int(row['unidades'] or 0),
                })

        # --- Todos os Produtos (para Produtos Sugeridos) ---
        cursor.execute("SELECT produto, categoria AS categoria FROM produtos WHERE produto != '' ORDER BY produto")
        todos_produtos = [{'produto': r['produto'], 'categoria': r['categoria'] or ''} for r in cursor.fetchall()]

        # --- Filtros ---
        cursor.execute("SELECT DISTINCT empresa FROM vendas_geral ORDER BY empresa")
        empresas = [r['empresa'] for r in cursor.fetchall()]
        cursor.execute("SELECT DISTINCT ano FROM vendas_geral ORDER BY ano DESC")
        anos = [r['ano'] for r in cursor.fetchall()]
        cursor.execute("SELECT DISTINCT COALESCE(nomenclatura, produto) FROM produtos WHERE produto != '' ORDER BY COALESCE(nomenclatura, produto)")
        produtos = [r[0] for r in cursor.fetchall()]
        cursor.execute("SELECT DISTINCT cliente FROM vendas_geral WHERE cliente != '' AND cliente != ? ORDER BY cliente", ('EMPRESA DEMO LTDA',))
        clientes = [r['cliente'] for r in cursor.fetchall()]

        # --- Caixas por UF (para mapa) ---
        cursor.execute(f"""
        WITH total_nacional AS (
            SELECT ROUND(SUM(qtd_caixas)) AS total
            FROM vendas_geral WHERE {where_sql}
        )
        SELECT uf,
            ROUND(SUM(qtd_caixas)) AS caixas_total,
            COUNT(DISTINCT numero_nota || '_' || empresa) AS total_notas,
            ROUND((SUM(qtd_caixas) * 100.0 / (SELECT total FROM total_nacional)), 2) AS porcentagem
        FROM vendas_geral
        WHERE {where_sql} AND uf != '' AND uf IS NOT NULL
        GROUP BY uf ORDER BY caixas_total DESC
        """, params + params)
        mapa_rows = cursor.fetchall()
        nomes_estados = {
            'AC': 'Acre', 'AL': 'Alagoas', 'AP': 'Amapá', 'AM': 'Amazonas',
            'BA': 'Bahia', 'CE': 'Ceará', 'DF': 'Distrito Federal', 'ES': 'Espírito Santo',
            'GO': 'Goiás', 'MA': 'Maranhão', 'MT': 'Mato Grosso', 'MS': 'Mato Grosso do Sul',
            'MG': 'Minas Gerais', 'PA': 'Pará', 'PB': 'Paraíba', 'PR': 'Paraná',
            'PE': 'Pernambuco', 'PI': 'Piauí', 'RJ': 'Rio de Janeiro', 'RN': 'Rio Grande do Norte',
            'RS': 'Rio Grande do Sul', 'RO': 'Rondônia', 'RR': 'Roraima', 'SC': 'Santa Catarina',
            'SP': 'São Paulo', 'SE': 'Sergipe', 'TO': 'Tocantins'
        }
        dados_por_uf = {}
        for row in mapa_rows:
            uf_val = row['uf']
            dados_por_uf[uf_val] = {
                'nome': nomes_estados.get(uf_val, uf_val),
                'caixas': int(row['caixas_total'] or 0),
                'notas': int(row['total_notas'] or 0),
                'porcentagem': round(row['porcentagem'] or 0, 2),
            }
        max_caixas = max((d['caixas'] for d in dados_por_uf.values()), default=0)

        return jsonify({
            'kpis': {
                'total_caixas': total_caixas,
                'total_litros': total_litros,
                'total_unidades': total_unidades,
                'total_notas': total_notas,
                'media_cx_nota': media_cx_nota,
            },
            'volume': {
                'por_empresa': vol_por_empresa,
            },
            'evolucao_mensal': {
                'labels': ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
                           'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'],
                'data': evolucao_caixas,
                'data_anterior': evolucao_caixas_anterior,
                'ano_atual': ref_year,
            },
            'evolucao_diaria': {
                'labels': [f'D{d}' for d in range(1, 32)],
                'dias_reais': list(range(1, 32)),
                'data': evolucao_diaria,
            },
            'rank_semana': {
                'labels': ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'],
                'data': rank_semana,
            },
            'top10': {
                'labels': top10_labels,
                'data': top10_data,
            },
            'market_share': {
                'labels': market_labels,
                'data': market_data,
            },
            'vendas_uf': {
                'labels': uf_labels,
                'data': uf_data,
            },
            'rank_categoria': {
                'labels': cat_labels,
                'data': cat_data,
            },
        'filtros': {
            'empresas': empresas,
            'anos': anos,
            'produtos': produtos,
            'clientes': clientes,
        },
        'top20_clientes': top20_clientes,
        'mix_por_cliente': mix_por_cliente,
        'todos_produtos': todos_produtos,
        'transacoes_recentes': transacoes,
        'mapa_caixas': {
            'dados_por_uf': dados_por_uf,
            'max_valor': max_caixas,
        },
        })

    except Exception as e:
        return jsonify({'erro': str(e)}), 500
    finally:
        conn.close()


@app.route('/')
def serve_spa():
    return send_from_directory('../frontend', 'index.html')


if __name__ == '__main__':
    print("=" * 60)
    print(" API Dashboard Financeiro BI - DASHBOARD FINANCEIRO")
    print("=" * 60)
    print(f" Host: http://{API_HOST}:{API_PORT}")
    print(f" SPA (nova): http://{API_HOST}:{API_PORT}/")
    print(f" Dashboard (original): http://{API_HOST}:{API_PORT}/dashboard")
    print(f" API Dados: http://{API_HOST}:{API_PORT}/api/dados")
    print(f" Status: http://{API_HOST}:{API_PORT}/api/status")
    print(f" Database: {DB_PATH}")
    print("=" * 60)

    app.run(host=API_HOST, port=API_PORT, debug=False)
