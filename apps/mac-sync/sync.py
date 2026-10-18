#!/usr/bin/env python3
"""Import manually collected WoW SavedVariables and submit new pages to Azure API.

No game interaction, memory reading, UI automation or background auction queries.
Use only after /reload or logout writes the SavedVariables file.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile
import urllib.error
import urllib.request

from lua_savedvars import parse_savedvariables


def load_scans(path: Path) -> list[dict]:
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("SavedVariables file >64 MiB; refusing unbounded input")
    data = parse_savedvariables(path.read_text(encoding="utf-8"))
    scans = data.get("scans") or []
    if not isinstance(scans, list):
        raise ValueError("AuctionCollectorDB.scans must be a Lua array")
    return [scan for scan in scans if isinstance(scan, dict) and scan.get("scan_id")]


def persist_state(path: Path, uploaded: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as f:
        json.dump(sorted(uploaded), f)
        temp_name = f.name
    os.replace(temp_name, path)


def send(url: str, token: str, scans: list[dict]) -> dict:
    if not url.startswith("https://") and not url.startswith("http://127.0.0.1:"):
        raise ValueError("Remote endpoint must use HTTPS")
    payload = json.dumps({"scans": scans}, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url.rstrip("/") + "/api/scans",
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + token},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("savedvariables", type=Path, help=".../WTF/Account/<account>/SavedVariables/AuctionCollector.lua")
    p.add_argument("--url", default=os.getenv("AUCTION_API_URL", ""))
    p.add_argument("--state", type=Path, default=Path.home() / ".auctioncollector" / "uploaded.json")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    scans = load_scans(args.savedvariables)
    uploaded = set(json.loads(args.state.read_text(encoding="utf-8"))) if args.state.exists() else set()
    new = [s for s in scans if str(s["scan_id"]) not in uploaded]
    print(f"Saved scans: {len(scans)}; already uploaded: {len(scans)-len(new)}; new: {len(new)}")
    if args.dry_run:
        for s in new:
            print(s["scan_id"], s.get("query"), "page", s.get("page"), "rows", len(s.get("rows", [])))
        return
    if not new:
        return
    token = os.getenv("AUCTION_API_TOKEN")
    if not token or not args.url:
        raise SystemExit("Set AUCTION_API_TOKEN and AUCTION_API_URL or pass --url")
    for start in range(0, len(new), 20):
        batch = new[start:start + 20]
        response = send(args.url, token, batch)
        accepted = set(str(x) for x in response.get("accepted_ids", []))
        if accepted != {str(s["scan_id"]) for s in batch}:
            raise RuntimeError(f"Server did not acknowledge full batch: {response}")
        uploaded.update(accepted)
        persist_state(args.state, uploaded)
        print(f"Uploaded {len(accepted)} pages; stored acknowledgment.")
    print("Complete.")


if __name__ == "__main__":
    main()
