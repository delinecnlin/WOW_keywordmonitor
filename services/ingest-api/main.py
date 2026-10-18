"""AuctionMarket Azure API (research MVP).

Store immutable scan pages and derived listings in DuckDB; raw scan snapshots in gzip.
Run single Uvicorn worker because DuckDB file writes are serialized here.
"""
from __future__ import annotations

from datetime import datetime, timezone
import gzip
import hashlib
import hmac
import json
import os
from pathlib import Path
import threading

import duckdb
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request

DATA_DIR = Path(os.getenv("MARKET_DATA_DIR", "/data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "market.duckdb"
LOCK = threading.RLock()
app = FastAPI(title="AuctionMarket Research API", version="0.1.0")

def _db() -> duckdb.DuckDBPyConnection:
    con = duckdb.connect(str(DB_PATH))
    con.execute("""CREATE TABLE IF NOT EXISTS scans (
        scan_id VARCHAR PRIMARY KEY, observed_at BIGINT, realm VARCHAR, faction VARCHAR,
        query VARCHAR, page INTEGER, reported_total INTEGER, complete BOOLEAN,
        coverage VARCHAR, rows_count INTEGER, missing_owner_rows INTEGER,
        raw_sha256 VARCHAR, ingested_at TIMESTAMP
    )""")
    con.execute("""CREATE TABLE IF NOT EXISTS listings (
        scan_id VARCHAR, listing_index INTEGER, item_id BIGINT, item_name VARCHAR,
        quantity BIGINT, buyout_copper BIGINT, unit_buyout_copper BIGINT,
        seller_character VARCHAR
    )""")
    con.execute("""CREATE TABLE IF NOT EXISTS gold_quotes (
        quote_id VARCHAR PRIMARY KEY, observed_at BIGINT, realm VARCHAR, faction VARCHAR,
        yuan_per_1000g DOUBLE, visible_depth_1000g DOUBLE,
        source VARCHAR, notes VARCHAR, ingested_at TIMESTAMP
    )""")
    return con


def require_auth(authorization: str | None = Header(default=None)) -> None:
    secret = os.getenv("AUCTION_API_TOKEN")
    if not secret:
        raise HTTPException(503, "AUCTION_API_TOKEN is not configured")
    provided = (authorization or "").removeprefix("Bearer ").strip()
    if not hmac.compare_digest(provided, secret):
        raise HTTPException(401, "Missing or invalid bearer token")


@app.get("/api/health")
def health() -> dict:
    return {"ok": True, "service": "AuctionMarket API", "note": "AH observations are not real sales"}


@app.post("/api/scans", dependencies=[Depends(require_auth)])
async def ingest_scans(request: Request) -> dict:
    if int(request.headers.get("content-length") or 0) > 12 * 1024 * 1024:
        raise HTTPException(413, "Payload too large")
    data = await request.json()
    scans = data.get("scans") if isinstance(data, dict) else None
    if not isinstance(scans, list) or not 1 <= len(scans) <= 20:
        raise HTTPException(422, "Expected 1–20 scans")
    for scan in scans:
        if not isinstance(scan, dict) or not isinstance(scan.get("scan_id"), str) or not 3 <= len(scan["scan_id"]) <= 160:
            raise HTTPException(422, "Missing/invalid scan_id")
        if not isinstance(scan.get("rows"), list) or len(scan["rows"]) > 10000:
            raise HTTPException(422, "Invalid rows")
        if not isinstance(scan.get("observed_at"), int) or scan["observed_at"] < 1500000000:
            raise HTTPException(422, "Invalid observation time")
        if len(json.dumps(scan, ensure_ascii=False)) > 5_000_000:
            raise HTTPException(413, "Single scan too large")

    ids: list[str] = []
    added = 0
    with LOCK:
        con = _db()
        try:
            for scan in scans:
                scan_id = scan["scan_id"]
                present = con.execute("SELECT 1 FROM scans WHERE scan_id = ?", [scan_id]).fetchone()
                if present:
                    ids.append(scan_id)
                    continue
                payload = json.dumps(scan, ensure_ascii=False, sort_keys=True).encode("utf-8")
                digest = hashlib.sha256(payload).hexdigest()
                raw = DATA_DIR / "raw" / digest[:2] / (digest + ".json.gz")
                raw.parent.mkdir(parents=True, exist_ok=True)
                if not raw.exists():
                    temporary = raw.with_name(raw.name + ".tmp")
                    temporary.write_bytes(gzip.compress(payload))
                    os.replace(temporary, raw)
                con.execute("BEGIN TRANSACTION")
                try:
                    con.execute("""INSERT INTO scans VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", [
                        scan_id, scan["observed_at"], str(scan.get("realm") or "UNKNOWN"),
                        str(scan.get("faction") or "UNKNOWN"), str(scan.get("query") or ""),
                        int(scan.get("page") or 0), scan.get("reported_total"),
                        bool(scan.get("complete")), str(scan.get("coverage") or "unknown"),
                        len(scan["rows"]), int(scan.get("missing_owner_rows") or 0),
                        digest, datetime.now(timezone.utc),
                    ])
                    for row in scan["rows"]:
                        if not isinstance(row, dict):
                            raise ValueError("Invalid listing row")
                        con.execute("INSERT INTO listings VALUES (?, ?, ?, ?, ?, ?, ?, ?)", [
                            scan_id, int(row.get("index") or 0), row.get("item_id"),
                            str(row.get("item_name") or ""), int(row.get("quantity") or 0),
                            int(row.get("buyout_copper") or 0),
                            row.get("unit_buyout_copper"), row.get("seller_character"),
                        ])
                    con.execute("COMMIT")
                except Exception:
                    con.execute("ROLLBACK")
                    raise
                ids.append(scan_id)
                added += 1
        finally:
            con.close()
    return {"accepted_ids": ids, "newly_stored": added, "duplicates": len(ids) - added}


@app.get("/api/overview", dependencies=[Depends(require_auth)])
def overview() -> dict:
    with LOCK:
        con = _db()
        try:
            scan = con.execute("""SELECT scan_id, observed_at, realm, faction, query, page,
                  reported_total, complete, coverage, rows_count, missing_owner_rows
                  FROM scans ORDER BY observed_at DESC, ingested_at DESC LIMIT 1""").fetchone()
            if not scan:
                return {"status": "no_data", "caveat": "尚无实测 AH 数据"}
            keys = ("scan_id", "observed_at", "realm", "faction", "query", "page",
                    "reported_total", "complete", "coverage", "rows_count", "missing_owner_rows")
            items = con.execute("""SELECT item_name, SUM(quantity)::BIGINT AS visible_qty,
                       COUNT(*) AS rows_count, SUM(CASE WHEN seller_character IS NULL THEN quantity ELSE 0 END)::BIGINT AS unknown_seller_qty,
                       MIN(CASE WHEN unit_buyout_copper > 0 THEN unit_buyout_copper END) AS min_unit_copper
                       FROM listings WHERE scan_id = ? GROUP BY item_name ORDER BY visible_qty DESC LIMIT 50""", [scan[0]]).fetchall()
            return {
                "status": "ok", "scan": dict(zip(keys, scan)),
                "items": [dict(zip(("name", "visible_qty", "listings", "unknown_seller_qty", "min_unit_copper"), x)) for x in items],
                "scope": "latest_observed_page_only",
                "caveat": "不是全服库存、当日采集量或成交量。"
            }
        finally:
            con.close()


@app.get("/api/sellers", dependencies=[Depends(require_auth)])
def sellers(item_name: str = Query(default="黑莲花", max_length=80)) -> dict:
    with LOCK:
        con = _db()
        try:
            scan = con.execute("""SELECT s.scan_id, s.observed_at, s.coverage
                FROM scans s JOIN listings l ON s.scan_id = l.scan_id
                WHERE l.item_name = ? ORDER BY s.observed_at DESC, s.ingested_at DESC LIMIT 1""", [item_name]).fetchone()
            if not scan:
                return {"status": "no_data", "item": item_name, "sellers": []}
            rows = con.execute("""SELECT seller_character, SUM(quantity)::BIGINT qty
                FROM listings WHERE scan_id = ? AND item_name = ?
                GROUP BY seller_character ORDER BY qty DESC""", [scan[0], item_name]).fetchall()
            total = sum(int(r[1]) for r in rows)
            known = sum(int(r[1]) for r in rows if r[0])
            visible = [{"character": r[0], "visible_qty": int(r[1])} for r in rows if r[0]]
            visible.sort(key=lambda x: x["visible_qty"], reverse=True)
            return {
                "status": "ok", "item": item_name, "scan_id": scan[0], "observed_at": scan[1],
                "coverage": scan[2], "total_visible_qty": total, "known_seller_qty": known,
                "known_fraction": known / total if total else None,
                "hhi_known_only": sum((v["visible_qty"] / known) ** 2 for v in visible) if known else None,
                "top5_share_known_only": sum(v["visible_qty"] for v in visible[:5]) / known if known else None,
                "sellers": visible[:50],
                "caveat": "卖家角色不等于工作室；仅此扫描页，无法证明全服份额或交易完成。"
            }
        finally:
            con.close()


@app.get("/api/seller-daily", dependencies=[Depends(require_auth)])
def seller_daily(item_name: str = Query(default="黑莲花", max_length=80)) -> dict:
    with LOCK:
        con = _db()
        try:
            rows = con.execute("""WITH per_page AS (
                SELECT CAST(to_timestamp(s.observed_at) AS DATE) AS day, l.seller_character,
                       s.scan_id, SUM(l.quantity)::BIGINT AS qty
                FROM scans s JOIN listings l ON s.scan_id = l.scan_id
                WHERE l.item_name = ? AND l.seller_character IS NOT NULL
                GROUP BY 1, 2, 3
            )
            SELECT CAST(day AS VARCHAR), seller_character, MAX(qty)::BIGINT,
                   COUNT(*)::INTEGER
            FROM per_page GROUP BY 1, 2 ORDER BY day DESC, MAX(qty) DESC LIMIT 500""", [item_name]).fetchall()
            return {
                "item": item_name,
                "records": [dict(zip(("day", "seller_character", "max_observed_page_qty", "snapshots_seen"), r)) for r in rows],
                "caveat": "同日每卖家单页最大可见量；不叠加重复扫描，也不代表日新增产量。"
            }
        finally:
            con.close()


@app.get("/api/history", dependencies=[Depends(require_auth)])
def history(item_name: str = Query(default="黑莲花", max_length=80), limit: int = Query(default=300, ge=1, le=1000)) -> dict:
    with LOCK:
        con = _db()
        try:
            rows = con.execute("""SELECT s.scan_id, s.observed_at, s.page, s.reported_total,
                    s.complete, s.coverage, SUM(l.quantity)::BIGINT,
                    MIN(CASE WHEN l.unit_buyout_copper > 0 THEN l.unit_buyout_copper END)
                FROM scans s JOIN listings l ON s.scan_id = l.scan_id
                WHERE l.item_name = ? GROUP BY 1,2,3,4,5,6 ORDER BY s.observed_at DESC LIMIT ?""",
                [item_name, limit]).fetchall()
            return {"item": item_name, "snapshots": [
                dict(zip(("scan_id", "observed_at", "page", "reported_total", "complete",
                          "coverage", "visible_qty", "min_unit_copper"), r)) for r in rows],
                "caveat": "分页快照不可直接加总为市场库存。"}
        finally:
            con.close()


@app.post("/api/gold-quotes", dependencies=[Depends(require_auth)])
async def add_gold_quote(request: Request) -> dict:
    d = await request.json()
    try:
        when = int(d["observed_at"])
        price = float(d["yuan_per_1000g"])
        if when < 1500000000 or not 0 < price < 1_000_000:
            raise ValueError("Out of bounds")
        source = str(d.get("source") or "manual_7881_reference")[:120]
        realm = str(d.get("realm") or "硬核服")[:120]
        faction = str(d.get("faction") or "Alliance")[:40]
        depth = d.get("visible_depth_1000g")
        if depth is not None:
            depth = float(depth)
            if not 0 <= depth < 1e10:
                raise ValueError("Invalid depth")
        notes = str(d.get("notes") or "")[:400]
    except (KeyError, ValueError, TypeError) as exc:
        raise HTTPException(422, "Invalid quote fields") from exc
    quote_id = hashlib.sha256(f"{when}|{price}|{source}|{realm}|{faction}".encode()).hexdigest()
    with LOCK:
        con = _db()
        try:
            con.execute("""INSERT INTO gold_quotes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (quote_id) DO NOTHING""", [
                quote_id, when, realm, faction, price, depth, source, notes, datetime.now(timezone.utc)
            ])
        finally:
            con.close()
    return {"quote_id": quote_id, "source": source, "status": "reference_quote_not_trade"}


@app.get("/api/gold-quotes", dependencies=[Depends(require_auth)])
def gold_quotes(limit: int = Query(default=200, ge=1, le=1000)) -> dict:
    with LOCK:
        con = _db()
        try:
            rows = con.execute("""SELECT observed_at, realm, faction, yuan_per_1000g,
                visible_depth_1000g, source, notes FROM gold_quotes
                ORDER BY observed_at DESC LIMIT ?""", [limit]).fetchall()
            return {"quotes": [dict(zip(("observed_at", "realm", "faction",
                "yuan_per_1000g", "visible_depth_1000g", "source", "notes"), r)) for r in rows],
                "caveat": "第三方挂牌观察不等于成交价格；未验证 7881 自动采集权限。"}
        finally:
            con.close()
