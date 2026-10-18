import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "services" / "market-analysis"))
from core import visible_supply_metrics, theoretical_daily_capacity, net_visible_change, rolling_gold_price_test


class TestMarketResearch(unittest.TestCase):
    def test_concentration_denominator(self):
        rows = [
            {"quantity": 10, "seller_character": "A", "buyout_copper": 1000},
            {"quantity": 5, "seller_character": "B", "buyout_copper": 500},
            {"quantity": 5, "seller_character": None, "buyout_copper": 500},
        ]
        x = visible_supply_metrics(rows)
        self.assertEqual(x["observed_visible_quantity"], 20)
        self.assertAlmostEqual(x["seller_known_fraction"], 0.75)
        self.assertAlmostEqual(x["hhi_known_sellers_only"], 5 / 9)
        self.assertEqual(x["total_visible_buyout_copper"], 2000)

    def test_capacity_is_only_scenario(self):
        x = theoretical_daily_capacity(layers=7, spawn_min_per_layer_hour=0.5,
                                       spawn_max_per_layer_hour=2.0,
                                       utilization_min=0.2, utilization_max=0.8)
        self.assertAlmostEqual(x["lower_bound"], 16.8)
        self.assertAlmostEqual(x["upper_bound"], 268.8)
        self.assertTrue(x["requires_verified_game_mechanics"])

    def test_net_not_sales(self):
        x = net_visible_change(
            [{"seller_character": "A", "quantity": 10}],
            [{"seller_character": "A", "quantity": 14}],
        )
        self.assertEqual(x["positive_visible_changes"], 4)

    def test_insufficient(self):
        x = rolling_gold_price_test([])
        self.assertEqual(x["status"], "insufficient_data")

    def test_walk_forward(self):
        from datetime import date, timedelta
        data = [
            {"date": str(date(2026, 1, 1) + timedelta(days=i)),
             "gold_yuan_per_1000g": 60 + i * 0.3,
             "lotus_unit_copper": 100000 + 100 * i,
             "lotus_visible_qty": 100 + i % 7}
            for i in range(55)
        ]
        x = rolling_gold_price_test(data)
        self.assertEqual(x["status"], "ok")
        self.assertGreater(x["test_points"], 10)
        self.assertGreaterEqual(x["ridge"]["mae"], 0)


if __name__ == "__main__":
    unittest.main()
