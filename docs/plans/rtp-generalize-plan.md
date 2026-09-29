# Обобщение rtp — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** убрать из скилла `run-task-pipeline` (CLI `rtp`) привязки к restoplace-frontend; проектная
специфика — в необязательном `docs/tasks/.rtp.json` и CLAUDE.md проекта.

**Architecture:** `lib.mjs` получает `loadProjectConfig`, `shQuote`, `resolveBaseBranch`;
`gitContext` принимает предпочтительную базовую ветку. `rtp.mjs` грузит конфиг по папке
файла задачи и передаёт его в `nextActionFor(fm, cfg, {verbose})`. Stop-хук перестаёт считать
не-`.md` файлы в `docs/tasks/` кодом. Тексты SKILL.md / шаблона / references — нейтральные.
restoplace получает свой `.rtp.json` и абзац в CLAUDE.md.

**Tech Stack:** Node ≥18 ESM без зависимостей, POSIX sh (регресс), git.

**Spec:** `docs/features/rtp-generalize-spec.md` (читать вместе с планом).

## Global Constraints

- `SK=~/.claude/skills/run-task-pipeline` — не под git. Бэкап: `~/.claude/skills-backup-run-task-pipeline-2026-09-29` (уже сделан). Коммитов в `SK` нет; чекпойнт каждой задачи — зелёный регресс.
- Регресс: `sh $SK/scripts/regress.sh` — успех = exit 0 (`[ "$FAIL" -eq 0 ]` в конце).
- Новые кейсы регресса — в конец `regress.sh`, **перед** строкой `echo ""` / `echo "итог (все секции)…"`. Хелперы `rtp`, `ok`, `bad`, `mk`, `stop`, переменные `ROOT`, `H`, `RTP`, `LIB` уже определены выше.
- `loadProjectConfig` никогда не бросает; предупреждения — одной строкой в stderr, начинаются с `rtp: `: про содержимое конфига — `rtp: <путь>/.rtp.json: <причина> — использую умолчания`, про ненайденную ветку — `rtp: baseBranch "<x>" из .rtp.json не найден — определяю автоматически`.
- Конфиг грузится по `dirname(<файл задачи>)`, не по cwd.
- `rtp` ничего не запускает по конфигу — только печатает подсказки.
- Коммит в restoplace-frontend — только после явного «да» пользователя.

---

### Step 1: `loadProjectConfig` и `shQuote` в lib.mjs

**Files:**
- Modify: `$SK/scripts/lib.mjs` (новые экспорты рядом с `projectRootOf`, ≈697)
- Test: `$SK/scripts/regress.sh` (новая секция в конце)

**Interfaces:**
- Produces: `export const EMPTY_CONFIG = Object.freeze({ baseBranch: undefined, verify: [], reviewers: [] })`;
  `export async function loadProjectConfig(tasksDir, warn?) → Promise<{ baseBranch?: string, verify: Array<{run: string, timeout?: number} | {record: string}>, reviewers: string[] }>`;
  `export function shQuote(s: string) → string`.

- [ ] **Шаг 1.1: написать падающие кейсы**

Добавить в конец `regress.sh` (перед итогом):

```sh
echo "C1: loadProjectConfig — нормализация и устойчивость"
CFGD="$ROOT/cfgload"; mkdir -p "$CFGD"
lc() { node --input-type=module -e "
import { loadProjectConfig } from '$LIB';
const c = await loadProjectConfig(process.argv[1]);
process.stdout.write(JSON.stringify(c));
" "$CFGD"; }
[ "$(lc 2>/dev/null)" = '{"verify":[],"reviewers":[]}' ] && ok "нет файла → пустой конфиг" || bad "нет файла: $(lc 2>&1)"
printf '%s' '{"baseBranch":"dev","verify":["make a",{"run":"make b","timeout":60},{"record":"CI: x"},{"bogus":1},{"run":"make c","timeout":-1}],"reviewers":["r1","",3],"extra":true}' > "$CFGD/.rtp.json"
[ "$(lc 2>/dev/null)" = '{"verify":[{"run":"make a"},{"run":"make b","timeout":60},{"record":"CI: x"}],"reviewers":["r1"],"baseBranch":"dev"}' ] \
  && ok "поля нормализованы, мусор отброшен" || bad "нормализация: $(lc 2>/dev/null)"
lc 2>&1 >/dev/null | grep -q 'verify\[3\]' && ok "предупреждение про verify[3]" || bad "нет предупреждения про verify[3]"
printf '%s' '{bad' > "$CFGD/.rtp.json"
OUT=$(lc 2>"$ROOT/c1.err"); RC=$?
[ $RC -eq 0 ] && [ "$OUT" = '{"verify":[],"reviewers":[]}' ] && grep -q '.rtp.json: битый JSON' "$ROOT/c1.err" \
  && ok "битый JSON → умолчания + stderr" || bad "битый JSON: rc=$RC out=$OUT err=$(cat "$ROOT/c1.err")"
printf '%s' '[1]' > "$CFGD/.rtp.json"
lc 2>&1 >/dev/null | grep -q 'корень не объект' && ok "массив в корне отвергнут" || bad "массив в корне принят"
rm -f "$CFGD/.rtp.json"
Q=$(node --input-type=module -e "import { shQuote } from '$LIB'; process.stdout.write(shQuote(process.argv[1]))" "it's \"x\" \$HOME")
[ "$(sh -c "printf '%s' $Q")" = "it's \"x\" \$HOME" ] && ok "shQuote переживает sh" || bad "shQuote: $Q"
```

