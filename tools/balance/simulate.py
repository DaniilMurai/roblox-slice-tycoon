#!/usr/bin/env python3
"""Balance simulator for AC-8: mirrors robloxcore/src/logic/economy.luau and
progression.luau formulas exactly, so a divergence here is a divergence with the game.

Model assumption: the simulator only supports single-currency economies, i.e. every
upgrade cost and the rebirth requirement are denominated in currencies[0]. That is what
configs/main.json (and roblox-slice-tycoon's config, per T-19) actually looks like; a
config with mixed currencies is rejected with an explicit error rather than silently
simulating something the game would not do.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from typing import Any

# Same 15 min / 3 h corridor as plan.md AC-8.
FIRST_WINDOW_SECONDS = 15 * 60
FIRST_WINDOW_MIN_UPGRADES = 5
REBIRTH_DEADLINE_SECONDS = 3 * 60 * 60

# Upper bound so a stalled economy (income never enough) fails fast instead of hanging.
SIMULATION_HORIZON_SECONDS = 48 * 60 * 60


def load_config(path: str) -> dict[str, Any]:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def upgrade_cost(upgrade: dict[str, Any], level: int) -> int:
    # Ported 1:1 from Economy.upgradeCost.
    return math.floor(upgrade["baseCost"] * upgrade["growth"] ** level)


def rebirth_cost(config: dict[str, Any], rebirths: int) -> int:
    # Ported 1:1 from Progression.rebirthCost.
    requirement = config["rebirth"]["requirement"]
    return math.floor(requirement["base"] * requirement["growth"] ** rebirths)


def rebirth_multiplier(config: dict[str, Any], rebirths: int) -> float:
    # Ported 1:1 from Economy.rebirthMultiplier.
    rebirth = config["rebirth"]
    multiplier = 1 + rebirth["multiplierPerRebirth"] * rebirths
    return min(multiplier, rebirth["multiplierCap"])


def income_per_second(config: dict[str, Any], levels: dict[str, int], rebirths: int) -> float:
    # Ported from Economy.incomePerSecond with ownedPassIds == {}: the task asks for the
    # baseline curve, not the boosted-by-a-gamepass one.
    flat = config["baseIncomePerSecond"]
    multiplier = 1.0
    for upgrade in config["upgrades"]:
        level = levels.get(upgrade["id"], 0)
        effect = upgrade["effect"]
        if effect["kind"] == "IncomeFlat":
            flat += effect["perLevel"] * level
        elif effect["kind"] == "IncomeMultiplier":
            multiplier *= effect["perLevel"] ** level
    multiplier *= rebirth_multiplier(config, rebirths)
    return flat * multiplier


def format_duration(seconds: float) -> str:
    total = int(round(seconds))
    if total < 3600:
        m, s = divmod(total, 60)
        return f"{m}m {s:02d}s"
    h, rem = divmod(total, 3600)
    m = rem // 60
    return f"{h}h {m:02d}m"


def check_single_currency_assumption(config: dict[str, Any]) -> str | None:
    primary = config["currencies"][0]["id"]
    for upgrade in config["upgrades"]:
        if upgrade["currency"] != primary:
            return (
                f"upgrade '{upgrade['id']}' costs currency '{upgrade['currency']}', "
                f"but this simulator only models the primary currency '{primary}'"
            )
    rebirth_currency = config["rebirth"]["requirement"]["currency"]
    if rebirth_currency != primary:
        return (
            f"rebirth requirement is denominated in '{rebirth_currency}', "
            f"but this simulator only models the primary currency '{primary}'"
        )
    return None


def simulate(config: dict[str, Any]) -> dict[str, Any]:
    """Continuous-income model: money accrues at `income_per_second` and the player
    instantly buys the cheapest available target as soon as the balance reaches it.
    Rebirth is treated as just another purchasable target competing with upgrades on
    cost, which is what makes "buy cheapest" a single, uniform rule.
    """
    mismatch = check_single_currency_assumption(config)
    if mismatch is not None:
        return {"error": mismatch, "rows": [], "first_rebirth_time": None}

    primary = config["currencies"][0]["id"]
    levels = {u["id"]: 0 for u in config["upgrades"]}
    balance = float(config["currencies"][0]["starting"])
    elapsed = 0.0
    rebirths = 0
    rows: list[dict[str, Any]] = []
    first_rebirth_time: float | None = None

    while elapsed <= SIMULATION_HORIZON_SECONDS:
        targets: list[tuple[int, str, dict[str, Any] | None]] = []
        for upgrade in config["upgrades"]:
            level = levels[upgrade["id"]]
            if level < upgrade["maxLevel"]:
                targets.append((upgrade_cost(upgrade, level), "upgrade", upgrade))
        if first_rebirth_time is None:
            targets.append((rebirth_cost(config, rebirths), "rebirth", None))

        if not targets:
            break  # every upgrade maxed and rebirth already reached

        cost, kind, payload = min(targets, key=lambda t: t[0])

        if cost > balance:
            income = income_per_second(config, levels, rebirths)
            if income <= 0:
                return {
                    "error": f"income stalled at {income}/s before reaching cost {cost}",
                    "rows": rows,
                    "first_rebirth_time": first_rebirth_time,
                }
            elapsed += (cost - balance) / income
            balance = float(cost)

        if kind == "rebirth":
            first_rebirth_time = elapsed
            break  # the table only needs the first rebirth, not what happens after

        balance -= cost
        levels[payload["id"]] += 1
        rows.append(
            {
                "index": len(rows) + 1,
                "upgrade_id": payload["id"],
                "level": levels[payload["id"]],
                "cost": cost,
                "elapsed": elapsed,
                "income_after": income_per_second(config, levels, rebirths),
            }
        )

    return {"error": None, "rows": rows, "first_rebirth_time": first_rebirth_time}


def check_corridor(result: dict[str, Any]) -> list[str]:
    """Returns a list of human-readable failure reasons; empty means the corridor holds."""
    if result["error"] is not None:
        return [result["error"]]

    reasons = []
    bought_in_window = sum(1 for r in result["rows"] if r["elapsed"] <= FIRST_WINDOW_SECONDS)
    if bought_in_window < FIRST_WINDOW_MIN_UPGRADES:
        reasons.append(
            f"only {bought_in_window} upgrades bought in the first 15 min, "
            f"need at least {FIRST_WINDOW_MIN_UPGRADES}"
        )

    first_rebirth = result["first_rebirth_time"]
    if first_rebirth is None:
        reasons.append(f"first rebirth not reached within {SIMULATION_HORIZON_SECONDS}s horizon")
    elif first_rebirth > REBIRTH_DEADLINE_SECONDS:
        reasons.append(
            f"first rebirth reached at {format_duration(first_rebirth)}, "
            f"deadline is {format_duration(REBIRTH_DEADLINE_SECONDS)}"
        )
    return reasons


def print_table(result: dict[str, Any]) -> None:
    if result["error"] is not None:
        print(f"simulation aborted: {result['error']}")
        return

    print(f"{'#':>3}  {'upgrade':<16} {'level':>5} {'cost':>10} {'time':>10} {'income/s':>10}")
    for row in result["rows"]:
        print(
            f"{row['index']:>3}  {row['upgrade_id']:<16} {row['level']:>5} "
            f"{row['cost']:>10} {format_duration(row['elapsed']):>10} "
            f"{row['income_after']:>10.2f}"
        )

    bought_in_window = sum(1 for r in result["rows"] if r["elapsed"] <= FIRST_WINDOW_SECONDS)
    print(f"\nupgrades bought in first 15 min: {bought_in_window}")
    first_rebirth = result["first_rebirth_time"]
    if first_rebirth is None:
        print(f"first rebirth: not reached within {SIMULATION_HORIZON_SECONDS}s")
    else:
        print(f"first rebirth: {format_duration(first_rebirth)}")


# Grid kept small and monotonically shrinking on purpose: the first candidate that
# passes is the smallest change from the original numbers, so the diff stays explainable.
SCALE_GRID = [1.0, 0.75, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15, 0.1, 0.075, 0.05, 0.035, 0.025, 0.02, 0.015, 0.01, 0.0075, 0.005]


def grid_search(config: dict[str, Any]) -> tuple[dict[str, Any], float, float] | None:
    orig_cost = config["upgrades"][0]["baseCost"]
    orig_rebirth_base = config["rebirth"]["requirement"]["base"]

    for scale_cost in SCALE_GRID:
        for scale_rebirth in SCALE_GRID:
            candidate = copy.deepcopy(config)
            candidate["upgrades"][0]["baseCost"] = max(1, round(orig_cost * scale_cost))
            candidate["rebirth"]["requirement"]["base"] = max(1, round(orig_rebirth_base * scale_rebirth))
            result = simulate(candidate)
            if not check_corridor(result):
                return candidate, scale_cost, scale_rebirth
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="AC-8 balance simulator")
    parser.add_argument("--config", default="configs/main.json", help="TitleConfig to simulate")
    parser.add_argument("--out", default=None, help="write a corridor-fitting config here")
    args = parser.parse_args()

    config = load_config(args.config)
    result = simulate(config)
    print_table(result)
    reasons = check_corridor(result)

    if args.out is None:
        if reasons:
            print("\ncorridor FAILED:")
            for reason in reasons:
                print(f"  - {reason}")
            return 1
        print("\ncorridor OK")
        return 0

    found = grid_search(config)
    if found is None:
        print(f"\ncould not find a config within the corridor over the scale grid {SCALE_GRID}")
        return 1

    candidate, scale_cost, scale_rebirth = found
    orig_upgrade_cost = config["upgrades"][0]["baseCost"]
    orig_rebirth_base = config["rebirth"]["requirement"]["base"]
    new_upgrade_cost = candidate["upgrades"][0]["baseCost"]
    new_rebirth_base = candidate["rebirth"]["requirement"]["base"]

    if scale_cost == 1.0 and scale_rebirth == 1.0:
        print("\nconfig already satisfies the corridor, writing it unchanged")
    else:
        print("\ntuned to fit the corridor:")
        print(
            f"  upgrades[0].baseCost: {orig_upgrade_cost} -> {new_upgrade_cost} "
            f"(x{scale_cost})"
        )
        print(
            f"  rebirth.requirement.base: {orig_rebirth_base} -> {new_rebirth_base} "
            f"(x{scale_rebirth})"
        )

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(candidate, f, indent=2)
        f.write("\n")
    print(f"written to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
