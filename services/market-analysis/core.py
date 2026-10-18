"""Research-only observation metrics and leakage-controlled regression baselines.

No claim of sales, real ownership, workshop identity or causal price effects.
"""
from __future__ import annotations

from collections import defaultdict
from math import sqrt
from typing import Any


def visible_supply_metrics(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Statistics for ONE observed scan/page, not the full realm."""
    per_seller: dict[str, int] = defaultdict(int)
    visible_qty = 0
    known_qty = 0
    priced_qty = 0
    total_buyout_copper = 0
    for row in rows:
        qty = max(0, int(row.get("quantity") or 0))
        visible_qty += qty
        if qty and (row.get("buyout_copper") or 0) > 0:
            priced_qty += qty
            total_buyout_copper += int(row["buyout_copper"])
        seller = row.get("seller_character")
        if isinstance(seller, str) and seller.strip():
            known_qty += qty
            per_seller[seller] += qty
    ordered = sorted(per_seller.items(), key=lambda kv: kv[1], reverse=True)
    concentration = (
        sum((amount / known_qty) ** 2 for _, amount in ordered)
        if known_qty else None
    )
    return {
        "scope": "observed_scan_only",
        "observed_visible_quantity": visible_qty,
        "priced_quantity": priced_qty,
        "total_visible_buyout_copper": total_buyout_copper,
        "seller_known_quantity": known_qty,
        "seller_known_fraction": known_qty / visible_qty if visible_qty else None,
        "hhi_known_sellers_only": concentration,
        "top5_share_known_sellers_only": sum(q for _, q in ordered[:5]) / known_qty if known_qty else None,
        "top10_share_known_sellers_only": sum(q for _, q in ordered[:10]) / known_qty if known_qty else None,
        "top_seller_characters": [{"character": name, "quantity": qty} for name, qty in ordered[:20]],
        "disclaimer": "角色不等于账号/个人/工作室；采样页不等于全服，挂单消失不等于成交。",
    }


def net_visible_change(previous: list[dict], current: list[dict]) -> dict:
    """Same-seller observable quantity deltas. NOT harvested production or sales."""
    def aggregate(rows: list[dict]) -> dict[str, int]:
        quantities: dict[str, int] = defaultdict(int)
        for row in rows:
            seller = row.get("seller_character")
            if seller:
                quantities[str(seller)] += max(0, int(row.get("quantity") or 0))
        return quantities
    old = aggregate(previous)
    new = aggregate(current)
    keys = set(old) | set(new)
    return {
        "net_visible_change_known_sellers": sum(new.values()) - sum(old.values()),
        "positive_visible_changes": sum(max(new.get(k, 0) - old.get(k, 0), 0) for k in keys),
        "negative_visible_changes": sum(max(old.get(k, 0) - new.get(k, 0), 0) for k in keys),
        "note": "包含重复上架、刷新、重新定价和漏检；不代表采集/成交量。请确保扫描覆盖范围可比。",
    }


def theoretical_daily_capacity(
    *, layers: int, spawn_min_per_layer_hour: float, spawn_max_per_layer_hour: float,
    utilization_min: float, utilization_max: float, hours: float = 24
) -> dict:
    """Pure scenario calculator: all inputs must be sourced/verified externally."""
    if not 0 < layers < 500 or not 0 < hours <= 24:
        raise ValueError("Invalid layer count or hours")
    if not 0 <= spawn_min_per_layer_hour <= spawn_max_per_layer_hour:
        raise ValueError("Invalid spawn bounds")
    if not 0 <= utilization_min <= utilization_max <= 1:
        raise ValueError("Utilization must be between 0 and 1")
    return {
        "lower_bound": layers * hours * spawn_min_per_layer_hour * utilization_min,
        "upper_bound": layers * hours * spawn_max_per_layer_hour * utilization_max,
        "type": "scenario_only_not_measured_production",
        "requires_verified_game_mechanics": True,
    }


def rolling_gold_price_test(
    observations: list[dict], *,
    min_train: int = 30,
    alpha: float = 10.0
) -> dict:
    """Walk-forward one-step-ahead gold quote test using PRIOR day's features only.

    Input: daily observations sorted by date (ISO-8601 YYYY-MM-DD).
    Required: date, gold_yuan_per_1000g, lotus_unit_copper, lotus_visible_qty.
    Model includes lagged price and commodity observations; naive baseline is prior price.
    It does not estimate causality or tradeable profit.
    """
    import numpy as np

    cols = ("gold_yuan_per_1000g", "lotus_unit_copper", "lotus_visible_qty")
    clean = sorted(observations, key=lambda r: str(r.get("date", "")))
    if len(clean) < min_train + 12:
        return {"status": "insufficient_data", "required_daily_points": min_train + 12, "available": len(clean)}
    dates = [str(r["date"]) for r in clean]
    try:
        from datetime import date, timedelta
        parsed_dates = [date.fromisoformat(d) for d in dates]
        if (len(set(parsed_dates)) != len(parsed_dates)
                or any(d.isoformat() != original for d, original in zip(parsed_dates, dates))
                or any(b - a != timedelta(days=1) for a, b in zip(parsed_dates, parsed_dates[1:]))):
            return {"status": "invalid_dates", "message": "Require consecutive daily observations"}
    except ValueError:
        return {"status": "invalid_dates", "message": "Require YYYY-MM-DD dates"}

    if not all(all(r.get(k) is not None for k in cols) for r in clean):
        return {"status": "missing_features", "message": "Daily features must be complete"}
    matrix = np.array([[float(r[k]) for k in cols] for r in clean], dtype=float)
    if not np.isfinite(matrix).all() or (matrix[:, 0] <= 0).any():
        return {"status": "invalid_numeric_data"}
    feature_rows = matrix[:-1, :]
    actual = matrix[1:, 0]
    naive = matrix[:-1, 0]
    if len(actual) - min_train < 10:
        return {"status": "insufficient_test_period"}
    predicted: list[float] = []
    gold_only: list[float] = []
    baseline: list[float] = []
    observed: list[float] = []

    def predict_ridge(train_x: Any, train_y: Any, next_x: Any) -> float:
        means = train_x.mean(axis=0)
        std = train_x.std(axis=0)
        std[std < 1e-9] = 1.0
        x = (train_x - means) / std
        x = np.column_stack([np.ones(len(x)), x])
        penalty = np.eye(x.shape[1]) * alpha
        penalty[0, 0] = 0.0
        weights = np.linalg.solve(x.T @ x + penalty, x.T @ train_y)
        x_test = np.concatenate([[1.0], (next_x - means) / std])
        return float(x_test @ weights)

    for test_i in range(min_train, len(actual)):
        train_x = feature_rows[:test_i]
        train_y = actual[:test_i]
        predicted.append(predict_ridge(train_x, train_y, feature_rows[test_i]))
        gold_only.append(predict_ridge(train_x[:, :1], train_y, feature_rows[test_i, :1]))
        baseline.append(float(naive[test_i]))
        observed.append(float(actual[test_i]))
    y = np.array(observed)
    pred = np.array(predicted)
    base = np.array(baseline)
    gold_pred = np.array(gold_only)

    def score(p: Any) -> dict:
        return {
            "mae": float(np.mean(np.abs(y - p))),
            "rmse": float(sqrt(np.mean((y - p) ** 2))),
            "direction_accuracy": float(np.mean(np.sign(p - base) == np.sign(y - base))),
        }

    return {
        "status": "ok",
        "scope": "one_step_out_of_sample",
        "model": "walk_forward_standardized_ridge",
        "test_points": len(y),
        "from_date": dates[min_train + 1],
        "through_date": dates[-1],
        "ridge_with_lotus": score(pred),
        "ridge_gold_only": score(gold_pred),
        "naive": score(base),
        "lotus_incremental_mae_reduction": score(gold_pred)["mae"] - score(pred)["mae"],
        "warning": "预测增益不是因果证据；未模拟交易流动性、费用或可成交价。",
    }
