"""
Olist E-Commerce — Step 1: load raw CSVs into DuckDB and profile them.

Usage (from the project root):
    python load_data.py

Expects the 9 Olist CSVs in data/raw/. Creates olist.duckdb with one table per CSV
(short names, e.g. 'orders', 'order_items') and prints a quick data-quality report.
"""
import glob
import os
import re

import duckdb

RAW_DIR = os.path.join("data", "raw")
DB_PATH = "olist.duckdb"


def short_name(path: str) -> str:
    """olist_order_items_dataset.csv -> order_items"""
    name = os.path.splitext(os.path.basename(path))[0]
    name = re.sub(r"^olist_", "", name)
    name = re.sub(r"_dataset$", "", name)
    return name


def main() -> None:
    files = sorted(glob.glob(os.path.join(RAW_DIR, "*.csv")))
    if not files:
        raise SystemExit(f"No CSVs found in {RAW_DIR}/ — unzip the Kaggle download there first.")

    con = duckdb.connect(DB_PATH)

    print("=== Loading tables ===")
    for f in files:
        table = short_name(f)
        con.execute(
            f"CREATE OR REPLACE TABLE {table} AS "
            f"SELECT * FROM read_csv_auto(?, header=true, sample_size=-1)",
            [f],
        )
        rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        cols = len(con.execute(f"DESCRIBE {table}").fetchall())
        print(f"{table:<40} {rows:>9,} rows  {cols:>3} cols")

    print("\n=== Null counts (columns with any nulls) ===")
    for (table,) in con.execute("SHOW TABLES").fetchall():
        for col, *_ in con.execute(f"DESCRIBE {table}").fetchall():
            nulls = con.execute(f'SELECT COUNT(*) - COUNT("{col}") FROM {table}').fetchone()[0]
            if nulls:
                print(f"{table}.{col:<35} {nulls:>7,} nulls")

    print("\n=== Quick sanity checks ===")
    checks = {
        "Order date range": "SELECT MIN(order_purchase_timestamp), MAX(order_purchase_timestamp) FROM orders",
        "Order status mix": "SELECT order_status, COUNT(*) AS n FROM orders GROUP BY 1 ORDER BY n DESC",
        "Unique customers (customer_unique_id)": "SELECT COUNT(DISTINCT customer_unique_id) FROM customers",
        "Duplicate order_ids in orders": "SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders",
    }
    for label, sql in checks.items():
        print(f"\n{label}:")
        for row in con.execute(sql).fetchall():
            print("  ", row)

    con.close()
    print(f"\nDone. Database saved to {DB_PATH}")


if __name__ == "__main__":
    main()
