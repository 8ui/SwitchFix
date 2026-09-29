#!/bin/sh
# Regression suite for the code-review findings on rtp.
set -u
# Self-contained: runs in a throwaway dir, never touches a real docs/tasks.
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rtp-regress.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/docs/tasks" "$ROOT/docs/plans"
TD="$ROOT/docs/tasks"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
# Test the rtp.mjs NEXT TO THIS SCRIPT — not whatever is on PATH (a non-login
# shell has no ~/.claude/bin and every case would go red behind 2>/dev/null)
# and not the installed copy (a snapshot of the skill must test itself).
RTP="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/rtp.mjs"
LIB="$(dirname "$RTP")/lib.mjs"
rtp() { node "$RTP" "$@"; }

echo "F2: \\Z в regex обрезал секцию на первой букве Z"
rtp new --title "Zed task" --type chore --pipeline minimal --reason r --tasks-dir "$TD" >/dev/null 2>&1
ZED=$(rtp find zed --tasks-dir "$TD" | head -1 | cut -f1)
rtp phase "$ZED" --to impl --log "Zod schema added" --tasks-dir "$TD" >/dev/null 2>&1
rtp resume zed --tasks-dir "$TD" | grep -q "Zod schema added" && ok "последняя запись лога не обрезана" || bad "лог обрезан на Z"

echo "F4: \$& в title ломал frontmatter через String.replace"
rtp new --title 'Fix $& and $` here' --type chore --pipeline minimal --reason r --tasks-dir "$TD" >/dev/null 2>&1
ID=$(rtp find fix --tasks-dir "$TD" | head -1 | cut -f1)
rtp phase "$ID" --to impl --log "touch" --tasks-dir "$TD" >/dev/null 2>&1
node -e "
const fs=require('fs');const f=process.argv[1];const s=fs.readFileSync(f,'utf8');
const fm=s.split('---')[1]||'';
process.exit(fm.includes('id:')&&!fm.includes('\n---')&&(fm.match(/title:/g)||[]).length===1?0:1)
" "$TD/$ID.md" && ok "frontmatter цел" || bad "frontmatter разрушен"

echo "F8: appendLog падал на файле без секции ## Log"
node -e "
const fs=require('fs');const p=process.argv[1];
fs.writeFileSync(p,'---\nid: legacy-task\ntitle: Legacy\ntype: chore\npipeline: minimal\nphase: impl\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n## Context\n\nстарый файл без Log и Debt\n');
" "$TD/legacy-task.md"
rtp phase legacy-task --to review --log "works on legacy file" --tasks-dir "$TD" >/dev/null 2>&1 \
  && grep -q "works on legacy file" "$TD/legacy-task.md" && ok "секция ## Log создана, фаза записана" || bad "phase на легаси-файле падает"
rtp debt legacy-task --add "долг на легаси-файле" --tasks-dir "$TD" >/dev/null 2>&1 \
  && grep -q '\- \[ \] долг на легаси-файле' "$TD/legacy-task.md" && ok "секция ## Debt создана" || bad "debt на легаси-файле падает"

echo "F10: значение флага, начинающееся с --"
rtp phase legacy-task --to review --log "--fix applied" --tasks-dir "$TD" >/dev/null 2>&1 && bad "молча проглотил --log без значения" || ok "падает с ошибкой вместо записи true"
rtp phase legacy-task --to review --log="--fix applied" --tasks-dir "$TD" >/dev/null 2>&1 \
  && grep -q '\-\-fix applied' "$TD/legacy-task.md" && ok "форма --log= работает" || bad "форма --log= не работает"

echo "F12: плейсхолдер Handoff подхватывался как заметка"
rtp handoff legacy-task --tasks-dir "$TD" >/dev/null 2>&1
rtp handoff legacy-task --tasks-dir "$TD" >/dev/null 2>&1
grep -c 'пусто — добавь' "$TD/legacy-task.md" | grep -qx 1 && ok "плейсхолдер не размножается" || bad "плейсхолдер закрепился как заметка"

echo "F9: step_current — позиция, а не номер из файла"
rtp steps legacy-task --set "a|b|c" --tasks-dir "$TD" >/dev/null 2>&1
node -e "
const fs=require('fs');const p=process.argv[1];let s=fs.readFileSync(p,'utf8');
s=s.replace(/^2\. .*\n/m,'');fs.writeFileSync(p,s);
" "$TD/legacy-task.md"
rtp step legacy-task --done 1 --quiet --tasks-dir "$TD" >/dev/null 2>&1
node -e "
const fs=require('fs');const s=fs.readFileSync(process.argv[1],'utf8');
const total=+/steps_total: (\d+)/.exec(s)[1];const cur=+/step_current: (\d+)/.exec(s)[1];
process.exit(cur>=1&&cur<=total?0:1);
" "$TD/legacy-task.md" && ok "step_current в пределах списка" || bad "step_current вне диапазона"

echo "F6: гигантская строка вывода не заливается в файл"
rtp verify legacy-task --run "node -e \"process.stdout.write('x'.repeat(200000))\"" --tasks-dir "$TD" >/dev/null 2>&1
node -e "
const fs=require('fs');const n=fs.statSync(process.argv[1]).size;
console.log('    размер файла задачи:',n,'байт');process.exit(n<20000?0:1);
" "$TD/legacy-task.md" && ok "файл задачи не раздут" || bad "весь вывод попал в файл"

echo "F1: выбор задачи по mtime, а не по алфавиту"
rtp new --title "Alpha" --type chore --pipeline minimal --reason r --tasks-dir "$TD" >/dev/null 2>&1
rtp new --title "Zulu" --type chore --pipeline minimal --reason r --tasks-dir "$TD" >/dev/null 2>&1
ZULU=$(rtp find zulu --tasks-dir "$TD" | head -1 | cut -f1)
rtp phase "$ZULU" --to impl --log "это моя задача" --tasks-dir "$TD" >/dev/null 2>&1
rtp status --tasks-dir "$TD" | head -1 | grep -q zulu && ok "выбрана последняя тронутая, не алфавитно первая" || bad "выбрана не та задача"

echo "F_artifact: rtp artifact вместо ручной правки YAML"
echo "# plan" > "$ROOT/docs/plans/p.md"
rtp artifact "$ZULU" --plan docs/plans/p.md --tasks-dir "$TD" >/dev/null 2>&1 \
  && grep -q "plan: docs/plans/p.md" "$TD/${ZULU}.md" && ok "artifacts.plan записан" || bad "artifacts.plan не записан"
rtp artifact "$ZULU" --plan docs/plans/NOPE.md --tasks-dir "$TD" >/dev/null 2>&1 && bad "принял несуществующий путь" || ok "несуществующий путь отвергнут"
rtp artifact "$ZULU" --pipeline full --tasks-dir "$TD" >/dev/null 2>&1 && ok "эскалация minimal → full" || bad "эскалация не сработала"
rtp artifact "$ZULU" --pipeline minimal --tasks-dir "$TD" >/dev/null 2>&1 && bad "разрешил сужение пресета" || ok "сужение пресета отвергнуто"
rtp validate "$ZULU" --tasks-dir "$TD" >/dev/null 2>&1 && ok "validate проходит после artifact" || bad "validate падает после artifact"

