// Shared helpers for rtp CLI and build-index.
// Zero dependencies. ESM.

import { readdir, readFile, writeFile, mkdir, stat, access, rename } from 'node:fs/promises';
import { constants as FS } from 'node:fs';
import { execFile } from 'node:child_process';
import { dirname, isAbsolute, join, resolve, basename, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

// ──────────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────────

export const VALID_TYPES = ['feature', 'bug', 'refactor', 'chore'];
export const VALID_PIPELINES = ['full', 'no-spec', 'minimal'];
export const VALID_PHASES = [
  'triage',
  'spec',
  'spec-review',
  'plan',
  'plan-review',
  'impl',
  'review',
  'done',
  'blocked',
];

// fileURLToPath, not .pathname: a repo checkout may live under a path with
// spaces or Cyrillic, which .pathname leaves percent-encoded.
export const SKILL_DIR = resolve(fileURLToPath(new URL('..', import.meta.url)));
export const TEMPLATE_PATH = join(SKILL_DIR, 'templates', 'task.md');

// ──────────────────────────────────────────────────────────────────────────
// Date / slug
// ──────────────────────────────────────────────────────────────────────────

// Local calendar date. toISOString() is UTC: between midnight and the UTC
// offset (00:00–03:00 in Moscow) a task created "today" got yesterday's id.
export function today() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const RU_TRANSLIT = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z',
  и: 'i', й: 'i', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r',
  с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch',
  ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya',
};

export function slugify(title) {
  if (!title) return '';
  const lower = String(title).toLowerCase();
  let out = '';
  for (const ch of lower) {
    if (ch in RU_TRANSLIT) out += RU_TRANSLIT[ch];
    else out += ch;
  }
  let s = out.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (s.length > 60) {
    // Cut on a word boundary: `…-nazyvaetsya-za` is not an id anyone retypes.
    const cut = s.lastIndexOf('-', 60);
    s = s.slice(0, cut > 20 ? cut : 60).replace(/-+$/, '');
  }
  return s;
}

// ──────────────────────────────────────────────────────────────────────────
// Paths
// ──────────────────────────────────────────────────────────────────────────

export async function exists(p) {
  try {
    await access(p, FS.F_OK);
    return true;
  } catch {
    return false;
  }
}

