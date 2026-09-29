#!/usr/bin/env node
// rtp — run-task-pipeline CLI.
// Subcommands: new, phase, debt, list, find, resume, validate, index,
//              show, hook-postedit, help.
//
// Zero dependencies. Usage:
//   node ~/.claude/skills/run-task-pipeline/scripts/rtp.mjs <subcommand> [args]

import { readFile, stat, open } from 'node:fs/promises';
import { dirname, join, relative, resolve, basename } from 'node:path';
import {
  SKILL_DIR,
  TEMPLATE_PATH,
  VALID_TYPES,
  VALID_PIPELINES,
  VALID_PHASES,
  today,
  slugify,
  findTasksDir,
  findTasksDirStrict,
  ensureDir,
  exists,
  resolveTaskFile,
  parseFrontmatter,
  splitFrontmatter,
  replaceFrontmatterField,
  readTask,
  writeTaskRaw,
  appendLog,
  addDebtItem,
  closeDebtItem,
  rewriteDebtItem,
  getDebtSectionContent,
  countOpenDebts,
  parseArgs,
  loadAllTasks,
  listTaskFiles,
  getSectionContent,
  setSection,
  parseSteps,
  renderSteps,
  writeSteps,
  stepStats,
  progressBar,
  extractPlanSteps,
  STEP_STATUS,
  run,
  gitContext,
  loadProjectConfig,
  shQuote,
  EMPTY_CONFIG,
  projectRootOf,
  lastLogEntries,
  openDebtLines,
  blockerLines,
  extractHandoffNotes,
  replaceNestedFrontmatterField,
  parseYamlScalar,
  strFlag,
  NOTES_OPEN,
  NOTES_CLOSE,
} from './lib.mjs';
import { writeFile } from 'node:fs/promises';
import { buildIndex } from './build-index.mjs';

const SUBCOMMANDS = {
  new: cmdNew,
  phase: cmdPhase,
  debt: cmdDebt,
  list: cmdList,
  find: cmdFind,
  resume: cmdResume,
  validate: cmdValidate,
  index: cmdIndex,
  show: cmdShow,
  artifact: cmdArtifact,
  steps: cmdSteps,
  step: cmdStep,
  status: cmdStatus,
  handoff: cmdHandoff,
  verify: cmdVerify,
  next: cmdNext,
  sweep: cmdSweep,
  'hook-postedit': cmdHookPostEdit,
  'hook-sessionstart': cmdHookSessionStart,
  'hook-precompact': cmdHookPreCompact,
  'hook-stop': cmdHookStop,
  help: cmdHelp,
  '--help': cmdHelp,
  '-h': cmdHelp,
};

// Dispatch lives at the BOTTOM of this file, not here: function declarations
// hoist but `const` does not, so running the handler before the module's
// constants are initialized threw "Cannot access X before initialization" —
// and only for the one subcommand that touched such a constant.

// ──────────────────────────────────────────────────────────────────────────
// rtp help
// ──────────────────────────────────────────────────────────────────────────

async function cmdHelp() {
  console.log(`rtp — run-task-pipeline CLI

USAGE
  rtp <subcommand> [args]

SUBCOMMANDS
  new        Create a new task file from template
  phase      Update task phase + append Log entry
  artifact   Link spec/plan/branch/PR, escalate pipeline (instead of hand-editing YAML)
  steps      Seed / replace the plan-step checklist (## Progress)
  step       Mark a plan step done / current / blocked
  status     Print the paste-ready Status Block (progress bar + next action)
  handoff    Regenerate ## Handoff and print a paste-ready handoff block
  verify     Run a verification command and record the evidence
  next       Print the next concrete action for the current phase
  sweep      List stale tasks (stuck in review/impl)
  debt       Add or close a debt item
  list       List tasks (active/blocked/done)
  find       Search tasks by id/title/slug substring
  resume     Print resume-ready announcement for matching task
  validate   Validate task file (frontmatter, artifacts, debt format)
  show       Print task frontmatter + recent log
  index      Regenerate docs/tasks/index.md
  help       Show this help

COMMON OPTIONS
  --tasks-dir <path>   Override docs/tasks location (default: auto-detect from CWD)

EXAMPLES
  rtp new --title "Fix login redirect" --type bug --pipeline minimal \\
          --reason "single-file fix"
  rtp phase 2026-01-10-fix-login-redirect --to impl --log "plan approved"
  rtp debt 2026-01-10-fix-login-redirect --add "extract redirect helper — duplicated in two routes"
  rtp debt 2026-01-10-fix-login-redirect --close "extract redirect helper" --ref 2026-01-12-redirect-refactor
  rtp list --active
  rtp resume "login redirect"
  rtp steps 2026-01-10-fix-login-redirect --from-plan docs/plans/login-redirect-plan.md
  rtp step 2026-01-10-fix-login-redirect --done 2 --note "тесты зелёные"
  rtp status 2026-01-10-fix-login-redirect
  rtp verify 2026-01-10-fix-login-redirect --run "make test"
  rtp handoff 2026-01-10-fix-login-redirect --write "редирект воспроизводится только с просроченной сессией"
  rtp validate 2026-01-10-fix-login-redirect
  rtp index

Run 'rtp <subcommand> --help' for subcommand-specific options.
`);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp new
// ──────────────────────────────────────────────────────────────────────────

async function cmdNew(args) {
  const { flags } = parseArgs(args, { booleans: ['help', 'force'] });
  if (flags.help) {
    console.log(`rtp new — create a new task file.

OPTIONS
  --title <text>         Task title (required)
  --type <T>             feature | bug | refactor | chore (required)
  --pipeline <P>         full | no-spec | minimal (required)
  --reason <text>        Triage reason (printed in first Log entry; defaults to pipeline)
  --slug <slug>          Custom slug (default: auto from title)
  --date <YYYY-MM-DD>    Override creation date (default: today)
  --tasks-dir <path>     Override docs/tasks location
  --force                Overwrite if file exists

OUTPUT
  Prints the absolute path of the created task file.
`);
    return;
  }

  const title = required(flags, 'title');
  const type = required(flags, 'type');
  const pipeline = required(flags, 'pipeline');
  if (!VALID_TYPES.includes(type)) {
    throw new Error(`type must be one of: ${VALID_TYPES.join(', ')}`);
  }
  if (!VALID_PIPELINES.includes(pipeline)) {
    throw new Error(`pipeline must be one of: ${VALID_PIPELINES.join(', ')}`);
  }

  const date = flags.date || today();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error('date must be YYYY-MM-DD');
  }

  const slug = flags.slug ? slugify(flags.slug) : slugify(title);
  if (!slug) throw new Error('Could not derive slug from title; pass --slug explicitly.');
  const id = `${date}-${slug}`;
  const reason = flags.reason || `pipeline ${pipeline}`;

  const tasksDir = await resolveTasksDir(flags);
  await ensureDir(tasksDir);
  const file = join(tasksDir, `${id}.md`);

  if ((await exists(file)) && !flags.force) {
    throw new Error(`Already exists: ${file} (use --force to overwrite)`);
  }

  const template = await readFile(TEMPLATE_PATH, 'utf8');
  // Function replacements: a title or reason containing `$&` / `$'` / `$$`
  // would otherwise be expanded as a substitution pattern.
  const filled = template
    .replaceAll('{{id}}', () => id)
    .replaceAll('{{title}}', () => escapeYaml(title))
    .replaceAll('{{type}}', () => type)
    .replaceAll('{{pipeline}}', () => pipeline)
    .replaceAll('{{date}}', () => date)
    .replaceAll('{{triage_reason}}', () => reason);

  await writeFile(file, filled);
  await buildIndex(tasksDir);

  console.log(file);
  console.error(
    `created task ${id} (pipeline=${pipeline}, type=${type})\n` +
      `next: invoke superpowers:brainstorming, then 'rtp phase ${id} --to ${nextPhaseAfter('triage', pipeline)} --log "<what>"'`,
  );
}

function nextPhaseAfter(phase, pipeline) {
  // Suggestion only; not enforced.
  const flow = {
    full: ['triage', 'spec', 'spec-review', 'plan', 'plan-review', 'impl', 'review', 'done'],
    'no-spec': ['triage', 'plan', 'plan-review', 'impl', 'review', 'done'],
    minimal: ['triage', 'impl', 'review', 'done'],
  };
  const seq = flow[pipeline] || flow['no-spec'];
  const i = seq.indexOf(phase);
  return i >= 0 && i < seq.length - 1 ? seq[i + 1] : 'impl';
}

// ──────────────────────────────────────────────────────────────────────────
// rtp phase
// ──────────────────────────────────────────────────────────────────────────

