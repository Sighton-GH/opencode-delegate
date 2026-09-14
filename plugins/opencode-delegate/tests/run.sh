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

summary
