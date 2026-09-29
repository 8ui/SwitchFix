#!/usr/bin/env python3
"""Prototype of dictionary-free wrong-layout detection with character n-grams.

Reproduces the numbers in plan/005_ngram_layout_detection.md.
Run from the repo root:  python3 plan/benchmarks/ngram_prototype.py [n]

Models are trained on the existing word lists (no frequencies), and evaluated on
4000 held-out words per language, so this is an optimistic upper bound for long
words and a pessimistic one for short words (real text is dominated by frequent
short words, which a frequency-weighted corpus would model much better).
"""
import collections
import math
import random
import re
import sys

RES = "Sources/Dictionary/Resources/"
random.seed(1)

EN_KEYS = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
RU_KEYS = "йцукенгшщзхъфывапролджэячсмитьбюё"
UK_KEYS = "йцукенгшщзхїфівапролджєячсмитьбюґ"
E2R = dict(zip(EN_KEYS, RU_KEYS)); R2E = {v: k for k, v in E2R.items()}
E2U = dict(zip(EN_KEYS, UK_KEYS)); U2E = {v: k for k, v in E2U.items()}


def conv(word, table):
    return "".join(table.get(c, c) for c in word)


def load(name, alphabet, limit=None):
    words = [line.strip().lower() for line in open(RES + name, encoding="utf-8")]
    words = [w for w in words if re.fullmatch(alphabet, w)]
    random.shuffle(words)
    return words[:limit] if limit else words


class CharNgramModel:
    def __init__(self, words, n=3, k=0.1):
        self.n, self.k = n, k
        self.grams, self.hist = collections.Counter(), collections.Counter()
        vocab = set()
        for w in words:
            p = "^" * (n - 1) + w + "$"
            for i in range(n - 1, len(p)):
                self.grams[p[i - n + 1:i + 1]] += 1
                self.hist[p[i - n + 1:i]] += 1
                vocab.add(p[i])
        self.v = len(vocab) + 5

    def logprob(self, word):
        n, p, total = self.n, "^" * (self.n - 1) + word + "$", 0.0
        for i in range(n - 1, len(p)):
            num = self.grams[p[i - n + 1:i + 1]] + self.k
            den = self.hist[p[i - n + 1:i]] + self.k * self.v
            total += math.log(num / den)
        return total


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    en = load("en_US.txt", r"[a-z]{2,}")
    ru = load("ru_RU.txt", r"[а-яё]{2,}")
    uk = load("uk_UA.txt", r"[а-щьюяєіїґ]{2,}", 400000)
    hold = 4000
    models = {
        "en": CharNgramModel(en[hold:], n),
        "ru": CharNgramModel(ru[hold:], n),
        "uk": CharNgramModel(uk[hold:], n),
    }
    en_h, ru_h, uk_h = en[:hold], ru[:hold], uk[:hold]

    def margin(typed, src, converted, tgt):
        return models[tgt].logprob(converted) - models[src].logprob(typed)

    wrong, ok = [], []  # (case, length, margin)
    for w in en_h:
        for lang, table in (("ru", E2R), ("uk", E2U)):
            t = conv(w, table)
            wrong.append(("en-typed-in-" + lang, len(w), margin(t, lang, w, "en")))
            ok.append(("en-correct-vs-" + lang, len(w), margin(w, "en", t, lang)))
    for w in ru_h:
        t = conv(w, R2E)
        wrong.append(("ru-typed-in-en", len(w), margin(t, "en", w, "ru")))
        ok.append(("ru-correct", len(w), margin(w, "ru", t, "en")))
    for w in uk_h:
        t = conv(w, U2E)
        wrong.append(("uk-typed-in-en", len(w), margin(t, "en", w, "uk")))
        ok.append(("uk-correct", len(w), margin(w, "uk", t, "en")))

    print("wrong-layout rows = recall (higher is better); correct rows = false positives (lower is better)")
    for threshold in (0, 5, 10):
        for lo, hi in ((2, 3), (4, 5), (6, 99)):
            stats = collections.defaultdict(lambda: [0, 0])
            for name, length, m in wrong + ok:
                if lo <= length <= hi:
                    stats[name][0] += m > threshold
                    stats[name][1] += 1
            row = {k: f"{100 * a / b:.2f}%" for k, (a, b) in sorted(stats.items())}
            print(f"n={n} T={threshold} len {lo}-{hi}: {row}")

    # Russian vs Ukrainian target choice for Latin input when both layouts are installed.
    choice = collections.Counter()
    for name, held, true_map, other_map, lang, other in (
        ("ru", ru_h, R2E, E2U, "ru", "uk"),
        ("uk", uk_h, U2E, E2R, "uk", "ru"),
    ):
        for w in held:
            if len(w) < 4:
                continue
            alt = conv(conv(w, true_map), other_map)
            if alt == w:
                choice[name + " identical"] += 1
            elif models[lang].logprob(w) > models[other].logprob(alt):
                choice[name + " right"] += 1
            else:
                choice[name + " wrong"] += 1
    print("ru/uk target choice:", dict(choice))

    for typed, src, tgt in [
        ("ghbdtn", "en", "ru"), ("hf,jnftn", "en", "ru"), ("ntcn", "en", "ru"),
        ("сщььше", "ru", "en"), ("пше", "ru", "en"), ("лгиуктуеуы", "ru", "en"),
        ("git", "en", "ru"), ("json", "en", "ru"), ("ok", "en", "ru"),
        ("yf", "en", "ru"), ("ns", "en", "ru"),
    ]:
        converted = conv(typed, E2R if src == "en" else R2E)
        print(f"{typed} -> {converted}: margin {margin(typed, src, converted, tgt):.1f}")
    print("distinct n-grams per model:", {k: len(m.grams) for k, m in models.items()})


if __name__ == "__main__":
    main()
