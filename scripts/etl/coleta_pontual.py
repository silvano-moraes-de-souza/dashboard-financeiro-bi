# -*- coding: utf-8 -*-
# coleta_pontual.py - Baixa dias especificos do ERP System (10-15 Jun/2026)
import requests, time, os, sys, sqlite3, json
from datetime import datetime, timedelta
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding='utf-8')
load_dotenv()

TOKEN_FILIAL_B = os.getenv("External_TOKEN_FILIAL_B")
TOKEN_FILIAL = os.getenv("External_TOKEN_FILIAL")
DB_PATH   = os.getenv("DB_PATH", "APP_financeiro.db")

BASE_URL_LISTA   = "https://api.External.com.br/api2/notas.fiscais.pesquisa.php"
BASE_URL_DETALHE = "https://api.External.com.br/api2/nota.fiscal.obter.php"

EMPRESAS = [
    ("FILIAL_B", TOKEN_FILIAL_B, "vendas_filial_b"),
    ("FILIAL", TOKEN_FILIAL, "vendas_filial"),
]

def safe_request(url, params, tentativas=3, timeout=60):
    for t in range(tentativas):
        try:
            r = requests.get(url, params=params, timeout=timeout)
            if r.status_code == 429:
                print(f"  Rate limit. Aguardando 60s...")
                time.sleep(60); continue
            if r.status_code != 200 or not r.text.strip():
                print(f"  Erro HTTP {r.status_code}")
                time.sleep(2); continue
            return r.json()
        except requests.exceptions.Timeout:
            espera = [10, 30, 60][t]
            print(f"  Timeout. Retry {t+1}/{tentativas} em {espera}s...")
            time.sleep(espera)
        except Exception as e:
            espera = [10, 30, 60][t]
            print(f"  Erro: {e}. Retry {t+1}/{tentativas} em {espera}s...")
            time.sleep(espera)
    print(f"  FALHA APOS {tentativas} TENTATIVAS")
    return {}

def normalizar_data(data_str):
    if not data_str or not isinstance(data_str, str): return data_str
    if '/' in data_str:
        p = data_str.split('/')
        if len(p) == 3: return f"{p[2]}-{p[1]}-{p[0]}"
    return data_str

def tipo_pessoa(doc):
    doc = ''.join(c for c in str(doc) if c.isdigit())
    return "Juridica" if len(doc) >= 14 else "Fisica" if len(doc) == 11 else ""

def nota_ja_existe(cursor, tabela, numero_nota, sku_ref, data_emissao):
    cursor.execute(
        f"SELECT COUNT(*) FROM {tabela} WHERE numero_nota=? AND sku_ref=? AND data_emissao=?",
        (numero_nota, sku_ref, data_emissao)
    )
    return cursor.fetchone()[0] > 0

def processar_empresa(nome, token, tabela, conn, data_ini, data_fim):
    print(f"\n{'='*50}")
    print(f"  {nome}: {data_ini} -> {data_fim}")
    print(f"{'='*50}")

    pagina = 1
    total_inseridos = 0
    total_pular = 0

    while True:
        resp = safe_request(BASE_URL_LISTA, {
            "token": token, "formato": "json", "pagina": pagina,
            "dataInicial": data_ini.strftime("%d/%m/%Y"),
            "dataFinal":   data_fim.strftime("%d/%m/%Y")
        })
        if not resp: break
        if resp.get("retorno", {}).get("status") == "Erro":
            print(f"  Erro API pag {pagina}: {resp}"); break

        notas = resp.get("retorno", {}).get("notas_fiscais", [])
        if not notas:
            print(f"  Sem notas na pag {pagina}. Fim."); break

        total_paginas = int(resp.get("retorno", {}).get("numero_paginas", 1))
        print(f"  Pag {pagina}/{total_paginas} - {len(notas)} notas")

        for n in notas:
            nota_id = n["nota_fiscal"]["id"]
            detalhe = safe_request(BASE_URL_DETALHE, {
                "token": token, "id": nota_id, "formato": "json"
            })
            nd = detalhe.get("retorno", {}).get("nota_fiscal", {})

            numero_nota     = str(nd.get("numero", ""))
            data_emissao    = normalizar_data(nd.get("data_emissao", ""))
            natureza_op     = nd.get("natureza_operacao", "")
            frete           = float(nd.get("valor_frete", 0) or 0)
            cli             = nd.get("cliente", {})
            nome_cliente    = cli.get("nome", "")
            cpf_cnpj        = cli.get("cpf_cnpj", "")
            cidade          = cli.get("cidade", "")
            uf              = cli.get("uf", "")
            cep             = cli.get("cep", "")
            endereco         = cli.get("endereco", "")
            numero_endereco = cli.get("numero", "")

            itens = nd.get("itens", [])
            cursor = conn.cursor()
            inseridos_nota = 0
            pulados_nota = 0

            for iw in itens:
                item = iw.get("item", {})
                sku_ref     = item.get("codigo", "")
                produto     = item.get("descricao", "")
                qtd_str     = item.get("quantidade", 0)
                quantidade  = int(float(qtd_str))
                vlr_str     = item.get("valor_unitario", 0)
                valor_unit  = float(vlr_str)
                valor_total = quantidade * valor_unit

                if nota_ja_existe(cursor, tabela, numero_nota, sku_ref, data_emissao):
                    pulados_nota += 1; continue

                cursor.execute(f"""
                    INSERT INTO {tabela}
                        (data_emissao, numero_nota, natureza_operacao, sku_ref,
                         produto, nome_cliente, cpf_cnpj, tipo_pessoa,
                         cidade, uf, cep, endereco, numero,
                         quantidade, valor_unitario, frete, valor_total, empresa)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, (
                    data_emissao, numero_nota, natureza_op, sku_ref,
                    produto, nome_cliente, cpf_cnpj, tipo_pessoa(cpf_cnpj),
                    cidade, uf, cep, endereco, numero_endereco,
                    quantidade, valor_unit, frete, valor_total, nome
                ))
                inseridos_nota += 1

            conn.commit()
            total_inseridos += inseridos_nota
            total_pular += pulados_nota
            print(f"    Nota {numero_nota}: +{inseridos_nota} itens, {pulados_nota} duplicatas. Pausa 3s...")
            time.sleep(3)

        if pagina >= total_paginas: break
        pagina += 1
        print(f"  Prox pagina em 3s...")
        time.sleep(3)

    print(f"  {nome}: {total_inseridos} novos, {total_pular} duplicatas ignoradas")
    return total_inseridos

def main():
    inicio = datetime.now()
    print(f"Inicio: {inicio.strftime('%d/%m/%Y %H:%M:%S')}")
    print(f"Banco: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    data_ini = datetime(2026, 6, 10)
    data_fim = datetime(2026, 6, 15)

    total_geral = 0
    for nome, token, tabela in EMPRESAS:
        total_geral += processar_empresa(nome, token, tabela, conn, data_ini, data_fim)

    conn.close()
    fim = datetime.now()
    print(f"\n{'='*50}")
    print(f"  FINALIZADO: {total_geral} novos registros em {fim-inicio}")
    print(f"{'='*50}")

    if total_geral > 0:
        print("\nAgora execute: python scripts/db/refresh_vendas_geral.py")

if __name__ == "__main__":
    main()