async function cmdPhase(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp phase — update task phase + append Log entry.

USAGE
  rtp phase <id-or-path> --to <phase> [--log <message>] [--date <YYYY-MM-DD>]

OPTIONS
  --to <phase>           New phase: ${VALID_PHASES.join(' | ')}
  --log <message>        Log entry (optional but recommended)
  --date <YYYY-MM-DD>    Override date (default: today)
  --blocked-by <ref>     Set blocked_by frontmatter field (only with --to blocked)
  --tasks-dir <path>     Override docs/tasks location
`);
    return;
  }

  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.\nUsage: rtp phase <id> --to <phase>');
  const toPhase = required(flags, 'to');
  if (!VALID_PHASES.includes(toPhase)) {
    throw new Error(`--to must be one of: ${VALID_PHASES.join(', ')}`);
  }
  const date = flags.date || today();

  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw, fm } = await readTask(file);

  const fromPhase = fm.phase || 'unknown';
  raw = replaceFrontmatterField(raw, 'phase', toPhase);
  raw = replaceFrontmatterField(raw, 'updated', date);
  if (toPhase === 'blocked' && flags['blocked-by']) {
    raw = replaceFrontmatterField(raw, 'blocked_by', flags['blocked-by']);
  } else if (toPhase !== 'blocked' && fm.blocked_by) {
    raw = replaceFrontmatterField(raw, 'blocked_by', null);
  }

  const { header, body } = splitFrontmatter(raw);
  const logMsg = flags.log !== undefined ? strFlag(flags, 'log') : `phase ${fromPhase} → ${toPhase}`;
  const newBody = appendLog(body, date, logMsg);
  await writeTaskRaw(file, header + newBody);
  await buildIndex(tasksDir);

  console.log(`${basename(file)}: phase ${fromPhase} → ${toPhase}`);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp debt
// ──────────────────────────────────────────────────────────────────────────

async function cmdDebt(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'list'] });
  if (flags.help) {
    console.log(`rtp debt — add, close, rewrite or list debt items in a task file.

USAGE
  rtp debt <id-or-path> --add "<what — why>"
  rtp debt <id-or-path> --close "<substring>" [--ref <id-or-url>]
  rtp debt <id-or-path> --rewrite "<substring>" --to "<new text>"
  rtp debt <id-or-path> --list

OPTIONS
  --add <text>           Append new open item: '- [ ] <text>'
  --close <pattern>      Close first matching open item (substring, case-insensitive)
  --ref <ref>            Reference for closed item (task id or URL)
  --rewrite <pattern>    Replace the wording of the ONE open item matching <pattern>
                         (with its indented continuation lines). The work stays open;
                         the item gets ' — переформулировано <date>'. Several matches
                         are an error — nothing is written.
  --to <text>            New wording for --rewrite: one line, without '- [ ]'
  --list                 Print open and closed items of ## Debt
                         (also '## Debt <tail>', e.g. '## Debt (накапливается…)')
  --date <YYYY-MM-DD>    Override date (default: today)
  --tasks-dir <path>     Override docs/tasks location
`);
    return;
  }
  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required. To see items: rtp debt <id> --list');

  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw } = await readTask(file);
  const { header, body } = splitFrontmatter(raw);
  const date = flags.date || today();

  // The if-chain below takes the first mode it sees — two modes at once used to
  // silently drop the second one, and a flag of another mode (`--close X --to Y`,
  // a typo for --rewrite) closed the item without a word.
  const modes = ['list', 'add', 'close', 'rewrite'].filter((k) => flags[k] !== undefined);
  if (modes.length > 1) {
    throw new Error(`Use one of --list, --add, --close, --rewrite at a time (got: ${modes.map((k) => `--${k}`).join(', ')}).`);
  }
  if (flags.to !== undefined && flags.rewrite === undefined) throw new Error('--to works only with --rewrite.');
  if (flags.ref !== undefined && flags.close === undefined) throw new Error('--ref works only with --close.');

  if (flags.list) {
    const items = (getDebtSectionContent(body) || '')
      .split('\n')
      .filter((l) => /^\s*-\s*\[[ x]\]/.test(l));
    console.log(items.length ? items.join('\n') : '(долгов нет)');
    return;
  }

  let newBody;
  let summary;
  if (flags.add !== undefined) {
    const text = strFlag(flags, 'add');
    newBody = addDebtItem(body, text);
    summary = `+ debt: ${text}`;
  } else if (flags.close !== undefined) {
    const pattern = strFlag(flags, 'close');
    const ref = flags.ref !== undefined ? strFlag(flags, 'ref') : null;
    newBody = closeDebtItem(body, pattern, ref, date);
    summary = `x debt: ${pattern}${ref ? ` (ref: ${ref})` : ''}`;
  } else if (flags.rewrite !== undefined) {
    const pattern = strFlag(flags, 'rewrite');
    const text = strFlag(flags, 'to', { required: true });
    // A newline would split the item into a debt plus a stray paragraph; a leading
    // checkbox would produce `- [ ] - [ ] …`; blank text erases the wording.
    if (/[\r\n]/.test(text)) throw new Error('--to must be a single line.');
    if (!text.trim()) throw new Error('--to is empty.');
    if (/^\s*(?:[-*+]\s*)?\[[ xX]?\]/.test(text)) throw new Error("--to is the wording only — drop the leading '- [ ]'.");
    const rewritten = rewriteDebtItem(body, pattern, text, date);
    newBody = rewritten.body;
    summary = `~ debt: ${pattern} → ${text}\n  was:\n${rewritten.removed.split('\n').map((l) => `    ${l}`).join('\n')}`;
  } else {
    throw new Error('Specify --add, --close, --rewrite or --list.');
  }

  // Also bump `updated` so index reflects activity.
  raw = header + newBody;
  raw = replaceFrontmatterField(raw, 'updated', date);

  await writeTaskRaw(file, raw);
  await buildIndex(tasksDir);
  console.log(`${basename(file)}: ${summary}`);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp list
// ──────────────────────────────────────────────────────────────────────────

async function cmdList(args) {
  const { flags } = parseArgs(args, {
    booleans: ['help', 'active', 'blocked', 'done', 'all', 'json'],
  });
  if (flags.help) {
    console.log(`rtp list — list tasks in docs/tasks.

OPTIONS
  --active              Phase ≠ done/blocked (default)
  --blocked             Phase = blocked
  --done                Phase = done
  --all                 All tasks
  --search <pattern>    Filter by id/title substring (case-insensitive)
  --json                Output as JSON
  --tasks-dir <path>    Override docs/tasks location
`);
    return;
  }

  const tasksDir = await resolveTasksDir(flags);
  const tasks = await loadAllTasks(tasksDir);

  let filtered = tasks;
  const filterPhase = flags.blocked
    ? 'blocked'
    : flags.done
      ? 'done'
      : flags.all
        ? null
        : 'active';
  if (filterPhase === 'active') {
    filtered = filtered.filter((t) => !['done', 'blocked'].includes(t.fm.phase));
  } else if (filterPhase === 'blocked') {
    filtered = filtered.filter((t) => t.fm.phase === 'blocked');
  } else if (filterPhase === 'done') {
    filtered = filtered.filter((t) => t.fm.phase === 'done');
  }
  if (flags.search) {
    const needle = String(flags.search).toLowerCase();
    filtered = filtered.filter(
      (t) =>
        (t.fm.id || '').toLowerCase().includes(needle) ||
        (t.fm.title || '').toLowerCase().includes(needle),
    );
  }
  filtered.sort((a, b) => (b.fm.updated || '').localeCompare(a.fm.updated || ''));

  if (flags.json) {
    console.log(
      JSON.stringify(
        filtered.map((t) => ({ ...t.fm, debts: t.debts, file: t.file })),
        null,
        2,
      ),
    );
    return;
  }

  if (!filtered.length) {
    console.log('(no tasks)');
    return;
  }
  const cols = [
    ['ID', 28],
    ['Phase', 12],
    ['Pipeline', 10],
    ['Type', 9],
    ['Updated', 11],
    ['Debt', 5],
    ['Title', 0],
  ];
  console.log(formatRow(cols.map(([h]) => h), cols));
  console.log(formatRow(cols.map(([h]) => '-'.repeat(Math.max(3, h.length))), cols));
  for (const t of filtered) {
    console.log(
      formatRow(
        [
          t.fm.id || '',
          t.fm.phase || '',
          t.fm.pipeline || '',
          t.fm.type || '',
          t.fm.updated || '',
          t.debts > 0 ? String(t.debts) : '',
          t.fm.title || '',
        ],
        cols,
      ),
    );
  }
}

function formatRow(cells, cols) {
  return cells
    .map((cell, i) => {
      const [, width] = cols[i];
      if (width === 0) return cell;
      return String(cell).padEnd(width).slice(0, width);
    })
    .join('  ');
}

// ──────────────────────────────────────────────────────────────────────────
// rtp find / resume
// ──────────────────────────────────────────────────────────────────────────

async function cmdFind(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp find <pattern> — search tasks by id/title substring (case-insensitive).`);
    return;
  }
  const pattern = positional[0];
  if (!pattern) throw new Error('Pattern required.');
  const tasksDir = await resolveTasksDir(flags);
  const tasks = await loadAllTasks(tasksDir);
  const needle = pattern.toLowerCase();
  const matches = tasks.filter(
    (t) =>
      (t.fm.id || '').toLowerCase().includes(needle) ||
      (t.fm.title || '').toLowerCase().includes(needle),
  );
  if (!matches.length) {
    console.log('(no matches)');
    return;
  }
  for (const t of matches) {
    console.log(`${t.fm.id}\t${t.fm.phase}\t${t.fm.title}`);
  }
}

async function cmdResume(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp resume [<pattern>] — print resume-ready announcement.

Prints the most recently updated active task matching <pattern>, with its
last Log entry, ready to paste into a session start.
If no pattern given, returns the most recently updated active task.
`);
    return;
  }
  const tasksDir = await resolveTasksDir(flags);
  const tasks = await loadAllTasks(tasksDir);
  const pattern = positional[0];
  const needle = pattern ? pattern.toLowerCase() : null;
  const matches = (t) =>
    !needle ||
    (t.fm.id || '').toLowerCase().includes(needle) ||
    (t.fm.title || '').toLowerCase().includes(needle);
  const byUpdated = (a, b) =>
    (b.fm.updated || '').localeCompare(a.fm.updated || '') || (b.mtime || 0) - (a.mtime || 0);
  const live = tasks.filter((t) => t.fm.phase !== 'done' && matches(t)).sort(byUpdated);
  const t = live[0];
  if (!t) {
    // "(no resumable task)" for a pattern that DID match — only closed tasks —
    // reads as a typo. Say what matched and where to look instead.
    const closed = tasks.filter((c) => c.fm.phase === 'done' && matches(c)).sort(byUpdated);
    if (closed.length) {
      const scope = pattern ? `по «${pattern}»` : 'в этом каталоге';
      console.log(`Активных задач ${scope} нет; совпало только с закрытыми (${closed.length}):`);
      for (const c of closed.slice(0, 5)) {
        console.log(`  ${c.fm.id}\tdone\t${c.fm.updated || ''}\t${c.fm.title || ''}`);
      }
      if (closed.length > 5) console.log(`  … ещё ${closed.length - 5}`);
      console.log(`Посмотреть: rtp show ${closed[0].fm.id}   Новая работа: rtp new`);
      return;
    }
    console.log('(no resumable task)');
    return;
  }
  if (!pattern) {
    // The primary source of foreign ids: an agent reads this and then "names"
    // the task itself, which every hook invariant then honours.
    console.error(
      'rtp resume: без паттерна выбрана последняя активная задача В ЭТОМ каталоге — ' +
        'она может принадлежать соседней сессии (worktree), сверься.',
    );
  }
  const lastLog = extractLastLog(t.raw);
  console.log(
    `Resuming \`${t.fm.id}\` from phase \`${t.fm.phase}\`. ` +
      `Last log: ${lastLog || '(no log entry)'}`,
  );
  console.log(`File: ${t.file}`);
}

