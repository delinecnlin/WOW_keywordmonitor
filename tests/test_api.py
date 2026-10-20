import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient


class TestAPI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        os.environ["MARKET_DATA_DIR"] = cls.temp.name
        os.environ["AUCTION_API_TOKEN"] = "unit-test-token"
        research = Path(__file__).resolve().parents[1] / "services" / "market-analysis" / "core.py"
        research_spec = importlib.util.spec_from_file_location("research_core", research)
        research_module = importlib.util.module_from_spec(research_spec)
        sys.modules["research_core"] = research_module
        research_spec.loader.exec_module(research_module)
        spec = importlib.util.spec_from_file_location(
            "auction_api", Path(__file__).resolve().parents[1] / "services" / "ingest-api" / "main.py"
        )
        cls.module = importlib.util.module_from_spec(spec)
        sys.modules["auction_api"] = cls.module
        spec.loader.exec_module(cls.module)
        cls.client = TestClient(cls.module.app)
        cls.auth = {"Authorization": "Bearer unit-test-token"}

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_auth_and_dedup(self):
        scan = {
            "scan_id": "test-001", "observed_at": 1790000000, "realm": "硬核服",
            "faction": "Alliance", "coverage": "single_page", "page": 0,
            "query": "黑莲花", "reported_total": 2, "complete": True,
            "time_left_api_available": True, "missing_time_left_rows": 1,
            "rows": [
                {"index": 1, "item_id": 13468, "item_name": "黑莲花", "quantity": 2,
                 "buyout_copper": 200000, "unit_buyout_copper": 100000, "seller_character": "甲",
                 "time_left_bucket": 2},
                {"index": 2, "item_id": 13468, "item_name": "黑莲花", "quantity": 3,
                 "buyout_copper": 300000, "unit_buyout_copper": 100000, "seller_character": None},
            ],
        }
        self.assertEqual(self.client.get("/api/overview").status_code, 401)
        one = self.client.post("/api/scans", json={"scans": [scan]}, headers=self.auth)
        self.assertEqual(one.status_code, 200, one.text)
        self.assertEqual(one.json()["newly_stored"], 1)
        two = self.client.post("/api/scans", json={"scans": [scan]}, headers=self.auth)
        self.assertEqual(two.json()["newly_stored"], 0)
        overview = self.client.get("/api/overview", headers=self.auth).json()
        self.assertEqual(overview["items"][0]["visible_qty"], 5)
        sellers = self.client.get("/api/sellers", headers=self.auth).json()
        self.assertEqual(sellers["known_fraction"], 2 / 5)
        self.assertEqual(sellers["coverage"], "single_page")
        history = self.client.get("/api/history", headers=self.auth).json()["snapshots"][0]
        self.assertTrue(history["time_left_api_available"])
        self.assertEqual(history["missing_time_left_rows"], 1)
        self.assertEqual(history["time_left_known_rows"], 1)
        self.assertEqual(history["time_left_bucket_2_rows"], 1)

        bad = {**scan, "scan_id": "test-invalid-time", "rows": [
            {**scan["rows"][0], "time_left_bucket": 5}
        ]}
        invalid = self.client.post("/api/scans", json={"scans": [bad]}, headers=self.auth)
        self.assertEqual(invalid.status_code, 422)

    def test_forecast_insufficient(self):
        response = self.client.get("/api/research/gold-forecast", headers=self.auth)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["model_result"]["status"], "insufficient_data")

    def test_parquet_export(self):
        exporter = Path(__file__).resolve().parents[1] / "services" / "ingest-api" / "export_parquet.py"
        spec = importlib.util.spec_from_file_location("export_parquet", exporter)
        module = importlib.util.module_from_spec(spec)
        sys.modules["export_parquet"] = module
        spec.loader.exec_module(module)
        files = module.export(Path(self.temp.name))
        self.assertEqual(len(files), 3)
        self.assertTrue(all(p.stat().st_size > 0 for p in files))

    def test_additive_migration_for_existing_database(self):
        import tempfile
        old_db = Path(self.temp.name) / "old-schema.duckdb"
        con = self.module.duckdb.connect(str(old_db))
        con.execute("""CREATE TABLE scans (
            scan_id VARCHAR PRIMARY KEY, observed_at BIGINT, realm VARCHAR, faction VARCHAR,
            query VARCHAR, page INTEGER, reported_total INTEGER, complete BOOLEAN,
            coverage VARCHAR, rows_count INTEGER, missing_owner_rows INTEGER,
            raw_sha256 VARCHAR, ingested_at TIMESTAMP
        )""")
        con.execute("""CREATE TABLE listings (
            scan_id VARCHAR, listing_index INTEGER, item_id BIGINT, item_name VARCHAR,
            quantity BIGINT, buyout_copper BIGINT, unit_buyout_copper BIGINT,
            seller_character VARCHAR
        )""")
        con.close()
        original = self.module.DB_PATH
        self.module.DB_PATH = old_db
        try:
            migrated = self.module._db()
            try:
                scan_columns = {row[0] for row in migrated.execute("DESCRIBE scans").fetchall()}
                listing_columns = {row[0] for row in migrated.execute("DESCRIBE listings").fetchall()}
                self.assertIn("time_left_api_available", scan_columns)
                self.assertIn("missing_time_left_rows", scan_columns)
                self.assertIn("time_left_bucket", listing_columns)
            finally:
                migrated.close()
        finally:
            self.module.DB_PATH = original

    def test_gold_quote_manual(self):
        q = {"observed_at": 1790000000, "yuan_per_1000g": 64,
             "realm": "硬核服", "faction": "Alliance", "source": "manual_7881_reference"}
        r = self.client.post("/api/gold-quotes", json=q, headers=self.auth)
        self.assertEqual(r.status_code, 200, r.text)
        self.assertTrue(self.client.get("/api/gold-quotes", headers=self.auth).json()["quotes"])


if __name__ == "__main__":
    unittest.main()
