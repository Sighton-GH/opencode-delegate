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
[[ -L "$wt/node_modules" ]] && ok "node_modules is linked into the worktree" \
  || no "node_modules is linked into the worktree" "a symlink" "$(ls -ld "$wt/node_modules" 2>&1)"
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
[[ -L "$wt/node_modules" ]] && ok "the review run keeps the node_modules link" \
  || no "the review run keeps the node_modules link" "a symlink" "$(ls -ld "$wt/node_modules" 2>&1)"

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

section "the new flags are merge-only"
new_fixture mergeonly
brief="$FIX_ROOT/brief.md"; write_brief "$brief"
run_oc --brief "$brief" --branch oc/mo --no-commit --dry-run
neq "--no-commit outside --merge is refused" 0 "$STATUS"
contains "and says so" "--merge" "$OUT"

summary
