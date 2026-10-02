#!/bin/sh
# Fails when Sources/UI/L10n.swift repeats a key: a repeated key in the
# dictionary literal crashes the first Russian lookup. Run by ci.yml and release.yml.
set -eu
cd "$(dirname "$0")/.."
dups=$(grep -oE '^ *"([^"\\]|\\.)*":( |$)' Sources/UI/L10n.swift | sed -E 's/^ *//; s/ $//' | sort | uniq -d)
if [ -n "$dups" ]; then
  echo "Duplicate L10n keys:"
  echo "$dups"
  exit 1
fi
echo "L10n: no duplicate keys"