function extractLastLog(raw) {
  const { body } = splitFrontmatter(raw);
  const entries = lastLogEntries(body, 1);
  return entries.length ? entries[0] : null;
}

// ──────────────────────────────────────────────────────────────────────────
// rtp validate
// ──────────────────────────────────────────────────────────────────────────

async function cmdValidate(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'all'] });
  if (flags.help) {
    console.log(`rtp validate [<id-or-path>] — sanity-check a task file.

USAGE
  rtp validate <id>        one task
  rtp validate             the most recently updated active task in this directory
  rtp validate --all       every task file; exit 1 if any has errors

Checks:
  - frontmatter has id, title, type, pipeline, phase, created, updated
  - phase ∈ ${VALID_PHASES.join('|')}
  - type ∈ ${VALID_TYPES.join('|')}
  - pipeline ∈ ${VALID_PIPELINES.join('|')}
  - artifacts.spec/plan paths exist (if non-null)
  - ## Log has ≥1 entry
  - debt section: no plain '- text' without checkbox (would be invisible to the index and debt reports)
`);
    return;
  }
  const tasksDir = await resolveTasksDir(flags);

  if (flags.all) {
    // listTaskFiles, not loadAllTasks: the latter skips files without an `id`,
    // i.e. exactly the broken frontmatter this check exists to find.
    const files = await listTaskFiles(tasksDir);
    let bad = 0;
    let warned = 0;
    for (const file of files) {
      const { errors, warnings } = await validateTaskFile(file).catch((err) => ({
        errors: [err.message || String(err)],
        warnings: [],
      }));
      if (errors.length) bad++;
      else if (warnings.length) warned++;
      printValidation(file, errors, warnings);
    }
    console.log(`\n${files.length} задач: ошибок в ${bad}, предупреждений в ${warned}`);
    if (bad) process.exit(1);
    return;
  }

  let file;
  if (positional[0]) {
    file = await resolveTaskFile(positional[0], tasksDir);
  } else {
    const t = await mostRecentActive(tasksDir);
    if (!t) {
      console.log('(no active task)');
      return;
    }
    file = t.file;
    console.error(
      'rtp validate: без id взята последняя активная задача В ЭТОМ каталоге — ' +
        'она может принадлежать соседней сессии (worktree), сверься.',
    );
  }
  const { errors, warnings } = await validateTaskFile(file);
  printValidation(file, errors, warnings);
  if (errors.length) process.exit(1);
}

function printValidation(file, errors, warnings) {
  if (errors.length) {
    console.log(`❌ ${basename(file)}`);
    for (const e of errors) console.log(`  ERROR: ${e}`);
    for (const w of warnings) console.log(`  WARN:  ${w}`);
  } else if (warnings.length) {
    console.log(`⚠️  ${basename(file)}`);
    for (const w of warnings) console.log(`  WARN:  ${w}`);
  } else {
    console.log(`✅ ${basename(file)} — OK`);
  }
}

async function validateTaskFile(file) {
  const { raw, fm } = await readTask(file);
  const { body } = splitFrontmatter(raw);

  const errors = [];
  const warnings = [];

  for (const k of ['id', 'title', 'type', 'pipeline', 'phase', 'created', 'updated']) {
    if (!fm[k]) errors.push(`missing frontmatter: ${k}`);
  }
  if (fm.phase && !VALID_PHASES.includes(fm.phase)) {
    errors.push(`invalid phase: ${fm.phase}`);
  }
  if (fm.type && !VALID_TYPES.includes(fm.type)) {
    errors.push(`invalid type: ${fm.type}`);
  }
  if (fm.pipeline && !VALID_PIPELINES.includes(fm.pipeline)) {
    errors.push(`invalid pipeline: ${fm.pipeline}`);
  }

  // artifacts.spec/plan path existence (parse nested manually)
  const fmMatch = raw.match(/^---\n([\s\S]*?)\n---/);
  if (fmMatch) {
    const artifacts = parseNestedKey(fmMatch[1], 'artifacts');
    const projectRoot = await findProjectRoot(file);
    for (const k of ['spec', 'plan']) {
      const v = artifacts[k];
      if (v && v !== 'null' && v !== '~') {
        const path = resolve(projectRoot, v);
        if (!(await exists(path))) {
          errors.push(`artifacts.${k} → file not found: ${v}`);
        }
      }
    }
  }

  const logSec = getSectionContent(body, 'Log');
  if (!logSec || !/^- /m.test(logSec)) {
    warnings.push('## Log has no entries');
  }

  const debtSec = getDebtSectionContent(body);
  if (debtSec) {
    const lines = debtSec.split('\n');
    for (const line of lines) {
      if (/^\s*- (?!\[[ x]\])/.test(line) && !/^\s*- _/.test(line)) {
        warnings.push(`Debt: plain bullet without [ ]/[x] — invisible to the index and debt reports: "${line.trim()}"`);
      }
    }
  }

  return { errors, warnings };
}

function parseNestedKey(fmText, parentKey) {
  // Very minimal nested parser. Looks for `parentKey:` then collects indented lines.
  const lines = fmText.split('\n');
  const result = {};
  let inside = false;
  for (const line of lines) {
    if (!inside) {
      if (line.match(new RegExp(`^${parentKey}:\\s*$`))) inside = true;
      continue;
    }
    const m = line.match(/^(\s+)([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (!m) {
      if (/^\S/.test(line)) inside = false;
      continue;
    }
    result[m[2]] = parseYamlScalar(m[3].trim());
  }
  return result;
}

async function findProjectRoot(taskFile) {
  // task file is at <project>/docs/tasks/<id>.md → walk up two
  return resolve(dirname(taskFile), '..', '..');
}

// ──────────────────────────────────────────────────────────────────────────
// rtp index
// ──────────────────────────────────────────────────────────────────────────

async function cmdIndex(args) {
  const { flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(
      `rtp index — regenerate docs/tasks/index.md from task frontmatter.\n\nOPTIONS\n  --tasks-dir <path>   Override docs/tasks location`,
    );
    return;
  }
  const tasksDir = await resolveTasksDir(flags);
  const result = await buildIndex(tasksDir);
  console.log(
    `Wrote ${result.indexFile} — active: ${result.active}, blocked: ${result.blocked}, done(shown): ${result.done}`,
  );
}

// ──────────────────────────────────────────────────────────────────────────
// rtp show
// ──────────────────────────────────────────────────────────────────────────

async function cmdShow(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp show <id-or-path> — print frontmatter + last 5 Log entries.`);
    return;
  }
  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.');
  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  const { raw, fm } = await readTask(file);
  console.log(`File: ${file}`);
  for (const k of ['id', 'title', 'type', 'pipeline', 'phase', 'created', 'updated', 'blocked_by']) {
    console.log(`  ${k}: ${fm[k] ?? '—'}`);
  }
  console.log(`  open debts: ${countOpenDebts(raw)}`);

  const { body } = splitFrontmatter(raw);
  const entries = lastLogEntries(body, 5);
  if (entries.length) {
    console.log('\nLast log entries:');
    for (const e of entries) console.log(`  - ${e}`);
  }
  const steps = parseSteps(body);
  if (steps.length) {
    const { total, done } = stepStats(steps);
    console.log(`\nProgress ${done}/${total} ${progressBar(done, total)}:`);
    console.log(renderSteps(steps));
  }
}

// ──────────────────────────────────────────────────────────────────────────
// rtp artifact — set artifacts.* / escalate pipeline (никакого ручного YAML)
// ──────────────────────────────────────────────────────────────────────────

async function cmdArtifact(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp artifact — link an artifact to a task (no hand-edited frontmatter).

USAGE
  rtp artifact <id> --spec docs/features/<slug>-spec.md
  rtp artifact <id> --plan docs/plans/<slug>-plan.md
  rtp artifact <id> --branch feat/foo --pr https://…
  rtp artifact <id> --pipeline full        # escalate only: minimal → no-spec → full

OPTIONS
  --spec/--plan <path>   Path relative to the project root (existence is checked)
  --branch <name>        artifacts.branch
  --pr <url-or-number>   artifacts.pr
  --pipeline <P>         Escalate the preset (narrowing is refused)
  --tasks-dir <path>
`);
    return;
  }

  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.');
  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw, fm } = await readTask(file);
  const date = flags.date || today();
  const root = projectRootOf(file);

  const changes = [];
  for (const key of ['spec', 'plan', 'branch', 'pr']) {
    if (flags[key] === undefined) continue;
    const value = strFlag(flags, key);
    if ((key === 'spec' || key === 'plan') && !(await exists(resolve(root, value)))) {
      throw new Error(`artifacts.${key} → file not found: ${value} (relative to ${root})`);
    }
    raw = replaceNestedFrontmatterField(raw, 'artifacts', key, value);
    changes.push(`artifacts.${key} = ${value}`);
  }

  if (flags.pipeline !== undefined) {
    const next = strFlag(flags, 'pipeline');
    if (!VALID_PIPELINES.includes(next)) {
      throw new Error(`--pipeline must be one of: ${VALID_PIPELINES.join(', ')}`);
    }
    // Escalation is allowed, narrowing is not — a preset chosen after triage
    // may only grow (см. Presets в SKILL.md).
    const rank = { minimal: 0, 'no-spec': 1, full: 2 };
    if (rank[next] < rank[fm.pipeline ?? 'minimal']) {
      throw new Error(
        `pipeline can only escalate: ${fm.pipeline} → ${next} is a narrowing. Refused.`,
      );
    }
    raw = replaceFrontmatterField(raw, 'pipeline', next);
    changes.push(`pipeline ${fm.pipeline} → ${next}`);
  }

  if (!changes.length) throw new Error('Nothing to set. Use --spec/--plan/--branch/--pr/--pipeline.');

  const { header, body } = splitFrontmatter(raw);
  raw = header + appendLog(body, date, changes.join('; '));
  raw = replaceFrontmatterField(raw, 'updated', date);
  await writeTaskRaw(file, raw);
  await buildIndex(tasksDir);
  console.log(`${basename(file)}: ${changes.join('; ')}`);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp steps — seed / replace the plan-step checklist
// ──────────────────────────────────────────────────────────────────────────

async function cmdSteps(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'list'] });
  if (flags.help) {
    console.log(`rtp steps — seed or edit the plan-step checklist (## Progress).

USAGE
  rtp steps <id> --set "Шаг 1|Шаг 2|Шаг 3"
  rtp steps <id> --from-plan docs/plans/<slug>-plan.md
  rtp steps <id> --add "Ещё один шаг"
  rtp steps <id> --list

OPTIONS
  --set <a|b|c>        Replace the whole checklist (pipe-separated)
  --from-plan <path>   Derive steps from '## Фаза N …' / '### Step N …' headings
  --add <text>         Append one step as ⬜ todo
  --list               Print the current checklist
  --tasks-dir <path>   Override docs/tasks location

NOTE
  Steps are numbered lines with a glyph (✅ ▶ ⬜ ⛔), never '- [ ]' checkboxes —
  checkboxes anywhere in a task file are counted as technical debt by
  the index and debt reports.
`);
    return;
  }

  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.');
  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw } = await readTask(file);
  let { header, body } = splitFrontmatter(raw);
  const date = flags.date || today();

  if (flags.list) {
    const steps = parseSteps(body);
    console.log(renderSteps(steps));
    return;
  }

  let steps = parseSteps(body);
  let summary;

  if (flags['from-plan'] !== undefined) {
    const planPath = resolve(projectRootOf(file), strFlag(flags, 'from-plan'));
    const planText = await readFile(planPath, 'utf8').catch(() => {
      throw new Error(`Plan file not readable: ${planPath}`);
    });
    const titles = extractPlanSteps(planText);
    if (!titles.length) {
      throw new Error(
        `No step headings found in ${planPath}. Expected '## Фаза N …' / '### Step N …'. Use --set instead.`,
      );
    }
    steps = titles.map((t, i) => ({ n: i + 1, status: i === 0 ? 'current' : 'todo', text: t }));
    summary = `steps seeded from plan (${steps.length})`;
  } else if (flags.set !== undefined) {
    const titles = strFlag(flags, 'set')
      .split('|')
      .map((s) => s.trim())
      .filter(Boolean);
    if (!titles.length) throw new Error('--set produced no steps.');
    steps = titles.map((t, i) => ({ n: i + 1, status: i === 0 ? 'current' : 'todo', text: t }));
    summary = `steps set (${steps.length})`;
  } else if (flags.add !== undefined) {
    const text = strFlag(flags, 'add');
    steps.push({ n: steps.length + 1, status: 'todo', text });
    summary = `+ step: ${text}`;
  } else {
    throw new Error('Specify --set, --from-plan, --add or --list.');
  }

  body = writeSteps(body, steps);
  raw = applyStepStats(header + body, steps, date);
  await writeTaskRaw(file, raw);
  await buildIndex(tasksDir);
  console.log(`${basename(file)}: ${summary}`);
  console.log(renderSteps(steps));
}

