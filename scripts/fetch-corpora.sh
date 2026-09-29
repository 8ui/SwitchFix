#!/usr/bin/env bash
# Download the text corpora used to train the character n-gram language models
# (plan/005_ngram_layout_detection.md, §5) into .build/corpora/<lang>/*.txt.
#
# Every output file is plain UTF-8 text, one sentence (or subtitle line) per line.
# Sources and versions are pinned so the trained models are reproducible:
#   - Leipzig Corpora Collection (news / web, 100K sentences each), CC BY 4.0
#   - OpenSubtitles v2018 monolingual (OPUS), first N lines — conversational text
#   - github/docs content (CC BY 4.0) — technical English, which is what users
#     embed into Russian/Ukrainian text ("создай новую worktree")
#
# The UD treebanks in Tests/LayoutEval are the eval set and must NOT be added here.
#
# Usage: scripts/fetch-corpora.sh            (skips files that already exist)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/corpora"
LEIPZIG="https://downloads.wortschatz-leipzig.de/corpora"
OPUS="https://object.pouta.csc.fi/OPUS-OpenSubtitles/v2018/mono"
SUBTITLE_LINES=1000000
GITHUB_DOCS_COMMIT="f4e8afc6979acd8de6b5da035066281b9a5f4025"

mkdir -p "$OUT"/{en,ru,uk}

leipzig() {  # leipzig <lang> <corpus-name>
    local lang="$1" name="$2" dest="$OUT/$1/leipzig_$2.txt"
    [[ -s "$dest" ]] && { echo "have $dest"; return; }
    echo "fetch $name"
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL "$LEIPZIG/$name.tar.gz" | tar xz -C "$tmp"
    # <name>-sentences.txt: "<id>\t<sentence>"
    cut -f2 "$tmp"/*/"$name"-sentences.txt > "$dest"
    rm -rf "$tmp"
}

subtitles() {  # subtitles <lang>
    local lang="$1" dest="$OUT/$1/opensubtitles.txt"
    [[ -s "$dest" ]] && { echo "have $dest"; return; }
    echo "fetch OpenSubtitles $lang (first $SUBTITLE_LINES lines)"
    # The stream is cut on purpose; ignore the resulting SIGPIPE from curl/gzip.
    (curl -fsSL "$OPUS/$lang.txt.gz" 2>/dev/null | gzip -dc 2>/dev/null | head -n "$SUBTITLE_LINES" > "$dest") || true
    [[ -s "$dest" ]] || { echo "failed to fetch subtitles for $lang" >&2; exit 1; }
}

github_docs() {
    local dest="$OUT/en/github_docs.txt"
    [[ -s "$dest" ]] && { echo "have $dest"; return; }
    echo "fetch github/docs content@$GITHUB_DOCS_COMMIT"
    local tmp; tmp="$(mktemp -d)"
    git init -q "$tmp/docs"
    git -C "$tmp/docs" remote add origin https://github.com/github/docs
    git -C "$tmp/docs" sparse-checkout set content
    git -C "$tmp/docs" fetch -q --depth 1 --filter=blob:none origin "$GITHUB_DOCS_COMMIT"
    git -C "$tmp/docs" checkout -q FETCH_HEAD
    # Keep prose lines only: drop front matter keys, code fences, tables and Liquid tags.
    # Sorted so the concatenation is identical on every filesystem (C locale order).
    find "$tmp/docs/content" -name '*.md' -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 cat \
        | awk '/^```/{code=!code; next} !code' \
        | grep -v -E '^[[:space:]]*($|[|#>{-]|[a-zA-Z_]+:)' \
        | sed -E 's/\{%[^%]*%\}//g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/`[^`]*`//g' \
        > "$dest"
    rm -rf "$tmp"
}

leipzig en eng_news_2023_100K
leipzig en eng-com_web-public_2018_100K
subtitles en
github_docs

leipzig ru rus_news_2023_100K
leipzig ru rus-ru_web-public_2019_100K
subtitles ru

leipzig uk ukr_news_2020_100K
leipzig uk ukr-ua_web_2019_100K
subtitles uk

echo
wc -l "$OUT"/*/*.txt
echo
# Compare with the checksums the committed models were trained on.
if (cd "$OUT" && shasum -a 256 -c --quiet "$ROOT/scripts/corpora.sha256"); then
    echo "corpora match scripts/corpora.sha256"
else
    echo "WARNING: corpora differ from scripts/corpora.sha256 — retrained models will differ" >&2
fi
