#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ADDONS="$WORK/AddOns"
mkdir -p "$ADDONS"
bash "$ROOT/scripts/install-macos.sh" "$ADDONS"
[[ -f "$ADDONS/WOW_keywordmonitor/WOW_keywordmonitor.toc" ]]
[[ -f "$ADDONS/AuctionCollector/AuctionCollector.toc" ]]
[[ -z "$(find "$ADDONS" -maxdepth 1 -name '.wow-addon-install.*' -print -quit)" ]]
echo "fresh install: PASS"

printf 'old keyword addon\n' > "$ADDONS/WOW_keywordmonitor/old-install-marker"
printf 'old collector addon\n' > "$ADDONS/AuctionCollector/old-install-marker"
bash "$ROOT/scripts/install-macos.sh" "$ADDONS"
keyword_backup="$(find "$ADDONS" -maxdepth 1 -name 'WOW_keywordmonitor.backup-*' -print -quit)"
collector_backup="$(find "$ADDONS" -maxdepth 1 -name 'AuctionCollector.backup-*' -print -quit)"
[[ -f "$keyword_backup/old-install-marker" ]]
[[ -f "$collector_backup/old-install-marker" ]]
[[ -f "$ADDONS/WOW_keywordmonitor/WOW_keywordmonitor.toc" ]]
[[ -f "$ADDONS/AuctionCollector/AuctionCollector.toc" ]]
echo "replacement with backups: PASS"

FAKE="$WORK/incomplete-repo"
FAILED_ADDONS="$WORK/ExistingAddOns"
mkdir -p "$FAKE/scripts" "$FAKE/addons/KeywordMonitor" "$FAILED_ADDONS/WOW_keywordmonitor" "$FAILED_ADDONS/AuctionCollector"
cp "$ROOT/scripts/install-macos.sh" "$FAKE/scripts/install-macos.sh"
touch "$FAKE/addons/KeywordMonitor/WOW_keywordmonitor.toc"
printf 'keep keyword\n' > "$FAILED_ADDONS/WOW_keywordmonitor/keep-marker"
printf 'keep collector\n' > "$FAILED_ADDONS/AuctionCollector/keep-marker"
if bash "$FAKE/scripts/install-macos.sh" "$FAILED_ADDONS"; then
  echo "incomplete source unexpectedly installed" >&2
  exit 1
fi
[[ -f "$FAILED_ADDONS/WOW_keywordmonitor/keep-marker" ]]
[[ -f "$FAILED_ADDONS/AuctionCollector/keep-marker" ]]
[[ -z "$(find "$FAILED_ADDONS" -maxdepth 1 -name '*.backup-*' -print -quit)" ]]
echo "missing-source preflight: PASS"
