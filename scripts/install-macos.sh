#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" ]]; then
  echo "Usage: bash scripts/install-macos.sh /path/to/_classic_era_/Interface/AddOns" >&2
  exit 2
fi

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(cd "$1" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

for pair in "KeywordMonitor:WOW_keywordmonitor" "AuctionCollector:AuctionCollector"; do
  source_name="${pair%%:*}"
  target_name="${pair##*:}"
  origin="$SOURCE/addons/$source_name"
  [[ -f "$origin/$target_name.toc" ]] || { echo "Missing TOC: $origin/$target_name.toc" >&2; exit 1; }
  if [[ -e "$TARGET/$target_name" ]]; then
    backup="$TARGET/$target_name.backup-$STAMP"
    [[ ! -e "$backup" ]] || { echo "Backup exists: $backup" >&2; exit 1; }
    mv "$TARGET/$target_name" "$backup"
    echo "Backup: $backup"
  fi
  cp -R "$origin" "$TARGET/$target_name"
  echo "Installed $target_name"
done

echo "WTF/SavedVariables was not modified. Restart WoW to load addons."