Ожидаемый порядок ключей в JSON — `verify`, `reviewers`, затем `baseBranch` (только если задан):
реализация ниже собирает объект именно так.

- [ ] **Шаг 1.2: прогнать — упадёт**

Run: `sh $SK/scripts/regress.sh 2>&1 | grep -A8 '^C1'`
Expected: `FAIL` на всех кейсах C1 (`loadProjectConfig` не экспортирован).

- [ ] **Шаг 1.3: реализация в lib.mjs** (после `projectRootOf`)

```js
// ──────────────────────────────────────────────────────────────────────────
// Project config: <tasksDir>/.rtp.json — optional, every field optional.
// Never throws: a broken config must not take down hooks or `rtp status`.
// ──────────────────────────────────────────────────────────────────────────

export const EMPTY_CONFIG = Object.freeze({ baseBranch: undefined, verify: [], reviewers: [] });

const defaultWarn = (m) => process.stderr.write(`${m}\n`);

function normalizeVerifyEntry(v) {
  if (typeof v === 'string') return v.trim() ? { run: v.trim() } : null;
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  if (typeof v.run === 'string' && v.run.trim() && v.record === undefined) {
    if (v.timeout === undefined) return { run: v.run.trim() };
    return Number.isInteger(v.timeout) && v.timeout > 0 ? { run: v.run.trim(), timeout: v.timeout } : null;
  }
  if (typeof v.record === 'string' && v.record.trim() && v.run === undefined) return { record: v.record.trim() };
  return null;
}

export async function loadProjectConfig(tasksDir, warn = defaultWarn) {
  const empty = () => ({ verify: [], reviewers: [] });
  if (!tasksDir) return empty();
  const path = join(tasksDir, '.rtp.json');
  const say = (why) => warn(`rtp: ${path}: ${why} — использую умолчания`);
  let text;
  try {
    text = await readFile(path, 'utf8');
  } catch (e) {
    if (e?.code !== 'ENOENT') say(`не читается (${e?.code || e?.message})`);
    return empty();
  }
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    say(`битый JSON (${e.message})`);
    return empty();
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    say('корень не объект');
    return empty();
  }
  const cfg = empty();
  if (raw.verify !== undefined) {
    if (!Array.isArray(raw.verify)) say('verify не массив');
    else raw.verify.forEach((v, i) => {
      const n = normalizeVerifyEntry(v);
      if (n) cfg.verify.push(n);
      else say(`verify[${i}] неверной формы`);
    });
  }
  if (raw.reviewers !== undefined) {
    if (!Array.isArray(raw.reviewers)) say('reviewers не массив');
    else raw.reviewers.forEach((r, i) => {
      if (typeof r === 'string' && r.trim()) cfg.reviewers.push(r.trim());
      else say(`reviewers[${i}] не непустая строка`);
    });
  }
  if (raw.baseBranch !== undefined) {
    if (typeof raw.baseBranch === 'string' && raw.baseBranch.trim()) cfg.baseBranch = raw.baseBranch.trim();
    else say('baseBranch не непустая строка');
  }
  return cfg;
}

// POSIX single-quote escaping: the printed hint can be pasted into sh as is.
export function shQuote(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}
```

`readFile` и `join` уже импортированы в `lib.mjs` (строки 4, 7).

- [ ] **Шаг 1.4: прогнать — зелёно**

Run: `sh $SK/scripts/regress.sh; echo "exit=$?"`
Expected: все `C1` — `ok`, `exit=0`.

---

### Step 2: базовая ветка в `gitContext` и handoff

**Files:**
- Modify: `$SK/scripts/lib.mjs:702-725` (`gitContext`)
- Modify: `$SK/scripts/rtp.mjs:1198-1260` (`cmdHandoff`: help ≈1213, вызов ≈1242, строка ветки ≈1258)
- Modify: импорт из `./lib.mjs` в `rtp.mjs` (≈11-59): добавить `loadProjectConfig`, `shQuote`, `EMPTY_CONFIG`
- Test: `$SK/scripts/regress.sh`

**Interfaces:**
- Consumes: `loadProjectConfig(tasksDir)` (Step 1).
- Produces: `export async function resolveBaseBranch(cwd, preferred?, warn?) → Promise<string|null>`;
  `gitContext(cwd, preferredBase?)` → `{ worktree, branch, baseBranch: string|null, aheadOfBase: string, behindBase: string, lastCommits, diffStat, dirtyFiles, dirtyCount }`
  (поля `aheadOfMaster`/`behindMaster` удалены).