// ──────────────────────────────────────────────────────────────────────────
// rtp step — advance one plan step
// ──────────────────────────────────────────────────────────────────────────

async function cmdStep(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'quiet'] });
  if (flags.help) {
    console.log(`rtp step — mark a plan step done / current / blocked.

USAGE
  rtp step <id> --done 2 [--note "tests green"]
  rtp step <id> --start 3
  rtp step <id> --block 4 --why "backend не отдаёт поле"
  rtp step <id> --todo 4

OPTIONS
  --done <n>        Mark step n ✅ and auto-start the next todo step
  --start <n>       Mark step n ▶ current
  --block <n>       Mark step n ⛔ blocked (use with --why)
  --todo <n>        Reset step n to ⬜
  --note <text>     Log note attached to the transition
  --why <text>      Reason for --block (also appended to ## Blockers)
  --quiet           Do not print the Status Block afterwards
  --tasks-dir <path>
`);
    return;
  }

  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.');
  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw } = await readTask(file);
  let { header, body } = splitFrontmatter(raw);
  const date = flags.date || today();

  const steps = parseSteps(body);
  if (!steps.length) {
    throw new Error(
      `No steps in ## Progress. Seed them first: rtp steps ${basename(file, '.md')} --set "…"`,
    );
  }

  const pick = (key) => {
    if (flags[key] == null || flags[key] === true) return null;
    const n = Number(flags[key]);
    if (!Number.isInteger(n) || n < 1 || n > steps.length) {
      throw new Error(`--${key} must be 1..${steps.length}`);
    }
    return n;
  };

  const doneN = pick('done');
  const startN = pick('start');
  const blockN = pick('block');
  const todoN = pick('todo');
  if (!doneN && !startN && !blockN && !todoN) {
    throw new Error('Specify --done / --start / --block / --todo.');
  }

  const note = flags.note !== undefined ? strFlag(flags, 'note') : null;
  const why = flags.why !== undefined ? strFlag(flags, 'why') : null;

  let action;
  if (doneN) {
    steps[doneN - 1].status = 'done';
    action = `шаг ${doneN} ✅ ${steps[doneN - 1].text}`;
    // Auto-advance: first remaining todo becomes current (unless one already is).
    if (!steps.some((s) => s.status === 'current')) {
      const nextTodo = steps.find((s) => s.status === 'todo');
      if (nextTodo) nextTodo.status = 'current';
    }
  } else if (startN) {
    for (const s of steps) if (s.status === 'current') s.status = 'todo';
    steps[startN - 1].status = 'current';
    action = `шаг ${startN} ▶ ${steps[startN - 1].text}`;
  } else if (blockN) {
    steps[blockN - 1].status = 'blocked';
    action = `шаг ${blockN} ⛔ ${steps[blockN - 1].text}${why ? ` — ${why}` : ''}`;
    if (why) {
      const blockers = getSectionContent(body, 'Blockers') || '';
      const kept = blockers
        .split('\n')
        .filter((l) => /^- /.test(l.trim()))
        .join('\n');
      body = setSection(body, 'Blockers', `${kept}\n- ${date}: шаг ${blockN} — ${why}`.trim());
    }
  } else {
    steps[todoN - 1].status = 'todo';
    action = `шаг ${todoN} ⬜ ${steps[todoN - 1].text}`;
  }

  body = writeSteps(body, steps);
  const logMsg = note ? `${action} — ${note}` : action;
  body = appendLog(body, date, logMsg);
  raw = applyStepStats(header + body, steps, date);
  await writeTaskRaw(file, raw);
  await buildIndex(tasksDir);

  console.log(`${basename(file)}: ${action}`);
  if (!flags.quiet) {
    console.log('');
    console.log(await buildStatusBlock(file));
  }
}

// Writes steps_done / steps_total / step_current / updated into frontmatter.
function applyStepStats(raw, steps, date) {
  const { total, done, current } = stepStats(steps);
  let out = replaceFrontmatterField(raw, 'steps_total', total);
  out = replaceFrontmatterField(out, 'steps_done', done);
  out = replaceFrontmatterField(out, 'step_current', current);
  out = replaceFrontmatterField(out, 'updated', date);
  return out;
}

// ──────────────────────────────────────────────────────────────────────────
// rtp status — the paste-ready Status Block
// ──────────────────────────────────────────────────────────────────────────

async function cmdStatus(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp status [<id>] — print the paste-ready Status Block.

Without <id>, uses the most recently updated active task.
`);
    return;
  }
  const tasksDir = await resolveTasksDir(flags);
  const file = positional[0]
    ? await resolveTaskFile(positional[0], tasksDir)
    : (await mostRecentActive(tasksDir))?.file;
  if (!file) {
    console.log('(no active task)');
    return;
  }
  console.log(await buildStatusBlock(file));
}

// `updated:` is day-granular, so every task touched today ties. File mtime
// breaks the tie — without it "the task this session is working on" silently
// became "the alphabetically first task touched today".
async function mostRecentActive(tasksDir) {
  const tasks = await loadAllTasks(tasksDir);
  const active = tasks
    .filter((t) => !['done'].includes(t.fm.phase))
    .sort(
      (a, b) =>
        (b.fm.updated || '').localeCompare(a.fm.updated || '') ||
        (b.mtime || 0) - (a.mtime || 0),
    );
  return active[0] || null;
}

async function buildStatusBlock(file) {
  const { raw, fm } = await readTask(file);
  const { body } = splitFrontmatter(raw);
  const steps = parseSteps(body);
  const { total, done, current } = stepStats(steps);
  const bar = progressBar(done, total);
  const currentStep = current ? steps[current - 1] : null;
  const nextStep = currentStep || steps.find((s) => s.status === 'todo') || null;
  const lastDone = [...steps].reverse().find((s) => s.status === 'done');
  const logs = lastLogEntries(body, 2);
  const debts = openDebtLines(body);
  const blockers = blockerLines(body);

  const head = total
    ? `📍 ${fm.id} · ${fm.phase} · шаг ${done}/${total} ${bar}`
    : `📍 ${fm.id} · ${fm.phase} · pipeline ${fm.pipeline}`;

  const doneLine = lastDone
    ? `✅ Сделано: ${lastDone.text}`
    : logs.length
      ? `✅ Сделано: ${logs[logs.length - 1]}`
      : '✅ Сделано: —';

  const nextLine = nextStep
    ? `🔜 Дальше: шаг ${steps.indexOf(nextStep) + 1} — ${nextStep.text}`
    : `🔜 Дальше: ${nextActionFor(fm, await loadProjectConfig(dirname(file)))}`;

  const openBits = [];
  if (debts.length) openBits.push(`${debts.length} долг(ов)`);
  if (blockers.length) openBits.push(`${blockers.length} блокер(ов)`);
  const openLine = `⚠️ Открыто: ${openBits.length ? openBits.join(', ') : 'нет'}`;

  return [
    head,
    doneLine,
    nextLine,
    openLine,
    `▶ Продолжить: rtp resume ${fm.id}`,
  ].join('\n');
}

// ──────────────────────────────────────────────────────────────────────────
// rtp next — next concrete action
// ──────────────────────────────────────────────────────────────────────────

const NEUTRAL_VERIFY = '<команды проверки из CLAUDE.md проекта>';

// Review-phase hint. Commands and reviewers come from the task's project
// config (.rtp.json); rtp only prints them — running is the agent's job.
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
  const id = fm.id;
  switch (fm.phase) {
    case 'triage':
      return fm.pipeline === 'full'
        ? `написать spec → rtp phase ${id} --to spec-review`
        : fm.pipeline === 'no-spec'
          ? `написать план → rtp phase ${id} --to plan-review`
          : `реализовать → rtp phase ${id} --to impl`;
    case 'spec':
      return `дописать spec → rtp phase ${id} --to spec-review`;
    case 'spec-review':
      return `дать spec независимому субагенту-ревьюеру, потом rtp phase ${id} --to plan`;
    case 'plan':
      return `дописать план, засеять шаги (rtp steps ${id} --from-plan …) → rtp phase ${id} --to plan-review`;
    case 'plan-review':
      return `дать план субагенту-архитектору, потом rtp phase ${id} --to impl`;
    case 'impl':
      return `следующий шаг плана; каждый закрытый шаг — rtp step ${id} --done <n>`;
    case 'review':
      return reviewAction(id, cfg, verbose);
    case 'blocked':
      return `снять блокер (${fm.blocked_by || 'см. ## Blockers'}) → rtp phase ${id} --to impl`;
    default:
      return 'задача закрыта';
  }
}

async function cmdNext(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp next [<id>] — print the next concrete action for the current phase.`);
    return;
  }
  const tasksDir = await resolveTasksDir(flags);
  const t = positional[0]
    ? { file: await resolveTaskFile(positional[0], tasksDir) }
    : await mostRecentActive(tasksDir);
  if (!t?.file) {
    console.log('(no active task)');
    return;
  }
  const { raw, fm } = await readTask(t.file);
  const { body } = splitFrontmatter(raw);
  const steps = parseSteps(body);
  const cur = steps.find((s) => s.status === 'current');
  console.log(`${fm.id} · phase ${fm.phase}`);
  if (cur) console.log(`шаг ${steps.indexOf(cur) + 1}/${steps.length}: ${cur.text}`);
  const cfg = await loadProjectConfig(dirname(t.file));
  const [first, ...rest] = nextActionFor(fm, cfg, { verbose: true }).split('\n');
  console.log(`→ ${first}`);
  for (const l of rest) console.log(`  ${l}`);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp handoff — context transfer to the next agent
