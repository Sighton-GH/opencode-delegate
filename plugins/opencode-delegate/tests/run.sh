#!/usr/bin/env bash
# Test suite for the opencode-delegate bin scripts.
#
#   bash plugins/opencode-delegate/tests/run.sh
#
# Offline and hermetic: a stub `opencode` stands in for the real binary, so
# nothing here needs a provider account, a network, or the user's opencode
# config. Every fixture repo is created under a path containing a space.
set -uo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$TESTS_DIR/../bin"
OC_TASK="$BIN_DIR/oc-task"
export TESTS_DIR OC_TASK

. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixture.sh"
trap fixture_cleanup EXIT

section "syntax"
for f in oc-task oc-models oc-undo; do
  out=$(bash -n "$BIN_DIR/$f" 2>&1)
  eq "bash -n $f is clean" "" "$out"
done

section "the suite is hermetic"
# A stub that cannot be executed sends bash on to the user's real opencode and
# the whole suite then measures the wrong binary, while still passing. Prove
# the stub is the one answering before trusting anything below.
new_fixture hermetic
resolved=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" command -v opencode)
eq "opencode resolves to the fixture's stub" "$FIX_BIN/opencode" "$resolved"
models=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" opencode models </dev/null 2>&1)
contains "the stub answers \`models\`" "opencode/stub-alternate-free" "$models"

section "helpers"
# Sourcing oc-task turns on `set -euo pipefail` in this shell; turn it back off
# immediately or the first failing assertion would abort the suite.
OC_TASK_SOURCE_ONLY=1 . "$OC_TASK"
set +eu +o pipefail
eq "fmt_duration 0"    "0m00s"  "$(fmt_duration 0)"
eq "fmt_duration 65"   "1m05s"  "$(fmt_duration 65)"
eq "fmt_duration 3600" "60m00s" "$(fmt_duration 3600)"

tmpspec=$(mktemp)
cat >"$tmpspec" <<'SPEC'
# Files
Create:
- `src/a.ts`
- `docs/`
Modify:
- `README.md`

# Tasks
Not a path section.
SPEC
tokens=$(spec_file_tokens "$tmpspec" | tr '\n' ' ')
contains "spec_file_tokens finds a created path" "src/a.ts" "$tokens"
contains "spec_file_tokens finds a modified path" "README.md" "$tokens"
contains "spec_file_tokens keeps the trailing slash on directories" "docs/" "$tokens"
rm -f "$tmpspec"

section "brief validation"
new_fixture validate
brief="$FIX_ROOT/brief.md"
write_brief "$brief"
run_oc --brief "$brief" --dry-run
eq "a complete brief passes --dry-run" 0 "$STATUS"
contains "--dry-run reports the model" "model:" "$OUT"
contains "--dry-run reports the worktree" "worktree:" "$OUT"

printf '# Objective\nonly this\n' >"$FIX_ROOT/thin.md"
run_oc --brief "$FIX_ROOT/thin.md" --dry-run
eq "a brief missing sections exits 2" 2 "$STATUS"
contains "it names a missing section" "missing section:" "$OUT"

run_oc --brief "$FIX_ROOT/nope.md" --dry-run
eq "a missing brief exits 2" 2 "$STATUS"

run_oc --brief "$brief" --role review --dry-run
eq "review briefs are judged by the review sections" 2 "$STATUS"
contains "review role names its own missing section" "Diff under review" "$OUT"

run_oc --brief "$brief" --model nonsense/not-a-model --dry-run
eq "a model outside the catalog is refused" 1 "$STATUS"
contains "the refusal lists live free models" "muse-spark-1.3-contributor-free" "$OUT"

run_oc --brief "$brief" --role sideways --dry-run
eq "an unknown role is refused" 1 "$STATUS"

section "session directory encoding (finding #1)"
lacks "the session POST does not interpolate the raw worktree path" \
  'directory=$worktree' "$(cat "$OC_TASK")"

new_fixture encode
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/encode
eq "a dispatch under a path with a space succeeds" 0 "$STATUS"
recorded=$(cat "$FIX_STUB_STATE/session-directory" 2>/dev/null || echo "")
eq "the server received the worktree path decoded and intact" \
  "$FIX_REPO/.oc-worktrees/oc/encode" "$recorded"

section "failed dispatch leaves nothing behind (finding #2)"
new_fixture faildispatch
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_SESSION_STATUS=500 run_oc --brief "$brief" --branch oc/failed
neq "a refused session-create is not reported as success" 0 "$STATUS"
contains "the failure says the worktree was removed" "removed" "$OUT"
eq "no worktree is left behind" "" "$(ls -A "$FIX_REPO/.oc-worktrees/oc" 2>/dev/null)"
branches=$(git -C "$FIX_REPO" branch --list 'oc/failed')
eq "no branch is left behind" "" "$branches"

new_fixture orphanwt
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
git -C "$FIX_REPO" worktree add -q -b oc/orphan "$FIX_REPO/.oc-worktrees/oc/orphan" HEAD
run_oc --brief "$brief" --branch oc/orphan --session new --dry-run
eq "--session new adopts a recordless worktree" 0 "$STATUS"
contains "it says the worktree already exists" "(existing)" "$OUT"

new_fixture nothingatall
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/ghost --session new --dry-run
neq "--session new still refuses when there is neither record nor worktree" 0 "$STATUS"
contains "and says so plainly" "no worktree" "$OUT"

section "idle watchdog (finding #4)"
new_fixture stall
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
started=$(date +%s)
OC_STUB_RUN_MODE=stall run_oc --brief "$brief" --branch oc/stall --idle-timeout 3
elapsed=$(( $(date +%s) - started ))
eq "a stalled run exits 6" 6 "$STATUS"
contains "the summary says it stalled" "stalled" "$OUT"
contains "it tells the operator to re-dispatch" "--session new" "$OUT"
[[ $elapsed -lt 60 ]] && ok "the watchdog fired instead of hanging (${elapsed}s)" \
  || no "the watchdog fired instead of hanging" "<60s" "${elapsed}s"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "the run record marks the session dead" "true" "$(jq -r .dead "$rec")"
eq "the record names the reason" "stalled" "$(jq -r .dead_reason "$rec")"

