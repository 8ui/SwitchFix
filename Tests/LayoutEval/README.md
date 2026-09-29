# Layout-detection eval set

Real-text data for measuring wrong-layout detection (plan `plan/005_ngram_layout_detection.md`,
Phase 0). Used by `TestRunner` (`LayoutEval.swift`):

```bash
swift run -c release TestRunner --layout-eval-only   # only the eval, from the repo root
```

The eval is report-only: it prints recall / false-positive tables and does not fail on
quality. Results are recorded in `plan/benchmarks/`.

## Files

| File | Content |
|---|---|
| `en.txt`, `ru.txt`, `uk.txt` | one raw sentence per line, ~5000 words per language |
| `edge_cases.tsv` | hand-written cases: code/CLI words, chat slang, names, transliteration (`keep`) and tech terms / word forms typed on the wrong layout (`fix`) |
| `extract_ud.py` | regenerates the sentence files from pinned treebank commits |

## Sources and licenses

Sentences are sampled (fixed seed) from the **test** splits of Universal Dependencies
treebanks. They are redistributed here under their original license, **CC BY-SA 4.0**:

| File | Treebank | Genres |
|---|---|---|
| `en.txt` | [UD_English-EWT](https://github.com/UniversalDependencies/UD_English-EWT) @ `4a4d77f` | blog, social, reviews, email, web |
| `ru.txt` | [UD_Russian-Taiga](https://github.com/UniversalDependencies/UD_Russian-Taiga) @ `fcfd7db` | blog, fiction, news, poetry, social, wiki |
| `uk.txt` | [UD_Ukrainian-ParlaMint](https://github.com/UniversalDependencies/UD_Ukrainian-ParlaMint) @ `7d3fcb7` | parliamentary speech (spoken, formal) |

Openly licensed Ukrainian treebanks with conversational text (UD_Ukrainian-IU, BRUK) are
CC BY-NC-SA, so the Ukrainian set is more formal than the others.

**Do not train language models on these treebanks** — the eval must stay held out.

## How the eval works

- Tokens: letter runs of the language's script (inner `'` / `-` allowed); tokens mixed with
  digits or another script are dropped.
- **Isolated words**: every token is checked (a) typed correctly — any correction is a false
  positive; (b) typed on the other script's layout (en on ru/uk, ru/uk on en) — it must be
  restored to the original word in the original language. Mistypings whose key mapping does
  not round-trip are reported as `unreachable` and skipped. Two layout configurations:
  all three installed, and English plus one Cyrillic layout.
- **Sentences**: whole sentences typed with one detector (context carries over, as in the
  app). When a correction switches the layout, the rest of the sentence is typed on the new
  layout.
- **Edge cases**: `edge_cases.tsv`, reported per group with the failing words.
