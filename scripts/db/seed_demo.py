"""Create a demo SQLite database so the dashboard runs without the ERP.

    python scripts/db/seed_demo.py            # writes APP_financeiro.db (or $DB_PATH)

Everything here is synthetic: products, customers, cities and amounts are
generated with a fixed seed. The schema and the consolidated vendas_geral
table follow the production layout (see sql/security_emergency_fix.sql).
"""

from __future__ import annotations

import os
import random
import re
import sqlite3
from datetime import date, timedelta
from pathlib import Path

# Reuse the DDL of init_sqlite_schema.py without executing that script.
_INIT = (Path(__file__).resolve().parent / "init_sqlite_schema.py").read_text(encoding="utf-8")
SCHEMA = re.search(r'executescript\("""(.*?)"""\)', _INIT, re.S).group(1)

DB_PATH = os.getenv("DB_PATH", "APP_financeiro.db")
SEED = 7

PRODUCTS = [
    # sku, name, category, liters, units per box, cost, base price
    ("DET-500", "Detergente Neutro 500ml", "Detergentes", 0.5, 24, 1.10, 2.40),
    ("DET-5L", "Detergente Neutro 5L", "Detergentes", 5.0, 4, 8.90, 17.90),
    ("DES-1L", "Desinfetante Lavanda 1L", "Desinfetantes", 1.0, 12, 2.30, 5.20),
    ("DES-5L", "Desinfetante Lavanda 5L", "Desinfetantes", 5.0, 4, 9.80, 21.50),
    ("AMA-2L", "Amaciante Floral 2L", "Amaciantes", 2.0, 6, 5.40, 11.90),
    ("AMA-5L", "Amaciante Floral 5L", "Amaciantes", 5.0, 4, 12.10, 26.90),
    ("SAB-1L", "Sabao Liquido 1L", "Lava-roupas", 1.0, 12, 4.20, 9.30),
    ("SAB-3L", "Sabao Liquido 3L", "Lava-roupas", 3.0, 6, 11.50, 24.90),
    ("SHA-400", "Shampoo Hidratante 400ml", "Cosmeticos", 0.4, 12, 4.90, 13.90),
    ("CON-400", "Condicionador Hidratante 400ml", "Cosmeticos", 0.4, 12, 5.10, 14.90),
    ("SAB-90", "Sabonete Liquido 250ml", "Cosmeticos", 0.25, 24, 2.10, 6.50),
    ("LIM-1L", "Limpa Vidros 500ml", "Multiuso", 0.5, 12, 2.60, 6.90),
    ("MUL-1L", "Multiuso Tradicional 500ml", "Multiuso", 0.5, 24, 1.70, 3.90),
    ("ALV-1L", "Agua Sanitaria 1L", "Alvejantes", 1.0, 12, 0.90, 2.60),
    ("ALV-5L", "Agua Sanitaria 5L", "Alvejantes", 5.0, 4, 3.80, 9.90),
]  # fmt: skip

CITIES = [
    ("Sorocaba", "SP", 0.22), ("Sao Paulo", "SP", 0.18), ("Campinas", "SP", 0.10),
    ("Itu", "SP", 0.06), ("Votorantim", "SP", 0.05), ("Curitiba", "PR", 0.07),
    ("Belo Horizonte", "MG", 0.07), ("Rio de Janeiro", "RJ", 0.08),
    ("Londrina", "PR", 0.04), ("Uberlandia", "MG", 0.04), ("Goiania", "GO", 0.04),
    ("Florianopolis", "SC", 0.05),
]  # fmt: skip

CUSTOMER_KINDS = ["Mercado", "Atacado", "Distribuidora", "Loja", "Supermercado"]
SURNAMES = ["Silva", "Oliveira", "Souza", "Pereira", "Costa", "Almeida", "Ferreira", "Lima"]


def customers(rng: random.Random, n: int) -> list[tuple[str, str, str, str]]:
    out = []
    for i in range(n):
        city, uf, _ = rng.choices(CITIES, weights=[c[2] for c in CITIES])[0]
        kind = rng.choice(CUSTOMER_KINDS)
        pj = kind != "Loja" or rng.random() < 0.7
        name = f"{kind} {rng.choice(SURNAMES)} {i + 1:03d}"
        out.append((name, "PJ" if pj else "PF", city, uf))
    return out


