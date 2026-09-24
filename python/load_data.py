"""Load the Olist CSVs into PostgreSQL.

Usage (from the project root):
    python python/load_data.py

Reads DATABASE_URL from .env, (re)creates the tables with sql/00_schema.sql,
bulk-loads each CSV with COPY, then checks row counts against the CSVs.
"""

import io
import os
from pathlib import Path

import pandas as pd
import psycopg2
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
SCHEMA = ROOT / "sql" / "00_schema.sql"

# Parents before children so foreign keys are satisfied.
TABLES = [
    ("customers", "olist_customers_dataset.csv"),
    ("sellers", "olist_sellers_dataset.csv"),
    ("category_translation", "product_category_name_translation.csv"),
    ("products", "olist_products_dataset.csv"),
    ("geolocation", "olist_geolocation_dataset.csv"),
    ("orders", "olist_orders_dataset.csv"),
    ("order_items", "olist_order_items_dataset.csv"),
    ("order_payments", "olist_order_payments_dataset.csv"),
    ("order_reviews", "olist_order_reviews_dataset.csv"),
]


def read_csv(table: str, filename: str) -> pd.DataFrame:
    # Read everything as text so zip prefixes keep leading zeros.
    df = pd.read_csv(RAW / filename, dtype=str)

    if table == "products":
        df = df.rename(columns={
            "product_name_lenght": "product_name_length",
            "product_description_lenght": "product_description_length",
        })
        # "40.0" -> 40 so the values fit INTEGER columns.
        num_cols = df.columns.drop(["product_id", "product_category_name"])
        df[num_cols] = df[num_cols].apply(pd.to_numeric).astype("Int64")

    if table == "geolocation":
        df["geolocation_lat"] = pd.to_numeric(df["geolocation_lat"])
        df["geolocation_lng"] = pd.to_numeric(df["geolocation_lng"])
        # One averaged point per zip prefix; most common city/state.
        df = (
            df.groupby("geolocation_zip_code_prefix")
            .agg(
                lat=("geolocation_lat", "mean"),
                lng=("geolocation_lng", "mean"),
                city=("geolocation_city", lambda s: s.mode().iat[0]),
                state=("geolocation_state", lambda s: s.mode().iat[0]),
            )
            .round(6)
            .reset_index()
            .rename(columns={"geolocation_zip_code_prefix": "zip_code_prefix"})
        )

    return df


def copy_df(cur, table: str, df: pd.DataFrame) -> None:
    buf = io.StringIO()
    df.to_csv(buf, index=False, header=False)  # NaN -> empty -> NULL
    buf.seek(0)
    cols = ", ".join(df.columns)
    cur.copy_expert(f"COPY {table} ({cols}) FROM STDIN WITH (FORMAT csv)", buf)


def main() -> None:
    load_dotenv(ROOT / ".env")
    url = os.getenv("DATABASE_URL")
    if not url or "PASTE" in url:
        raise SystemExit("Set DATABASE_URL in .env first.")

    with psycopg2.connect(url) as conn, conn.cursor() as cur:
        print("Creating tables...")
        cur.execute(SCHEMA.read_text(encoding="utf-8"))

        expected = {}
        for table, filename in TABLES:
            df = read_csv(table, filename)
            print(f"Loading {table:<22} {len(df):>9,} rows")
            copy_df(cur, table, df)
            expected[table] = len(df)

        print("\nRow count check:")
        for table, n in expected.items():
            cur.execute(f"SELECT COUNT(*) FROM {table}")
            actual = cur.fetchone()[0]
            status = "OK" if actual == n else "MISMATCH"
            print(f"  {table:<22} {actual:>9,}  {status}")

    print("\nDone.")


if __name__ == "__main__":
    main()