section "poisoned session (finding #3)"
new_fixture poison
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=poison run_oc --brief "$brief" --branch oc/poison
eq "an encrypted_content failure exits 4, not 1" 4 "$STATUS"
contains "the summary explains the session is unrecoverable" "not resumable" "$OUT"
contains "it tells the operator to re-dispatch" "--session new" "$OUT"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "the poisoned session is recorded dead" "true" "$(jq -r .dead "$rec")"
eq "with its own reason" "encrypted-content" "$(jq -r .dead_reason "$rec")"
run_oc --brief "$brief" --session ses_stub0000000000000000
eq "resuming a dead session is refused" 4 "$STATUS"
contains "the refusal names the reason" "encrypted-content" "$OUT"

section "rate limiting still classifies as 5 (no regression)"
new_fixture ratelimit
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=ratelimit run_oc --brief "$brief" --branch oc/rl
eq "a 429 still exits 5" 5 "$STATUS"

section "process group cleanup (finding #8)"
contains "the run is started as its own process group" 'set -m' "$(cat "$OC_TASK")"
contains "cleanup kills the run, not just the server" "kill_run" "$(cat "$OC_TASK")"

section "provisioning the worktree (findings #6, #7)"
new_fixture provision
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$FIX_REPO/inputs"
printf 'untracked input\n' >"$FIX_REPO/inputs/raw.md"
mkdir -p "$FIX_REPO/node_modules/.bin"
printf 'dep\n' >"$FIX_REPO/node_modules/dep.js"

run_oc --brief "$brief" --branch oc/prov --copy-untracked inputs
eq "the dispatch succeeds" 0 "$STATUS"
wt="$FIX_REPO/.oc-worktrees/oc/prov"
eq "the untracked input is in the worktree" "untracked input" "$(cat "$wt/inputs/raw.md" 2>/dev/null)"
[[ -d "$wt/node_modules" && ! -L "$wt/node_modules" ]] && ok "the worktree gets its own node_modules directory" \
  || no "the worktree gets its own node_modules directory" "a real directory" "$(ls -ld "$wt/node_modules" 2>&1)"
[[ -L "$wt/node_modules/dep.js" ]] && ok "its entries link to the base checkout's packages" \
  || no "its entries link to the base checkout's packages" "a symlink" "$(ls -ld "$wt/node_modules/dep.js" 2>&1)"
eq "the link resolves to the base checkout's node_modules" "dep" \
  "$(cat "$wt/node_modules/dep.js" 2>/dev/null | tr -d '\n')"

tracked=$(git -C "$wt" log --name-only --pretty=format: | sort -u | grep -E '^(inputs|node_modules)' || true)
eq "nothing provisioned was committed" "" "$tracked"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
contains "the record lists what was provisioned" "inputs" "$(jq -c .provisioned "$rec")"
contains "including node_modules" "node_modules" "$(jq -c .provisioned "$rec")"

excl_file="$(git -C "$wt" rev-parse --git-dir)/oc-provisioned.excludes"
grep -qxF "/inputs" "$excl_file" \
  && ok "the excludes entry for inputs is root-anchored" \
  || no "the excludes entry for inputs is root-anchored" "/inputs" "$(cat "$excl_file" 2>/dev/null)"
grep -qxF "inputs" "$excl_file" \
  && no "no bare basename pattern remains" "absent" "present" \
  || ok "no bare basename pattern remains"