def sales(rng: random.Random, company: str, start: date, months: int, base: float):
    buyers = customers(rng, 140)
    weights = [rng.paretovariate(1.3) for _ in buyers]
    rows, note = [], 1000 if company == "FILIAL" else 50000
    for m in range(months):
        month_start = date(start.year + (start.month - 1 + m) // 12, (start.month - 1 + m) % 12 + 1, 1)
        season = 1.25 if month_start.month in (11, 12) else (0.85 if month_start.month in (1, 2) else 1.0)
        trend = 1 + 0.018 * m
        for _ in range(int(base * season * trend)):
            day = month_start + timedelta(days=rng.randrange(28))
            note += 1
            client = rng.choices(buyers, weights=weights)[0]
            for sku, prod, _cat, _l, uni_cx, _cost, price in rng.sample(PRODUCTS, rng.randint(1, 4)):
                boxes = rng.randint(1, 12)
                qty = boxes * uni_cx
                unit = round(price * rng.uniform(0.92, 1.06), 2)
                total = round(qty * unit, 2)
                freight = round(total * rng.uniform(0.0, 0.04), 2)
                rows.append((day.isoformat(), str(note), "Venda de mercadoria", sku, prod,
                             client[0], client[1], client[2], client[3], qty, unit, freight,
                             total, company))  # fmt: skip
    return rows


def main() -> None:
    rng = random.Random(SEED)
    if Path(DB_PATH).exists():
        Path(DB_PATH).unlink()
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(SCHEMA)
    conn.execute("INSERT INTO natureza (natureza_operacao, nomenclatura) VALUES (?, ?)",
                 ("Venda de mercadoria", "VENDA"))  # fmt: skip
    conn.executemany(
        "INSERT INTO produtos (sku, produto, categoria, litros, uni_cx, custo, nomenclatura) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        [(s, p, c, lt, u, cost, p) for s, p, c, lt, u, cost, _ in PRODUCTS],
    )
    cols = ("data_emissao, numero_nota, natureza_operacao, sku_ref, produto, nome_cliente, "
            "tipo_pessoa, cidade, uf, quantidade, valor_unitario, frete, valor_total, empresa")  # fmt: skip
    start = date(2024, 10, 1)
    for table, company, base in (("vendas_filial", "FILIAL", 55), ("vendas_filial_b", "FILIAL_B", 35)):
        conn.executemany(f"INSERT INTO {table} ({cols}) VALUES ({','.join('?' * 14)})",
                         sales(rng, company, start, 24, base))  # fmt: skip
    # SQLite version of view_vendas_geral: both companies, sales only, with product attributes.
    select = """
        SELECT v.id, v.data_emissao, v.numero_nota, v.natureza_operacao, v.sku_ref, v.produto,
               v.nome_cliente AS cliente, v.tipo_pessoa, v.cidade, v.uf, v.quantidade,
               v.valor_unitario, v.frete, v.valor_total AS val_item, v.empresa,
               n.nomenclatura, p.categoria AS categoria_produto, p.litros AS litros_produto,
               p.uni_cx AS uni_cx_produto, v.quantidade * 1.0 / p.uni_cx AS qtd_caixas,
               CAST(strftime('%Y', v.data_emissao) AS INTEGER) AS ano,
               CAST(strftime('%m', v.data_emissao) AS INTEGER) AS mes,
               CAST(strftime('%d', v.data_emissao) AS INTEGER) AS dia,
               strftime('%Y-%m', v.data_emissao) AS ano_mes
        FROM {t} v
        JOIN natureza n ON n.natureza_operacao = v.natureza_operacao
        JOIN produtos p ON p.produto = v.produto
        WHERE n.nomenclatura = 'VENDA'"""
    conn.execute("DROP TABLE IF EXISTS vendas_geral")
    conn.execute("CREATE TABLE vendas_geral AS " + select.format(t="vendas_filial")
                 + " UNION ALL " + select.format(t="vendas_filial_b"))  # fmt: skip
    conn.commit()
    n = conn.execute("SELECT count(*), round(sum(val_item)) FROM vendas_geral").fetchone()
    print(f"{DB_PATH}: {n[0]:,} sale lines, R$ {n[1]:,.0f} (synthetic)")


if __name__ == "__main__":
    main()