// ──────────────────────────────────────────────────────────────────────────

async function cmdHandoff(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'auto', 'print-only'] });
  if (flags.help) {
    console.log(`rtp handoff — regenerate ## Handoff and print a paste-ready block.

USAGE
  rtp handoff <id> [--write "<gotcha the code does not show>"]
  rtp handoff --auto            # most recently updated active task; silent if none

OPTIONS
  --write <text>     Append a durable note (survives regeneration)
  --print-only       Do not write the task file, only print the block
  --tasks-dir <path>

WHAT IT CAPTURES
  phase + plan step, worktree path + branch, ahead/behind the base branch
  (.rtp.json baseBranch → origin/HEAD → main/master), dirty files,
  git diff --stat, last log entries, open debts, blockers, next action,
  agent notes added with --write.
`);
    return;
  }

  const tasksDir = await resolveTasksDir(flags);
  let file;
  if (positional[0]) {
    file = await resolveTaskFile(positional[0], tasksDir);
  } else {
    const t = await mostRecentActive(tasksDir);
    if (!t) {
      if (flags.auto) return; // silent for hook use
      console.log('(no active task)');
      return;
    }
    file = t.file;
  }

  const { raw, fm } = await readTask(file);
  let { header, body } = splitFrontmatter(raw);
  const date = flags.date || today();

  const notes = extractHandoffNotes(body);
  if (flags.write !== undefined) notes.push(`${date}: ${strFlag(flags, 'write')}`);

  const root = projectRootOf(file);
  const cfg = await loadProjectConfig(dirname(file));
  const g = await gitContext(root, cfg.baseBranch);
  const steps = parseSteps(body);
  const { total, done } = stepStats(steps);
  const debts = openDebtLines(body);
  const blockers = blockerLines(body);
  const logs = lastLogEntries(body, 5);

  const lines = [];
  lines.push(`**Сгенерировано:** ${date} · \`rtp handoff\``);
  lines.push('');
  lines.push(`- **Задача:** \`${fm.id}\` — ${fm.title}`);
  lines.push(`- **Фаза:** ${fm.phase} (pipeline \`${fm.pipeline}\`, type \`${fm.type}\`)`);
  if (total) {
    lines.push(`- **Прогресс:** ${done}/${total} ${progressBar(done, total)}`);
  }
  lines.push(`- **Worktree:** \`${g.worktree}\``);
  lines.push(
    g.baseBranch
      ? `- **Ветка:** \`${g.branch}\` — своих коммитов ${g.aheadOfBase}, отставание от ${g.baseBranch} ${g.behindBase}`
      : `- **Ветка:** \`${g.branch}\` — базовая ветка не определена`,
  );
  lines.push(`- **Незакоммиченного:** ${g.dirtyCount} файл(ов)`);
  lines.push('');

  if (steps.length) {
    lines.push('**Шаги плана**');
    lines.push('');
    lines.push(renderSteps(steps));
    lines.push('');
  }

  if (g.dirtyFiles.length) {
    lines.push('**Файлы в работе**');
    lines.push('');
    for (const f of g.dirtyFiles) lines.push(`- \`${f}\``);
    if (g.dirtyCount > g.dirtyFiles.length) {
      lines.push(`- …ещё ${g.dirtyCount - g.dirtyFiles.length}`);
    }
    lines.push('');
  }

  if (g.diffStat.length) {
    lines.push('**git diff HEAD --stat**');
    lines.push('');
    lines.push('```');
    lines.push(...g.diffStat.slice(-20));
    lines.push('```');
    lines.push('');
  }

  if (g.lastCommits.length) {
    lines.push('**Последние коммиты**');
    lines.push('');
    for (const c of g.lastCommits) lines.push(`- \`${c}\``);
    lines.push('');
  }

  if (logs.length) {
    lines.push('**Последние записи лога**');
    lines.push('');
    for (const l of logs) lines.push(`- ${l}`);
    lines.push('');
  }

  if (blockers.length) {
    lines.push('**Блокеры**');
    lines.push('');
    for (const b of blockers) lines.push(`- ${b}`);
    lines.push('');
  }

  if (debts.length) {
    lines.push(`**Открытые долги (${debts.length})**`);
    lines.push('');
    for (const d of debts.slice(0, 10)) lines.push(`- ${d}`);
    if (debts.length > 10) lines.push(`- …ещё ${debts.length - 10}`);
    lines.push('');
  }

  lines.push('**Следующее действие**');
  lines.push('');
  lines.push(`- ${nextActionFor(fm, cfg)}`);
  lines.push('');
  lines.push('**Заметки агента** (не выводятся из кода — грабли, тупики, договорённости)');
  lines.push('');
  lines.push(NOTES_OPEN);
  if (notes.length) {
    for (const n of notes) lines.push(`- ${n}`);
  } else {
    // NOT a `- ` bullet: extractHandoffNotes() harvests bullets, so a bulleted
    // placeholder would be carried forward as a real note forever.
    lines.push('_пусто — добавь через `rtp handoff <id> --write "…"`_');
  }
  lines.push(NOTES_CLOSE);

  const section = lines.join('\n');

  if (!flags['print-only']) {
    body = setSection(body, 'Handoff', section);
    let out = replaceFrontmatterField(header + body, 'updated', date);
    await writeTaskRaw(file, out);
    await buildIndex(tasksDir);
  }

  console.log(`# Handoff — ${fm.id}`);
  console.log('');
  console.log(section);
  if (!flags['print-only']) {
    console.error(`\nwritten to ${file} (## Handoff)`);
  }
}

// ──────────────────────────────────────────────────────────────────────────
// rtp verify — record verification evidence
// ──────────────────────────────────────────────────────────────────────────

async function cmdVerify(args) {
  const { positional, flags } = parseArgs(args, { booleans: ['help', 'list'] });
  if (flags.help) {
    console.log(`rtp verify — run a verification command and record the evidence.

USAGE
  rtp verify <id> --run "<команда из .rtp.json / CLAUDE.md проекта>"
  rtp verify <id> --run "<команда прогона тестов проекта — см. его CLAUDE.md>" --timeout 900
  rtp verify <id> --record "manual: проверено в браузере" --exit 0 --out "скрин приложен"
  rtp verify <id> --list

OPTIONS
  --run <cmd>        Execute via 'sh -c' in the project root, capture exit code + output tail
  --cwd <path>       Working directory for --run (default: project root of the task file)
  --timeout <sec>    Timeout for --run (default 900)
  --record <label>   Record an entry without executing anything
  --exit <n>         Exit code for --record (default 0)
  --out <text>       Output note for --record
  --list             Print the ## Verification section
  --tasks-dir <path>

EXIT CODE
  With --run, rtp exits with the command's exit code — a red run stays red.
`);
    return;
  }

  const idOrPath = positional[0];
  if (!idOrPath) throw new Error('Task id/path required.');
  const tasksDir = await resolveTasksDir(flags);
  const file = await resolveTaskFile(idOrPath, tasksDir);
  let { raw } = await readTask(file);
  let { header, body } = splitFrontmatter(raw);
  const date = flags.date || today();

  if (flags.list) {
    console.log(getSectionContent(body, 'Verification') || '(нет секции ## Verification)');
    return;
  }

  let label;
  let code;
  let tail;
  let infra = null;

  if (flags.run !== undefined) {
    const cmd = strFlag(flags, 'run');
    const cwd = flags.cwd ? resolve(String(flags.cwd)) : projectRootOf(file);
    const timeoutMs = (Number(flags.timeout) || 900) * 1000;
    console.error(`running: ${cmd}\n  cwd: ${cwd}`);
    const res = await run('sh', ['-c', cmd], cwd, timeoutMs);
    label = cmd;
    code = res.code;
    infra = res.infra;
    tail = tailLines(`${res.stdout}\n${res.stderr}`, 15);
    console.log(res.stdout.trim());
    if (res.stderr.trim()) console.error(res.stderr.trim());
  } else if (flags.record !== undefined) {
    label = strFlag(flags, 'record');
    code = Number(flags.exit ?? 0);
    tail = flags.out !== undefined ? strFlag(flags, 'out') : '(без вывода)';
  } else {
    throw new Error('Specify --run "<cmd>" or --record "<label>".');
  }

  // An infra failure is not a red test — recording it as a plain "exit 1"
  // would make a green run look failed and hide the timeout.
  const mark = infra ? '⚠️ ИНФРА' : code === 0 ? '✅' : '❌';
  if (infra) tail = `[${infra}]\n${tail}`;
  const prev = (getSectionContent(body, 'Verification') || '')
    .split('\n')
    .filter((l) => !/^\s*_.*_\s*$/.test(l))
    .join('\n')
    .trim();

  const entry = [
    `- ${date} · \`${label}\` · exit ${code} ${mark}`,
    '',
    '  ```',
    ...tail.split('\n').map((l) => `  ${l}`),
    '  ```',
  ].join('\n');

  body = setSection(body, 'Verification', `${prev}\n\n${entry}`.trim());
  body = appendLog(body, date, `verify: \`${label}\` → exit ${code} ${mark}`);
  raw = replaceFrontmatterField(header + body, 'updated', date);
  await writeTaskRaw(file, raw);
  await buildIndex(tasksDir);

  console.error(`${basename(file)}: verification recorded — exit ${code} ${mark}`);
  if (code !== 0) process.exit(code);
}

