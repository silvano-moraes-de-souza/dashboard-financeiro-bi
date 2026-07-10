#========================================
# etl_supabase.py
# Descrição:
# Criado por: Silvano Moraes de Souza
#========================================

# -*- coding: utf-8 -*-
# ETL via Supabase REST API (Data API)
# Nao precisa de supabase-py - usa requests puro
import sqlite3
import requests
import sys
import os
import json
from datetime import datetime
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding='utf-8')

load_dotenv()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "APP_financeiro.db")
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://seu-projeto.supabase.co")
SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates",
}

BATCH_SIZE = 500


def upsert_table(table_name, sqlite_conn):
    cursor = sqlite_conn.cursor()
    cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
    total = cursor.fetchone()[0]
    print(f"\n[{table_name}] {total:,} registros")

    if total == 0:
        return

    cursor.execute(f"SELECT * FROM {table_name} ORDER BY id")
    rows = cursor.fetchall()
    columns = [desc[0] for desc in cursor.description]

    url = f"{SUPABASE_URL}/rest/v1/{table_name}"
    upserted = 0
    batch = []

    for row in rows:
        record = {}
        for i, col in enumerate(columns):
            val = row[i]
            if isinstance(val, datetime):
                val = val.isoformat()
            record[col] = val
        batch.append(record)

        if len(batch) >= BATCH_SIZE:
            try:
                resp = requests.post(url, headers=HEADERS, json=batch, timeout=30)
                if resp.status_code in (200, 201):
                    upserted += len(batch)
                else:
                    print(f"\n  ERRO batch: {resp.status_code} {resp.text[:200]}")
            except Exception as e:
                print(f"\n  ERRO: {e}")
            batch = []
            print(f"  {upserted}/{total} ({upserted*100//total}%)", end="\r")

    if batch:
        try:
            resp = requests.post(url, headers=HEADERS, json=batch, timeout=30)
            if resp.status_code in (200, 201):
                upserted += len(batch)
            else:
                print(f"\n  ERRO final: {resp.status_code} {resp.text[:200]}")
        except Exception as e:
            print(f"\n  ERRO: {e}")

    print(f"\n  {table_name}: {upserted:,}/{total:,} upserted")
    return upserted


def run_sql(query):
    """Executa SQL via Management API"""
    TOKEN = os.getenv("SUPABASE_MGMT_TOKEN")
    if not TOKEN:
        print("  ERRO: SUPABASE_MGMT_TOKEN nao definido nas variaveis de ambiente")
        return False
    headers_mgmt = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    }
    resp = requests.post(
        f"https://api.supabase.com/v1/projects/{SUPABASE_URL.split('.')[0].split('//')[1]}/database/query",
        headers=headers_mgmt,
        json={"query": query},
        timeout=60
    )
    if resp.status_code not in (200, 201):
        print(f"  ERRO: {resp.text[:200]}")
        return False
    return True


def main():
    print("=" * 60)
    print(f"  ETL via REST API - {datetime.now().strftime('%d/%m/%Y %H:%M')}")
    print(f"  Supabase: {SUPABASE_URL}")
    print("=" * 60)

    if not os.path.exists(DB_PATH):
        print(f"ERRO: {DB_PATH} nao encontrado")
        return

    conn = sqlite3.connect(DB_PATH)
    total_upserted = 0

    # 1. Tabelas de referencia (pequenas)
    total_upserted += upsert_table("natureza", conn) or 0
    total_upserted += upsert_table("produtos", conn) or 0

    # 2. Tabelas de vendas (grandes)
    total_upserted += upsert_table("vendas_filial_b", conn) or 0
    total_upserted += upsert_table("vendas_filial", conn) or 0

    # 3. Refresh vendas_geral
    print(f"\n[Refresh vendas_geral]... ", end="")
    if run_sql("SELECT refresh_vendas_geral()"):
        print("OK")
    else:
        print("Tentando INSERT direto...")
        run_sql("DELETE FROM vendas_geral")
        run_sql("INSERT INTO vendas_geral SELECT * FROM view_vendas_geral")

    # 4. Verificar
    result = run_sql("SELECT COUNT(*) as total FROM vendas_geral")
    if result:
        print(f"\nvendas_geral no Supabase: atualizada")

    conn.close()
    print(f"\nETL concluido! Total: {total_upserted:,} registros upserted")


if __name__ == "__main__":
    main()
