"""
Olist E-Commerce - Step 2: build the star schema and answer the business questions.

Usage (from the project root, after load_data.py):
    python run_analysis.py

What it does:
  1. Runs sql/01_build_model.sql  -> clean fact & dimension tables in olist.duckdb
  2. Exports those tables to data/clean/*.csv  (these are what Power BI will load)
  3. Runs every query in sql/02_business_questions.sql, prints the results
     and saves each one to outputs/Qn.csv
"""
import os
import re

import duckdb

DB_PATH = "olist.duckdb"
MODEL_TABLES = ["fact_orders", "fact_order_items", "dim_customers", "dim_products", "dim_sellers"]


def read_sql(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def split_questions(sql: str):
    """Split the questions file into (title, query) pairs using the '-- Qn:' lines."""
    parts = re.split(r"^-- (Q\d+): (.*)$", sql, flags=re.MULTILINE)
    # parts = [header, 'Q1', 'title', 'query', 'Q2', 'title', 'query', ...]
    for i in range(1, len(parts), 3):
        yield parts[i], parts[i + 1].strip(), parts[i + 2].strip().rstrip(";")


def main() -> None:
    if not os.path.exists(DB_PATH):
        raise SystemExit("olist.duckdb not found - run load_data.py first.")

    con = duckdb.connect(DB_PATH)

    print("=== 1. Building star schema ===")
    con.execute(read_sql(os.path.join("sql", "01_build_model.sql")))
    os.makedirs(os.path.join("data", "clean"), exist_ok=True)
    for t in MODEL_TABLES:
        rows = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        out = os.path.join("data", "clean", f"{t}.csv")
        con.execute(f"COPY {t} TO '{out}' (HEADER, DELIMITER ',')")
        print(f"{t:<20} {rows:>8,} rows  -> {out}")

    print("\n=== 2. Business questions ===")
    os.makedirs("outputs", exist_ok=True)
    for qid, title, query in split_questions(read_sql(os.path.join("sql", "02_business_questions.sql"))):
        df = con.execute(query).df()
        df.to_csv(os.path.join("outputs", f"{qid}.csv"), index=False)
        print(f"\n--- {qid}: {title} ---")
        print(df.to_string(index=False))

    con.close()
    print("\nDone. Clean tables are in data/clean/, query results in outputs/.")


if __name__ == "__main__":
    main()