// Walk up from `start` looking for an existing `docs/tasks` directory.
// If none found, fall back to `<git-root>/docs/tasks` or `<start>/docs/tasks`.
export async function findTasksDir(start = process.cwd()) {
  let dir = resolve(start);
  let gitRoot = null;
  while (true) {
    const candidate = join(dir, 'docs', 'tasks');
    if (await exists(candidate)) return candidate;
    if (!gitRoot && (await exists(join(dir, '.git')))) gitRoot = dir;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  // No existing docs/tasks dir — pick best fallback location.
  const base = gitRoot || resolve(start);
  return join(base, 'docs', 'tasks');
}

// Like findTasksDir, but never invents a fallback path: returns null when no
// docs/tasks exists above `start`. Hooks need this — "there is no tracker for
// these files" must be distinguishable from "here is where one would live".
export async function findTasksDirStrict(start) {
  let dir = resolve(start);
  while (true) {
    const candidate = join(dir, 'docs', 'tasks');
    if (await exists(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

export async function ensureDir(p) {
  await mkdir(p, { recursive: true });
}

// Resolve a task identifier (id, slug substring, filename, or absolute path)
// to an absolute file path. Throws if no match or multiple matches.
export async function resolveTaskFile(idOrPath, tasksDir) {
  if (!idOrPath) throw new Error('Task id or path is required.');
  if (isAbsolute(idOrPath)) return idOrPath;

  // If it looks like a path with extension, treat as relative.
  if (idOrPath.endsWith('.md') && idOrPath.includes('/')) {
    return resolve(idOrPath);
  }

  let files;
  try {
    files = await readdir(tasksDir);
  } catch (err) {
    if (err.code === 'ENOENT') {
      throw new Error(`Tasks dir not found: ${tasksDir}`);
    }
    throw err;
  }
  const candidates = files.filter(
    (f) => f.endsWith('.md') && f !== 'index.md' && !f.startsWith('_'),
  );

  // Exact id match: 2026-05-14-foo
  const exact = candidates.filter((f) => f === `${idOrPath}.md`);
  if (exact.length === 1) return join(tasksDir, exact[0]);

  // Substring match
  const partial = candidates.filter((f) => f.includes(idOrPath));
  if (partial.length === 1) return join(tasksDir, partial[0]);
  if (partial.length === 0) {
    throw new Error(`No task file matched: ${idOrPath} (in ${tasksDir})`);
  }
  throw new Error(
    `Ambiguous task id "${idOrPath}" — multiple matches: ${partial.join(', ')}`,
  );
}

// ──────────────────────────────────────────────────────────────────────────
// Frontmatter
// ──────────────────────────────────────────────────────────────────────────

// Parses TOP-LEVEL frontmatter keys only. Nested objects (artifacts:) are
// preserved as a raw substring under key `_raw_artifacts` for write-back.
// For updates we use targeted replaceFrontmatterField instead of reserialize.
export function parseFrontmatter(raw) {
  const m = raw.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const obj = {};
  for (const line of m[1].split('\n')) {
    const kv = line.match(/^([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (!kv) continue;
    obj[kv[1]] = parseYamlScalar(kv[2].trim());
  }
  return obj;
}

// Unquotes a scalar the way renderYamlValue()/escapeYaml() wrote it: those use
// JSON.stringify, so a naive quote-strip leaves \" and \\ in the value.
export function parseYamlScalar(v) {
  if (v === '' || v === 'null' || v === '~') return null;
  if (v === 'true') return true;
  if (v === 'false') return false;
  if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
    try {
      return JSON.parse(v);
    } catch {
      return v.slice(1, -1);
    }
  }
  if (v.startsWith("'") && v.endsWith("'") && v.length >= 2) {
    return v.slice(1, -1).replace(/''/g, "'");
  }
  return v;
}

export function splitFrontmatter(raw) {
  const m = raw.match(/^(---\n[\s\S]*?\n---\n?)([\s\S]*)$/);
  if (!m) return { header: '', body: raw };
  return { header: m[1], body: m[2] };
}

// Replace `key: <old>` line in frontmatter block. Creates the key if missing
// (inserted right before closing `---`).
export function replaceFrontmatterField(raw, key, value) {
  const fmMatch = raw.match(/^(---\n)([\s\S]*?)(\n---\n?)/);
  if (!fmMatch) throw new Error('No frontmatter found.');
  const [, open, body, close] = fmMatch;
  const lines = body.split('\n');
  const rendered = renderYamlValue(value);
  let found = false;
  const updated = lines.map((line) => {
    const m = line.match(/^([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (m && m[1] === key) {
      found = true;
      return `${key}: ${rendered}`;
    }
    return line;
  });
  if (!found) updated.push(`${key}: ${rendered}`);
  // Function replacement, NOT a string: a title containing `$&` / `$'` / `$$`
  // would otherwise be expanded as a substitution pattern and destroy the file.
  return raw.replace(fmMatch[0], () => open + updated.join('\n') + close);
}

// Sets a key one level deep, e.g. artifacts.spec. Creates the child key under
// an existing parent block; throws when the parent block is absent.
export function replaceNestedFrontmatterField(raw, parentKey, childKey, value) {
  const fmMatch = raw.match(/^(---\n)([\s\S]*?)(\n---\n?)/);
  if (!fmMatch) throw new Error('No frontmatter found.');
  const [, open, body, close] = fmMatch;
  const lines = body.split('\n');
  const parentIdx = lines.findIndex((l) => new RegExp(`^${parentKey}:\\s*$`).test(l));
  if (parentIdx < 0) throw new Error(`No '${parentKey}:' block in frontmatter.`);

  let end = parentIdx + 1;
  while (end < lines.length && /^\s+\S/.test(lines[end])) end++;
  const indent = (lines[parentIdx + 1] || '  x').match(/^(\s*)/)[1] || '  ';
  const rendered = renderYamlValue(value);

  let found = false;
  for (let i = parentIdx + 1; i < end; i++) {
    const m = lines[i].match(/^(\s+)([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (m && m[2] === childKey) {
      lines[i] = `${m[1]}${childKey}: ${rendered}`;
      found = true;
      break;
    }
  }
  if (!found) lines.splice(end, 0, `${indent}${childKey}: ${rendered}`);
  return raw.replace(fmMatch[0], () => open + lines.join('\n') + close);
}

function renderYamlValue(v) {
  if (v === null || v === undefined) return 'null';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return String(v);
  const s = String(v);
  // Quote if contains chars that need it.
  if (/[:#@`*&!|>{}\[\],"']/.test(s) || s !== s.trim()) {
    return JSON.stringify(s);
  }
  return s;
}

// ──────────────────────────────────────────────────────────────────────────
// Task file IO
// ──────────────────────────────────────────────────────────────────────────

export async function readTask(file) {
  const raw = await readFile(file, 'utf8');
  const fm = parseFrontmatter(raw);
  if (!fm) throw new Error(`No frontmatter in ${file}`);
  const { body } = splitFrontmatter(raw);
  return { file, raw, fm, body };
}

// Atomic: a hook killed at its timeout mid-write must not leave a truncated
// task file. (Lost updates between two concurrent sessions are NOT solved here.)
export async function writeTaskRaw(file, raw) {
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, raw);
  await rename(tmp, file);
}

// ──────────────────────────────────────────────────────────────────────────
// Body sections (Log / Debt)
// ──────────────────────────────────────────────────────────────────────────

// Returns indices [startOfHeader, startOfNextHeader] for a section ## Title.
export function findSection(body, title) {
  // `[ \t]*$` — NOT `\s*$`: in multiline mode `\s*` swallows the blank lines
  // after the heading, so every rewrite of a section pushed two more newlines
  // in front of its content.
  const re = new RegExp(`^##\\s+${escapeRegex(title)}[ \\t]*$`, 'm');
  const m = re.exec(body);
  if (!m) return null;
  const start = m.index;
  const headerEnd = start + m[0].length;
  // Find next `## ` heading or EOF.
  const rest = body.slice(headerEnd);
  const next = rest.match(/^##\s+/m);
  const end = next ? headerEnd + next.index : body.length;
  return { start, headerEnd, end };
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// The debt section, tolerating a tail after the title: trackers written by hand
// carry headings like `## Debt (накапливается по мере миграции)`. With the exact
// `findSection` such a file had no debt section at all — `--close`/`--list` threw
// or showed nothing, and `addDebtItem` created a SECOND `## Debt` next to it.
// The exact heading wins when both exist. The tail must start with a space or tab,
// so `## Debts` / `## Debt-кандидаты` stay other sections. `headerEnd` is the end
// of the whole heading line — cutting after the word `Debt` would split the tail
// into a paragraph on the next rewrite.
export function findDebtSection(body) {
  const exact = findSection(body, 'Debt');
  if (exact) return exact;
  const m = /^##[ \t]+Debt[ \t][^\n]*$/m.exec(body);
  if (!m) return null;
  const start = m.index;
  const headerEnd = start + m[0].length;
  const rest = body.slice(headerEnd);
  const next = rest.match(/^##\s+/m);
  const end = next ? headerEnd + next.index : body.length;
  return { start, headerEnd, end };
}

export function getDebtSectionContent(body) {
  const sec = findDebtSection(body);
  return sec ? body.slice(sec.headerEnd, sec.end) : null;
}

export function appendLog(body, date, message) {
  // Legacy task files predate some sections — create rather than throw, or a
  // `rtp phase` on such a file would fail after the frontmatter was already
  // rewritten in memory, silently losing the phase change.
  let sec = findSection(body, 'Log');
  if (!sec) {
    body = setSection(body, 'Log', '');
    sec = findSection(body, 'Log');
  }
  const sectionContent = body.slice(sec.headerEnd, sec.end);
  // Strip trailing whitespace, add newline, then our entry, then a trailing blank.
  const trimmed = sectionContent.replace(/\s+$/, '');
  const newLine = `- ${date}: ${message}`;
  const updated = `${trimmed}\n${newLine}\n\n`;
  return body.slice(0, sec.headerEnd) + '\n\n' + updated.replace(/^\n+/, '') + body.slice(sec.end);
}

// Strips italic placeholder text from a Debt section (lines starting with `_`).
function stripDebtPlaceholder(content) {
  return content
    .split('\n')
    .filter((line) => !/^\s*_.*_\s*$/.test(line))
    .join('\n');
}

export function addDebtItem(body, text) {
  let sec = findDebtSection(body);
  if (!sec) {
    body = setSection(body, 'Debt', '');
    sec = findSection(body, 'Debt');
  }
  let content = body.slice(sec.headerEnd, sec.end);
  content = stripDebtPlaceholder(content).replace(/\s+$/, '');
  const updated = `${content}\n- [ ] ${text}\n\n`;
  return body.slice(0, sec.headerEnd) + '\n\n' + updated.replace(/^\n+/, '') + body.slice(sec.end);
}

export function closeDebtItem(body, pattern, ref, date) {
  const sec = findDebtSection(body);
  if (!sec) throw new Error('## Debt section not found.');
  const content = body.slice(sec.headerEnd, sec.end);
  const lines = content.split('\n');
  let closed = false;
  const matcher = pattern.toLowerCase();
  const updated = lines.map((line) => {
    if (closed) return line;
    const m = line.match(/^(\s*)- \[ \] (.+)$/);
    if (!m) return line;
    if (!m[2].toLowerCase().includes(matcher)) return line;
    closed = true;
    const tail = ref ? ` — закрыто ${date}: ${ref}` : ` — закрыто ${date}`;
    // If the existing item already has " — ..." context, keep it but mark closed.
    return `${m[1]}- [x] ${m[2]}${tail}`;
  });
  if (!closed) {
    throw new Error(`No open debt matching "${pattern}" found.`);
  }
  return body.slice(0, sec.headerEnd) + updated.join('\n') + body.slice(sec.end);
}

// Rewrites one open debt in place: the work is still open, but its wording has
// drifted from the code (dead symbol, wrong key, a claim that is no longer true).
//
// A debt item is its `- [ ] …` line PLUS everything indented deeper under it
// until a blank line or a NESTED CHECKBOX. Prose wrapped as `  + …` or `  1. …`
// is part of the item — stopping at any list-looking line left the old claims
// hanging under the new wording. A nested `- [ ]` is its own debt and stays.
// This is the same notion of "continuation" as tools/debts/parse-debts.mjs.
//
// Matching mirrors closeDebtItem (first line, case-insensitive) but is stricter:
// more than one match is an error. Closing the wrong item at least leaves a
// visible `[x]`; rewriting it erases the original wording of someone's work.
//
// Leading machine markers (`[LEGACY-AHEAD …]`, `[DIVERGENCE …]`) must survive:
// reports count open items by grepping for them, and a rewrite that drops one
// silently removes the item from those counts. Returns the removed text too, so
// the caller can show what was replaced.
export function rewriteDebtItem(body, pattern, newText, date) {
  const sec = findDebtSection(body);
  if (!sec) throw new Error('## Debt section not found.');
  const lines = body.slice(sec.headerEnd, sec.end).split('\n');
  const matcher = pattern.toLowerCase();
  const hits = [];
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(\s*)- \[ \] (.+)$/);
    if (!m || !m[2].toLowerCase().includes(matcher)) continue;
    const depth = m[1].length;
    let end = i + 1;
    while (end < lines.length) {
      const line = lines[end];
      if (line.trim() === '') break;
      if (line.match(/^\s*/)[0].length <= depth) break;
      if (/^\s*[-*+]\s+\[[ xX]\]/.test(line)) break;
      end += 1;
    }
    hits.push({ start: i, end, indent: m[1], first: m[2] });
  }
  if (hits.length === 0) throw new Error(`No open debt matching "${pattern}" found.`);
  if (hits.length > 1) {
    const found = hits.map((h) => `  ${lines[h.start].trim().slice(0, 120)}`).join('\n');
    throw new Error(`"${pattern}" matches ${hits.length} open debts, nothing rewritten. Narrow the pattern:\n${found}`);
  }
  const [hit] = hits;
  const lead = hit.first.match(/^(?:\[[A-Z][A-Z-]*(?:\s[^\]]*)?\]\s*)+/);
  const markers = lead ? lead[0].match(/\[[A-Z][A-Z-]*(?:\s[^\]]*)?\]/g) : [];
  const text = newText.replace(/(?:\s+—\s+переформулировано \d{4}-\d{2}-\d{2})+\s*$/, '').trim();
  const lost = markers.filter((mk) => !text.includes(mk));
  if (lost.length) {
    throw new Error(`New wording drops the marker(s) ${lost.join(' ')} — keep them in --to, nothing rewritten.`);
  }
  const removed = lines.slice(hit.start, hit.end).join('\n');
  lines.splice(hit.start, hit.end - hit.start, `${hit.indent}- [ ] ${text} — переформулировано ${date}`);
  return { body: body.slice(0, sec.headerEnd) + lines.join('\n') + body.slice(sec.end), removed };
}

export function countOpenDebts(raw) {
  const { body } = splitFrontmatter(raw);
  const m = body.match(/^\s*-\s*\[ \]\s+/gm);
  return m ? m.length : 0;
}

// ──────────────────────────────────────────────────────────────────────────
// CLI arg parsing (minimal, zero-dep)
// ──────────────────────────────────────────────────────────────────────────

// Parses `--key value` and `--flag` from argv array. Positional args become positional[].
export function parseArgs(argv, { booleans = [] } = {}) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      // `--key=value` — the only form that survives a value starting with `--`
      // (e.g. --log="--fix applied"), which the space form reads as a flag.
      const eq = a.indexOf('=');
      if (eq > 2) {
        flags[a.slice(2, eq)] = a.slice(eq + 1);
        continue;
      }
      const key = a.slice(2);
      if (booleans.includes(key)) {
        flags[key] = true;
      } else {
        const next = argv[i + 1];
        if (next === undefined || next.startsWith('--')) {
          flags[key] = true;
        } else {
          flags[key] = next;
          i++;
        }
      }
    } else {
      positional.push(a);
    }
  }
  return { positional, flags };
}

// Reads a flag that must carry text. parseArgs() yields boolean `true` when the
// value was missing or looked like another flag — silently writing "true" into
// a Log entry is worse than failing loudly.
export function strFlag(flags, key, { required = false } = {}) {
  const v = flags[key];
  if (v === undefined) {
    if (required) throw new Error(`--${key} is required`);
    return null;
  }
  if (v === true || v === '') {
    throw new Error(
      `--${key} needs a value. A value starting with "--" must use the = form: --${key}="--like-this"`,
    );
  }
  return String(v);
}

// ──────────────────────────────────────────────────────────────────────────
// List task files
// ──────────────────────────────────────────────────────────────────────────

export async function listTaskFiles(tasksDir) {
  let files;
  try {
    files = await readdir(tasksDir);
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  return files
    .filter((f) => f.endsWith('.md') && f !== 'index.md' && !f.startsWith('_'))
    .map((f) => join(tasksDir, f));
}

export async function loadAllTasks(tasksDir) {
  const files = await listTaskFiles(tasksDir);
  const tasks = [];
  for (const file of files) {
    try {
      const raw = await readFile(file, 'utf8');
      const fm = parseFrontmatter(raw);
      if (!fm || !fm.id) continue;
      // mtime, not just `updated:` — the date field is day-granular, so every
      // task touched today ties and "most recent" would fall back to readdir
      // order. Hooks pick a task by this; picking the wrong one rewrites
      // another session's Handoff.
      const mtime = await stat(file)
        .then((s) => s.mtimeMs)
        .catch(() => 0);
      tasks.push({ file, raw, fm, mtime, debts: countOpenDebts(raw) });
    } catch {
      // skip unreadable
    }
  }
  return tasks;
}

// ──────────────────────────────────────────────────────────────────────────
// Generic section read/write (Progress / Verification / Handoff)
// ──────────────────────────────────────────────────────────────────────────

// Canonical section order in the task template. Used when a section is missing
// from an older task file and has to be inserted in the right place.
export const SECTION_ORDER = [
  'Context',
  'Progress',
  'Log',
  'Decisions',
  'Debt',
  'Verification',
  'Handoff',
  'Blockers',
];

export function getSectionContent(body, title) {
  const sec = findSection(body, title);
  if (!sec) return null;
  return body.slice(sec.headerEnd, sec.end);
}

// Replaces the whole content of `## <title>`. Creates the section (in
// SECTION_ORDER position) when it does not exist yet — task files created
// before a section was introduced still work.
export function setSection(body, title, content) {
  const inner = String(content).replace(/^\n+|\s+$/g, '');
  const normalized = inner ? `\n\n${inner}\n\n` : '\n\n';
  const sec = findSection(body, title);
  if (sec) {
    return body.slice(0, sec.headerEnd) + normalized + body.slice(sec.end);
  }
  const block = `## ${title}\n${normalized.replace(/^\n+/, '\n')}`;
  const idx = SECTION_ORDER.indexOf(title);
  if (idx >= 0) {
    for (const later of SECTION_ORDER.slice(idx + 1)) {
      const laterSec = later === 'Debt' ? findDebtSection(body) : findSection(body, later);
      if (laterSec) {
        return body.slice(0, laterSec.start) + block + body.slice(laterSec.start);
      }
    }
  }
  return `${body.replace(/\s+$/, '')}\n\n${block}`;
}

// ──────────────────────────────────────────────────────────────────────────
// Progress steps
// ──────────────────────────────────────────────────────────────────────────

// Step lines are NUMBERED with a glyph — deliberately not `- [ ]` checkboxes:
// debt reports and countOpenDebts() count every `- [ ]` in the body, so
// checkbox steps would be counted as technical debt.
export const STEP_STATUS = {
  done: '✅',
  current: '▶',
  todo: '⬜',
  blocked: '⛔',
};
const GLYPH_TO_STATUS = Object.fromEntries(
  Object.entries(STEP_STATUS).map(([k, v]) => [v, k]),
);
const STEP_RE = /^\s*(\d+)\.\s+(✅|▶|⬜|⛔)\s+(.*)$/;

export function parseSteps(body) {
  const content = getSectionContent(body, 'Progress');
  if (!content) return [];
  const steps = [];
  for (const line of content.split('\n')) {
    const m = line.match(STEP_RE);
    if (!m) continue;
    steps.push({ n: Number(m[1]), status: GLYPH_TO_STATUS[m[2]], text: m[3].trim() });
  }
  return steps;
}

export function renderSteps(steps) {
  if (!steps.length) return '_Шаги не заданы. `rtp steps <id> --set "…"` или `--from-plan <файл>`._';
  return steps
    .map((s, i) => `${i + 1}. ${STEP_STATUS[s.status] || STEP_STATUS.todo} ${s.text}`)
    .join('\n');
}

export function writeSteps(body, steps) {
  return setSection(body, 'Progress', renderSteps(steps));
}

export function stepStats(steps) {
  const total = steps.length;
  const done = steps.filter((s) => s.status === 'done').length;
  const blocked = steps.filter((s) => s.status === 'blocked').length;
  // Position, not the number parsed from the file: renderSteps() renumbers by
  // index, so a hand-edited gap would otherwise put step_current out of range.
  const idx = steps.findIndex((s) => s.status === 'current');
  return { total, done, blocked, current: idx >= 0 ? idx + 1 : null };
}

export function progressBar(done, total) {
  const t = Number(total) || 0;
  if (!t) return '';
  const width = Math.min(Math.max(t, 1), 12);
  const d = Math.max(0, Math.min(Number(done) || 0, t));
  const filled = Math.round((d / t) * width);
  return '▰'.repeat(filled) + '▱'.repeat(width - filled);
}

// Extracts step titles from a plan file: `## Фаза 2 — …`, `### Step 3: …`,
// `## Этап 1.`, or plain `## 4) …`.
export function extractPlanSteps(planText) {
  const out = [];
  const re = /^#{2,4}\s+(?:(?:Фаза|Фазa|Phase|Шаг|Step|Этап|Stage)\s*)?(\d+)(?:[.)\-–:]|\s)\s*(.*)$/gim;
  let m;
  while ((m = re.exec(planText)) !== null) {
    const title = (m[2] || '').trim().replace(/^[—–\-:]\s*/, '');
    out.push(title ? `${title}` : `Шаг ${m[1]}`);
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────────
// git (best-effort; never throws)
// ──────────────────────────────────────────────────────────────────────────

export function run(cmd, args, cwd, timeoutMs = 15000) {
  return new Promise((resolveP) => {
    execFile(cmd, args, { cwd, timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
      // A process killed by timeout or by the stdout cap also arrives here with
      // a non-numeric err.code. Reporting that as a plain "exit 1" would record
      // a green run as red — say which infra failure it was instead.
      let infra = null;
      if (err && typeof err.code !== 'number') {
        if (err.killed && err.signal) infra = `убит по сигналу ${err.signal} (таймаут ${Math.round(timeoutMs / 1000)}с)`;
        else if (String(err.code || '').includes('MAXBUFFER')) infra = 'вывод превысил лимит 8 МБ, процесс убит';
        else infra = String(err.code || err.message || 'неизвестный сбой запуска');
      }
      resolveP({
        code: err ? (typeof err.code === 'number' ? err.code : 1) : 0,
        infra,
        stdout: String(stdout || ''),
        stderr: String(stderr || ''),
      });
    });
  });
}

export async function git(args, cwd) {
  const { code, stdout } = await run('git', args, cwd);
  return code === 0 ? stdout.trim() : '';
}

// Project root for a task file: <root>/docs/tasks/<id>.md → <root>
export function projectRootOf(taskFile) {
  return resolve(dirname(taskFile), '..', '..');
}

// ──────────────────────────────────────────────────────────────────────────
// Project config: <tasksDir>/.rtp.json — optional, every field optional.
// Never throws: a broken config must not take down hooks or `rtp status`.
// ──────────────────────────────────────────────────────────────────────────

export const EMPTY_CONFIG = Object.freeze({ baseBranch: undefined, verify: [], reviewers: [] });

const defaultWarn = (m) => process.stderr.write(`${m}\n`);

// A newline would split the printed hint across lines (and `rtp next` indents
// continuation lines, corrupting the quoted value) — reject it.
const oneLine = (s) => typeof s === 'string' && s.trim() !== '' && !/[\r\n]/.test(s);

// `badTimeout` is told about a timeout that is not a positive integer: the command
// itself is kept (with the default timeout) — dropping it would hide a check.
function normalizeVerifyEntry(v, badTimeout = () => {}) {
  if (typeof v === 'string') return oneLine(v) ? { run: v.trim() } : null;
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  if ((v.run !== undefined && !oneLine(v.run)) || (v.record !== undefined && !oneLine(v.record))) return null;
  // `only` scopes an entry to local or cloud (CLAUDE_CODE_REMOTE=true) sessions.
  if (v.only !== undefined && v.only !== 'local' && v.only !== 'cloud') return null;
  const scope = v.only ? { only: v.only } : {};
  if (typeof v.run === 'string' && v.run.trim() && v.record === undefined) {
    if (v.timeout === undefined) return { run: v.run.trim(), ...scope };
    if (Number.isInteger(v.timeout) && v.timeout > 0) return { run: v.run.trim(), timeout: v.timeout, ...scope };
    badTimeout();
    return { run: v.run.trim(), ...scope };
  }
  if (typeof v.record === 'string' && v.record.trim() && v.run === undefined) return { record: v.record.trim(), ...scope };
  return null;
}

// Verify entries that apply to this session: `only: local` is hidden in cloud
// sessions (no toolchain there), `only: cloud` — locally.
export function verifyForEnv(cfg, env = process.env) {
  const here = env.CLAUDE_CODE_REMOTE === 'true' ? 'cloud' : 'local';
  return cfg.verify.filter((v) => !v.only || v.only === here);
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
    raw = JSON.parse(text.replace(/^﻿/, '')); // editors on Windows save a BOM
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
      const n = normalizeVerifyEntry(v, () =>
        warn(`rtp: ${path}: verify[${i}].timeout не положительное целое — команда оставлена с timeout по умолчанию`));
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

// `--flag 'value'` for a printed hint; a value starting with `-` uses the `=` form,
// which parseArgs() reads as a value instead of the next flag.
export function shFlag(flag, value) {
  return String(value).startsWith('-') ? `--${flag}=${shQuote(value)}` : `--${flag} ${shQuote(value)}`;
}

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

// Handoff notes are the only hand-written part of a regenerated ## Handoff —
// they live between these markers so regeneration can carry them forward.
export const NOTES_OPEN = '<!-- handoff-notes -->';
export const NOTES_CLOSE = '<!-- /handoff-notes -->';

export function extractHandoffNotes(body) {
  const content = getSectionContent(body, 'Handoff') || '';
  const m = content.match(new RegExp(`${NOTES_OPEN}([\\s\\S]*?)${NOTES_CLOSE}`));
  if (!m) return [];
  return m[1]
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => /^- /.test(l))
    .map((l) => l.replace(/^- /, ''));
}

export function lastLogEntries(body, n = 5) {
  const content = getSectionContent(body, 'Log');
  if (!content) return [];
  const lines = content.split('\n').filter((l) => /^- /.test(l));
  return lines.slice(-n).map((l) => l.replace(/^- /, ''));
}

export function openDebtLines(body) {
  const content = getDebtSectionContent(body);
  if (!content) return [];
  return content
    .split('\n')
    .filter((l) => /^\s*-\s*\[ \]\s+/.test(l))
    .map((l) => l.replace(/^\s*-\s*\[ \]\s+/, ''));
}

export function blockerLines(body) {
  const content = getSectionContent(body, 'Blockers');
  if (!content) return [];
  return content
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => /^- /.test(l))
    .map((l) => l.replace(/^- /, ''));
}