- [ ] **Шаг 2.1: падающие кейсы**

```sh
echo "C2: handoff — базовая ветка"
GR="$ROOT/gitrepo"; GT="$GR/docs/tasks"; mkdir -p "$GT"
git -C "$GR" init -q -b main && git -C "$GR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
rtp new --title "Base task" --type chore --pipeline minimal --reason r --tasks-dir "$GT" >/dev/null 2>&1
GID=$(rtp find base --tasks-dir "$GT" | head -1 | cut -f1)
rtp handoff "$GID" --print-only --tasks-dir "$GT" 2>/dev/null | grep -q 'отставание от main 0' \
  && ok "без конфига база = main" || bad "без конфига: $(rtp handoff "$GID" --print-only --tasks-dir "$GT" 2>&1 | grep Ветка)"
git -C "$GR" branch dev
printf '%s' '{"baseBranch":"dev"}' > "$GT/.rtp.json"
rtp handoff "$GID" --print-only --tasks-dir "$GT" 2>/dev/null | grep -q 'отставание от dev' \
  && ok "baseBranch из конфига" || bad "baseBranch из конфига не применён"
printf '%s' '{"baseBranch":"nope"}' > "$GT/.rtp.json"
OUT=$(rtp handoff "$GID" --print-only --tasks-dir "$GT" 2>"$ROOT/c2.err")
echo "$OUT" | grep -q 'отставание от main' && grep -q 'nope' "$ROOT/c2.err" \
  && ok "несуществующая baseBranch → предупреждение и автоопределение" || bad "несуществующая baseBranch: $(cat "$ROOT/c2.err")"
rm -f "$GT/.rtp.json"
NR="$ROOT/nobase"; mkdir -p "$NR/docs/tasks"
git -C "$NR" init -q -b trunk && git -C "$NR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty -m init
rtp new --title "Nobase task" --type chore --pipeline minimal --reason r --tasks-dir "$NR/docs/tasks" >/dev/null 2>&1
NID=$(rtp find nobase --tasks-dir "$NR/docs/tasks" | head -1 | cut -f1)
rtp handoff "$NID" --print-only --tasks-dir "$NR/docs/tasks" 2>/dev/null | grep -q 'базовая ветка не определена' \
  && ok "нет main/master/origin → база не определена" || bad "без базы: $(rtp handoff "$NID" --print-only --tasks-dir "$NR/docs/tasks" 2>&1 | grep Ветка)"
```

- [ ] **Шаг 2.2: прогнать — C2 падает** (`отставание от master` вместо `main`).

Run: `sh $SK/scripts/regress.sh 2>&1 | grep -A6 '^C2'`

- [ ] **Шаг 2.3: `resolveBaseBranch` + новый `gitContext` в lib.mjs** (заменить функцию целиком)

```js
async function refExists(ref, cwd) {
  const { code } = await run('git', ['rev-parse', '--verify', '--quiet', `${ref}^{commit}`], cwd);
  return code === 0;
}

// Base for ahead/behind: config → origin/HEAD → main/master → null.
export async function resolveBaseBranch(cwd, preferred, warn = defaultWarn) {
  if (preferred) {
    if (await refExists(preferred, cwd)) return preferred;
    warn(`rtp: baseBranch "${preferred}" из .rtp.json не найден — определяю автоматически`);
  }
  const head = await git(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'], cwd);
  if (head) {
    const local = head.replace(/^origin\//, '');
    if (await refExists(local, cwd)) return local;
    if (await refExists(head, cwd)) return head;
  }
  for (const b of ['main', 'master']) if (await refExists(b, cwd)) return b;
  return null;
}

export async function gitContext(cwd, preferredBase) {
  const baseBranch = await resolveBaseBranch(cwd, preferredBase);
  const [worktree, branch, counts, lastCommits, diffStat, porcelain] = await Promise.all([
    git(['rev-parse', '--show-toplevel'], cwd),
    git(['rev-parse', '--abbrev-ref', 'HEAD'], cwd),
    baseBranch ? git(['rev-list', '--left-right', '--count', `${baseBranch}...HEAD`], cwd) : '',
    git(['log', '--oneline', '-3'], cwd),
    git(['diff', 'HEAD', '--stat'], cwd),
    git(['status', '--porcelain'], cwd),
  ]);
  const [behind, ahead] = (counts || '').split(/\s+/);
  const dirty = porcelain ? porcelain.split('\n').filter(Boolean) : [];
  return {
    worktree: worktree || cwd,
    branch: branch || '(unknown)',
    baseBranch,
    behindBase: behind || '0',
    aheadOfBase: ahead || '0',
    lastCommits: lastCommits ? lastCommits.split('\n') : [],
    diffStat: diffStat ? diffStat.split('\n').filter(Boolean) : [],
    dirtyFiles: dirty.map((l) => l.slice(3)).slice(0, 25),
    dirtyCount: dirty.length,
  };
}
```

