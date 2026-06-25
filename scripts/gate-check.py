#!/usr/bin/env python3
"""Validate repository deployment checklist and criteria."""
from __future__ import annotations

import argparse
import csv
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

DONE = {"pass", "passed", "waived"}
REQUIRED = {"1", "true", "yes", "required"}
COLUMNS = ("id", "required", "status", "evidence", "notes")


def evidence_exists(raw: str, repo: Path) -> bool:
    if not raw or raw in {"-", "n/a"}:
        return False
    if raw.startswith(("http://", "https://")):
        return True
    path = raw.split("#", 1)[0]
    if not path:
        return False
    p = Path(path)
    if not p.is_absolute():
        p = repo / p
    return p.exists()


def load_gates(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    missing = [c for c in COLUMNS if c not in (rows[0].keys() if rows else [])]
    if missing:
        raise SystemExit(f"{path} missing columns: {', '.join(missing)}")
    return [{k: (row.get(k) or "").strip() for k in COLUMNS} for row in rows]


def render(gates: list[dict[str, str]], repo: Path) -> tuple[bool, str]:
    blockers: list[str] = []
    warnings: list[str] = []
    lines = [
        "# Deployment Gate Checklist Status",
        "",
        f"- timestamp_utc: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        "",
        "| gate | required | status | evidence | notes |",
        "| --- | --- | --- | --- | --- |",
    ]
    for gate in gates:
        gid = gate["id"]
        required = gate["required"].lower() in REQUIRED
        status = gate["status"].lower()
        evidence = gate["evidence"]
        notes = gate["notes"]
        ok_status = status in DONE
        ok_evidence = status == "waived" or evidence_exists(evidence, repo)
        if required and not ok_status:
            blockers.append(f"{gid}: status={status or 'missing'}")
        if required and ok_status and not ok_evidence:
            blockers.append(f"{gid}: evidence missing ({evidence or 'empty'})")
        if not required and ok_status and not ok_evidence:
            warnings.append(f"{gid}: evidence missing ({evidence or 'empty'})")
        lines.append(f"| {gid} | {'yes' if required else 'no'} | {status or 'missing'} | {evidence or '-'} | {notes or '-'} |")

    lines += ["", "## Result"]
    if blockers:
        lines.append("BLOCKED — Outstanding deployment gates are still pending.")
        lines += ["", "## Blockers", *[f"- {b}" for b in blockers]]
        complete = False
    else:
        lines.append("PASS — All required deployment gates are passed or waived.")
        complete = True
    if warnings:
        lines += ["", "## Warnings", *[f"- {w}" for w in warnings]]
    return complete, "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Check or watch the OntoPortal validation gate ledger.")
    parser.add_argument("--gate-file", default="docs/deployment-gates.tsv")
    parser.add_argument("--status-file", default="")
    parser.add_argument("--watch", action="store_true", help="Keep checking until all required gates pass/waive.")
    parser.add_argument("--interval", type=int, default=300)
    args = parser.parse_args()

    repo = Path.cwd()
    gate_file = Path(args.gate_file)
    if not gate_file.is_absolute():
        gate_file = repo / gate_file
    status_file = Path(args.status_file) if args.status_file else None

    while True:
        complete, text = render(load_gates(gate_file), repo)
        if status_file:
            status_file.parent.mkdir(parents=True, exist_ok=True)
            status_file.write_text(text)
        print(text, end="", flush=True)
        if complete:
            return 0
        if not args.watch:
            return 1
        time.sleep(max(args.interval, 5))


if __name__ == "__main__":
    sys.exit(main())
