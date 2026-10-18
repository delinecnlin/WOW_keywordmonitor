"""Optional research snapshot export to Parquet for offline/backtesting analysis.

Run manually in the API container, or after a consistent backup:
    python /app/export_parquet.py
Does not mutate the DuckDB/source snapshot tables.
"""
from __future__ import annotations

import os
from pathlib import Path

import duckdb


def export(data_dir: Path) -> list[Path]:
    database = data_dir / "market.duckdb"
    if not database.exists():
        raise FileNotFoundError("No market.duckdb yet: " + str(database))
    target_dir = data_dir / "exports"
    target_dir.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(database), read_only=True)
    exported: list[Path] = []
    try:
        for table in ("scans", "listings", "gold_quotes"):
            target = target_dir / f"{table}.parquet"
            temporary = target_dir / f"{table}.partial.parquet"
            quoted = str(temporary).replace("'", "''")
            con.execute(f"COPY (SELECT * FROM {table}) TO '{quoted}' (FORMAT PARQUET, COMPRESSION ZSTD)")
            os.replace(temporary, target)
            exported.append(target)
    finally:
        con.close()
    return exported


if __name__ == "__main__":
    for path in export(Path(os.getenv("MARKET_DATA_DIR", "/data"))):
        print(path)
