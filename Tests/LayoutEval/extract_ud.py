#!/usr/bin/env python3
"""Build the layout-detection eval set from Universal Dependencies test splits.

Usage (from repo root, needs git + network):
    python3 Tests/LayoutEval/extract_ud.py [--workdir /tmp/ud]

Writes Tests/LayoutEval/{en,ru,uk}.txt — one raw sentence per line, sampled with a
fixed seed from the *test* split of each treebank, until the target number of
letter tokens in the language's script is reached. Deterministic for a given
treebank commit (pinned below).
"""
import argparse
import os
import random
import re
import subprocess

TREEBANKS = {
    # lang: (repo, commit, test files, token regex for the language's script)
    "en": ("UD_English-EWT", "4a4d77f599ea53cc405f85d0cec4b2f14f81d42b",
           ["en_ewt-ud-test.conllu"], r"[A-Za-z]"),
    "ru": ("UD_Russian-Taiga", "fcfd7dbdf1a7f307e23b40bb951db94a4a89df52",
           ["ru_taiga-ud-test.conllu"], r"[А-Яа-яЁё]"),
    "uk": ("UD_Ukrainian-ParlaMint", "7d3fcb7e207e3d36fec4d5f27070a23db2b9a996",
           ["uk_parlamint-ud-test.conllu"], r"[А-ЩЬЮЯЄІЇҐа-щьюяєіїґ]"),
}
TARGET_TOKENS = 5000
SEED = 5


def fetch(workdir, repo, commit):
    path = os.path.join(workdir, repo)
    if not os.path.isdir(path):
        subprocess.run(["git", "clone", "-q", f"https://github.com/UniversalDependencies/{repo}", path], check=True)
    subprocess.run(["git", "-C", path, "checkout", "-q", commit], check=True)
    return path


def sentences(path):
    for line in open(path, encoding="utf-8"):
        if line.startswith("# text = "):
            yield line[len("# text = "):].strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", default="/tmp/ud-treebanks")
    args = parser.parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    out_dir = os.path.dirname(os.path.abspath(__file__))

    for lang, (repo, commit, files, letter) in TREEBANKS.items():
        root = fetch(args.workdir, repo, commit)
        pool = []
        for name in files:
            pool.extend(sentences(os.path.join(root, name)))
        pool = sorted(set(pool))
        random.Random(SEED).shuffle(pool)
        token_re = re.compile(rf"{letter}+(?:['’\-]{letter}+)*")
        picked, tokens = [], 0
        for sentence in pool:
            count = len(token_re.findall(sentence))
            if count == 0:
                continue
            picked.append(sentence)
            tokens += count
            if tokens >= TARGET_TOKENS:
                break
        with open(os.path.join(out_dir, f"{lang}.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(picked) + "\n")
        print(f"{lang}: {len(picked)} sentences, {tokens} tokens from {repo}@{commit[:7]}")


if __name__ == "__main__":
    main()
