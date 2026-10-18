import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Git blob hashes from main before migration. Verify byte-for-byte identity.
ORIGINAL = {
    "Alerts.lua": "119f5f3487e66ad69d3013041c9fa74a0f79b92a",
    "Core.lua": "ef31b0d6cc5e54fbf8c0130d9756d6969d3613c2",
    "Minimap.lua": "84e0ce34a101bd8501fafab50318ce67237b855a",
    "Parser.lua": "605e9df42962b8ec8839b9153bbcb06a77572519",
    "Rules.lua": "291e06bd27152f0fdbe00b52d24f863685f0ae86",
    "UI.lua": "fc2f9029f8cf863602c36af2aa186b22f7f60d75",
    "UI_Blacklist.lua": "7d2955347495a57a2829a4e209c90bb9e090cbdc",
    "UI_History.lua": "3e4c7dbc921e559bd78c1c9a3949fb8e01e4bd1e",
    "UI_Rules.lua": "c9910eef59b73afff4b6a2d9b28d94de98aca7a7",
    "WOW_keywordmonitor.toc": "ff2c7f7a6ad347a394d71a645822fdeead34d8ee",
    "README.md": "8381a1cfe06d604dce9e3c4b7e8124318bfa287f",
}


class TestOriginalPluginPreserved(unittest.TestCase):
    def test_original_blobs_are_unchanged(self):
        for filename, expected in ORIGINAL.items():
            with self.subTest(filename=filename):
                file = ROOT / "addons" / "KeywordMonitor" / filename
                self.assertTrue(file.is_file(), str(file))
                blob = subprocess.check_output(["git", "hash-object", str(file)], text=True).strip()
                self.assertEqual(blob, expected)


if __name__ == "__main__":
    unittest.main()
