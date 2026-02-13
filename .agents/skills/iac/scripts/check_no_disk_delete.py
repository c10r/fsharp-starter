#!/usr/bin/env python3
"""Fail if an OpenTofu plan deletes or replaces persistent data disk resources."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate that tfplan JSON does not delete/replace data disk resources."
    )
    parser.add_argument(
        "plan_json",
        help="Path to `tofu show -json <plan-file>` output",
    )
    parser.add_argument(
        "--address-prefix",
        default="google_compute_disk.data_",
        help="Resource address prefix to protect (default: google_compute_disk.data_)",
    )
    return parser.parse_args()


def load_plan(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def is_delete_or_replace(actions: list[str]) -> bool:
    actions_set = set(actions)
    if "delete" in actions_set:
        return True
    return actions_set == {"delete", "create"}


def main() -> int:
    args = parse_args()
    plan_path = Path(args.plan_json)
    if not plan_path.exists():
        print(f"ERROR: plan file not found: {plan_path}", file=sys.stderr)
        return 2

    try:
        plan = load_plan(plan_path)
    except Exception as exc:
        print(f"ERROR: failed to parse plan json: {exc}", file=sys.stderr)
        return 2

    resource_changes = plan.get("resource_changes", [])
    violations: list[tuple[str, list[str]]] = []

    for rc in resource_changes:
        address = rc.get("address", "")
        if not address.startswith(args.address_prefix):
            continue

        change = rc.get("change", {})
        actions = change.get("actions", [])
        if is_delete_or_replace(actions):
            violations.append((address, actions))

    if violations:
        print("ERROR: persistent disk safety check failed.")
        for address, actions in violations:
            print(f"  - {address}: actions={actions}")
        print(
            "Hint: keep preserve_data_disk_on_destroy=true and avoid changes that replace/delete protected data disks."
        )
        return 1

    print("OK: no protected data disk delete/replace actions found in plan.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
