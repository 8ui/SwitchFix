#!/bin/sh
# Fails when Sources/UI/L10n.swift repeats a key: a repeated key in the
# dictionary literal crashes the first Russian lookup. Run by ci.yml and release.yml.
set -eu
cd "$(dirname "$0")/.."
file=Sources/UI/L10n.swift
# grep fails on a missing file and on a file without keys: never report those as clean.
matches=$(grep -oE '^ *"([^"\\]|\\.)*":( |$)' "$file") || {
  echo "No L10n keys found in $file"
  exit 1
}
keys=$(printf '%s\n' "$matches" | sed -E 's/^ *//; s/ $//')
dups=$(printf '%s\n' "$keys" | sort | uniq -d)
if [ -n "$dups" ]; then
  echo "Duplicate L10n keys:"
  echo "$dups"
  exit 1
fi
echo "L10n: $(printf '%s\n' "$keys" | wc -l | tr -d ' ') keys, no duplicates"
