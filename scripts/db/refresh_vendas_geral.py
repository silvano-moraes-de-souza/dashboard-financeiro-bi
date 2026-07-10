import sqlite3, os
from dotenv import load_dotenv

load_dotenv()
DB_PATH = os.getenv("DB_PATH", "APP_financeiro.db")

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

c.execute("SELECT COUNT(*) FROM view_vendas_geral")
view_count = c.fetchone()[0]

c.execute("SELECT COUNT(*) FROM vendas_geral")
table_count = c.fetchone()[0]
c.execute("SELECT MAX(data_emissao) FROM vendas_geral")
max_date_old = c.fetchone()[0]
c.execute("SELECT MAX(data_emissao) FROM view_vendas_geral")
max_date_view = c.fetchone()[0]

print(f"vendas_geral (antes): {table_count} registros, ate {max_date_old}")
print(f"view_vendas_geral:    {view_count} registros, ate {max_date_view}")

print("\nAtualizando vendas_geral...")
c.execute("DELETE FROM vendas_geral")
c.execute("INSERT INTO vendas_geral SELECT * FROM view_vendas_geral")
conn.commit()

c.execute("SELECT COUNT(*) FROM vendas_geral")
new_count = c.fetchone()[0]
c.execute("SELECT MAX(data_emissao) FROM vendas_geral")
new_max = c.fetchone()[0]

print(f"vendas_geral (depois): {new_count} registros, ate {new_max}")
conn.close()