mkdir -p "$wt/src/inputs"
printf 'nested\n' >"$wt/src/inputs/x"
( cd "$wt" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$excl_file" git check-ignore -q src/inputs/x ) \
  && no "a nested same-named path is not ignored" "not ignored" "ignored" \
  || ok "a nested same-named path is not ignored"
( cd "$wt" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0="$excl_file" git check-ignore -q inputs/raw.md ) \
  && ok "the provisioned path itself is ignored" \
  || no "the provisioned path itself is ignored" "ignored" "not ignored"

run_oc --brief "$brief" --branch oc/prov --session new
eq "a second run in the same worktree succeeds" 0 "$STATUS"
tracked=$(git -C "$wt" log --name-only --pretty=format: | sort -u | grep -E '^(inputs|node_modules)' || true)
eq "and still commits nothing provisioned" "" "$tracked"

printf 'reviewer scratch\n' >"$wt/reviewer-scratch.txt"
cat >"$FIX_ROOT/review.md" <<'BRIEF'
# Objective
Review it.

# Diff under review
stub-output.txt

# Required output
End your final message with a block in exactly this form:
## RESULT
Status: DONE
BRIEF
OC_STUB_RUN_MODE=nochange run_oc --brief "$FIX_ROOT/review.md" --role review --branch oc/prov --session new
eq "a review run in a provisioned worktree succeeds" 0 "$STATUS"
contains "the review run says it discarded changes" "changes discarded" "$OUT"
[[ -e "$wt/reviewer-scratch.txt" ]] \
  && no "the review run discards the reviewer's stray file" "absent" "present" \
  || ok "the review run discards the reviewer's stray file"
eq "the review run keeps the provisioned input" "untracked input" "$(cat "$wt/inputs/raw.md" 2>/dev/null)"
[[ -L "$wt/node_modules/dep.js" ]] && ok "the review run keeps the linked node_modules" \
  || no "the review run keeps the linked node_modules" "a symlink" "$(ls -ld "$wt/node_modules/dep.js" 2>&1)"

new_fixture noprovision
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$FIX_REPO/node_modules"
run_oc --brief "$brief" --branch oc/nolink --no-link-node-modules
eq "--no-link-node-modules dispatches fine" 0 "$STATUS"
[[ -e "$FIX_REPO/.oc-worktrees/oc/nolink/node_modules" ]] \
  && no "--no-link-node-modules leaves node_modules out" "absent" "present" \
  || ok "--no-link-node-modules leaves node_modules out"

new_fixture badcopy
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/badcopy --copy-untracked does/not/exist --dry-run
neq "--copy-untracked refuses a path that does not exist" 0 "$STATUS"
[[ -e "$FIX_REPO/.oc-worktrees/oc/badcopy" ]] \
  && no "the bad-path refusal creates no worktree" "absent" "present" \
  || ok "the bad-path refusal creates no worktree"

new_fixture plaindispatch
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/plain
eq "a dispatch with no provisioning flags still works" 0 "$STATUS"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "and records an empty provisioned list" "[]" "$(jq -c .provisioned "$rec")"

new_fixture subdir
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$FIX_REPO/inputs" "$FIX_REPO/sub"
printf 'untracked input\n' >"$FIX_REPO/inputs/raw.md"
sub_out=$(cd "$FIX_REPO/sub" && PATH="$FIX_BIN:$PATH" bash "$OC_TASK" --brief "$brief" --branch oc/sub --copy-untracked inputs 2>&1)
sub_status=$?
eq "a dispatch from a repo subdirectory succeeds" 0 "$sub_status"
contains "it reports the copy" "copied untracked inputs" "$sub_out"
eq "the input still lands in the worktree" "untracked input" "$(cat "$FIX_REPO/.oc-worktrees/oc/sub/inputs/raw.md" 2>/dev/null)"

run_oc --brief "$brief" --branch oc/abs --copy-untracked /etc/passwd
neq "an absolute --copy-untracked path is refused" 0 "$STATUS"
[[ -e "$FIX_REPO/.oc-worktrees/oc/abs" ]] \
  && no "refusing an absolute path creates no worktree" "absent" "present" \
  || ok "refusing an absolute path creates no worktree"

run_oc --brief "$brief" --branch oc/dotdot --copy-untracked ../x
neq "a --copy-untracked path with .. is refused" 0 "$STATUS"
[[ -e "$FIX_REPO/.oc-worktrees/oc/dotdot" ]] \
  && no "refusing a .. path creates no worktree" "absent" "present" \
  || ok "refusing a .. path creates no worktree"

run_oc --brief "$brief" --branch oc/tracked --copy-untracked seed.txt
neq "a tracked --copy-untracked path is refused" 0 "$STATUS"
contains "the refusal says the path is tracked" "tracked" "$OUT"
[[ -e "$FIX_REPO/.oc-worktrees/oc/tracked" ]] \
  && no "refusing a tracked path creates no worktree" "absent" "present" \
  || ok "refusing a tracked path creates no worktree"

new_fixture envcount
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$FIX_REPO/inputs"
printf 'untracked input\n' >"$FIX_REPO/inputs/raw.md"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.abbrev GIT_CONFIG_VALUE_0=12 run_oc --brief "$brief" --branch oc/env --copy-untracked inputs
eq "a dispatch with a preset GIT_CONFIG_COUNT succeeds" 0 "$STATUS"
eq "the provisioned input lands despite the preset env" "untracked input" \
  "$(cat "$FIX_REPO/.oc-worktrees/oc/env/inputs/raw.md" 2>/dev/null)"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
sha="$(jq -r .head_sha "$rec")"
eq "the operator's git config survives the dispatch" 12 "${#sha}"

section "merge modes (finding #10)"
# Each fixture gets its own branch that is ready to merge: the stub's default
# `ok` mode writes and commits stub-output.txt, which write_brief's # Files
# section names, so the audit passes.
merge_fixture() { # $1 = label, also the branch suffix
  new_fixture "$1"
  brief="$FIX_ROOT/brief.md"; write_brief "$brief"
  run_oc --brief "$brief" --branch "oc/$1"
  eq "[$1] setup dispatch succeeded" 0 "$STATUS"
}

merge_fixture custommsg
run_oc --merge --branch oc/custommsg --verified "true" -m "feat: my own subject"
eq "--merge -m succeeds" 0 "$STATUS"
eq "the caller's subject is used" "feat: my own subject" "$(git -C "$FIX_REPO" log -1 --format=%s)"
contains "the oc-task-run trailer survives for oc-undo" "oc-task-run:" "$(git -C "$FIX_REPO" log -1 --format=%B)"

merge_fixture longmsg
run_oc --merge --branch oc/longmsg --verified "true" --message "feat: the long form subject"
eq "--merge --message succeeds" 0 "$STATUS"
eq "the long-form subject is used" "feat: the long form subject" "$(git -C "$FIX_REPO" log -1 --format=%s)"
contains "the oc-task-run trailer survives for oc-undo" "oc-task-run:" "$(git -C "$FIX_REPO" log -1 --format=%B)"

merge_fixture nocommit
run_oc --merge --branch oc/nocommit --verified "true" --no-commit
eq "--merge --no-commit succeeds" 0 "$STATUS"
eq "it did not commit" "seed" "$(git -C "$FIX_REPO" log -1 --format=%s)"
contains "the change is staged for the caller" "stub-output.txt" "$(git -C "$FIX_REPO" diff --cached --name-only)"
contains "the summary tells the caller to commit" "commit" "$OUT"

merge_fixture squash
run_oc --merge --branch oc/squash --verified "true" --squash
eq "--merge --squash succeeds" 0 "$STATUS"
eq "it did not commit either" "seed" "$(git -C "$FIX_REPO" log -1 --format=%s)"
contains "the squashed change is staged" "stub-output.txt" "$(git -C "$FIX_REPO" diff --cached --name-only)"

merge_fixture plainmerge
run_oc --merge --branch oc/plainmerge --verified "true"
eq "a plain --merge still succeeds" 0 "$STATUS"
contains "and still reports the undo command" "oc-undo" "$OUT"
eq "and it is still a merge commit (two parents)" "2" \
  "$(git -C "$FIX_REPO" log -1 --format=%P | wc -w)"

section "merge refusals still hold (no regression)"
merge_fixture refusals
run_oc --merge --branch oc/refusals --no-commit
neq "--merge without --verified is refused" 0 "$STATUS"
contains "and says why" "verified" "$OUT"
printf 'dirt\n' >"$FIX_REPO/dirt.txt"
git -C "$FIX_REPO" add dirt.txt
run_oc --merge --branch oc/refusals --verified "true" --no-commit
neq "a dirty tree is still refused" 0 "$STATUS"
contains "and says why" "dirty" "$OUT"
git -C "$FIX_REPO" reset -q --hard

new_fixture noruns
run_oc --merge --branch oc/noruns --verified "true"
neq "--merge with no .oc-runs directory is refused" 0 "$STATUS"
contains "it gives the tool's own refusal, not a bash error" "merge refused" "$OUT"
contains "it names the missing run record" "no implement run record" "$OUT"

section "the merge audit unions every brief on the branch"
# The audit reads each run's spec in `sort -u` order over spec paths, so the
# brief filenames below are chosen deliberately: `a-brief.md` sorts first,
# the review brief `m-review-brief.md` sorts between, and `z-brief.md` — the
# only brief naming the file the stub actually writes — sorts last. A review
# brief has no `# Files` section at all, so if one can abort the union the
# audit never reaches `z-brief.md` and refuses a merge every brief covers.
new_fixture unionspecs
a_brief="$FIX_ROOT/a-brief.md"; write_brief "$a_brief"
# Name a file the branch never touches, so this brief alone cannot cover it.
sed -i 's|`stub-output.txt`|`placeholder.txt`|' "$a_brief"
run_oc --brief "$a_brief" --branch oc/unionspecs
eq "[unionspecs] first implement dispatch succeeded" 0 "$STATUS"

r_brief="$FIX_ROOT/m-review-brief.md"
cat >"$r_brief" <<'RB'
# Objective
Stub review.

# Diff under review
Nothing.

# Required output
End your final message with a block in exactly this form:
## RESULT
Status: DONE
RB
run_oc --brief "$r_brief" --role review --branch oc/unionspecs --session new
eq "[unionspecs] the review dispatch succeeded" 0 "$STATUS"

z_brief="$FIX_ROOT/z-brief.md"; write_brief "$z_brief"
run_oc --brief "$z_brief" --branch oc/unionspecs --session new
eq "[unionspecs] second implement dispatch succeeded" 0 "$STATUS"

run_oc --merge --branch oc/unionspecs --verified "true"
eq "a review brief between two implement briefs does not truncate the audit" 0 "$STATUS"
lacks "and stub-output.txt is not reported as unlisted" "not listed in the spec" "$OUT"

# The union above must not have become a blanket pass: a file that no brief on
# the branch names is still refused. This is the refusal the widened union
# could most easily have weakened.
new_fixture uncovered
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
sed -i 's|`stub-output.txt`|`placeholder.txt`|' "$brief"
run_oc --brief "$brief" --branch oc/uncovered
eq "[uncovered] setup dispatch succeeded" 0 "$STATUS"
run_oc --merge --branch oc/uncovered --verified "true"
neq "a file no brief names is still refused" 0 "$STATUS"
contains "and the refusal names the file" "stub-output.txt" "$OUT"

section "the new flags are merge-only"
new_fixture mergeonly
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/mo --no-commit --dry-run
neq "--no-commit outside --merge is refused" 0 "$STATUS"
contains "and says so" "--merge" "$OUT"

# ======================================================== v0.5.0 (field report v0.4.0)
# The watchdog polls every OC_TASK_POLL seconds; one keeps these tests quick.
export OC_TASK_POLL=1

section "v0.5 helpers"
OC_TASK_SOURCE_ONLY=1 . "$OC_TASK"
set +eu +o pipefail
tmpf=$(mktemp)
printf '%s\n' \
  'timestamp=x level=WARN message=hello' \
  'timestamp=x level=ERROR run=1 message="stream error" session.id=ses_a error.error="AI_APICallError: Rate limit exceeded. Please try again later."' \
  'timestamp=x level=ERROR message="share subscriber failed" cause="noise"' \
  'timestamp=x level=ERROR message=process session.id=ses_a error="Failed to execute statement" stack="Error"' >"$tmpf"
printf 'timestamp=x level=ERROR message="stream error" error.error="half a li' >>"$tmpf"
serrs=$(serve_errors "$tmpf")
contains "serve_errors reads a provider's stream error" "Rate limit exceeded" "$serrs"
contains "serve_errors reads opencode's own errors" "Failed to execute statement" "$serrs"
lacks "serve_errors drops share-subscriber noise" "noise" "$serrs"
lacks "serve_errors leaves a half-written last line for the next look" "half a li" "$serrs"

printf '%s\n' '{"type":"text","part":{"id":"a","text":"first"}}' 'plain stderr noise' \
  '{"type":"error","error":{"name":"APIError","data":{"message":"after the noise"}}}' \
  '{"type":"text","part":{"id":"b","text":"## RESULT\nStatus: DONE"}}' >"$tmpf"
contains "run_text reads past a non-JSON line" "Status: DONE" "$(run_text "$tmpf")"
contains "run_errors reads past a non-JSON line" "after the noise" "$(run_errors "$tmpf")"
eq "model_event_count ignores errors" "2" "$(model_event_count "$tmpf")"
eq "limit_reset finds a reset time" "Resets in 3h 51m" "$(limit_reset 'AI_APICallError: Usage limit reached. Resets in 3h 51m.')"
eq "dedouble_result collapses a block whose every line is doubled" \
  "$(printf '## RESULT\nStatus: DONE\nFiles changed: a')" \
  "$(printf '## RESULT\nStatus: DONE\nStatus: DONE\nFiles changed: a\nFiles changed: a\n' | dedouble_result)"
eq "dedouble_result leaves an ordinary block alone" \
  "$(printf '## RESULT\nStatus: DONE\n- none\n- none\nFiles changed: a')" \
  "$(printf '## RESULT\nStatus: DONE\n- none\n- none\nFiles changed: a\n' | dedouble_result)"

cat >"$tmpf" <<'SPEC'
# Files
- `packages/dashboard/src/pages/assistant.tsx`, `assistant-skills.tsx`, `./docs/x.md`
SPEC
tokens=$(spec_file_tokens "$tmpf" | tr '\n' ' ')
contains "a bare filename resolves against the previous path's directory" "packages/dashboard/src/pages/assistant-skills.tsx" "$tokens"
contains "a leading ./ is dropped" "docs/x.md" "$tokens"
rm -f "$tmpf"

section "help and argument checks"
new_fixture help
run_oc --help
eq "--help exits 0" 0 "$STATUS"
for flag in --base --continue-from --install --no-link-node-modules --link-node-modules --idle-timeout --copy-untracked; do
  contains "--help lists $flag" "$flag" "$OUT"
done
contains "--help lists exit 7" "7  opencode's local database" "$OUT"
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --session ses_nope
eq "resuming a session with no record exits 1, not 0 (finding #16)" 1 "$STATUS"
contains "and says how to start fresh" "--session new" "$OUT"
OC_STUB_MODELS_PAD=20000 run_oc --brief "$brief" --dry-run
eq "a long catalog does not make the listed model look missing" 0 "$STATUS"

section "brief validation names every missing section (evaluation D44)"
printf '# Objective\nonly this\n' >"$FIX_ROOT/thin.md"
run_oc --brief "$FIX_ROOT/thin.md" --dry-run
contains "it names # Files" "missing section: # Files" "$OUT"
contains "and # Verification in the same refusal" "missing section: # Verification" "$OUT"

section "the record exists from dispatch; a killed wrapper still reports (#1, #4, #16, #22)"
new_fixture killed
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
( cd "$FIX_REPO" && OC_STUB_RUN_MODE=stall PATH="$FIX_BIN:$PATH" exec bash "$OC_TASK" --brief "$brief" --branch oc/killed --idle-timeout 120 >"$FIX_ROOT/bg.out" 2>&1 ) &
bg=$!
rec=""
for _ in $(seq 1 100); do rec=$(ls "$FIX_REPO/.oc-runs"/*.json 2>/dev/null | tail -1); [[ -n "$rec" ]] && break; sleep 0.1; done
eq "the record exists while the run is live" "running" "$(jq -r .state "$rec" 2>/dev/null)"
eq "and already holds the session id" "ses_stub0000000000000000" "$(jq -r .session_id "$rec" 2>/dev/null)"
run_oc --brief "$brief" --branch oc/killed --session new --dry-run
neq "a second run in a live worktree is refused" 0 "$STATUS"
contains "the refusal says another run is live" "another oc-task run is live" "$OUT"
OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/beside
contains "a dispatch beside a live run on the same model warns" "already use opencode/big-pickle" "$OUT"
kill -TERM "$bg"; wait "$bg" && bg_status=0 || bg_status=$?
eq "SIGTERM exits 143" 143 "$bg_status"
contains "the killed run still prints its summary" "killed by SIGTERM" "$(cat "$FIX_ROOT/bg.out")"
eq "the record is final" "done" "$(jq -r .state "$rec")"
eq "and holds the exit code" "143" "$(jq -r .exit_code "$rec")"
[[ -s "${rec%.json}.summary" ]] && ok "the summary is saved beside the record" \
  || no "the summary is saved beside the record" "a .summary file" "none"
left=$(ps -eo args= | grep -F -- "--dir $FIX_REPO/.oc-worktrees/oc/killed" | grep -v grep || true)
eq "no opencode process outlives the killed wrapper" "" "$left"
run_oc --brief "$brief" --branch oc/killed --session new --dry-run
eq "the lock goes with the wrapper" 0 "$STATUS"
run_oc --brief "$brief" --session ses_stub0000000000000000 --dry-run
eq "the killed run's session can be resumed from its record" 0 "$STATUS"

section "provider errors in the server's log (#1, #3, #12, #15, #19, #24)"
new_fixture srvrate
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
started=$(date +%s)
OC_STUB_RUN_MODE=stall OC_DELEGATE_RATE_LIMIT_GRACE=2 \
  OC_STUB_SERVE_ERROR="AI_APICallError: Error from provider (Console): Rate limit exceeded. Please try again later." \
  run_oc --brief "$brief" --branch oc/srvrate --idle-timeout 120
elapsed=$(( $(date +%s) - started ))
eq "a rate limit in the server log exits 5" 5 "$STATUS"
contains "the summary carries the provider's message" "Rate limit exceeded" "$OUT"
lacks "and no internal-error line" "internal error" "$OUT"
[[ $elapsed -lt 30 ]] && ok "within the grace, not the idle timeout (${elapsed}s)" \
  || no "within the grace, not the idle timeout" "<30s" "${elapsed}s"
contains "--print-logs is how the server reports it" "--print-logs" "$(cat "$FIX_STUB_STATE/serve-args")"
[[ -s "$(ls "$FIX_REPO/.oc-runs"/*.serve.log | tail -1)" ]] && ok "the server log is kept with the run" \
  || no "the server log is kept with the run" "a .serve.log" "none"

new_fixture srvusage
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
started=$(date +%s)
OC_STUB_RUN_MODE=stall OC_DELEGATE_RATE_LIMIT_GRACE=600 \
  OC_STUB_SERVE_ERROR="AI_APICallError: Usage limit reached. Resets in 3h 51m." \
  run_oc --brief "$brief" --branch oc/srvusage --idle-timeout 120
elapsed=$(( $(date +%s) - started ))
eq "a usage limit exits 5" 5 "$STATUS"
contains "and prints when it resets" "reset:    Resets in 3h 51m" "$OUT"
[[ $elapsed -lt 20 ]] && ok "at once, without waiting out the grace (${elapsed}s)" \
  || no "at once, without waiting out the grace" "<20s" "${elapsed}s"

new_fixture srvrecover
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=slowok OC_STUB_RUN_PAUSE=4 OC_DELEGATE_RATE_LIMIT_GRACE=15 \
  OC_STUB_SERVE_ERROR="AI_APICallError: Rate limit exceeded. Please retry after a brief wait." \
  run_oc --brief "$brief" --branch oc/srvrecover --idle-timeout 120
eq "a run that recovers from a rate limit still succeeds" 0 "$STATUS"
contains "and the recovered error is still shown" "server: AI_APICallError" "$OUT"

new_fixture stallrate
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=stall OC_DELEGATE_RATE_LIMIT_GRACE=600 \
  OC_STUB_SERVE_ERROR="AI_APICallError: Rate limit exceeded." \
  run_oc --brief "$brief" --branch oc/stallrate --idle-timeout 3
eq "a stall with a rate limit behind it exits 5, not 6" 5 "$STATUS"
contains "and says the run went quiet after it" "went quiet" "$OUT"

new_fixture silent
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=silent run_oc --brief "$brief" --branch oc/silent --idle-timeout 3
eq "a run with no model output at all exits 5 (#39, #41)" 5 "$STATUS"
contains "and says so" "no model output at all" "$OUT"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "its session is not marked dead" "false" "$(jq -r .dead "$rec")"

new_fixture titlerate
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=stall OC_DELEGATE_RATE_LIMIT_GRACE=2 OC_STUB_SERVE_ERROR_SMALL=1 \
  OC_STUB_SERVE_ERROR="AI_APICallError: Rate limit exceeded." \
  run_oc --brief "$brief" --branch oc/titlerate --idle-timeout 8
eq "a rate limit on the title agent does not end the run as 5" 6 "$STATUS"

section "errors in the run's own stream (#14, #21, D41)"
for mode in usage dbbusy; do
  new_fixture "rl-$mode"
  brief="$FIX_ROOT/brief.md"; write_brief "$brief"
  OC_STUB_RUN_MODE=$mode run_oc --brief "$brief" --branch "oc/$mode"
  case $mode in
    usage)  eq "a usage limit in the run log exits 5" 5 "$STATUS"
            contains "with its reset time" "Resets in 3h 51m" "$OUT" ;;
    dbbusy) eq "opencode's busy database exits 7" 7 "$STATUS"
            contains "and names the cause" "database was busy" "$OUT" ;;
  esac
done

new_fixture errhang
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
started=$(date +%s)
OC_STUB_RUN_MODE=errhang OC_DELEGATE_ERROR_GRACE=2 run_oc --brief "$brief" --branch oc/errhang --idle-timeout 120
elapsed=$(( $(date +%s) - started ))
eq "an error event followed by silence exits 1" 1 "$STATUS"
contains "it names the error" "ECONNRESET" "$OUT"
[[ $elapsed -lt 30 ]] && ok "after the error grace, not the idle timeout (${elapsed}s)" \
  || no "after the error grace, not the idle timeout" "<30s" "${elapsed}s"

new_fixture noisy
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=noisy run_oc --brief "$brief" --branch oc/noisy
eq "a stderr line in the log does not hide the RESULT" 0 "$STATUS"
contains "the RESULT block is found" "Status: DONE" "$OUT"

new_fixture dup
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=dup run_oc --brief "$brief" --branch oc/dup
eq "a doubled RESULT block is printed once (#9)" 1 "$(grep -c '^Status: DONE' <<<"$OUT")"

new_fixture needsctx
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=needsctx run_oc --brief "$brief" --branch oc/needsctx
eq "a NEEDS_CONTEXT with no heading still exits 3" 3 "$STATUS"
contains "the exit line names NEEDS_CONTEXT (#20)" "stopped with NEEDS_CONTEXT" "$OUT"
contains "and shows the model's question" "which config file" "$OUT"
lacks "a normal non-zero exit prints no internal-error line" "internal error" "$OUT"

section "the collect phase reports instead of dying (#27, #29)"
new_fixture stage
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=stage run_oc --brief "$brief" --branch oc/stage
contains "a failed checkpoint is reported" "checkpoint failed (git add)" "$OUT"
contains "and the summary is still printed" "## RESULT" "$OUT"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "and the record is still written" "done" "$(jq -r .state "$rec")"

new_fixture ctrl
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=ctrl run_oc --brief "$brief" --branch oc/ctrl
contains "a diff that adds raw control bytes is flagged (#17)" "gained raw control bytes" "$OUT"

section "the stash is off limits (#13)"
new_fixture stash
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/stash
body=$(tail -1 "$FIX_STUB_STATE/session-body")
eq "the blanket allow comes first" "allow" "$(jq -r '.permission[0].action' <<<"$body")"
eq "git stash is denied after it, so the denial wins" "deny" \
  "$(jq -r '.permission[] | select(.pattern == "*git stash*") | .action' <<<"$body")"
eq "git -C <dir> stash is denied too" "deny" \
  "$(jq -r '.permission[] | select(.pattern == "*git -C * stash*") | .action' <<<"$body")"

section "--base and existing branches (#11, 2026-10-01, 2026-10-10)"
new_fixture base
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
cur=$(git -C "$FIX_REPO" symbolic-ref --short HEAD)
git -C "$FIX_REPO" switch -q -c side
printf 'side\n' >"$FIX_REPO/side.txt"; git -C "$FIX_REPO" add side.txt; git -C "$FIX_REPO" commit -q -m side
side_sha=$(git -C "$FIX_REPO" rev-parse side)
git -C "$FIX_REPO" switch -q "$cur"
run_oc --brief "$brief" --branch oc/based --base side
eq "a run forked from --base succeeds" 0 "$STATUS"
eq "the worktree starts from that ref" "side" "$(cat "$FIX_REPO/.oc-worktrees/oc/based/side.txt" 2>/dev/null)"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
eq "the record's base is the ref" "$side_sha" "$(jq -r .base_sha "$rec")"
eq "and it still merges into the checkout's branch" "$cur" "$(jq -r .base_branch "$rec")"
diffout=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$OC_TASK" --branch-diff --branch oc/based 2>/dev/null) || true
lacks "the branch diff leaves out the base's own commits" "side.txt" "$(cat "$diffout" 2>/dev/null)"
contains "and shows the run's" "stub-output.txt" "$(cat "$diffout" 2>/dev/null)"
run_oc --brief "$brief" --branch oc/x --base nope-not-a-ref
neq "an unknown --base is refused" 0 "$STATUS"
run_oc --brief "$brief" --base side --session new --branch oc/based
neq "--base with --session is refused" 0 "$STATUS"

new_fixture adopt
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
cur=$(git -C "$FIX_REPO" symbolic-ref --short HEAD)
git -C "$FIX_REPO" switch -q -c tool/branch
printf 'other\n' >"$FIX_REPO/other.txt"; git -C "$FIX_REPO" add other.txt; git -C "$FIX_REPO" commit -q -m other
git -C "$FIX_REPO" switch -q "$cur"
run_oc --brief "$brief" --branch tool/branch
neq "a fresh dispatch on an existing branch is still refused" 0 "$STATUS"
contains "and points at --session new" "--session new --branch tool/branch" "$OUT"
run_oc --brief "$brief" --branch tool/branch --session new --dry-run
eq "--session new adopts an existing branch that has no worktree" 0 "$STATUS"
contains "and says it will make one" "new, for the existing branch" "$OUT"
run_oc --brief "$brief" --branch tool/branch --session new
eq "the adopted branch runs" 0 "$STATUS"
eq "in a worktree of that branch" "other" "$(cat "$FIX_REPO/.oc-worktrees/tool/branch/other.txt" 2>/dev/null)"

new_fixture regone
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/gone
eq "[regone] setup dispatch succeeded" 0 "$STATUS"
rm -rf "$FIX_REPO/.oc-worktrees/oc/gone"
OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/gone --session new
eq "a worktree deleted by hand is re-created for its surviving branch" 3 "$STATUS"
[[ -d "$FIX_REPO/.oc-worktrees/oc/gone" ]] && ok "and the worktree is back" \
  || no "and the worktree is back" "a worktree" "none"

new_fixture stalelock
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/stale
printf '999999 dead-run\n' >"$(git -C "$FIX_REPO/.oc-worktrees/oc/stale" rev-parse --git-dir)/oc-task.lock"
OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/stale --session new
eq "a lock left by a dead wrapper is replaced" 3 "$STATUS"

new_fixture adoptfail
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
git -C "$FIX_REPO" branch keep/me
OC_STUB_SESSION_STATUS=500 run_oc --brief "$brief" --branch keep/me --session new
neq "a failed dispatch on an adopted branch fails" 0 "$STATUS"
git -C "$FIX_REPO" show-ref --verify --quiet refs/heads/keep/me \
  && ok "and never deletes the branch it did not create" \
  || no "and never deletes the branch it did not create" "branch kept" "branch deleted"

section "continuation briefs (#6, #23)"
new_fixture cont
parent="$FIX_ROOT/parent.md"; write_brief "$parent"
cont="$FIX_ROOT/cont.md"
printf '# Objective\nContinue from step 2.\n\n# Tasks\n2. Finish.\n' >"$cont"
run_oc --brief "$cont" --branch oc/cont --dry-run
eq "a short continuation brief alone is rejected" 2 "$STATUS"
run_oc --brief "$cont" --continue-from "$parent" --branch oc/cont --dry-run
eq "with --continue-from it is accepted" 0 "$STATUS"
contains "the dry run names the parent" "parent:" "$OUT"
run_oc --brief "$cont" --continue-from "$parent" --branch oc/cont
eq "the continuation dispatches" 0 "$STATUS"
prompt=$(cat "$FIX_STUB_STATE/last-prompt" 2>/dev/null) || true
contains "the model gets the continuation" "Continue from step 2." "$prompt"
contains "and the parent below it" "Parent brief (for reference)" "$prompt"
contains "with the parent's sections" "# Verification" "$prompt"
run_oc --merge --branch oc/cont --verified "true"
eq "the merge audit accepts files the parent brief names" 0 "$STATUS"

new_fixture runningrec
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/rr
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
jq '.state = "running" | .exit_code = null' "$rec" >"$rec.new" && mv "$rec.new" "$rec"
run_oc --merge --branch oc/rr --verified "true"
neq "a run that never finished is not merged" 0 "$STATUS"
contains "and the refusal says why" "never finished" "$OUT"

section "node_modules: its own directory, workspace-aware (#7, #37, D52, D55)"
new_fixture workspace
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$FIX_REPO/packages/pkg" "$FIX_REPO/packages/app"
printf '{"name":"@ws/pkg"}\n' >"$FIX_REPO/packages/pkg/package.json"
printf '{"name":"app"}\n' >"$FIX_REPO/packages/app/package.json"
printf 'node_modules/\n' >"$FIX_REPO/.gitignore"
git -C "$FIX_REPO" add -A; git -C "$FIX_REPO" commit -q -m workspace
mkdir -p "$FIX_REPO/node_modules/@ws" "$FIX_REPO/node_modules/.bin" "$FIX_REPO/node_modules/dep" \
  "$FIX_REPO/node_modules/.cache/tool" "$FIX_REPO/packages/app/node_modules/nested"
printf 'dep\n' >"$FIX_REPO/node_modules/dep/index.js"
ln -s ../../packages/pkg "$FIX_REPO/node_modules/@ws/pkg"
ln -s ../dep/index.js "$FIX_REPO/node_modules/.bin/dep"
printf 'nested\n' >"$FIX_REPO/packages/app/node_modules/nested/index.js"
run_oc --brief "$brief" --branch oc/ws
eq "a workspace dispatch succeeds" 0 "$STATUS"
wt="$FIX_REPO/.oc-worktrees/oc/ws"
eq "a workspace package resolves to the worktree's own copy" "$wt/packages/pkg" "$(readlink -f "$wt/node_modules/@ws/pkg")"
eq "a third-party package resolves to the base checkout" "$FIX_REPO/node_modules/dep" "$(readlink -f "$wt/node_modules/dep")"
eq ".bin entries resolve" "dep" "$(cat "$wt/node_modules/.bin/dep" 2>/dev/null)"
eq "a nested workspace install is linked too" "nested" "$(cat "$wt/packages/app/node_modules/nested/index.js" 2>/dev/null)"
[[ -e "$wt/node_modules/.cache" ]] && no "tool caches stay per checkout" "absent" "present" \
  || ok "tool caches stay per checkout"
tracked=$(git -C "$wt" log --name-only --pretty=format: | sort -u | grep -E 'node_modules' || true)
eq "nothing linked was committed" "" "$tracked"
# What `npm ci` does first: empty node_modules through whatever path it has.
find "$wt/node_modules/" "$wt/packages/app/node_modules/" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
eq "emptying the worktree's node_modules leaves the base checkout's intact" "dep" "$(cat "$FIX_REPO/node_modules/dep/index.js" 2>/dev/null)"
eq "and its nested install" "nested" "$(cat "$FIX_REPO/packages/app/node_modules/nested/index.js" 2>/dev/null)"

new_fixture install
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
printf '{"name":"x"}\n' >"$FIX_REPO/package.json"
printf '{"name":"x","lockfileVersion":3}\n' >"$FIX_REPO/package-lock.json"
printf 'node_modules/\n' >"$FIX_REPO/.gitignore"
git -C "$FIX_REPO" add -A; git -C "$FIX_REPO" commit -q -m npm
cat >"$FIX_BIN/npm" <<'NPM'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$OC_STUB_STATE/npm-args"
mkdir -p node_modules/installed && printf 'here\n' >node_modules/installed/marker
NPM
chmod +x "$FIX_BIN/npm"
run_oc --brief "$brief" --branch oc/inst --install
eq "--install dispatches" 0 "$STATUS"
contains "it runs the lockfile's clean install" "ci" "$(cat "$FIX_STUB_STATE/npm-args" 2>/dev/null)"
eq "in the worktree" "here" "$(cat "$FIX_REPO/.oc-worktrees/oc/inst/node_modules/installed/marker" 2>/dev/null)"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
contains "and records node_modules as provisioned" "node_modules" "$(jq -c .provisioned "$rec")"

new_fixture installsig
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
printf '{"name":"x"}\n' >"$FIX_REPO/package.json"
printf '{"name":"x","lockfileVersion":3}\n' >"$FIX_REPO/package-lock.json"
git -C "$FIX_REPO" add -A; git -C "$FIX_REPO" commit -q -m npm
cat >"$FIX_BIN/npm" <<'NPM'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$OC_STUB_STATE/npm-args"
sleep 30
NPM
chmod +x "$FIX_BIN/npm"
( cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" exec bash "$OC_TASK" --brief "$brief" --branch oc/instsig --install >"$FIX_ROOT/sig.out" 2>&1 ) &
sigpid=$!
for _ in $(seq 1 100); do [[ -f "$FIX_STUB_STATE/npm-args" ]] && break; sleep 0.1; done
kill -TERM "$sigpid"; wait "$sigpid" && sig_status=0 || sig_status=$?
eq "a signal during --install exits 143" 143 "$sig_status"
[[ -e "$FIX_REPO/.oc-worktrees/oc/instsig" ]] && no "and removes the worktree it made" "absent" "present" \
  || ok "and removes the worktree it made"
git -C "$FIX_REPO" show-ref --verify --quiet refs/heads/oc/instsig \
  && no "and the branch it made" "deleted" "kept" || ok "and the branch it made"

new_fixture nonm
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
printf '{"name":"x"}\n' >"$FIX_REPO/package.json"
git -C "$FIX_REPO" add -A; git -C "$FIX_REPO" commit -q -m pkg
OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/nonm
contains "a package with no node_modules to link says so (#26)" "has no node_modules" "$OUT"

section "opencode's database size"
new_fixture dbwarn
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
mkdir -p "$XDG_DATA_HOME/opencode"; printf 'x' >"$XDG_DATA_HOME/opencode/opencode.db"
OC_DELEGATE_DB_WARN_GB=0 OC_STUB_RUN_MODE=nochange run_oc --brief "$brief" --branch oc/db
contains "a large opencode database is reported" "opencode's database is" "$OUT"

section "oc-models (#8, #31, #34)"
new_fixture models
mout=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$BIN_DIR/oc-models" --free --verbose 2>&1) && mst=0 || mst=$?
eq "oc-models --free --verbose exits 0" 0 "$mst"
contains "it lists the free model" "opencode/muse-spark-1.3-contributor-free" "$mout"
lacks "and leaves out the paid one" "paid-model" "$mout"
lacks "with no parse error" "parse error" "$mout"
mout=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$BIN_DIR/oc-models" 2>&1)
eq "free models sort first" "opencode/muse-spark-1.3-contributor-free" "$(head -1 <<<"$mout")"
mout=$(cd "$FIX_REPO" && OC_STUB_MODELS_VERBOSE=truncated PATH="$FIX_BIN:$PATH" bash "$BIN_DIR/oc-models" --free 2>&1) && mst=0 || mst=$?
eq "a catalog that does not parse exits 3, not 5" 3 "$mst"
contains "and says so" "did not parse" "$mout"
lacks "and lists nothing from a partial catalog" "muse-spark" "$mout"

section "opencode v2 surface"
new_fixture v2
export OC_STUB_VERSION=2.0.32
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/v2
eq "a v2 dispatch succeeds" 0 "$STATUS"
contains "the summary names the run" "run:" "$OUT"
contains "v2 wants a lowercase log level" "--log-level warn" "$(cat "$FIX_STUB_STATE/serve-args")"
lacks "the v1 spelling is gone" "--log-level WARN" "$(cat "$FIX_STUB_STATE/serve-args")"
runargs=$(cat "$FIX_STUB_STATE/run-args")
contains "v2 attaches with --server" "--server" "$runargs"
lacks "and has no --attach" "--attach" "$runargs"
lacks "and no --dir (the session carries the worktree)" "--dir" "$runargs"
body=$(tail -1 "$FIX_STUB_STATE/session-body")
eq "the v2 blanket allow comes first" "allow" "$(jq -r '.permissions[0].effect' <<<"$body")"
eq "git stash is denied on the shell tool" "deny" \
  "$(jq -r '.permissions[] | select(.action == "shell" and .resource == "*git stash*") | .effect' <<<"$body")"
eq "git -C <dir> stash is denied too" "deny" \
  "$(jq -r '.permissions[] | select(.action == "shell" and .resource == "*git -C * stash*") | .effect' <<<"$body")"
eq "and on the code-mode execute tool" "deny" \
  "$(jq -r '.permissions[] | select(.action == "execute" and .resource == "*git stash*") | .effect' <<<"$body")"
eq "the worktree rides in the location object" "$FIX_REPO/.oc-worktrees/oc/v2" \
  "$(jq -r '.location.directory' <<<"$body")"
auth=$(tail -1 "$FIX_STUB_STATE/session-auth")
contains "the session request authenticates" "Basic " "$auth"

new_fixture v2refused
export OC_STUB_VERSION=2.0.32
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_SESSION_STATUS=401 run_oc --brief "$brief" --branch oc/v2refused
eq "a refused v2 session fails the dispatch" 1 "$STATUS"
contains "with the session-id explanation" "did not return a session id" "$OUT"

new_fixture v2err
export OC_STUB_VERSION=2.0.32
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
OC_STUB_RUN_MODE=stall OC_DELEGATE_RATE_LIMIT_GRACE=2 \
  OC_STUB_SERVE_ERROR="Rate limit exceeded. Please try again later." \
  run_oc --brief "$brief" --branch oc/v2err --idle-timeout 120
eq "a v2 rate limit in the server log exits 5" 5 "$STATUS"
contains "the v2 cause= line carries the provider's message" "Rate limit exceeded" "$OUT"

section "oc-models on v2"
new_fixture v2models
export OC_STUB_VERSION=2.0.32
mout=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$BIN_DIR/oc-models" --free --verbose 2>&1) && mst=0 || mst=$?
eq "oc-models --free --verbose exits 0 on v2" 0 "$mst"
contains "it lists the free model" "opencode/muse-spark-1.3-contributor-free" "$mout"
lacks "and leaves out the paid one" "paid-model" "$mout"
mout=$(cd "$FIX_REPO" && OC_STUB_MODELS_VERBOSE=truncated PATH="$FIX_BIN:$PATH" bash "$BIN_DIR/oc-models" --free 2>&1) && mst=0 || mst=$?
eq "a v2 catalog that does not parse exits 3, not 5" 3 "$mst"
lacks "and lists nothing from a partial catalog" "muse-spark" "$mout"
unset OC_STUB_VERSION

summary