echo "F3: hook-stop скоупится текущим ходом"
mkdir -p "$ROOT/src"
cat > "$ROOT/t_old.jsonl" <<EOF
{"type":"user","message":{"content":"первый запрос"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$ROOT/src/a.ts"}}]}}
{"type":"user","message":{"content":"а теперь просто вопрос без правок"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"ответ"}]}}
EOF
cat > "$ROOT/t_now.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$ROOT/src/a.ts"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
EOF
echo "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$ROOT/t_old.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 0 ] && ok "read-only ход после старой правки не блокируется" || bad "блокирует ход без правок"
echo "{\"cwd\":\"$ROOT\",\"transcript_path\":\"$ROOT/t_now.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 2 ] && ok "правка в текущем ходе без rtp — блокируется" || bad "не блокирует реальный случай"

echo "F11: кавычки в title не утекают экранированными"
rtp new --title 'Fix: "quoted" thing' --type chore --pipeline minimal --reason r --tasks-dir "$TD" >/dev/null 2>&1
rtp list --tasks-dir "$TD" | grep -q '\\"' && bad "в выводе видны \\\"" || ok "кавычки распакованы"

echo ""
echo "итог: PASS=$PASS FAIL=$FAIL"

# ── Резолв задачи в хуках: по месту правок и по сессии, а не по cwd ────────
H=$(mktemp -d "${TMPDIR:-/tmp}/rtp-hooks.XXXXXX")
trap 'rm -rf "$ROOT" "$H"' EXIT
mkdir -p "$H/repo-a/docs/tasks" "$H/repo-b/docs/tasks" "$H/elsewhere/src"
# repo-a: активная задача ЧУЖОЙ сессии. repo-b: активная задача другого репозитория.
rtp new --title "Foreign A" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-a/docs/tasks" >/dev/null 2>&1
FOREIGN=$(rtp find foreign --tasks-dir "$H/repo-a/docs/tasks" | head -1 | cut -f1)
rtp new --title "Mine B" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
MINE=$(rtp find mine --tasks-dir "$H/repo-b/docs/tasks" | head -1 | cut -f1)

echo "H1: правки вне любого docs/tasks — хук молчит, чужую задачу не называет"
cat > "$H/t1.jsonl" <<EOF
{"type":"user","message":{"content":"почини скилл"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$H/elsewhere/src/a.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t1.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
RC=$?
[ $RC -eq 0 ] && ok "exit 0 при правках вне трекера" || bad "exit $RC вместо 0"
echo "$OUT" | grep -q "$FOREIGN" && bad "назвал чужую задачу repo-a" || ok "чужая задача не названа"

echo "H2: правки в чужом репозитории — общий текст, без имени чужой задачи"
cat > "$H/t2.jsonl" <<EOF
{"type":"user","message":{"content":"поправь repo-b"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t2.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
RC=$?
[ $RC -eq 2 ] && ok "exit 2 — правки в репозитории с трекером" || bad "exit $RC вместо 2"
echo "$OUT" | grep -q "$FOREIGN" && bad "назвал задачу из cwd-репозитория" || ok "задача из cwd не подставлена"
echo "$OUT" | grep -q "$MINE" && bad "назвал несвязанную задачу repo-b" || ok "несвязанная задача repo-b не названа"
echo "$OUT" | grep -q "repo-b" && ok "указал репозиторий правок" || bad "не указал репозиторий"

echo "H3: сессия называла свою задачу — хук указывает именно на неё"
cat > "$H/t3.jsonl" <<EOF
{"type":"user","message":{"content":"работаем"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"rtp phase $MINE --to impl --log start"}}]}}
{"type":"user","message":{"content":"продолжай"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t3.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$MINE" && ok "назвал задачу сессии" || bad "не нашёл задачу сессии"
echo "$OUT" | grep -q "$FOREIGN" && bad "приплёл чужую" || ok "чужая не приплетена"

echo "H4: precompact не трогает файл задачи, к которой сессия не прикасалась"
BEFORE=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t1.jsonl\"}" | node $RTP hook-precompact >/dev/null 2>&1
AFTER=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
[ "$BEFORE" = "$AFTER" ] && ok "чужой ## Handoff не переписан" || bad "precompact переписал чужую задачу"

echo ""
echo "итог хуков: PASS=$PASS FAIL=$FAIL"

# ── Находки code-review по резолву в хуках ────────────────────────────────
mkdir -p "$H/repo-b/src"

echo "H5: id из --ref не подменяет задачу сессии"
cat > "$H/t5.jsonl" <<EOF
{"type":"user","message":{"content":"работаем"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"rtp debt $MINE --close 'extract helper' --ref $FOREIGN"}}]}}
{"type":"user","message":{"content":"дальше"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t5.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$MINE" && ok "назвал задачу сессии" || bad "не нашёл задачу сессии"
echo "$OUT" | grep -q "$FOREIGN" && bad "подменил задачей из --ref" || ok "id из --ref проигнорирован"

echo "H6: id внутри текста --log не подменяет задачу"
cat > "$H/t6.jsonl" <<EOF
{"type":"user","message":{"content":"работаем"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"rtp phase $MINE --to impl --log 'дубль $FOREIGN'"}}]}}
{"type":"user","message":{"content":"дальше"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t6.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$FOREIGN" && bad "взял id из текста лога" || ok "id из текста лога проигнорирован"

echo "H7: task-notification не считается новым ходом"
cat > "$H/t7.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"u1","content":"ok"}]}}
{"type":"user","message":{"content":"<task-notification>агент завершил работу</task-notification>"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"готово"}]}}
EOF
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t7.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 2 ] && ok "правка до нотификации всё ещё учитывается" || bad "нотификация сбросила ход"

echo "H8: посторонняя команда со словом rtp не снимает блок"
for CMD in "git commit -m 'chore: rtp pipeline docs'" "grep -n scanTranscript ~/.claude/skills/run-task-pipeline/scripts/rtp.mjs" "rtp list --active"; do
  cat > "$H/t8.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Bash","input":{"command":"$CMD"}}]}}
EOF
  echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t8.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
  [ $? -eq 2 ] && ok "не обманулся: $CMD" || bad "снял блок по команде: $CMD"
done

echo "H9: отклонённая правка не считается правкой"
cat > "$H/t9.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"u1","is_error":true,"content":"The user doesn't want to take this action right now"}]}}
EOF
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t9.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 0 ] && ok "не требует трекера за отклонённую правку" || bad "блокирует за несостоявшуюся правку"

echo "H10: rtp в одном сообщении с правкой засчитывается"
cat > "$H/t10.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}},{"type":"tool_use","id":"u2","name":"Bash","input":{"command":"rtp phase $MINE --to impl --log done"}}]}}
EOF
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t10.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 0 ] && ok "параллельный батч tool_use засчитан" || bad "батч в одном сообщении не засчитан"