`defaultWarn` определён в Step 1 выше по файлу — `resolveBaseBranch` ставить **после** него.

- [ ] **Шаг 2.4: `cmdHandoff` в rtp.mjs**

Импорт: в список `import { … } from './lib.mjs'` добавить `loadProjectConfig, shQuote, EMPTY_CONFIG`.

Вместо `const g = await gitContext(root);`:

```js
  const cfg = await loadProjectConfig(dirname(file));
  const g = await gitContext(root, cfg.baseBranch);
```

Вместо строки «Ветка» (≈1258-1260):

```js
  lines.push(
    g.baseBranch
      ? `- **Ветка:** \`${g.branch}\` — своих коммитов ${g.aheadOfBase}, отставание от ${g.baseBranch} ${g.behindBase}`
      : `- **Ветка:** \`${g.branch}\` — базовая ветка не определена`,
  );
```

В help (≈1213): `phase + plan step, worktree path + branch, ahead/behind the base branch
(.rtp.json baseBranch → origin/HEAD → main/master), dirty files,`.

Проверить, что других обращений к `aheadOfMaster`/`behindMaster` нет:
Run: `grep -n "OfMaster\|behindMaster" $SK/scripts/*.mjs` → пусто.

- [ ] **Шаг 2.5: регресс зелёный**

Run: `sh $SK/scripts/regress.sh; echo "exit=$?"` → `exit=0`.

---

### Step 3: подсказки verify/ревьюеров в `nextActionFor`

**Files:**
- Modify: `$SK/scripts/rtp.mjs:1098-1192` (`buildStatusBlock`, `nextActionFor`, `cmdNext`), `:1321` (`cmdHandoff`)
- Test: `$SK/scripts/regress.sh`

**Interfaces:**
- Consumes: `loadProjectConfig`, `shQuote`, `EMPTY_CONFIG` (Step 1); `cfg` в `cmdHandoff` (Step 2).
- Produces: `nextActionFor(fm, cfg = EMPTY_CONFIG, { verbose = false } = {}) → string` (многострочная при `verbose` в фазе `review`).

- [ ] **Шаг 3.1: падающие кейсы**

```sh
echo "C3: rtp next / status — подсказки из .rtp.json"
CR="$ROOT/cfgrepo"; CT="$CR/docs/tasks"; mkdir -p "$CT"
rtp new --title "Cfg task" --type chore --pipeline minimal --reason r --tasks-dir "$CT" >/dev/null 2>&1
CID=$(rtp find cfg --tasks-dir "$CT" | head -1 | cut -f1)
rtp phase "$CID" --to review --log x --tasks-dir "$CT" >/dev/null 2>&1
OUT=$(rtp next "$CID" --tasks-dir "$CT" 2>&1)
echo "$OUT" | grep -qF "CLAUDE.md проекта" && ! echo "$OUT" | grep -q npm \
  && ok "без конфига — нейтральная подсказка без npm" || bad "без конфига: $OUT"
printf '%s' '{"verify":["make build",{"run":"make test","timeout":600},{"record":"CI зелёный: <url>"},{"bogus":1}],"reviewers":["rev-a","rev-b"]}' > "$CT/.rtp.json"
OUT=$(rtp next "$CID" --tasks-dir "$CT" 2>"$ROOT/c3.err")
echo "$OUT" | grep -qF -- "--run 'make build'" && echo "$OUT" | grep -qF -- "--run 'make test' --timeout 600" \
  && echo "$OUT" | grep -qF -- "--record 'CI зелёный: <url>'" && echo "$OUT" | grep -qF "rev-a / rev-b" \
  && echo "$OUT" | grep -qF -- "--to done" \
  && ok "next печатает команды и ревьюеров" || bad "next с конфигом: $OUT"
grep -q 'verify\[3\]' "$ROOT/c3.err" && ok "мусорный элемент verify отброшен с предупреждением" || bad "нет предупреждения verify[3]"
printf '%s' '{"reviewers":["rev-a"]}' > "$CT/.rtp.json"
OUT=$(rtp next "$CID" --tasks-dir "$CT" 2>&1)
echo "$OUT" | grep -qF "CLAUDE.md проекта" && echo "$OUT" | grep -qF "rev-a" \
  && ok "только reviewers → нейтральный verify + ревьюер" || bad "только reviewers: $OUT"
printf '%s' '{"verify":["echo \"q\" $X"]}' > "$CT/.rtp.json"
LINE=$(rtp next "$CID" --tasks-dir "$CT" 2>/dev/null | grep -- '--run' | head -1)
ARG=${LINE#*--run }
[ "$(sh -c "printf '%s' $ARG")" = 'echo "q" $X' ] && ok "команда с \" и \$ вставляется как есть" || bad "экранирование: $LINE"
printf '%s' '{bad' > "$CT/.rtp.json"
rtp status "$CID" --tasks-dir "$CT" >/dev/null 2>"$ROOT/c3b.err" && rtp next "$CID" --tasks-dir "$CT" >/dev/null 2>&1 \
  && grep -q '.rtp.json' "$ROOT/c3b.err" && ok "битый JSON: status/next exit 0 + предупреждение" || bad "битый JSON валит status/next"
printf '%s' '{"verify":["make build"]}' > "$CT/.rtp.json"
OUT=$( (cd "$ROOT" && node "$RTP" status "$CT/$CID.md") 2>&1)
echo "$OUT" | grep -qF "rtp next $CID" && ok "status из чужого cwd берёт конфиг задачи" || bad "конфиг взят не по папке задачи: $OUT"
rtp index --tasks-dir "$CT" >/dev/null 2>&1 && ! grep -q 'rtp.json' "$CT/index.md" \
  && ok "index игнорирует .rtp.json" || bad "index видит .rtp.json"
rtp validate --all --tasks-dir "$CT" 2>&1 | grep -q 'rtp.json' && bad "validate --all видит .rtp.json" || ok "validate --all игнорирует .rtp.json"
rtp find rtp --tasks-dir "$CT" 2>&1 | grep -q 'rtp.json' && bad "find матчит .rtp.json" || ok "find игнорирует .rtp.json"
```

- [ ] **Шаг 3.2: прогнать — C3 падает** (подсказка содержит `npm run lint`). Кейсы index/validate/find — страховочные: зелёные и до, и после правки, это ожидаемо.

- [ ] **Шаг 3.3: `nextActionFor` + `reviewAction`** (заменить `case 'review'` и сигнатуру)

```js
const NEUTRAL_VERIFY = '<команды проверки из CLAUDE.md проекта>';

function reviewAction(id, cfg, verbose) {
  if (!verbose) {
    return cfg.verify.length
      ? `rtp verify по командам проекта (rtp next ${id}), затем ревью субагентом → rtp phase ${id} --to done`
      : `rtp verify ${id} --run "${NEUTRAL_VERIFY}", затем ревью субагентом → rtp phase ${id} --to done`;
  }
  const lines = cfg.verify.length
    ? cfg.verify.map((v) =>
        v.record !== undefined
          ? `rtp verify ${id} --record ${shQuote(v.record)}`
          : `rtp verify ${id} --run ${shQuote(v.run)}${v.timeout ? ` --timeout ${v.timeout}` : ''}`,
      )
    : [`rtp verify ${id} --run ${shQuote(NEUTRAL_VERIFY)}`];
  lines.push(
    cfg.reviewers.length
      ? `ревьюер: ${cfg.reviewers.join(' / ')} (иначе general-purpose)`
      : 'ревьюер: субагент из списка агентов сессии (иначе general-purpose)',
  );
  lines.push(`затем rtp phase ${id} --to done`);
  return lines.join('\n');
}

function nextActionFor(fm, cfg = EMPTY_CONFIG, { verbose = false } = {}) {
```

и в `switch`: `case 'review': return reviewAction(id, cfg, verbose);`

- [ ] **Шаг 3.4: вызывающие**

`buildStatusBlock(file)` — конфиг грузить только когда строка «Дальше» идёт из фазы, а не из
шага плана (иначе битый `.rtp.json` предупреждает на каждом `rtp step`). Вместо
`const nextLine = nextStep ? … : \`🔜 Дальше: ${nextActionFor(fm)}\`;`:

```js
  const nextLine = nextStep
    ? `🔜 Дальше: шаг ${steps.indexOf(nextStep) + 1} — ${nextStep.text}`
    : `🔜 Дальше: ${nextActionFor(fm, await loadProjectConfig(dirname(file)))}`;
```

`cmdNext` — вместо `console.log(\`→ ${nextActionFor(fm)}\`);`:

```js
  const cfg = await loadProjectConfig(dirname(t.file));
  const [first, ...rest] = nextActionFor(fm, cfg, { verbose: true }).split('\n');
  console.log(`→ ${first}`);
  for (const l of rest) console.log(`  ${l}`);
```

`cmdHandoff` (≈1321): `lines.push(\`- ${nextActionFor(fm, cfg)}\`);` — `cfg` из Step 2.

- [ ] **Шаг 3.5: регресс зелёный** — `sh $SK/scripts/regress.sh; echo "exit=$?"` → `exit=0`.

---

### Step 4: Stop-хук не считает `.rtp.json` кодом

**Files:**
- Modify: `$SK/scripts/rtp.mjs` в `walkTranscript`, ветка `EDIT_TOOLS`, перед `if (!(await trackerDirOf(f, acc))) continue;` (≈1986)
- Test: `$SK/scripts/regress.sh`

**Interfaces:** нет новых.

- [ ] **Шаг 4.1: падающий кейс**

```sh
echo "C4: Stop — правка docs/tasks/.rtp.json не требует обновления задачи"
mk "$H/c4.jsonl" '[user("настрой конфиг"),asst(edit("u1",E.H+"/repo-c/docs/tasks/.rtp.json"))]'
OUT=$(stop "$H/repo-c" "$H/c4.jsonl" c4); RC=$?
[ $RC -eq 0 ] && ok "ход с правкой .rtp.json не блокируется" || bad "exit $RC: $OUT"
```

- [ ] **Шаг 4.2: прогнать — C4 падает с exit 2.**

- [ ] **Шаг 4.3: реализация**

```js
        // Non-task files directly in docs/tasks (.rtp.json) are tracker
        // metadata: not code to demand a task update for, and they name no task.
        if (/\/docs\/tasks\/[^/]+$/.test(f.replace(/\\/g, '/'))) continue;
```

- [ ] **Шаг 4.4: регресс зелёный** — `exit=0`.

---

### Step 5: нейтральные тексты в rtp.mjs

**Files:**
- Modify: `$SK/scripts/rtp.mjs` — общий help (≈125-145), `validate --help` (≈596), предупреждение validate (≈701), `steps --help` NOTE (≈882-885), `verify --help` (≈1362), комментарий (≈1876-1881).

- [ ] **Шаг 5.1: правки**

- Общий help: `2026-05-14-fix-scheme-zoom` → `2026-01-10-fix-login-redirect`; `"Fix scheme zoom"` → `"Fix login redirect"`; `"single-file display fix"` → `"single-file fix"`; `extract zoom helper — coupled to floor state` → `extract redirect helper — duplicated in two routes`; `--close "extract zoom helper" --ref 2026-05-15-zoom-refactor` → `--close "extract redirect helper" --ref 2026-01-12-redirect-refactor`; `rtp resume "scheme zoom"` → `rtp resume "login redirect"`; `docs/plans/scheme-zoom-plan.md` → `docs/plans/login-redirect-plan.md`; `--run "npm run lint"` → `--run "make test"`; `--write "Konva-канвас не мерится в фоновой вкладке"` → `--write "редирект воспроизводится только с просроченной сессией"`.
- `verify --help`: `rtp verify <id> --run "npm run lint"` → `rtp verify <id> --run "<команда из .rtp.json / CLAUDE.md проекта>"` (следующую строку про тесты проекта оставить).
- `validate --help` и предупреждение validate: `invisible to /debts-report` → `invisible to the index and debt reports`.
- `steps --help` NOTE: `counted as technical debt by\n  /debts-report and by the index.` → `counted as technical debt by\n  the index and debt reports.`
- Комментарий ≈1879: `and with ~10 worktrees sharing\n// one docs/tasks a peeked id would otherwise become resolvable` → `and with parallel sessions in\n// neighbouring worktrees a peeked id would otherwise become resolvable`.
- Комментарий ≈1618-1620 (SessionStart): `Several worktree\n    // sessions share one docs/tasks, and the most recently updated task there\n    // may well belong to a parallel session.` → `Parallel sessions\n    // in neighbouring worktrees are common, and the most recently updated task\n    // may well belong to one of them.`
- `lib.mjs:598` (комментарий над `STEP_STATUS`): `` `/debts-report` and countOpenDebts() count `` → `` debt reports and countOpenDebts() count ``.
- `build-index.mjs:79-82`: `// Mirrors \`/debts-report\`'s regex (leading whitespace + flexible spacing) so\n// numbers in the index match what the aggregator surfaces.` → `// Leading whitespace + flexible spacing, the same shape debt-report\n// aggregators match, so the index numbers agree with them.`; `// same blind spot as \`/debts-report\`.` → `// the usual blind spot of line-based debt aggregators.`

- [ ] **Шаг 5.2: grep + регресс**

Run: `grep -niE "restoplace|test:remote|frontend-invariants|legacy-parity|caveman|openapi|migration-module|debts-report|npm run|konva|scheme-zoom|master\b" $SK/scripts/rtp.mjs $SK/scripts/lib.mjs $SK/scripts/build-index.mjs`
Expected: ровно две строки — `for (const b of ['main', 'master'])` в `lib.mjs` и строка handoff help
`(.rtp.json baseBranch → origin/HEAD → main/master)` в `rtp.mjs`.
Run: `sh $SK/scripts/regress.sh; echo "exit=$?"` → `exit=0` (кейсы регресса help-тексты не матчат — проверить, что `grep -n "scheme-zoom\|npm run lint" $SK/scripts/regress.sh` не завязан на help; если завязан — обновить ожидание в кейсе).

---

### Step 6: SKILL.md, шаблон, references

**Files:**
- Modify: `$SK/SKILL.md` (≈34-37, 60-66, 145-148 таблица хуков — без изменений, 174-178, 224/228, 336-366, 383, 406, 418, 452-456; новый раздел после «Tooling»)
- Modify: `$SK/templates/task.md:38`
- Modify: `$SK/references/anti-rationalization.md:20`

- [ ] **Шаг 6.1: правки SKILL.md**

1. ≈34-35: `Есть в списке специализированный ревьюер (\`caveman:cavecrew-reviewer\`,\n\`frontend-invariants-reviewer\`, \`legacy-parity-auditor\`) — бери его.` →
   `Специализированный ревьюер — из \`reviewers\` в \`docs/tasks/.rtp.json\` проекта (их печатает\n\`rtp next <id>\` в фазе review), иначе подходящий из списка агентов сессии (например, из\nподключённого плагина) — бери его.`
2. ≈60-66, раздел Delegation → 
   ```
   ## Delegation — when NOT this skill

   Если CLAUDE.md проекта называет более специфичный скилл для задачи (миграция модуля,
   кодогенерация и т. п.) — вызывай его вместо этого.

   For everything else that writes code — this skill.
   ```
3. ≈176-178: `id**: у проекта ~10 worktree с общим \`docs/tasks\`, и «последняя активная задача» там\nрегулярно принадлежит соседней сессии.` →
   `id**: в проекте могут идти параллельные сессии в соседних worktree, и «последняя активная\nзадача» регулярно принадлежит соседней.`
4. ≈224, 228: `2026-09-07-fix-scheme-zoom` → `2026-01-10-fix-login-redirect`; строки 225-226: `перенёс зум в контроллер` → `вынес проверку сессии в middleware`; `синхронизировать зум с миникартой` → `тест на просроченную сессию`.
5. ≈339-349: блок заменить на
   ````
      ```bash
      rtp next <id>     # в фазе review печатает готовые rtp verify из docs/tasks/.rtp.json
      rtp verify <id> --run "<команда проверки проекта>"
      rtp verify <id> --run "<прогон тестов проекта>" --timeout 900
      ```
      **Команды бери из `.rtp.json` проекта (их печатает `rtp next`), иначе из его CLAUDE.md,
      а не из этого файла.** В блоке выше — форма вызова, а не рецепт. Проект может предписывать
      удалённый прогон, другой раннер или прямой запрет на локальный полный прогон — такие
      правила существуют, потому что полный прогон на машине пользователя уже стоил кому-то
      минут работы ноутбука. Не нашёл ни конфига, ни правила в CLAUDE.md — спроси
      пользователя, а не подставляй дефолт отсюда.
   ````
   (строки 350-352 про код выхода и `--record` оставить).
6. ≈354-357: `4. Dispatch a reviewer subagent (opus) on the diff — \`caveman:cavecrew-reviewer\` /\n   \`frontend-invariants-reviewer\` / \`legacy-parity-auditor\` из списка агентов сессии, иначе\n   \`general-purpose\`` →
   `4. Dispatch a reviewer subagent (opus) on the diff — ревьюер из \`reviewers\` в \`.rtp.json\`\n   или подходящий из списка агентов сессии, иначе \`general-purpose\``.
7. ≈366: `их подхватит \`/debts-report\`` → `их подхватят индекс и отчёты по долгам проекта`.
8. ≈383: `ahead/behind master` → `ahead/behind базовой ветки (\`.rtp.json\` → \`origin/HEAD\` → \`main\`/\`master\`)`.
9. ≈406: `invisible to \`/debts-report\`` → `invisible to the index and debt reports`.
10. ≈418: строку `Same format is recommended for \`## Debt\` in \`docs/migration/modules/<module-id>.md\` (out of scope for this skill).` удалить.
11. ≈456: `- \`caveman:cavecrew-reviewer\` / \`frontend-invariants-reviewer\` / \`legacy-parity-auditor\` / \`general-purpose\` — Step 6 (code review)` →
    `- ревьюер из \`reviewers\` в \`.rtp.json\` / подходящий из списка агентов сессии / \`general-purpose\` — Step 6 (code review)`.
12. Новый раздел сразу после блока «Invocation forms…» / перед «### Хуки»:
    ````
    ### Конфиг проекта — `docs/tasks/.rtp.json`

    Необязательный файл рядом с задачами; всё проектное (команды проверки, ревьюеры,
    базовая ветка) живёт в нём и в CLAUDE.md проекта, а не в этом скилле.

    ```json
    {
      "baseBranch": "main",
      "verify": ["make build", {"run": "make test", "timeout": 900}, {"record": "CI зелёный: <ссылка>"}],
      "reviewers": ["<subagent_type ревьюера>"]
    }
    ```

    - Все поля необязательны. `verify`: строка (= `--run`), `{run, timeout}` или `{record}`.
    - Читается из папки **файла задачи**, не из cwd. Битый файл → предупреждение в stderr и
      умолчания; `rtp` из-за конфига не падает.
    - `rtp` ничего не запускает сам: `rtp next <id>` в фазе review печатает готовые
      `rtp verify …` и ревьюеров.
    - База для ahead/behind в handoff: `baseBranch` → `origin/HEAD` → `main`/`master`.
    ````

- [ ] **Шаг 6.2: шаблон и references**

- `templates/task.md:38`: `(читаются скилом \`/debts-report\`)` → `(их считают индекс и отчёты по долгам)`.
- `references/anti-rationalization.md:20`: `` `/debts-report` агрегирует только `- [ ]`. `` → `` Индекс и отчёты по долгам считают только `- [ ]`. ``

- [ ] **Шаг 6.3: grep по всему скиллу**

Run: `grep -rniE "restoplace|test:remote|frontend-invariants|legacy-parity|caveman|openapi|migration-module|debts-report|npm run|konva|scheme-zoom|master\b" $SK/SKILL.md $SK/scripts/rtp.mjs $SK/scripts/lib.mjs $SK/scripts/build-index.mjs $SK/templates $SK/references`
Expected: только `lib.mjs` (`['main', 'master']`) и SKILL.md строки про автоопределение (`main\`/\`master\``).
Регресс: `exit=0`.

---

### Step 7: restoplace-frontend — конфиг и CLAUDE.md

**Files:**
- Create: `~/Desktop/projects/restoplace-frontend/docs/tasks/.rtp.json`
- Modify: `~/Desktop/projects/restoplace-frontend/CLAUDE.md` — раздел с `run-task-pipeline` (≈363-368)

- [ ] **Шаг 7.1: `.rtp.json`**

```json
{
  "baseBranch": "master",
  "verify": [
    "npm run build",
    "npm run lint",
    { "run": "npm run test:remote -- --changed master", "timeout": 900 }
  ],
  "reviewers": ["frontend-invariants-reviewer", "legacy-parity-auditor"]
}
```

- [ ] **Шаг 7.2: CLAUDE.md** — в существующий список пунктов раздела `## Workflow` (≈367-369,
после пункта «**CLI пайплайна — голый `rtp`…**», т. е. ПОСЛЕ абзаца «Orchestrator subagents —
EXEMPTION», не перед ним) вставить:

```md
- **Делегирование из пайплайна:** задача — модуль миграции (`docs/migration/modules/<id>.md`,
  «миграция модуля X») → скилл `migration-module`; генерация типов API → `openapi-codegen`.
  Формат долгов `rtp` (`- [ ]` в `## Debt`) — и в `docs/migration/modules/<id>.md`.
- **Проверки и ревьюеры для `rtp`** — в `docs/tasks/.rtp.json` (`rtp next <id>` в фазе review
  печатает их готовыми командами).
```

- [ ] **Шаг 7.3: проверка поведения**

```sh
cd ~/Desktop/projects/restoplace-frontend
rtp list --active | head -5            # работает как раньше (таблица с заголовком)
ID=$(rtp list --active --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s)[0].id))')
rtp show "$ID" | head -12
rtp handoff "$ID" --print-only | grep 'Ветка'     # «отставание от master N»
T=$(mktemp -d); mkdir -p "$T/docs/tasks"; cp docs/tasks/.rtp.json "$T/docs/tasks/"
rtp new --title "probe" --type chore --pipeline minimal --reason r --tasks-dir "$T/docs/tasks" >/dev/null
P=$(rtp find probe --tasks-dir "$T/docs/tasks" | head -1 | cut -f1)
rtp phase "$P" --to review --log x --tasks-dir "$T/docs/tasks" >/dev/null
rtp next "$P" --tasks-dir "$T/docs/tasks"   # npm run build, npm run lint, test:remote --timeout 900, оба ревьюера
rm -rf "$T"
git status --short docs/tasks/.rtp.json CLAUDE.md
```

Expected: `rtp next` печатает 3 строки `rtp verify`, `ревьюер: frontend-invariants-reviewer / legacy-parity-auditor`.

- [ ] **Шаг 7.4: коммит в restoplace** — только после «да» пользователя:
`git add docs/tasks/.rtp.json CLAUDE.md && git commit -m "chore(rtp): project config for the generalized pipeline skill"`.

---

### Step 8: итоговая проверка и доказательства

- [ ] **Шаг 8.1:** `rtp verify 2026-09-29-rtp-generalize --run "sh $HOME/.claude/skills/run-task-pipeline/scripts/regress.sh"`
- [ ] **Шаг 8.2:** `rtp verify 2026-09-29-rtp-generalize --run "<grep из Step 6.3>"` — вывод сверить с ожиданием (grep с совпадениями даёт exit 0, это нормально; оценивать содержимое).
- [ ] **Шаг 8.3:** `rtp verify 2026-09-29-rtp-generalize --record "restoplace: rtp list/show/handoff/next проверены" --out "<что показали>"`
- [ ] **Шаг 8.4:** ревьюер-субагент (general-purpose, opus) по diff `diff -ru ~/.claude/skills-backup-run-task-pipeline-2026-09-29 ~/.claude/skills/run-task-pipeline` + спеке.
