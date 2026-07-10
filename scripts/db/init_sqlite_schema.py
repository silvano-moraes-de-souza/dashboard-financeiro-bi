#========================================
# init_sqlite_schema.py
# Descrição:
# Criado por: Silvano Moraes de Souza
#========================================

import sqlite3, sys, os

DB_PATH = os.getenv("DB_PATH", os.path.join(os.path.dirname(__file__), "APP_financeiro.db"))

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

c.executescript("""
CREATE TABLE IF NOT EXISTS natureza (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    natureza_operacao   TEXT NOT NULL UNIQUE,
    nomenclatura        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS produtos (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    sku         TEXT,
    produto     TEXT NOT NULL,
    categoria   TEXT,
    litros      REAL,
    uni_cx      INTEGER,
    custo       REAL DEFAULT 0,
    nomenclatura TEXT
);

CREATE TABLE IF NOT EXISTS vendas_filial_b (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    data_emissao        DATE NOT NULL,
    numero_nota         TEXT NOT NULL,
    natureza_operacao   TEXT,
    sku_ref             TEXT,
    produto             TEXT,
    nome_cliente        TEXT,
    cpf_cnpj            TEXT,
    tipo_pessoa         TEXT,
    cidade              TEXT,
    uf                  TEXT,
    cep                 TEXT,
    endereco            TEXT,
    numero              TEXT,
    quantidade          REAL DEFAULT 0,
    valor_unitario      REAL DEFAULT 0,
    frete               REAL DEFAULT 0,
    valor_total         REAL DEFAULT 0,
    empresa             TEXT DEFAULT 'FILIAL_B',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vendas_filial (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    data_emissao        DATE NOT NULL,
    numero_nota         TEXT NOT NULL,
    natureza_operacao   TEXT,
    sku_ref             TEXT,
    produto             TEXT,
    nome_cliente        TEXT,
    cpf_cnpj            TEXT,
    tipo_pessoa         TEXT,
    cidade              TEXT,
    uf                  TEXT,
    cep                 TEXT,
    endereco            TEXT,
    numero              TEXT,
    quantidade          REAL DEFAULT 0,
    valor_unitario      REAL DEFAULT 0,
    frete               REAL DEFAULT 0,
    valor_total         REAL DEFAULT 0,
    empresa             TEXT DEFAULT 'FILIAL',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
""")

conn.commit()
conn.close()
print(f"Schema inicializado: {DB_PATH}")