echo "H11: precompact не пишет в задачу, названную только через --ref"
BEFORE=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/t5.jsonl\"}" | node $RTP hook-precompact >/dev/null 2>&1
AFTER=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
[ "$BEFORE" = "$AFTER" ] && ok "чужой файл не тронут" || bad "precompact переписал задачу из --ref"

echo ""
echo "итог хуков-2: PASS=$PASS FAIL=$FAIL"

# ── Отчёт соседней ветки: id через переменную, done-задача, правки вне трекера ──
mkdir -p "$H/repo-b/src"
rtp new --title "Closed one" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
CLOSED=$(rtp find closed --tasks-dir "$H/repo-b/docs/tasks" | head -1 | cut -f1)
rtp phase "$CLOSED" --to done --log "закрыта" --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1

echo "V1: id, переданный через \$ID, виден хуку"
cat > "$H/v1.jsonl" <<EOF
{"type":"user","message":{"content":"работаем"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"ID=$MINE\nrtp phase \$ID --to impl --log start"}}]}}
{"type":"user","message":{"content":"дальше"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v1.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$MINE" && ok "\$ID резолвится" || bad "\$ID не резолвится"

echo "V2: форма \${ID} тоже видна"
cat > "$H/v2.jsonl" <<EOF
{"type":"user","message":{"content":"работаем"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"ID=$MINE; rtp verify \${ID} --record ok"}}]}}
{"type":"user","message":{"content":"дальше"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v2.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$MINE" && ok "\${ID} резолвится" || bad "\${ID} не резолвится"

echo "V3: свежая работа через переменную бьёт старое литеральное упоминание"
cat > "$H/v3.jsonl" <<EOF
{"type":"user","message":{"content":"закрой старую"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"rtp phase $CLOSED --to done --log закрыта"}}]}}
{"type":"user","message":{"content":"теперь новая задача"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Bash","input":{"command":"KY=$MINE\nrtp phase \$KY --to impl --log start"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u3","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v3.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$MINE" && ok "названа актуальная задача" || bad "названа не та задача"
echo "$OUT" | grep -q "$CLOSED" && bad "названа закрытая задача" || ok "закрытая не названа"

echo "V4: видна только done-задача — просит завести новую"
cat > "$H/v4.jsonl" <<EOF
{"type":"user","message":{"content":"почини"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"rtp phase $CLOSED --to done --log закрыта"}}]}}
{"type":"user","message":{"content":"а теперь другое"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Edit","input":{"file_path":"$H/repo-b/src/x.ts"}}]}}
EOF
OUT=$(echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v4.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "$CLOSED" && bad "предлагает дописать в закрытую задачу" || ok "закрытая задача не предлагается"
echo "$OUT" | grep -q "rtp new" && ok "просит завести новую" || bad "не предложил завести новую"

echo "V5: правка только в scratchpad — ход не блокируется"
mkdir -p "$H/scratch"
cat > "$H/v5.jsonl" <<EOF
{"type":"user","message":{"content":"запиши отчёт"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Bash","input":{"command":"ID=$MINE\nrtp phase \$ID --to impl --log start"}}]}}
{"type":"user","message":{"content":"теперь отчёт"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Write","input":{"file_path":"$H/scratch/report.md"}}]}}
EOF
echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v5.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop >/dev/null 2>&1
[ $? -eq 0 ] && ok "запись вне трекера не требует обновления задачи" || bad "блокирует за файл вне трекера"

echo "V6: id вне текущего хода — формулировка с оговоркой"
OUT=$(echo "{\"cwd\":\"$H/repo-b\",\"transcript_path\":\"$H/v1.jsonl\",\"stop_hook_active\":false}" | node $RTP hook-stop 2>&1)
echo "$OUT" | grep -q "Похоже, речь о" && ok "не утверждает, а предполагает" || bad "утверждает при догадке"

echo ""
echo "итог хуков-3: PASS=$PASS FAIL=$FAIL"

# ── Ревью 2026-09-07: cross-repo, rtp new, субагенты, SessionStart, границы хода, CLI UX ──
export H MINE FOREIGN CLOSED RTP
mkdir -p "$H/repo-c/docs/tasks" "$H/repo-c/src" "$H/repo-a/src"
# mk <file> <js-array>: JSONL из JS-выражения; E = process.env, хелперы user/asst/tu/res/edit/bash.
mk() {
  node -e '
const fs=require("fs");const E=process.env;
const user=t=>({type:"user",message:{content:t}});
const asst=(...parts)=>({type:"assistant",message:{content:parts}});
const tu=(id,name,input)=>({type:"tool_use",id,name,input});
const res=(id,content,x={})=>({type:"user",message:{content:[{type:"tool_result",tool_use_id:id,content,...(x.err?{is_error:true}:{})}]},...(x.tur?{toolUseResult:x.tur}:{})});
const edit=(id,f)=>tu(id,"Edit",{file_path:f});
const bash=(id,c)=>tu(id,"Bash",{command:c});
const arr=eval(process.argv[2]);
fs.writeFileSync(process.argv[1],arr.map(o=>JSON.stringify(o)).join("\n")+"\n");
' "$1" "$2"
}
stop()  { echo "{\"cwd\":\"$1\",\"transcript_path\":\"$2\",\"session_id\":\"$3\",\"stop_hook_active\":false}" | node "$RTP" hook-stop 2>&1; }
start() { echo "{\"cwd\":\"$1\",\"transcript_path\":\"$2\",\"session_id\":\"$3\",\"source\":\"$4\"}" | node "$RTP" hook-sessionstart 2>&1; }

echo "X1: задача в cwd-репо, правки в другом репо с трекером — хук называет задачу сессии"
mk "$H/x1.jsonl" '[user("работаем"),asst(bash("u1","rtp phase "+E.MINE+" --to impl --log s")),user("дальше"),asst(edit("u2",E.H+"/repo-c/src/y.ts"))]'
OUT=$(stop "$H/repo-b" "$H/x1.jsonl" x1); RC=$?
[ $RC -eq 2 ] && ok "exit 2" || bad "exit $RC вместо 2"
echo "$OUT" | grep -q "$MINE" && ok "названа задача сессии из cwd-каталога" || bad "задача сессии не найдена через cwd"
echo "$OUT" | grep -q "rtp new --title" && bad "просит завести новую при живой задаче" || ok "дубль не предлагается"

echo "X1b: read-only rtp show чужой задачи не делает её резолвимой через cwd"
mk "$H/x1b.jsonl" '[user("глянь"),asst(bash("u1","rtp show "+E.FOREIGN)),user("дальше"),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-a" "$H/x1b.jsonl" x1b)
echo "$OUT" | grep -q "$FOREIGN" && bad "назвал чужую задачу после rtp show" || ok "чужая после rtp show не названа"

echo "X1c: rtp show чужой задачи при правках в ТОМ ЖЕ трекере — не называет её, precompact не пишет"
mk "$H/x1c.jsonl" '[user("глянь"),asst(bash("u1","rtp show "+E.FOREIGN)),user("дальше"),asst(edit("u2",E.H+"/repo-a/src/a.ts"))]'
OUT=$(stop "$H/repo-a" "$H/x1c.jsonl" x1c)
echo "$OUT" | grep -q "$FOREIGN" && bad "названа осмотренная чужая задача" || ok "осмотренная задача не названа"
BEFORE=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/x1c.jsonl\",\"session_id\":\"x1c\"}" | node "$RTP" hook-precompact >/dev/null 2>&1
AFTER=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
[ "$BEFORE" = "$AFTER" ] && ok "precompact не переписал осмотренную задачу" || bad "precompact переписал Handoff после rtp show"

echo "X2: id из вывода rtp new (toolUseResult.stderr) виден хуку"
rtp new --title "Fresh one" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
NEWID=$(rtp find fresh --tasks-dir "$H/repo-b/docs/tasks" | head -1 | cut -f1); export NEWID
mk "$H/x2.jsonl" '[user("заведи"),asst(bash("u1","rtp new --title \"Fresh one\" --type chore --pipeline minimal")),res("u1","(вывод обрезан)",{tur:{stdout:E.H+"/repo-b/docs/tasks/"+E.NEWID+".md\n",stderr:"created task "+E.NEWID+" (pipeline=minimal, type=chore)\nnext: …\n"}}),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-b" "$H/x2.jsonl" x2); RC=$?
[ $RC -eq 2 ] && ok "exit 2" || bad "exit $RC вместо 2"
echo "$OUT" | grep -q "$NEWID" && ok "id из rtp new назван" || bad "id из rtp new не найден"
echo "$OUT" | grep -q "rtp new --title" && bad "просит завести дубль" || ok "дубль не предлагается"

echo "X2b: отклонённая правка чужого task-файла не называет задачу"
mk "$H/x2b.jsonl" '[user("правь"),asst(edit("u1",E.H+"/repo-a/docs/tasks/"+E.FOREIGN+".md")),res("u1","The user rejected this action",{err:true}),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-a" "$H/x2b.jsonl" x2b)
echo "$OUT" | grep -q "$FOREIGN" && bad "отклонённая правка task-файла назвала задачу" || ok "отклонённая правка task-файла не считается"

echo "X3: вывод rtp resume без паттерна (догадка по cwd) НЕ харвестится"
mk "$H/x3.jsonl" '[user("продолжи"),asst(bash("u1","rtp resume")),res("u1","Resuming `"+E.FOREIGN+"` from phase `triage`. Last log: x\nFile: "+E.H+"/repo-a/docs/tasks/"+E.FOREIGN+".md"),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-a" "$H/x3.jsonl" x3)
echo "$OUT" | grep -q "$FOREIGN" && bad "id из вывода resume подхвачен" || ok "вывод resume не харвестится"
BEFORE=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
echo "{\"cwd\":\"$H/repo-a\",\"transcript_path\":\"$H/x3.jsonl\",\"session_id\":\"x3\"}" | node "$RTP" hook-precompact >/dev/null 2>&1
AFTER=$(node -e "console.log(require('fs').statSync(process.argv[1]).mtimeMs)" "$H/repo-a/docs/tasks/$FOREIGN.md")
[ "$BEFORE" = "$AFTER" ] && ok "precompact не переписал чужой Handoff" || bad "precompact переписал задачу из вывода resume"

echo "X4: вывод rtp find/list не харвестится"
mk "$H/x4.jsonl" '[user("найди"),asst(bash("u1","rtp find foreign")),res("u1",E.FOREIGN+"\ttriage\tForeign A\n"),asst(edit("u2",E.H+"/repo-a/src/a.ts"))]'
OUT=$(stop "$H/repo-a" "$H/x4.jsonl" x4)
echo "$OUT" | grep -q "$FOREIGN" && bad "id из листинга подхвачен" || ok "листинг не харвестится"

echo "X5: правки субагента видны хуку"
mkdir -p "$H/x5/subagents"
mk "$H/x5/subagents/agent-sub1.jsonl" '[{type:"user",isSidechain:true,agentId:"sub1",message:{content:"правь"}},asst(edit("s1",E.H+"/repo-b/src/x.ts")),res("s1","ok")]'
mk "$H/x5.jsonl" '[user("работаем"),asst(bash("u1","rtp phase "+E.MINE+" --to impl --log s")),user("делегируй"),asst(tu("a1","Agent",{prompt:"…",subagent_type:"general-purpose"})),res("a1","готово",{tur:{agentId:"sub1"}})]'
OUT=$(stop "$H/repo-b" "$H/x5.jsonl" x5); RC=$?
[ $RC -eq 2 ] && ok "делегированная правка блокирует ход" || bad "exit $RC — правка субагента невидима"
echo "$OUT" | grep -q "$MINE" && ok "названа задача сессии" || bad "задача сессии не названа"

echo "X5b: rtp основного агента ПОСЛЕ возврата Agent снимает блок"
mk "$H/x5b.jsonl" '[user("делегируй"),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"sub1"}}),asst(bash("u2","rtp phase "+E.MINE+" --to impl --log done"))]'
stop "$H/repo-b" "$H/x5b.jsonl" x5 >/dev/null; [ $? -eq 0 ] && ok "exit 0" || bad "блокирует после rtp"

echo "X5c: rtp ДО вызова Agent, субагент правил → блок"
mk "$H/x5c.jsonl" '[user("делегируй"),asst(bash("u0","rtp phase "+E.MINE+" --to impl --log start")),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"sub1"}})]'
stop "$H/repo-b" "$H/x5c.jsonl" x5 >/dev/null; [ $? -eq 2 ] && ok "exit 2" || bad "rtp до Agent снял блок"

echo "X6: rtp субагента после правки основного агента виден; его Read/Bash правкой не считаются"
# Порядок внутри субагента: rtp, потом Read и git diff — считай хук Read правкой, ход бы заблокировался.
mk "$H/x5/subagents/agent-ro.jsonl" '[asst(bash("s1","rtp phase "+E.MINE+" --to impl --log s")),res("s1","ok"),asst(tu("s2","Read",{file_path:E.H+"/repo-b/src/x.ts"})),res("s2","…"),asst(bash("s3","git diff")),res("s3","")]'
mk "$H/x6.jsonl" '[user("правь и отметь"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"ro"}})]'
stop "$H/repo-b" "$H/x6.jsonl" x5 >/dev/null; [ $? -eq 0 ] && ok "rtp субагента снял блок, Read/Bash не правка" || bad "субагент не просканирован или Read счёлся правкой"

echo "X6b: файл субагента отсутствует — обход продолжается, без падения"
mk "$H/x6b.jsonl" '[user("ревью"),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"missing"}}),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-b" "$H/x6b.jsonl" x5); RC=$?
[ $RC -eq 2 ] && ok "правка после отсутствующего файла учтена" || bad "exit $RC — обход оборвался на отсутствующем файле"
echo "$OUT" | grep -qE '^ +at |Error' && bad "в stderr стектрейс" || ok "без стектрейса"
printf '{not json\n{"type":"assistant","message":{"content":[{"type":"tool_use","id":"s1","name":"Edit","input":{"file_path":"%s/repo-b/src/x.ts"}}]}}\n' "$H" > "$H/x5/subagents/agent-broken.jsonl"
mk "$H/x6c.jsonl" '[user("ревью"),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"broken"}})]'
stop "$H/repo-b" "$H/x6c.jsonl" x5 >/dev/null; [ $? -eq 2 ] && ok "битая строка пропущена, правка из целой учтена" || bad "битый файл сломал скан"

echo "X7: субагент правил и сам позвал rtp после правки → exit 0"
mk "$H/x5/subagents/agent-good.jsonl" '[asst(edit("s1",E.H+"/repo-b/src/x.ts")),res("s1","ok"),asst(bash("s2","rtp step "+E.MINE+" --done 1")),res("s2","ok")]'
mk "$H/x7.jsonl" '[user("делегируй"),asst(tu("a1","Agent",{prompt:"…"})),res("a1","готово",{tur:{agentId:"good"}})]'
stop "$H/repo-b" "$H/x7.jsonl" x5 >/dev/null; [ $? -eq 0 ] && ok "порядок правка→rtp внутри субагента учтён" || bad "дробный seq не работает"

echo "X9: батч [Agent, rtp phase] + правка после — дробный seq субагента не понижает lastCodeEdit"
mk "$H/x9.jsonl" '[user("делегируй и отметь"),asst(tu("a1","Agent",{prompt:"…"}),bash("u2","rtp phase "+E.MINE+" --to impl --log s")),res("u2","ok"),asst(edit("u3",E.H+"/repo-b/src/x.ts")),res("u3","ok"),res("a1","готово",{tur:{agentId:"sub1"}})]'
stop "$H/repo-b" "$H/x9.jsonl" x5 >/dev/null; [ $? -eq 2 ] && ok "правка основного агента после rtp не потеряна" || bad "Math.max: субагент понизил lastCodeEdit"

echo "X8: SessionStart на compact берёт задачу сессии из транскрипта"
OUT=$(start "$H/repo-a" "$H/t3.jsonl" t3 compact)
echo "$OUT" | grep -q "$MINE" && ok "названа задача сессии" || bad "задача сессии не названа"
echo "$OUT" | grep -q "$FOREIGN" && bad "названа чужая из cwd" || ok "чужая не названа"
echo "X8b: SessionStart на clear/startup — прежняя догадка по cwd с оговоркой"
for SRC in clear startup; do
  OUT=$(start "$H/repo-a" "$H/t3.jsonl" t3 $SRC)
  echo "$OUT" | grep -q "$MINE" && bad "$SRC: взял задачу из транскрипта" || ok "$SRC: транскрипт не используется"
  echo "$OUT" | grep -q "не факт, что твоя" && ok "$SRC: оговорка на месте" || bad "$SRC: оговорки нет"
done
echo "X8c: на compact строка про свежий Handoff — только при свежем Handoff"
# Своя задача: у MINE Handoff уже записан precompact-кейсом H11 выше.
rtp new --title "No handoff yet" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
NH=$(rtp find no-handoff --tasks-dir "$H/repo-b/docs/tasks" | head -1 | cut -f1); export NH
mk "$H/x8c.jsonl" '[user("работаем"),asst(bash("u1","rtp phase "+E.NH+" --to impl --log s")),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(start "$H/repo-b" "$H/x8c.jsonl" x8c compact)
echo "$OUT" | grep -q "$NH" && ok "названа задача сессии" || bad "задача сессии не названа"
echo "$OUT" | grep -q "перезаписан сегодня" && bad "заявлен свежий Handoff без него" || ok "без Handoff строки нет"
rtp handoff "$NH" --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
OUT=$(start "$H/repo-b" "$H/x8c.jsonl" x8c compact)
echo "$OUT" | grep -q "перезаписан сегодня" && ok "свежий Handoff отмечен" || bad "свежий Handoff не отмечен"

echo "X10: backslash-переносы в команде rtp"
mk "$H/x10.jsonl" '[user("долг"),asst(bash("u1","rtp debt \\\n  "+E.MINE+" \\\n  --add \"x\"")),user("дальше"),asst(edit("u2",E.H+"/repo-b/src/x.ts"))]'
OUT=$(stop "$H/repo-b" "$H/x10.jsonl" x10)
echo "$OUT" | grep -q "$MINE" && ok "id за переносом строки виден" || bad "id за backslash-переносом потерян"

echo "X11: служебная запись «Your previous response…» не начинает ход"
mk "$H/x11.jsonl" '[user("почини"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),user("[Your previous response had no visible output. Please continue and produce a user-visible response.]"),asst({type:"text",text:"готово"})]'
stop "$H/repo-b" "$H/x11.jsonl" x11 >/dev/null; [ $? -eq 2 ] && ok "правка до служебной записи учтена" || bad "служебная запись сбросила ход"

echo "X12: слэш-команда пользователя — новый ход"
mk "$H/x12.jsonl" '[user("почини"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),user("<command-message>rtp</command-message>\n<command-name>/rtp</command-name>"),asst({type:"text",text:"вот статус"})]'
stop "$H/repo-b" "$H/x12.jsonl" x12 >/dev/null; [ $? -eq 0 ] && ok "read-only слэш-ход не блокируется" || bad "слэш-команда не считается ходом"

echo "X13: красный rtp verify --run с записанным evidence снимает блок"
mk "$H/x13.jsonl" '[user("проверь"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(bash("u2","rtp verify "+E.MINE+" --run \"npm test\"")),res("u2","Exit code 1",{err:true,tur:{stdout:"FAIL src/x.test.ts\n",stderr:E.MINE+".md: verification recorded — exit 1 ❌\n"}})]'
stop "$H/repo-b" "$H/x13.jsonl" x13 >/dev/null; [ $? -eq 0 ] && ok "evidence записан — блок снят" || bad "красный verify не засчитан"
echo "X13b: rtp verify по несуществующему id блок не снимает"
mk "$H/x13b.jsonl" '[user("проверь"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(bash("u2","rtp verify nope --run \"npm test\"")),res("u2","Exit code 1",{err:true,tur:{stdout:"",stderr:"rtp verify: No task file matched: nope\n"}})]'
stop "$H/repo-b" "$H/x13b.jsonl" x13b >/dev/null; [ $? -eq 2 ] && ok "упавший rtp verify не засчитан" || bad "гейт слишком слабый"

echo "X14: rtp resume по закрытой задаче называет её, а не молчит"
OUT=$(rtp resume closed --tasks-dir "$H/repo-b/docs/tasks" 2>&1)
echo "$OUT" | grep -q "$CLOSED" && ok "закрытая задача показана" || bad "закрытая задача скрыта: $OUT"
echo "$OUT" | grep -q "no resumable" && bad "старый текст" || ok "текст объясняет, что совпали только закрытые"

echo "X14b: rtp resume без паттерна в каталоге только с закрытыми — без «undefined»"
mkdir -p "$H/repo-d/docs/tasks"
rtp new --title "Only closed" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-d/docs/tasks" >/dev/null 2>&1
OC=$(rtp find only-closed --tasks-dir "$H/repo-d/docs/tasks" | head -1 | cut -f1)
rtp phase "$OC" --to done --log x --tasks-dir "$H/repo-d/docs/tasks" >/dev/null 2>&1
OUT=$(rtp resume --tasks-dir "$H/repo-d/docs/tasks" 2>&1)
echo "$OUT" | grep -q "undefined" && bad "«undefined» в тексте" || ok "текст без undefined"
echo "$OUT" | grep -q "$OC" && ok "закрытая показана" || bad "закрытая не показана"

echo "X15: rtp validate без id и --all"
OUT=$(rtp validate --tasks-dir "$H/repo-b/docs/tasks" 2>&1); RC=$?
[ $RC -eq 0 ] && echo "$OUT" | grep -q "соседней сессии" && ok "без id — последняя активная с оговоркой" || bad "validate без id: rc=$RC"
printf -- '---\ntitle: no id here\nphase: impl\n---\n\n## Log\n\n- x\n' > "$H/repo-b/docs/tasks/2026-01-01-noid.md"
OUT=$(rtp validate --all --tasks-dir "$H/repo-b/docs/tasks" 2>&1)
rm -f "$H/repo-b/docs/tasks/2026-01-01-noid.md"
echo "$OUT" | grep -q "задач: ошибок в" && ok "--all печатает сводку" || bad "--all без сводки"
echo "$OUT" | grep -q "missing frontmatter: id" && ok "--all видит файл без id" || bad "--all пропустил файл без id"

echo "X16: rtp debt --list"
rtp debt "$MINE" --add "первый долг" --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
rtp debt "$MINE" --list --tasks-dir "$H/repo-b/docs/tasks" | grep -q "первый долг" && ok "--list показывает долг" || bad "--list пуст"
rtp debt "$MINE" --tasks-dir "$H/repo-b/docs/tasks" 2>&1 | grep -q -- "--list" && ok "ошибка подсказывает --list" || bad "подсказки нет"

echo "X17: today() — локальная дата под двумя TZ"
for Z in Pacific/Kiritimati Pacific/Midway; do
  J=$(TZ=$Z node -e "import('$LIB').then(m=>console.log(m.today()))"); S=$(TZ=$Z date +%F)
  [ "$J" = "$S" ] && ok "$Z: $J" || bad "$Z: today()=$J date=$S"
done

echo "X18: slug режется по границе слова"
rtp new --title "Проверка обрезки длинного заголовка по границе слова и не посреди слова точка" --type chore --pipeline minimal --reason r --tasks-dir "$H/repo-b/docs/tasks" >/dev/null 2>&1
LONG=$(rtp find proverka-obrezki --tasks-dir "$H/repo-b/docs/tasks" | head -1 | cut -f1)
case "$LONG" in *-slova-i-ne) ok "slug: $LONG" ;; *) bad "slug оборван посреди слова: $LONG" ;; esac

echo "X19: смешанный ход — правки в репо, rtp, затем запись вне трекера — не блокируется"
# Воспроизведение блока на самой сессии-авторе: последней шла правка файла памяти в ~/.claude.
mkdir -p "$H/outside/memory"
mk "$H/x19.jsonl" '[user("чини"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(bash("u2","ID="+E.MINE+"; rtp phase $ID --to impl --log s")),res("u2","ok"),asst(edit("u3",E.H+"/outside/memory/note.md")),res("u3","ok")]'
OUT=$(stop "$H/repo-b" "$H/x19.jsonl" x19); RC=$?
[ $RC -eq 0 ] && ok "запись вне трекера после rtp не считается правкой" || bad "exit $RC — правка вне трекера двигает lastCodeEdit"
# Контроль: та же запись вне трекера, но БЕЗ rtp после правки в репо — блок остаётся.
mk "$H/x19b.jsonl" '[user("чини"),asst(edit("u1",E.H+"/repo-b/src/x.ts")),res("u1","ok"),asst(edit("u3",E.H+"/outside/memory/note.md")),res("u3","ok")]'
stop "$H/repo-b" "$H/x19b.jsonl" x19b >/dev/null; [ $? -eq 2 ] && ok "правка в репо без rtp по-прежнему блокирует" || bad "гвард ослаблен: правка в репо не блокирует"

# ── D: секция долгов с хвостом в заголовке + rtp debt --rewrite ──────────────
# Фикстура повторяет форму реального трекера (docs/migration/modules/scheme-view.md):
# заголовок с хвостом, подсекции ###, разделитель ---, пункты после них, дальше ## Log.
DD="$ROOT/debt-tail"; mkdir -p "$DD"
# printf '%s\n' — не printf "$FM": строку формата, начинающуюся с ---, sh-printf
# принимает за опцию и пишет пустой файл, а кейсы «файл не тронут» зеленеют вхолостую.
fm() { printf '%s\n' '---' "id: $1" 'title: T' 'type: chore' 'pipeline: minimal' 'phase: impl' \
  'created: 2026-01-01' 'updated: 2026-01-01' '---' '' > "$DD/$1.md"; }
tail_task() { # $1 id — секция долгов с хвостом
  fm "$1"
  printf '%s\n' '## Debt (накапливается по мере миграции)' '' '### P1' '' \
    '- [ ] первый долг про alpha' '  продолжение первого долга' '  - [ ] вложенный пункт' '' '---' '' \
    '### P2' '' '- [ ] второй долг про beta' '- [ ] третий долг про beta' '' \
    '## Log' '' '- 2026-01-01: создано' >> "$DD/$1.md"
}
HDR='## Debt (накапливается по мере миграции)'

echo "D1: --close на заголовке с хвостом"
tail_task d1
rtp debt d1 --close "второй долг" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && grep -q '^- \[x\] второй долг про beta — закрыто 2026-09-13$' "$DD/d1.md" \
  && grep -q '^- \[ \] третий долг про beta$' "$DD/d1.md" \
  && ok "закрыт нужный пункт, сосед открыт" || bad "--close не видит секцию с хвостом"

echo "D2: --add на заголовке с хвостом"
tail_task d2
rtp debt d2 --add "новый долг gamma" --tasks-dir "$DD" >/dev/null 2>&1
[ "$(grep -c '^## Debt' "$DD/d2.md")" -eq 1 ] && ok "вторая секция ## Debt не создана" || bad "--add создал вторую секцию ## Debt"
grep -qxF "$HDR" "$DD/d2.md" && ok "строка заголовка байт в байт прежняя" || bad "заголовок с хвостом разрезан"
awk '/^## Debt/{s=1;next} /^## /{s=0} s' "$DD/d2.md" | grep -q '^- \[ \] новый долг gamma$' \
  && ok "новый пункт внутри секции долгов" || bad "новый пункт вне секции долгов"

echo "D3: --list и validate на заголовке с хвостом"
tail_task d3
[ "$(rtp debt d3 --list --tasks-dir "$DD" | grep -c '\[ \]')" -eq 4 ] && ok "--list видит 4 открытых" || bad "--list не видит секцию с хвостом"
awk '{print} /^## Debt/{print ""; print "- голый буллет в секции"}' "$DD/d3.md" > "$DD/d3.tmp" && mv "$DD/d3.tmp" "$DD/d3.md"
rtp validate d3 --tasks-dir "$DD" 2>&1 | grep -q 'plain bullet' && ok "validate проверяет секцию с хвостом" || bad "validate молча пропускает секцию с хвостом"

echo "D4: точный заголовок в приоритете перед хвостом"
fm d4
printf '%s\n' '## Debt (архив)' '' '- [ ] общий пункт в архиве' '' '## Debt' '' '- [ ] общий пункт в основной' >> "$DD/d4.md"
rtp debt d4 --close "общий пункт" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && grep -q '^- \[x\] общий пункт в основной' "$DD/d4.md" && grep -q '^- \[ \] общий пункт в архиве$' "$DD/d4.md" \
  && ok "закрыт пункт канонической секции" || bad "при двух секциях взята секция с хвостом"

echo "D5: ## Debts и ## Debt-кандидаты — не секции долгов"
fm d5
printf '%s\n' '## Debts' '' '- [ ] не долг раз' '' '## Debt-кандидаты, отклонённые сознательно' '' '- [ ] не долг два' >> "$DD/d5.md"
rtp debt d5 --list --tasks-dir "$DD" | grep -q 'долгов нет' && ok "--list их не видит" || bad "--list принял ## Debts/## Debt-кандидаты за долги"
cp "$DD/d5.md" "$DD/d5.orig"
rtp debt d5 --close "не долг" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d5.md" "$DD/d5.orig" && ok "--close отказывает и файл не тронут" || bad "--close закрыл пункт в чужой секции"

echo "D6: --rewrite happy path — файл целиком совпадает с эталоном"
tail_task d6
sed -e 's/^updated: 2026-01-01$/updated: 2026-09-13/' \
    -e 's/^- \[ \] второй долг про beta$/- [ ] второй долг, переписанный — переформулировано 2026-09-13/' "$DD/d6.md" > "$DD/d6.expected"
rtp debt d6 --rewrite "второй долг" --to "второй долг, переписанный" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && cmp -s "$DD/d6.md" "$DD/d6.expected" \
  && ok "заменена ровно одна строка, ## Log и соседи побайтно целы" || bad "--rewrite happy path: файл отличается от эталона"

echo "D7: --rewrite многострочного пункта"
tail_task d7
rtp debt d7 --rewrite "первый долг" --to "первый переписан" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1
grep -q '^- \[ \] первый переписан — переформулировано 2026-09-13$' "$DD/d7.md" && ! grep -q 'продолжение первого долга' "$DD/d7.md" \
  && ok "строка-продолжение заменена вместе с пунктом" || bad "хвост многострочного пункта приклеился к новому тексту"
grep -q '^  - \[ \] вложенный пункт$' "$DD/d7.md" && ok "вложенный пункт списка не проглочен" || bad "--rewrite съел вложенный пункт"

echo "D8: --rewrite отказы — файл побайтно не меняется"
tail_task d8; cp "$DD/d8.md" "$DD/d8.orig"
OUT=$(rtp debt d8 --rewrite "долг про beta" --to "x" --tasks-dir "$DD" 2>&1); RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && echo "$OUT" | grep -q 'третий долг' \
  && ok "два совпадения: ошибка с перечнем кандидатов" || bad "--rewrite при двух совпадениях переписал или не назвал кандидатов"
rtp debt d8 --rewrite "нет такого" --to "x" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "ноль совпадений: ошибка" || bad "--rewrite без совпадений не упал"
rtp debt d8 --rewrite "второй долг" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "без --to: ошибка" || bad "--rewrite без --to не упал"
rtp debt d8 --rewrite "второй долг" --to "$(printf 'строка\nвторая')" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "перевод строки в --to: ошибка" || bad "--to с переводом строки принят"
rtp debt d8 --rewrite "второй долг" --to "- [ ] уже с чекбоксом" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "чекбокс в начале --to: ошибка" || bad "--to с чекбоксом принят"
rtp debt d8 --close "второй долг" --rewrite "третий долг" --to "x" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "два режима сразу: ошибка" || bad "два режима сразу — один молча проигнорирован"
rtp debt d8 --rewrite "второй долг" --to "$(printf 'строка\rвторая')" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "CR в --to: ошибка" || bad "--to с CR принят"
rtp debt d8 --rewrite "второй долг" --to "   " --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "пустой --to: ошибка" || bad "--to из пробелов стёр формулировку"
rtp debt d8 --rewrite "второй долг" --to "* [ ] звёздочка" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "чекбокс со звёздочкой в --to: ошибка" || bad "--to '* [ ]' принят"
rtp debt d8 --close "второй долг" --to "x" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "--to без --rewrite: ошибка (опечатка не закрывает пункт)" || bad "--close --to молча закрыл пункт"
rtp debt d8 --rewrite "второй долг" --to "x" --ref "r" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "--ref без --close: ошибка" || bad "--ref с --rewrite молча проигнорирован"
rtp debt d8 --list --rewrite "второй долг" --to "x" --tasks-dir "$DD" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d8.md" "$DD/d8.orig" && ok "--list вместе с --rewrite: ошибка" || bad "--list проглотил --rewrite"

# Вторая фикстура: продолжение прозой, подсекция вплотную под пунктом, маркер, регистр.
edge_task() {
  fm "$1"
  printf '%s\n' '## Debt (хвост)' '' \
    '- [ ] пункт с прозой' '  + перенос прозы со старым утверждением' '  1. нумерованная деталь' '  - [ ] вложенный чекбокс' \
    '- [ ] пункт перед подсекцией' '### P3' \
    '- [ ] [LEGACY-AHEAD since=2026-01-01 commit=abc batch=1] маркированный пункт' \
    '- [ ] Регистр Не Должен Мешать' '' '## Log' '' '- 2026-01-01: создано' >> "$DD/$1.md"
}

echo "D9: --rewrite поглощает прозу-продолжение, но не вложенный чекбокс"
edge_task d9
awk '/^updated: /{print "updated: 2026-09-13"; next}
     /^- \[ \] пункт с прозой$/{print "- [ ] проза переписана — переформулировано 2026-09-13"; skip=1; next}
     skip && /^  [+1]/{next} {skip=0; print}' "$DD/d9.md" > "$DD/d9.expected"
rtp debt d9 --rewrite "пункт с прозой" --to "проза переписана" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && cmp -s "$DD/d9.md" "$DD/d9.expected" && ok "перенос '+ …' и '1. …' заменены, вложенный чекбокс цел" || bad "проза-продолжение осталась под новым текстом или съеден чекбокс"

echo "D10: подсекция вплотную под пунктом не поглощается"
edge_task d10
sed -e 's/^updated: 2026-01-01$/updated: 2026-09-13/' \
    -e 's/^- \[ \] пункт перед подсекцией$/- [ ] перед подсекцией — переформулировано 2026-09-13/' "$DD/d10.md" > "$DD/d10.expected"
rtp debt d10 --rewrite "пункт перед подсекцией" --to "перед подсекцией" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && cmp -s "$DD/d10.md" "$DD/d10.expected" && ok "### P3 и пункты после неё целы" || bad "--rewrite съел подсекцию без отступа"

echo "D11: маркер в начале пункта"
edge_task d11; cp "$DD/d11.md" "$DD/d11.orig"
OUT=$(rtp debt d11 --rewrite "маркированный пункт" --to "без маркера" --tasks-dir "$DD" 2>&1); RC=$?
[ $RC -ne 0 ] && cmp -s "$DD/d11.md" "$DD/d11.orig" && echo "$OUT" | grep -q 'LEGACY-AHEAD' \
  && ok "новый текст без маркера: ошибка с именем маркера" || bad "--rewrite молча срезал [LEGACY-AHEAD]"
rtp debt d11 --rewrite "маркированный пункт" --to "[LEGACY-AHEAD since=2026-01-01 commit=abc batch=1] с маркером — переформулировано 2026-01-01" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && grep -qx -- '- \[ \] \[LEGACY-AHEAD since=2026-01-01 commit=abc batch=1\] с маркером — переформулировано 2026-09-13' "$DD/d11.md" \
  && ok "маркер сохранён, суффикс не задвоен" || bad "маркер потерян или суффикс задвоен"

echo "D12: регистр паттерна, канонический ## Debt, rtp status"
edge_task d12
rtp debt d12 --rewrite "регистр не должен" --to "регистр учтён" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && grep -q '^- \[ \] регистр учтён — переформулировано 2026-09-13$' "$DD/d12.md" && ok "паттерн без учёта регистра" || bad "--rewrite чувствителен к регистру"
fm d13; printf '%s\n' '## Debt' '' '- [ ] канонический пункт' '- [ ] сосед' '' '## Log' '' '- 2026-01-01: x' >> "$DD/d13.md"
sed -e 's/^updated: 2026-01-01$/updated: 2026-09-13/' -e 's/^- \[ \] канонический пункт$/- [ ] переписан — переформулировано 2026-09-13/' "$DD/d13.md" > "$DD/d13.expected"
rtp debt d13 --rewrite "канонический" --to "переписан" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && cmp -s "$DD/d13.md" "$DD/d13.expected" && ok "--rewrite на каноническом ## Debt" || bad "--rewrite сломан на каноническом ## Debt"
tail_task d14
rtp status d14 --tasks-dir "$DD" 2>&1 | grep -q 'Открыто: 4 долг' && ok "rtp status считает долги секции с хвостом" || bad "status не видит секцию с хвостом"

echo "D14: пустая строка (даже из пробелов) заканчивает пункт — абзац с отступом после неё не поглощается"
# Строка из пробелов, а не '': у пустой строки отступ 0, её отсекает и проверка глубины,
# и без пробелов этот кейс не отличает «стоп на пустой строке» от его отсутствия.
fm d16; printf '%s\n' '## Debt' '' '- [ ] пункт до пустой строки' '    ' '  абзац с отступом после пустой строки' '- [ ] сосед' >> "$DD/d16.md"
sed -e 's/^updated: 2026-01-01$/updated: 2026-09-13/' \
    -e 's/^- \[ \] пункт до пустой строки$/- [ ] переписан — переформулировано 2026-09-13/' "$DD/d16.md" > "$DD/d16.expected"
rtp debt d16 --rewrite "пункт до пустой" --to "переписан" --date 2026-09-13 --tasks-dir "$DD" >/dev/null 2>&1 \
  && cmp -s "$DD/d16.md" "$DD/d16.expected" && ok "абзац за пустой строкой цел" || bad "--rewrite проглотил текст за пустой строкой"

echo "D13: новая секция встаёт перед секцией долгов с хвостом (порядок SECTION_ORDER)"
fm d15; printf '%s\n' '## Context' '' 'c' '' '## Debt (хвост)' '' '- [ ] один' >> "$DD/d15.md"
rtp phase d15 --to review --log "лог" --tasks-dir "$DD" >/dev/null 2>&1
[ "$(grep '^## ' "$DD/d15.md" | tr '\n' '|')" = "## Context|## Log|## Debt (хвост)|" ] \
  && ok "## Log создана до ## Debt (хвост)" || bad "## Log уехала за секцию долгов с хвостом: $(grep '^## ' "$DD/d15.md" | tr '\n' '|')"

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
# Страховочные кейсы: зелёные и до правки — .rtp.json не .md, его никто не должен подхватить.
rtp index --tasks-dir "$CT" >/dev/null 2>&1 && ! grep -q 'rtp.json' "$CT/index.md" \
  && ok "index игнорирует .rtp.json" || bad "index видит .rtp.json"
rtp validate --all --tasks-dir "$CT" 2>&1 | grep -q 'rtp.json' && bad "validate --all видит .rtp.json" || ok "validate --all игнорирует .rtp.json"
rtp find rtp --tasks-dir "$CT" 2>&1 | grep -q 'rtp.json' && bad "find матчит .rtp.json" || ok "find игнорирует .rtp.json"

echo "C4: Stop — правка docs/tasks/.rtp.json не требует обновления задачи"
mk "$H/c4.jsonl" '[user("настрой конфиг"),asst(edit("u1",E.H+"/repo-c/docs/tasks/.rtp.json"))]'
OUT=$(stop "$H/repo-c" "$H/c4.jsonl" c4); RC=$?
[ $RC -eq 0 ] && ok "ход с правкой .rtp.json не блокируется" || bad "exit $RC: $OUT"
# Положительный контроль: хук глотает исключения и выходит 0, так что без него C4 прошёл бы и на падении.
mk "$H/c4b.jsonl" '[user("правлю код"),asst(edit("u1",E.H+"/repo-c/src/y.ts"))]'
stop "$H/repo-c" "$H/c4b.jsonl" c4b >/dev/null; [ $? -eq 2 ] && ok "контроль: правка кода рядом блокируется" || bad "контроль: правка кода не блокируется"
mkdir -p "$H/repo-c/src/docs/tasks"
mk "$H/c4c.jsonl" '[user("правлю код"),asst(edit("u1",E.H+"/repo-c/src/docs/tasks/handler.ts"))]'
stop "$H/repo-c" "$H/c4c.jsonl" c4c >/dev/null; [ $? -eq 2 ] && ok "код в папке с именем docs/tasks — всё ещё код" || bad "исключение слишком широкое: handler.ts в docs/tasks не блокируется"

echo "C5: .rtp.json — BOM и переводы строк"
printf '\357\273\277%s' '{"verify":["make a"]}' > "$CFGD/.rtp.json"
[ "$(lc 2>/dev/null)" = '{"verify":[{"run":"make a"}],"reviewers":[]}' ] && ok "BOM не ломает JSON" || bad "BOM: $(lc 2>&1)"
printf '%s' '{"verify":["a\nb",{"record":"x\ny"},"ok"]}' > "$CFGD/.rtp.json"
[ "$(lc 2>/dev/null)" = '{"verify":[{"run":"ok"}],"reviewers":[]}' ] && ok "многострочные run/record отброшены" || bad "многострочные: $(lc 2>/dev/null)"
rm -f "$CFGD/.rtp.json"

echo ""
echo "итог (все секции): PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
