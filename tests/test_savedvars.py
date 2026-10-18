import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps" / "mac-sync"))
from lua_savedvars import parse_savedvariables
from sync import load_scans


class TestSavedVars(unittest.TestCase):
    def test_nested_and_chinese(self):
        raw = r'''AuctionCollectorDB = {
            ["schema_version"] = 1,
            ["scans"] = {
                [1] = {
                    ["scan_id"] = "123-1",
                    ["query"] = "黑莲花",
                    ["complete"] = false,
                    ["rows"] = { [1] = { ["quantity"] = 2, ["seller_character"] = "采集人" } },
                },
            },
        }'''
        obj = parse_savedvariables(raw)
        self.assertEqual(obj["scans"][0]["rows"][0]["quantity"], 2)
        self.assertEqual(obj["scans"][0]["query"], "黑莲花")
        self.assertEqual(obj["scans"][0]["complete"], False)

    def test_numeric_escape_utf8(self):
        obj = parse_savedvariables(r'AuctionCollectorDB = { ["query"] = "\233\187\145\232\142\178\232\138\177" }')
        self.assertEqual(obj["query"], "黑莲花")

    def test_reject_code(self):
        with self.assertRaises(ValueError):
            parse_savedvariables("AuctionCollectorDB = os.execute('oops')")

    def test_malformed(self):
        with self.assertRaises(ValueError):
            parse_savedvariables('AuctionCollectorDB = { ["hello"] = }')


if __name__ == "__main__":
    unittest.main()
