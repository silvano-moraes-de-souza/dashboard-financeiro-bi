#========================================
# coleta_External.py
# Descrição:
# Criado por: Silvano Moraes de Souza
#========================================

# -*- coding: utf-8 -*-
# coleta_External.py - Coleta dados do ERP System para o Dashboard Financeiro
# Autor: Silvano Moraes de Souza
# Gera vendas_MM_AAAA.xlsx + insere em vendas_filial_b / vendas_filial

import requests
import time
import os
import sys
import sqlite3
from datetime import datetime, timedelta
from openpyxl import Workbook, load_workbook
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding='utf-8')

load_dotenv()

TOKEN_FILIAL_B = os.getenv("External_TOKEN_FILIAL_B")
TOKEN_FILIAL = os.getenv("External_TOKEN_FILIAL")
DB_PATH = os.getenv("DB_PATH", "APP_financeiro.db")

if not TOKEN_FILIAL_B or not TOKEN_FILIAL:
    print("ERRO: External_TOKEN_FILIAL_B e External_TOKEN_FILIAL devem estar no .env")
    sys.exit(1)

BASE_URL_LISTA  = "https://api.External.com.br/api2/notas.fiscais.pesquisa.php"
BASE_URL_DETALHE = "https://api.External.com.br/api2/nota.fiscal.obter.php"

HEADERS_EXCEL = [
    "Data de Emissao", "Nota Fiscal", "Natureza de Operacao",
    "SKU/Ref", "Produto", "Nome do Cliente", "CPF/CNPJ",
    "Cidade", "UF", "CEP", "Endereco", "Numero",
    "Quantidade", "Valor Unitario", "Frete", "Valor Total"
]

EMPRESAS = [
    ("FILIAL_B", TOKEN_FILIAL_B, "vendas_filial_b"),
    ("FILIAL", TOKEN_FILIAL, "vendas_filial"),
]

def safe_request(url, params, tentativas=3, timeout=60):
    """Request com retry exponencial: 10s, 30s, 60s"""
    for tentativa in range(tentativas):
        try:
            r = requests.get(url, params=params, timeout=timeout)
            if r.status_code == 429:
                print(f"  Rate limit (429). Aguardando 60s...")
                time.sleep(60)
                continue
            if r.status_code != 200 or not r.text.strip():
                print(f"  Resposta vazia/erro HTTP {r.status_code}")
                time.sleep(2)
                continue
            return r.json()
        except requests.exceptions.Timeout:
            espera = [10, 30, 60][tentativa]
            print(f"  Timeout. Retry {tentativa+1}/{tentativas} em {espera}s...")
            time.sleep(espera)
        except requests.exceptions.ConnectionError:
            espera = [10, 30, 60][tentativa]
            print(f"  Erro de conexao. Retry {tentativa+1}/{tentativas} em {espera}s...")
            time.sleep(espera)
        except Exception as e:
            espera = [10, 30, 60][tentativa]
            print(f"  Erro: {e}. Retry {tentativa+1}/{tentativas} em {espera}s...")
            time.sleep(espera)
    print(f"  FALHA APOS {tentativas} TENTATIVAS")
    return {}

def gerar_meses(inicio, fim):
    """Gera pares (data_inicio, data_fim) para cada mes no intervalo"""
    atual = inicio
    while atual <= fim:
        prox = (atual.replace(day=28) + timedelta(days=4)).replace(day=1)
        yield atual, prox - timedelta(days=1)
        atual = prox

def mes_ja_tem_dados(cursor, tabela, ano, mes, empresa):
    """Verifica se ja existem registros para aquele mes/empresa"""
    prefixo = f"{ano}-{mes:02d}"
    cursor.execute(
        f"SELECT COUNT(*) FROM {tabela} "
        f"WHERE data_emissao LIKE ? || '%'",
        (prefixo,)
    )
    return cursor.fetchone()[0] > 0

def normalizar_data(data_str):
    """Converte DD/MM/YYYY -> YYYY-MM-DD (ISO)"""
    if not data_str or not isinstance(data_str, str):
        return data_str
    if '/' in data_str:
        partes = data_str.split('/')
        if len(partes) == 3:
            return f"{partes[2]}-{partes[1]}-{partes[0]}"
    return data_str