const TAIL_MAX_LINE = 300;
const TAIL_MAX_CHARS = 4000;

function tailLines(text, n) {
  const lines = String(text)
    .split('\n')
    // Progress bars redraw with \r and produce one enormous "line"; cap width
    // too, or the whole stream lands inside the task file.
    .map((l) => {
      const clean = l.replace(/.*\r/, '').replace(/\s+$/, '');
      return clean.length > TAIL_MAX_LINE
        ? `${clean.slice(0, TAIL_MAX_LINE)}… [обрезано ${clean.length - TAIL_MAX_LINE} симв.]`
        : clean;
    })
    .filter((l, i, arr) => !(l === '' && arr[i - 1] === ''));
  const slice = lines.slice(-n);
  while (slice.length && slice[0] === '') slice.shift();
  while (slice.length && slice[slice.length - 1] === '') slice.pop();
  if (!slice.length) return '(пустой вывод)';
  let out = slice.join('\n');
  if (out.length > TAIL_MAX_CHARS) {
    out = `… [начало обрезано]\n${out.slice(-TAIL_MAX_CHARS)}`;
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────────
// rtp sweep — stale tasks
// ──────────────────────────────────────────────────────────────────────────

async function cmdSweep(args) {
  const { flags } = parseArgs(args, { booleans: ['help'] });
  if (flags.help) {
    console.log(`rtp sweep — list stale tasks (active, not touched for N days).

OPTIONS
  --days <n>          Staleness threshold (default 14)
  --phase <phase>     Only this phase
  --limit <n>         Max rows (default 30)
  --tasks-dir <path>
`);
    return;
  }
  const days = Number(flags.days) || 14;
  const limit = Number(flags.limit) || 30;
  const tasksDir = await resolveTasksDir(flags);
  const tasks = await loadAllTasks(tasksDir);
  const cutoff = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);

  let stale = tasks
    .filter((t) => !['done'].includes(t.fm.phase))
    .filter((t) => (t.fm.updated || '0000-00-00') < cutoff);
  if (flags.phase) stale = stale.filter((t) => t.fm.phase === flags.phase);
  stale.sort((a, b) => (a.fm.updated || '').localeCompare(b.fm.updated || ''));

  if (!stale.length) {
    console.log(`(нет задач старше ${days} дн.)`);
    return;
  }

  const byPhase = {};
  for (const t of stale) byPhase[t.fm.phase] = (byPhase[t.fm.phase] || 0) + 1;
  console.log(
    `Висяки (>${days} дн. без правок): ${stale.length} — ` +
      Object.entries(byPhase)
        .map(([p, n]) => `${p}: ${n}`)
        .join(', '),
  );
  console.log('');
  for (const t of stale.slice(0, limit)) {
    console.log(
      `${(t.fm.updated || '??????????').padEnd(10)}  ${(t.fm.phase || '?').padEnd(11)} ${t.debts ? `debt:${t.debts} ` : ''}${t.fm.id}`,
    );
  }
  if (stale.length > limit) console.log(`… ещё ${stale.length - limit}`);
  console.log('');
  console.log('Закрыть:  rtp phase <id> --to done --log "закрыто при разборе висяков"');
}

// ──────────────────────────────────────────────────────────────────────────
// rtp hook-postedit  (used by PostToolUse hook)
// ──────────────────────────────────────────────────────────────────────────

async function cmdHookPostEdit() {
  // Read JSON event from stdin (hook protocol). Quiet on errors so we never
  // block tool calls.
  const input = await readStdin();
  let event = null;
  try {
    event = JSON.parse(input);
  } catch {
    process.exit(0);
  }
  const filePath =
    event?.tool_input?.file_path ||
    event?.tool_input?.path ||
    event?.tool_response?.filePath;
  if (!filePath || typeof filePath !== 'string') process.exit(0);

  // Only act for files inside a `docs/tasks/` directory, excluding index.md
  // and `_`-prefixed.
  const norm = filePath.replace(/\\/g, '/');
  const m = norm.match(/(.*\/docs\/tasks)\/([^/]+)$/);
  if (!m) process.exit(0);
  const [, tasksDir, fname] = m;
  if (fname === 'index.md' || fname.startsWith('_')) process.exit(0);
  if (!fname.endsWith('.md')) process.exit(0);

  try {
    await buildIndex(tasksDir);
  } catch {
    // never block on hook failure
  }
  process.exit(0);
}

function readStdin() {
  return new Promise((resolveP) => {
    let data = '';
    if (process.stdin.isTTY) return resolveP('');
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => (data += chunk));
    process.stdin.on('end', () => resolveP(data));
    // Safety timeout — hooks shouldn't hang.
    setTimeout(() => resolveP(data), 1000);
  });
}

async function readHookEvent() {
  const input = await readStdin();
  try {
    return JSON.parse(input);
  } catch {
    return {};
  }
}

// ──────────────────────────────────────────────────────────────────────────
// rtp hook-sessionstart  (SessionStart hook — stdout is injected as context)
// ──────────────────────────────────────────────────────────────────────────

async function cmdHookSessionStart() {
  try {
    const event = await readHookEvent();
    const cwd = event?.cwd || process.cwd();
    const source = event?.source || 'startup';
    const transcript = event?.transcript_path;

    // On resume/compact the transcript already exists, so the task this
    // session actually worked with is knowable — no guessing from cwd, where
    // the most recent task regularly belongs to a parallel worktree session.
    // `clear` is an explicit reset by the user; `startup` has no transcript.
    if ((source === 'resume' || source === 'compact') && transcript && (await exists(transcript))) {
      const scan = await scanTranscript(transcript, { sessionId: event?.session_id });
      const editDirs = await tasksDirsForFiles(scan.sessionEdits);
      const cwdDir = await findTasksDirStrict(cwd);
      const resolved = await resolveHookTask(scan, editDirs, cwdDir);
      if (resolved) {
        console.log(await sessionStartBlock(resolved.file, { own: true, source }));
        process.exit(0);
      }
    }

    const tasksDir = await findTasksDir(cwd);
    if (!(await exists(tasksDir))) process.exit(0);
    const t = await mostRecentActive(tasksDir);
    if (!t) process.exit(0);

    // Without a usable transcript this is necessarily a guess from cwd — keep
    // the window tight and say out loud that it is a guess. Parallel sessions
    // in neighbouring worktrees are common, and the most recently updated task
    // may well belong to one of them.
    const ageDays =
      (Date.now() - Date.parse(`${t.fm.updated || t.fm.created}T00:00:00Z`)) / 86400000;
    if (!Number.isFinite(ageDays) || ageDays > 3) process.exit(0);

    console.log(await sessionStartBlock(t.file, { own: false, source }));
  } catch {
    // never block session start
  }
  process.exit(0);
}

async function sessionStartBlock(file, { own, source }) {
  const { raw } = await readTask(file);
  const { body } = splitFrontmatter(raw);
  const notes = extractHandoffNotes(body);
  const out = ['<rtp-active-task>'];
  if (own) {
    out.push('Задача ЭТОЙ сессии (по её же rtp-вызовам в транскрипте):');
  } else {
    out.push(
      'Последняя активная задача В ЭТОМ каталоге (не факт, что твоя — её могла',
      'тронуть параллельная сессия в соседнем worktree; сверься, прежде чем писать в неё):',
    );
  }
  out.push(await buildStatusBlock(file), `Файл задачи: ${file}`);
  if (notes.length) {
    out.push('Заметки предыдущего агента:');
    for (const n of notes.slice(-5)) out.push(`- ${n}`);
  }
  // Only claim a fresh Handoff when there is one: the PreCompact hook may not
  // have resolved the task, and a stale Handoff read as fresh is worse than none.
  if (own && source === 'compact') {
    const handoff = getSectionContent(body, 'Handoff') || '';
    if (handoff.includes(`**Сгенерировано:** ${today()}`)) {
      out.push(
        'Перед компактом `## Handoff` в файле задачи перезаписан сегодня — читай его, ' +
          'а не восстанавливай контекст по памяти.',
      );
    }
  }
  out.push(
    own
      ? 'Продолжай через run-task-pipeline: `rtp show <id>`, секция `## Handoff` в файле задачи.'
      : 'Продолжаешь эту задачу — работай через run-task-pipeline: `rtp show <id>`, ' +
          'секция `## Handoff` в файле задачи. Начинаешь другую — заведи свою через `rtp new`.',
  );
  out.push('</rtp-active-task>');
  return out.join('\n');
}

// ──────────────────────────────────────────────────────────────────────────
// rtp hook-precompact  (PreCompact hook — last chance to persist context)
// ──────────────────────────────────────────────────────────────────────────

async function cmdHookPreCompact() {
  try {
    const event = await readHookEvent();
    const transcript = event?.transcript_path;
    if (!transcript || !(await exists(transcript))) process.exit(0);

    // Only a task THIS session worked with. A time window over "most recently
    // updated task in this directory" was not enough: a parallel worktree
    // session touching its own task within the window would have its ## Handoff
    // overwritten by our compaction.
    const scan = await scanTranscript(transcript, { sessionId: event?.session_id });
    const editDirs = await tasksDirsForFiles(scan.sessionEdits);
    // Unlike hook-stop, this does not depend on the current turn having edited
    // anything — but it still only ever locates an id this session itself
    // named (cwd tier: mutating-named ids only, see resolveHookTask).
    const cwdDir = await findTasksDirStrict(event?.cwd || process.cwd());
    const resolved = await resolveHookTask(scan, editDirs, cwdDir);
    if (!resolved) process.exit(0);

    const { fm } = await readTask(resolved.file);
    await cmdHandoff([fm.id, '--tasks-dir', dirname(resolved.file)]);
    console.log(
      `\n[rtp] контекст задачи ${fm.id} сохранён в ## Handoff перед компактом — ` +
        'после компакта читай его, а не восстанавливай по памяти.',
    );
  } catch {
    // never block compaction
  }
  process.exit(0);
}

