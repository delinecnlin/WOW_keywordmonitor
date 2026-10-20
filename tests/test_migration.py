import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TestAddonSeparation(unittest.TestCase):
    def test_keyword_monitor_remains_a_separate_loadable_addon(self):
        keyword_dir = ROOT / "addons" / "KeywordMonitor"
        collector_dir = ROOT / "addons" / "AuctionCollector"
        keyword_toc = keyword_dir / "WOW_keywordmonitor.toc"
        collector_toc = collector_dir / "AuctionCollector.toc"

        self.assertTrue(keyword_toc.is_file())
        self.assertTrue(collector_toc.is_file())

        keyword_manifest = keyword_toc.read_text(encoding="utf-8")
        collector_manifest = collector_toc.read_text(encoding="utf-8")
        self.assertIn("## Title: WOW Keyword Monitor", keyword_manifest)
        self.assertIn("## SavedVariables: WOWKeywordMonitorDB", keyword_manifest)
        self.assertIn("## SavedVariables: AuctionCollectorDB", collector_manifest)
        self.assertNotIn("AuctionCollectorDB", keyword_manifest)
        self.assertNotIn("WOWKeywordMonitorDB", collector_manifest)

        for manifest, addon_dir in (
            (keyword_manifest, keyword_dir),
            (collector_manifest, collector_dir),
        ):
            for entry in manifest.splitlines():
                entry = entry.strip()
                if entry and not entry.startswith("##"):
                    with self.subTest(addon=addon_dir.name, file=entry):
                        self.assertTrue((addon_dir / entry).is_file(), entry)


if __name__ == "__main__":
    unittest.main()