def tipo_pessoa(doc):
    """Deriva tipo_pessoa de CPF/CNPJ"""
    doc = ''.join(c for c in str(doc) if c.isdigit())
    if len(doc) >= 14:
        return "Juridica"
    elif len(doc) == 11:
        return "Fisica"
    return ""

def processar_empresa(nome_empresa, token, tabela_db, conn, inicio, fim):
    """Processa todos os meses de uma empresa"""
    print(f"\n{'='*60}")
    print(f"  PROCESSANDO: {nome_empresa}")
    print(f"{'='*60}")

    for data_ini, data_fim in gerar_meses(inicio, fim):
        mes_str = data_ini.strftime('%m_%Y')
        nome_arquivo = f"vendas_{nome_empresa}_{mes_str}.xlsx"

        # Pular se xlsx ja existe (checagem especifica por empresa)
        if os.path.exists(nome_arquivo):
            print(f"  [{nome_empresa}] {mes_str}: xlsx existe. Pulando...")
            continue

        cursor = conn.cursor()

        # Pular se dados ja estao no banco
        if mes_ja_tem_dados(cursor, tabela_db, data_ini.year, data_ini.month, nome_empresa):
            print(f"  [{nome_empresa}] {mes_str}: dados no banco. Pulando...")
            continue

        print(f"\n  [{nome_empresa}] {mes_str}: baixando "
              f"{data_ini.strftime('%d/%m/%Y')} -> {data_fim.strftime('%d/%m/%Y')}")

        pagina = 1
        linhas_mes = []
        total_inseridos = 0
        erro_no_mes = False
        primeira_pagina = True

        while True:
            response = safe_request(BASE_URL_LISTA, {
                "token": token,
                "formato": "json",
                "pagina": pagina,
                "dataInicial": data_ini.strftime("%d/%m/%Y"),
                "dataFinal": data_fim.strftime("%d/%m/%Y")
            })

            if not response:
                print(f"  Sem resposta na pagina {pagina}. Parando mes.")
                erro_no_mes = True
                break

            if response.get("retorno", {}).get("status") == "Erro":
                print(f"  Erro API pagina {pagina}: {response}")
                erro_no_mes = True
                break

            notas = response.get("retorno", {}).get("notas_fiscais", [])
            if not notas:
                print(f"  Sem notas na pagina {pagina}. Mes concluido.")
                break

            total_paginas = int(response.get("retorno", {}).get("numero_paginas", 1))
            print(f"  Pagina {pagina}/{total_paginas} - {len(notas)} notas")

            linhas_pagina = []

            for n in notas:
                nota_id = n["nota_fiscal"]["id"]

                detalhe = safe_request(BASE_URL_DETALHE, {
                    "token": token,
                    "id": nota_id,
                    "formato": "json"
                })

                nota_dados = detalhe.get("retorno", {}).get("nota_fiscal", {})

                numero_nota      = nota_dados.get("numero", "")
                data_emissao     = normalizar_data(nota_dados.get("data_emissao", ""))
                natureza_op      = nota_dados.get("natureza_operacao", "")
                frete            = float(nota_dados.get("valor_frete", 0) or 0)

                cliente          = nota_dados.get("cliente", {})
                nome_cliente     = cliente.get("nome", "")
                cpf_cnpj         = cliente.get("cpf_cnpj", "")
                cidade           = cliente.get("cidade", "")
                uf               = cliente.get("uf", "")
                cep              = cliente.get("cep", "")
                endereco          = cliente.get("endereco", "")
                numero_endereco  = cliente.get("numero", "")

                itens = nota_dados.get("itens", [])

                for item_wrapper in itens:
                    item = item_wrapper.get("item", {})

                    qtd_str        = item.get("quantidade", 0)
                    quantidade     = int(float(qtd_str))
                    vlr_str        = item.get("valor_unitario", 0)
                    valor_unitario = float(vlr_str)
                    valor_total    = quantidade * valor_unitario

                    linhas_pagina.append([
                        data_emissao,
                        numero_nota,
                        natureza_op,
                        item.get("codigo", ""),
                        item.get("descricao", ""),
                        nome_cliente,
                        cpf_cnpj,
                        cidade,
                        uf,
                        cep,
                        endereco,
                        numero_endereco,
                        quantidade,
                        valor_unitario,
                        frete,
                        valor_total
                    ])

                print(f"    Nota {numero_nota}: {len(itens)} itens. Pausa 30s...")
                time.sleep(30)

            # --- SALVAR XLSX (INCREMENTAL POR PAGINA) ---
            if linhas_pagina:
                if primeira_pagina:
                    wb = Workbook()
                    ws = wb.active
                    ws.title = f"Vendas_{nome_empresa}_{mes_str}"
                    ws.append(HEADERS_EXCEL)
                    primeira_pagina = False
                else:
                    wb = load_workbook(nome_arquivo)
                    ws = wb.active

                for row in linhas_pagina:
                    ws.append(row)
                wb.save(nome_arquivo)
                print(f"  XLSX atualizado: {len(linhas_pagina)} linhas (pag {pagina})")

            # --- INSERIR NO BANCO (INCREMENTAL POR PAGINA) ---
            if linhas_pagina:
                cursor = conn.cursor()
                inseridos = 0
                for row in linhas_pagina:
                    data_emissao, numero_nota, natureza_op, sku_ref, produto, \
                        nome_cliente, cpf_cnpj, cidade, uf, cep, endereco, \
                        numero_endereco, quantidade, valor_unitario, frete, valor_total = row

                    cursor.execute(f"""
                        INSERT INTO {tabela_db}
                            (data_emissao, numero_nota, natureza_operacao, sku_ref,
                             produto, nome_cliente, cpf_cnpj, tipo_pessoa,
                             cidade, uf, cep, endereco, numero,
                             quantidade, valor_unitario, frete, valor_total, empresa)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        data_emissao, numero_nota, natureza_op, sku_ref,
                        produto, nome_cliente, cpf_cnpj, tipo_pessoa(cpf_cnpj),
                        cidade, uf, cep, endereco, numero_endereco,
                        quantidade, valor_unitario, frete, valor_total, nome_empresa
                    ))
                    inseridos += 1
                conn.commit()
                total_inseridos += inseridos
                print(f"  Banco: +{inseridos} registros (pag {pagina})")

            linhas_mes.extend(linhas_pagina)

            if pagina >= total_paginas:
                break

            pagina += 1
            # PAUSA DE 30s entre paginas
            print(f"  Pagina {pagina} em 30s...")
            time.sleep(30)

        if erro_no_mes:
            print(f"  Mes {mes_str} teve erros.")
            continue

        print(f"  Mes {mes_str} concluido: {len(linhas_mes)} linhas, {total_inseridos} registros no banco")

        print(f"  PAUSA 30s antes do proximo mes...")
        time.sleep(30)


def main():
    inicio = datetime.now()
    print(f"Inicio: {inicio.strftime('%d/%m/%Y %H:%M:%S')}")
    print(f"Banco: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)

    # Periodo: Jan/2025 ate o ultimo dia do mes corrente
    data_inicial = datetime(2025, 1, 1)
    hoje = datetime.now()
    if hoje.month == 12:
        data_final = datetime(hoje.year + 1, 1, 1) - timedelta(days=1)
    else:
        data_final = datetime(hoje.year, hoje.month + 1, 1) - timedelta(days=1)

    print(f"Periodo: {data_inicial.strftime('%d/%m/%Y')} -> {data_final.strftime('%d/%m/%Y')}")

    for nome_empresa, token, tabela_db in EMPRESAS:
        processar_empresa(nome_empresa, token, tabela_db, conn, data_inicial, data_final)
        # PAUSA DE 30s entre empresas
        print(f"\nTrocando de empresa. Pausa 30s...")
        time.sleep(30)

    conn.close()

    fim = datetime.now()
    duracao = fim - inicio
    print(f"\n{'='*60}")
    print(f"  FINALIZADO em {duracao}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
