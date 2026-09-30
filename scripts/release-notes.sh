#!/bin/bash
set -euo pipefail

# Print Markdown release notes for a tag from its conventional commits.
#
# GitHub's generated notes list merged pull requests only, and most commits
# here land without a PR, so the notes are built from commit subjects instead:
# feat → "Новое", fix → "Исправления". Other types (docs, chore, ci, test,
# refactor), merges, version bumps and developer tooling scopes (rtp, claude,
# ci) are left out.
#
# Usage: scripts/release-notes.sh <tag> [<previous tag>] [<owner/repo>]
#   The previous tag (empty = default) is the nearest v* tag before <tag>; without one,
#   all commits up to <tag> are listed. <owner/repo> adds a compare link.

TAG="${1:?usage: scripts/release-notes.sh <tag> [<previous tag>] [<owner/repo>]}"
PREV="${2:-$(git describe --tags --match 'v*' --abbrev=0 "$TAG^" 2>/dev/null || true)}"
REPO="${3:-}"

RANGE="$TAG"
if [ -n "$PREV" ]; then
    RANGE="$PREV..$TAG"
fi

# "type(scope)!: subject" → prints the subject when type matches and no scope
# is a tooling one; scopes may be comma-separated, e.g. fix(rtp,ci).
section() {
    local type="$1"
    git log --no-merges --reverse --format=%s "$RANGE" | awk -v type="$type" '
        {
            if (!match($0, /^[a-z]+(\([^)]*\))?!?: /)) next
            head = substr($0, 1, RLENGTH - 2)
            subject = substr($0, RLENGTH + 1)
            t = head; sub(/[(!].*/, "", t)
            if (t != type) next
            if (match(head, /\([^)]*\)/)) {
                n = split(substr(head, RSTART + 1, RLENGTH - 2), scopes, ",")
                for (i = 1; i <= n; i++) {
                    s = scopes[i]; gsub(/ /, "", s)
                    if (s == "rtp" || s == "claude" || s == "ci") next
                }
            }
            print "- " subject
        }'
}

FEATURES="$(section feat)"
FIXES="$(section fix)"

if [ -n "$FEATURES" ]; then
    printf '## Новое\n%s\n\n' "$FEATURES"
fi
if [ -n "$FIXES" ]; then
    printf '## Исправления\n%s\n\n' "$FIXES"
fi
if [ -z "$FEATURES" ] && [ -z "$FIXES" ]; then
    printf 'Служебные изменения без новых функций и исправлений.\n\n'
fi
if [ -n "$REPO" ] && [ -n "$PREV" ]; then
    printf '**Full Changelog**: https://github.com/%s/compare/%s...%s\n' "$REPO" "$PREV" "$TAG"
fi