// ──────────────────────────────────────────────────────────────────────────
// rtp hook-stop  (Stop hook — refuses to end a turn that edited code
//                 without updating task state)
// ──────────────────────────────────────────────────────────────────────────

async function cmdHookStop() {
  try {
    if (process.env.RTP_NO_STOP_HOOK === '1') process.exit(0);
    const event = await readHookEvent();
    // Never loop: this flag is set when the previous Stop hook already blocked.
    if (event?.stop_hook_active) process.exit(0);

    const transcript = event?.transcript_path;
    if (!transcript || !(await exists(transcript))) process.exit(0);

    const scan = await scanTranscript(transcript, { sessionId: event?.session_id });
    if (scan.lastCodeEdit < 0) process.exit(0); // no code edits this turn — nothing to enforce
    if (scan.lastRtpCall > scan.lastCodeEdit) process.exit(0); // state already updated after the edit

    const editDirs = await tasksDirsForFiles(scan.turnEdits);
    // Edits outside every tracker (scratchpad, another repo without docs/tasks,
    // ~/.claude) cannot owe a tracker anything. This check must come BEFORE
    // task resolution: letting cwd resolve a previously named id here made a
    // scratch-file write block the turn.
    if (!editDirs.length) process.exit(0);

    // The task file often lives in the checkout the session started in while
    // the edits land in another worktree or repository (a frontend task with
    // backend edits, a task created before EnterWorktree). cwd is the second
    // tier of the lookup — mutating-named ids only, see resolveHookTask.
    const cwdDir = await findTasksDirStrict(event?.cwd || process.cwd());
    const sessionDirs = await tasksDirsForFiles(scan.sessionEdits);
    const resolved = await resolveHookTask(scan, [...editDirs, ...sessionDirs], cwdDir);

    // No "disable with RTP_NO_STOP_HOOK=1" hint here: that is an environment
    // variable of the claude process itself, the agent cannot set it from Bash.
    let msg;
    if (resolved) {
      const { fm } = await readTask(resolved.file);
      msg = [
        resolved.certain
          ? `RTP: правки в коде есть, состояние задачи ${fm.id} (phase ${fm.phase}) не обновлено.`
          : `RTP: правки в коде есть, состояние задачи не обновлено. Похоже, речь о ${fm.id} ` +
            `(phase ${fm.phase}) — её называла эта сессия, но не в текущем ходе. Не она — назови свою.`,
        'До завершения ответа:',
        `  1) rtp step ${fm.id} --done <n>   ИЛИ   rtp phase ${fm.id} --to <phase> --log "<что сделано>"`,
        `  2) rtp status ${fm.id}  → напечатай Status Block в ответе пользователю`,
        `  3) работа не закончена → rtp handoff ${fm.id} --write "<грабли, которых не видно в коде>"`,
      ].join('\n');
    } else {
      // Edits live in a repo that HAS a tracker (guaranteed by the early exit
      // above), but this session named no live task there. Never substitute
      // someone else's id — ask for a new task instead.
      const where = editDirs[0] ? dirname(dirname(editDirs[0])) : 'репозитории';
      msg = [
        `RTP: правки в ${where} есть, а задачи в этой сессии нет.`,
        'Заведи её и зафиксируй сделанное:',
        '  rtp new --title "<что делаем>" --type <feature|bug|refactor|chore> --pipeline <full|no-spec|minimal> --reason "<почему>"',
        '  rtp phase <id> --to impl --log "<что уже сделано>"',
        'Правки относятся к уже существующей задаче — назови её явно: rtp phase <id> --to impl --log "…"',
      ].join('\n');
    }

    console.error(msg);
    process.exit(2); // exit 2 → stderr is fed back to the agent, turn continues
  } catch {
    // never block on hook failure
  }
  process.exit(0);
}

// ──────────────────────────────────────────────────────────────────────────
// Transcript scanning — shared by the Stop / PreCompact / SessionStart hooks
// ──────────────────────────────────────────────────────────────────────────

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const AGENT_TOOLS = new Set(['Agent', 'Task']);
// Only the positional id slot of an rtp subcommand counts as "the task this
// session works with". Matching any date-slug in the command string picked up
// ids from `--ref`, from `--log` prose and from printed listings — which is
// exactly how a foreign task got named. Group 1 = subcommand, group 2 = slot.
const RTP_TASK_ARG =
  /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+(phase|artifact|steps|step|status|handoff|verify|debt|show|validate|next)\s+(?!-)(\S+)/g;
// "state was updated" requires a MUTATING subcommand: `rtp list`, a grep over
// rtp.mjs, or a commit message mentioning rtp must not disarm the hook. The
// same set decides which named ids are trusted enough for a cwd-only lookup.
const RTP_MUTATING_SUBS = new Set(['new', 'phase', 'artifact', 'steps', 'step', 'debt', 'verify', 'handoff']);
const RTP_MUTATING =
  /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+(?:new|phase|artifact|steps|step|debt|verify|handoff)\b/;
const RTP_NEW = /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+new\b/;
const RTP_VERIFY = /(?:^|[\s;&|(/])rtp(?:\.mjs)?["']?\s+verify\b/;
// Subagent transcripts live in <dir of transcript>/<session_id>/subagents/
// agent-<agentId>.jsonl. Real sessions reach 50+ files / 25 MB per directory
// and the Stop hook runs on every turn, so reading is capped.
const SUBAGENT_MAX_FILES = 20;
const SUBAGENT_MAX_BYTES = 8 * 1024 * 1024;
const MAIN_MAX_BYTES = 32 * 1024 * 1024;

function parseJsonl(lines) {
  return lines.map((line) => {
    if (!line.trim()) return null;
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  });
}

// Last `maxBytes` of a JSONL file, parsed (whole file when it fits); [] when
// absent. The main transcript goes through this too: reading a 40 MB session
// whole on every Stop cost ~200 MB RSS per hook run.
async function readJsonlTail(path, maxBytes) {
  try {
    const { size } = await stat(path);
    if (size <= maxBytes) return parseJsonl((await readFile(path, 'utf8')).split('\n'));
    const fh = await open(path, 'r');
    try {
      const buf = Buffer.alloc(maxBytes);
      const { bytesRead } = await fh.read(buf, 0, maxBytes, size - maxBytes);
      const raw = buf.subarray(0, bytesRead).toString('utf8');
      return parseJsonl(raw.slice(raw.indexOf('\n') + 1).split('\n'));
    } finally {
      await fh.close();
    }
  } catch {
    return [];
  }
}

// A real human turn. Harness-injected `user` entries are NOT turn boundaries:
// task notifications, interrupt markers and system reminders all arrive as
// plain-text user entries, and treating them as a new turn silently reset the
// "did this turn edit code" state mid-turn. A slash command the user typed
// (`<command-message>…` + `<command-name>/x`) IS a turn: it is their message.
function isHumanTurn(obj) {
  if (obj?.type !== 'user' || obj?.isMeta) return false;
  const content = obj?.message?.content;
  if (Array.isArray(content) && content.some((p) => p?.type === 'tool_result')) return false;
  const text =
    typeof content === 'string'
      ? content
      : Array.isArray(content)
        ? content
            .filter((p) => p?.type === 'text')
            .map((p) => p?.text || '')
            .join('\n')
        : '';
  if (!text.trim()) return false;
  if (/^\s*<(task-notification|system-reminder|local-command)/.test(text)) return false;
  if (/^\s*\[Request interrupted/.test(text)) return false;
  if (/^\s*\[Your previous response had no visible output/.test(text)) return false;
  if (/^\s*Caveat: The messages below/.test(text)) return false;
  return true;
}

// Tool output as text: the structured `toolUseResult` (stdout + stderr, never
// truncated) when the entry has one, else the rendered content parts.
function toolResultText(entry, part) {
  const r = entry?.toolUseResult;
  if (typeof r === 'string') return r;
  if (r && (typeof r.stdout === 'string' || typeof r.stderr === 'string')) {
    return `${r.stdout || ''}\n${r.stderr || ''}`;
  }
  const c = part?.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) return c.map((x) => (x?.type === 'text' ? x.text || '' : '')).join('\n');
  return '';
}

// "The session works with task X" is established only by WRITING to it: a
// mutating rtp subcommand, the `created task` line of `rtp new`, or an edit of
// the task file. Read-only `rtp show/status/validate/next <id>` do not count:
// that is how a neighbour's task gets inspected, and with parallel sessions in
// neighbouring worktrees a peeked id would otherwise become resolvable — and get its
// ## Handoff rewritten by PreCompact.
function noteTaskId(acc, id, inTurn) {
  acc.sessionTaskIds.push(id);
  if (inTurn) acc.turnTaskIds.push(id);
}

// docs/tasks that owns an edited file, or null; memoized per directory since a
// turn edits the same few directories many times.
async function trackerDirOf(file, acc) {
  const dir = dirname(file);
  if (!acc.dirCache.has(dir)) acc.dirCache.set(dir, await findTasksDirStrict(dir));
  return acc.dirCache.get(dir);
}

// Walks ONE transcript (main or subagent) and folds tool_use facts into `acc`.
// `seq` orders tool_use calls across files: a subagent's calls get fractional
// positions right after the Agent call that spawned them, so "rtp after the
// edit" still compares correctly when both happened inside the subagent.
async function walkTranscript(parsed, acc, { turnStart, seqBase, seqStep, subagentsDir, depth }) {
  // Tool calls the user rejected or that failed outright did not change the
  // working tree — demanding a task update for them is a false block. Kept per
  // file: tool_use ids like `Bash_16` repeat between the main transcript and
  // the subagent files.
  const errored = new Set();
  for (const obj of parsed) {
    const content = obj?.message?.content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part?.type === 'tool_result' && part?.is_error === true && part?.tool_use_id) {
        errored.add(part.tool_use_id);
      }
    }
  }

  const bashById = new Map();
  const agentById = new Map();
  let seq = seqBase;
  for (let i = 0; i < parsed.length; i++) {
    const obj = parsed[i];
    const content = obj?.message?.content;
    if (!Array.isArray(content)) continue;
    const inTurn = i >= turnStart;
    for (const part of content) {
      if (part?.type === 'tool_result') {
        const bash = bashById.get(part.tool_use_id);
        if (bash) {
          const text = toolResultText(obj, part);
          // `rtp new` prints the id only in its output — the command has none,
          // so a "new → edit → stop" turn used to read as "no task in session".
          if (bash.isNew) {
            for (const m of text.matchAll(/created task (\S+)/g)) {
              const id = resolveShellWord(m[1], new Map());
              if (id) noteTaskId(acc, id, bash.inTurn);
            }
          }
          // A red `rtp verify --run` exits with the command's code, so the tool
          // call is "errored" — but the evidence WAS recorded.
          if (
            bash.isVerify &&
            bash.inTurn &&
            errored.has(part.tool_use_id) &&
            /verification recorded/.test(text)
          ) {
            acc.lastRtpCall = Math.max(acc.lastRtpCall, bash.seq);
          }
        }
        const agent = agentById.get(part.tool_use_id);
        const agentId = obj?.toolUseResult?.agentId;
        if (agent && agentId && subagentsDir && depth < 1 && acc.subagentFiles < SUBAGENT_MAX_FILES) {
          const sub = await readJsonlTail(join(subagentsDir, `agent-${agentId}.jsonl`), SUBAGENT_MAX_BYTES);
          if (sub.length) {
            acc.subagentFiles++; // a missing file must not eat the budget
            await walkTranscript(sub, acc, {
              turnStart: 0,
              seqBase: agent.seq,
              seqStep: seqStep / 1e6,
              subagentsDir,
              depth: depth + 1,
            });
          }
        }
        continue;
      }
      if (part?.type !== 'tool_use') continue;
      seq += seqStep;
      const ok = !errored.has(part.id);

      if (EDIT_TOOLS.has(part.name)) {
        const f = String(part?.input?.file_path || part?.input?.path || '');
        // A rejected/failed edit changed nothing — neither the code nor, for a
        // task file, which task this session "works with".
        if (!f || !ok) continue;
        const taskFile = f.match(/(.*\/docs\/tasks)\/([^/]+)\.md$/);
        if (taskFile) {
          // Task-file edits ARE the state update, not the work being tracked.
          acc.taskDirsTouched.add(taskFile[1]);
          noteTaskId(acc, taskFile[2], inTurn);
          if (inTurn) acc.lastRtpCall = Math.max(acc.lastRtpCall, seq);
          continue;
        }
        // An edit outside every tracker (scratchpad, ~/.claude, a repo without
        // docs/tasks) is not "code" the hook can ask a task update for. Decided
        // per edit, not per turn: a mixed turn — repo edits, rtp, then a note
        // written to ~/.claude — used to end with the note as the "last edit"
        // and block for it.
        if (!(await trackerDirOf(f, acc))) continue;
        // The tracker's project config is metadata: not code to demand a task
        // update for, and it names no task. Only this exact file — any other
        // file in a directory that happens to be called docs/tasks stays code.
        if (/\/docs\/tasks\/\.rtp\.json$/.test(f)) continue;
        acc.sessionEdits.push(f);
        if (inTurn) {
          acc.lastCodeEdit = Math.max(acc.lastCodeEdit, seq);
          acc.turnEdits.push(f);
        }
      } else if (part.name === 'Bash') {
        // Line continuations (`rtp debt \⏎  <id> \⏎  --add …`): without the
        // join the slot regex captured the backslash instead of the id.
        const cmd = String(part?.input?.command || '').replace(/\\\r?\n\s*/g, ' ');
        // Agents habitually stash the long id in a shell variable
        // (`ID=2026-…` then `rtp phase $ID …`). Reading only the literal slot
        // made every such call invisible, so the newest id the hook could see
        // was often an old literal mention — typically the task just closed.
        const vars = new Map();
        for (const a of cmd.matchAll(/(?:^|[\s;&(])(\w+)=["']?(\S+?)["']?(?=\s|$|;)/gm)) {
          vars.set(a[1], a[2]);
        }
        for (const m of cmd.matchAll(RTP_TASK_ARG)) {
          const id = resolveShellWord(m[2], vars);
          if (id && RTP_MUTATING_SUBS.has(m[1])) noteTaskId(acc, id, inTurn);
        }
        if (inTurn && ok && RTP_MUTATING.test(cmd)) acc.lastRtpCall = Math.max(acc.lastRtpCall, seq);
        bashById.set(part.id, { seq, inTurn, isNew: RTP_NEW.test(cmd), isVerify: RTP_VERIFY.test(cmd) });
      } else if (AGENT_TOOLS.has(part.name)) {
        // Only subagents spawned in the current turn are followed (cost cap):
        // their edits are this turn's edits, invisible in the main transcript.
        if (inTurn) agentById.set(part.id, { seq });
      }
    }
  }
}

// Scans the session transcript: the CURRENT TURN for the last code edit and the
// last `rtp` call — scoping to the turn is the point, scanning the whole
// transcript would re-block every later read-only turn of a session that once
// edited code without updating the task — and the whole session for the task
// ids it named. Positions are tool_use sequence numbers (-1 when absent).
async function scanTranscript(path, { sessionId } = {}) {
  const parsed = (await readJsonlTail(path, MAIN_MAX_BYTES)).slice(-4000);

  let turnStart = 0;
  parsed.forEach((obj, i) => {
    if (isHumanTurn(obj)) turnStart = i;
  });

  const acc = {
    lastCodeEdit: -1,
    lastRtpCall: -1,
    turnEdits: [], // code edits in the current turn
    sessionEdits: [], // code edits in the whole (windowed) session
    sessionTaskIds: [], // every id the session wrote to, in order (see noteTaskId)
    turnTaskIds: [], // ids named in the CURRENT turn — preferred over older ones
    taskDirsTouched: new Set(),
    subagentFiles: 0,
    dirCache: new Map(),
  };
  const sid = sessionId || basename(path, '.jsonl');
  await walkTranscript(parsed, acc, {
    turnStart,
    seqBase: 0,
    seqStep: 1,
    subagentsDir: join(dirname(path), sid, 'subagents'),
    depth: 0,
  });
  const { dirCache, ...rest } = acc;
  return { ...rest, taskDirsTouched: [...acc.taskDirsTouched] };
}

// `$ID` / `${ID}` → the value assigned earlier in the same command; a bare word
// is returned as-is. Anything that is not a task id (unresolved variable,
// command substitution, a path) yields null.
function resolveShellWord(word, vars) {
  let w = String(word).replace(/^["']|["']$/g, '');
  const varRef = w.match(/^\$\{?(\w+)\}?$/);
  if (varRef) w = vars.get(varRef[1]) || '';
  w = w.replace(/\.md$/, '').replace(/.*\//, '');
  return /^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*$/.test(w) ? w : null;
}

// docs/tasks directories that actually own the edited files. NOT derived from
// the session cwd: a session sitting in repo A while editing repo B (or files
// outside any repo) must not be pointed at repo A's tracker.
async function tasksDirsForFiles(files) {
  const out = new Set();
  for (const f of files) {
    const dir = await findTasksDirStrict(dirname(f));
    if (dir) out.add(dir);
  }
  return [...out];
}

// Resolves the task this SESSION worked with. Only ids the session itself
// mentioned are considered, so a foreign task can never be named.
// `done` tasks are skipped: the hook's complaint is "state not updated", and a
// closed task has nothing left to update — naming one makes the agent append a
// false entry to finished work instead of tracking the live task.
async function sessionTaskFile(ids, dirs) {
  for (const id of [...ids].reverse()) {
    for (const dir of dirs) {
      const file = join(dir, `${id}.md`);
      if (!(await exists(file))) continue;
      try {
        const { fm } = await readTask(file);
        if (fm.phase === 'done') continue;
      } catch {
        continue;
      }
      return file;
    }
  }
  return null;
}

// Ids named in the current turn win over older mentions: an id from three
// turns ago is at best a guess about what is being worked on now.
async function resolveSessionTask(turnTaskIds, sessionTaskIds, dirs) {
  const fromTurn = await sessionTaskFile(turnTaskIds, dirs);
  if (fromTurn) return { file: fromTurn, certain: true };
  const older = await sessionTaskFile(sessionTaskIds, dirs);
  return older ? { file: older, certain: false } : null;
}

// Two tiers over the same ids (only ids the session WROTE to, see noteTaskId;
// ids it never named are never considered). Tier 1: where its edits (or
// task-file edits) live. Tier 2: the cwd tracker — the task is often created
// in one checkout while the edits land in another worktree or repository.
async function resolveHookTask(scan, editDirs, cwdDir) {
  const dirs = [...new Set([...scan.taskDirsTouched, ...editDirs])];
  const first = await resolveSessionTask(scan.turnTaskIds, scan.sessionTaskIds, dirs);
  if (first) return first;
  if (!cwdDir || dirs.includes(cwdDir)) return null;
  return resolveSessionTask(scan.turnTaskIds, scan.sessionTaskIds, [cwdDir]);
}

// ──────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────

function required(flags, key) {
  if (flags[key] == null || flags[key] === true || flags[key] === '') {
    throw new Error(`--${key} is required`);
  }
  return String(flags[key]);
}

async function resolveTasksDir(flags) {
  if (flags['tasks-dir']) return resolve(String(flags['tasks-dir']));
  return await findTasksDir();
}

function escapeYaml(s) {
  if (/[:#@`*&!|>{}\[\],"']/.test(s) || s !== s.trim()) {
    return JSON.stringify(s);
  }
  return s;
}

// ──────────────────────────────────────────────────────────────────────────
// Dispatch — must stay last: every module-level `const` above is initialized
// by the time a handler runs.
// ──────────────────────────────────────────────────────────────────────────

const [, , rawCmd, ...rest] = process.argv;
const cmd = rawCmd || 'help';
const handler = SUBCOMMANDS[cmd];

if (!handler) {
  console.error(`rtp: unknown subcommand "${cmd}"\nRun 'rtp help' for usage.`);
  process.exit(2);
}

try {
  await handler(rest);
} catch (err) {
  console.error(`rtp ${cmd}: ${err.message || err}`);
  process.exit(1);
}
