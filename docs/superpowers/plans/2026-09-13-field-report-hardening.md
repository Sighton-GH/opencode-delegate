# opencode-delegate v0.4.0 Field-Report Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `opencode-delegate:opencode-driven-development` to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the ten findings of the v0.3.0 field report to `oc-task` so that
a long ODD run survives a path with spaces, a failed dispatch, a poisoned
session, a silent stall, a killed wrapper, untracked inputs, and a caller who
wants to own the final commit — and ship the first test suite this repo has had.

**Architecture:** Everything lives in one bash script,
`plugins/opencode-delegate/bin/oc-task`. The changes are local edits to it plus
a new test harness under `plugins/opencode-delegate/tests/`. The harness fakes
`opencode` entirely (a bash dispatcher plus a small python3 HTTP server that
speaks the two endpoints `oc-task` uses), so the whole suite runs offline, in
under a minute, with no provider account. Docs changes land last, once the
flags they describe exist.

**Tech Stack:** bash 4+, git, jq, curl, python3 (tests only). No new runtime
dependencies — `python3` is a *test-only* dependency and the suite skips its
integration section with a clear message if python3 is absent.

**Spec:** `docs/superpowers/specs/2026-09-13-field-report-v0.3.0.md`

## Global Constraints

- **No new runtime dependencies.** `oc-task` may use only bash, git, jq, curl —
  the four already checked in its `for dep in git opencode jq curl` loop.
  `python3` may be used by tests only, never by `bin/*`.
- **Backward compatibility is mandatory.** Every existing flag, exit code, run
  record field, and summary line keeps working and keeps its meaning. New exit
  codes take new numbers; existing numbers never change meaning.
- **`.oc-runs/RUNID.json` is append-only in schema:** new fields may be added,
  existing fields never removed or renamed. Readers use `// default`.
- **Preserve the safety model.** `--role review` must stay read-only; merge
  must keep refusing a dirty tree, a non-zero implement run, files outside the
  briefs' `# Files` sections, and conflicts. Do not weaken any refusal.
- **Comment style:** this script explains *why*, not *what*, in full sentences
  wrapped at ~78 columns, above the code it explains. Match it. Every new
  comment must name the field-report finding it addresses where relevant.
- **`set -euo pipefail` is in force.** Any command whose non-zero exit is
  acceptable must end in `|| true` or be guarded.
- **The repo's checkout path contains spaces.** Every path variable must be
  quoted in every expansion. This is the bug being fixed; do not reintroduce it.
- **File mode note:** this repo lives on a mount with `core.filemode=false`.
  New executable files need `git update-index --chmod=+x <path>` after
  `git add`, or they ship non-executable.
- Verification command for every task: `bash plugins/opencode-delegate/tests/run.sh`

---

## File Structure

| File | Responsibility |
|---|---|
| `plugins/opencode-delegate/bin/oc-task` | All production changes (Tasks 2–5). |
| `plugins/opencode-delegate/tests/run.sh` | Test entry point: runs every section, prints a summary, exits non-zero on any failure. |
| `plugins/opencode-delegate/tests/lib/assert.sh` | Assertion helpers + counters. Sourced by `run.sh`. |
| `plugins/opencode-delegate/tests/lib/fixture.sh` | Builds a throwaway git repo **at a path containing a space** with the fake `opencode` on `PATH`. Sourced by `run.sh`. |
| `plugins/opencode-delegate/tests/lib/stub-opencode` | Fake `opencode` CLI: `models`, `serve`, `run`. Behaviour driven by `OC_STUB_*` env vars. |
| `plugins/opencode-delegate/tests/lib/stub-server.py` | The `serve` half: answers `GET /global/health` and `POST /session`, records the decoded `directory` query param. |
| `README.md`, `plugins/opencode-delegate/README.md`, `skills/.../SKILL.md`, `skills/.../implementer-brief.md` | Docs (Task 6). |
| `plugins/opencode-delegate/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version bump to 0.4.0 (Task 6). |

---

### Task 1: Test harness and the source-only hook

**Files:**
- Create: `plugins/opencode-delegate/tests/run.sh`
- Create: `plugins/opencode-delegate/tests/lib/assert.sh`
- Create: `plugins/opencode-delegate/tests/lib/fixture.sh`
- Create: `plugins/opencode-delegate/tests/lib/stub-opencode`
- Create: `plugins/opencode-delegate/tests/lib/stub-server.py`
- Modify: `plugins/opencode-delegate/bin/oc-task` (move helper functions above
  argument parsing; add the `OC_TASK_SOURCE_ONLY` hook)

**Interfaces:**
- Consumes: nothing.
- Produces, for every later task:
  - `bash plugins/opencode-delegate/tests/run.sh` — the verification command.
  - `assert.sh` exports: `ok MSG`, `no MSG EXPECTED ACTUAL`,
    `eq MSG EXPECTED ACTUAL`, `neq MSG NOTEXPECTED ACTUAL`,
    `contains MSG NEEDLE HAYSTACK`, `lacks MSG NEEDLE HAYSTACK`,
    `section NAME`, `summary` (prints totals, returns 1 if any failed).
    Counters are the globals `PASS` and `FAIL`.
  - `fixture.sh` exports `new_fixture` — creates a fresh throwaway repo and sets:
    `FIX_ROOT` (dir containing a space), `FIX_REPO` (the git repo inside it),
    `FIX_BIN` (dir holding the stub `opencode`, prepended to `PATH` by the
    caller), `FIX_STUB_STATE` (dir the stub writes observations into).
    Also exports `fixture_cleanup`.
  - `oc-task` sourced with `OC_TASK_SOURCE_ONLY=1` defines its helper functions
    and returns before parsing arguments.

- [ ] **Step 1: Reorder `oc-task` helpers above argument parsing**

In `plugins/opencode-delegate/bin/oc-task`, the helper functions `find_run`,
`fmt_duration`, `spec_file_tokens` and `check_spec` are currently defined
*after* argument parsing, the dependency check and the config block. Move all
four, unchanged in body, into a single block immediately after the `die()`
definition (currently line 43), deleting them from their old locations.

Their old locations are:
- `find_run` — the block starting `# Latest run record matching a jq filter`
- `fmt_duration` — the one-liner starting `fmt_duration() {`
- `spec_file_tokens` — the block starting `# Extract the paths a spec's`
- `check_spec` — the block under `# ---- spec checks`

Keep every comment attached to its function. Leave the `# ---- repo` and
`# ---- spec checks` section banners where the remaining code is; delete a
banner only if nothing is left under it. These functions read globals
(`$runs_dir`, `$spec`, `REQUIRED_SECTIONS`) that are still assigned later —
that is fine, bash resolves globals at call time, not definition time.

- [ ] **Step 2: Add the source-only hook**

Immediately after that helper block and immediately before the
`# ---------------------------------------------------------------- arguments`
banner, add:

```bash
# Test hook. `OC_TASK_SOURCE_ONLY=1 . oc-task` defines the helpers above and
# returns before any argument parsing, dependency check, or repo lookup, so the
# test suite can exercise them directly. `return` fails outside a sourced file,
# so an accidental direct execution with the variable set exits cleanly instead.
if [[ -n "${OC_TASK_SOURCE_ONLY:-}" ]]; then return 0 2>/dev/null || exit 0; fi
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "1: hoist oc-task helpers and add the source-only test hook"
```

- [ ] **Step 4: Write `tests/lib/assert.sh`**

```bash
#!/usr/bin/env bash
# Assertions for the oc-task suite. Sourced, never executed. Every helper
# prints one line and bumps a counter; nothing exits, so one failure does not
# hide the rest of the suite.

PASS=0
FAIL=0

section() { printf '\n== %s ==\n' "$1"; }
ok()      { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no()      { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"; }

eq()       { [[ "$2" == "$3" ]]   && ok "$1" || no "$1" "$2" "$3"; }
neq()      { [[ "$2" != "$3" ]]   && ok "$1" || no "$1" "anything but: $2" "$3"; }
contains() { [[ "$3" == *"$2"* ]] && ok "$1" || no "$1" "contains: $2" "$3"; }
lacks()    { [[ "$3" != *"$2"* ]] && ok "$1" || no "$1" "does not contain: $2" "$3"; }

summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
```

- [ ] **Step 5: Write `tests/lib/stub-server.py`**

This is the `opencode serve` half. It answers only the two endpoints `oc-task`
touches, and records the **decoded** `directory` query parameter so the suite
can prove the URL encoding is correct (field report #1).

```python
#!/usr/bin/env python3
"""Minimal stand-in for `opencode serve`, for the oc-task test suite.

Answers the two endpoints oc-task uses and records what it was sent:
  GET  /global/health  -> 200 {}
  POST /session        -> 200 {"id": "ses_stub..."} (or the status in
                          OC_STUB_SESSION_STATUS, to exercise failed dispatch)

The decoded `directory` query parameter of every POST /session is appended to
$OC_STUB_STATE/session-directory, one per line. A repo path containing a space
only survives that round trip if the client percent-encoded it.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

STATE = os.environ.get("OC_STUB_STATE", ".")
SESSION_STATUS = int(os.environ.get("OC_STUB_SESSION_STATUS", "200"))


def record(name, value):
    with open(os.path.join(STATE, name), "a") as fh:
        fh.write(value + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # keep the serve log to the one "listening on" line oc-task greps

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if urlparse(self.path).path == "/global/health":
            self._send(200, {})
        else:
            self._send(404, {})

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/session":
            self._send(404, {})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        directory = parse_qs(parsed.query).get("directory", [""])[0]
        record("session-directory", directory)
        if SESSION_STATUS != 200:
            self._send(SESSION_STATUS, {"error": "stub refused"})
            return
        self._send(200, {"id": "ses_stub0000000000000000"})


def main():
    port = int(sys.argv[1])
    server = HTTPServer(("127.0.0.1", port), Handler)
    print("listening on http://127.0.0.1:%d" % port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 6: Write `tests/lib/stub-opencode`**

```bash
#!/usr/bin/env bash
# Fake `opencode` for the oc-task test suite. Real opencode is never invoked:
# this covers the three subcommands oc-task calls, with behaviour chosen by
# environment variables so one stub serves every scenario.
#
#   OC_STUB_STATE            dir this stub records observations into (required)
#   OC_STUB_SESSION_STATUS   HTTP status for POST /session (default 200)
#   OC_STUB_RUN_MODE         what `opencode run` does (default: ok)
#       ok       write a short event stream with a DONE RESULT block, create a
#                file in the worktree and commit it
#       nochange write the same event stream but touch nothing
#       stall    write nothing at all and sleep until killed (finding #4)
#       poison   emit the provider's encrypted_content error (finding #3)
#       fail     emit a generic error event and exit 1
#       ratelimit emit a 429 error event and exit 1
#   OC_STUB_RUN_SLEEP        seconds `run` sleeps before acting (default 0)
set -uo pipefail

state="${OC_STUB_STATE:?stub needs OC_STUB_STATE}"
mkdir -p "$state"

# `opencode run` reads its prompt from stdin. Drain it so the caller's
# redirection behaves the way it does against the real binary.
drain_stdin() { cat >"$state/last-prompt" 2>/dev/null || true; }

emit() { printf '%s\n' "$1"; }

case "${1:-}" in
  models)
    # oc-task greps this for an exact match on the configured model id.
    emit 'opencode/muse-spark-1.3-contributor-free'
    emit 'opencode/stub-alternate-free'
    exit 0
    ;;

  serve)
    port=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --port) port="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    exec python3 "$(dirname "${BASH_SOURCE[0]}")/stub-server.py" "$port"
    ;;

  run)
    drain_stdin
    printf '%s\n' "$*" >"$state/run-args"
    dir="$PWD"
    while [[ $# -gt 0 ]]; do
      case "$1" in --dir) dir="${2:-}"; shift 2 ;; *) shift ;; esac
    done
    sleep "${OC_STUB_RUN_SLEEP:-0}"
    case "${OC_STUB_RUN_MODE:-ok}" in
      stall)
        # The exact failure from finding #4: the process is alive, the log
        # never grows, no error is ever emitted. Sleep far past any timeout.
        sleep 3600
        exit 0
        ;;
      poison)
        emit '{"type":"error","error":{"name":"APIError","data":{"message":"Error from provider (Console): Upstream request failed: [invalid_request_error] reasoning `encrypted_content` was not issued to this caller"}}}'
        exit 1
        ;;
      ratelimit)
        emit '{"type":"error","error":{"name":"APIError","data":{"message":"429 Too Many Requests: rate limit exceeded"}}}'
        exit 1
        ;;
      fail)
        emit '{"type":"error","error":{"name":"APIError","data":{"message":"stub failure"}}}'
        exit 1
        ;;
      nochange)
        emit '{"type":"text","part":{"text":"## RESULT\nStatus: DONE\nFiles changed: none\n"}}'
        exit 0
        ;;
      ok|*)
        printf 'stub wrote this\n' >>"$dir/stub-output.txt"
        git -C "$dir" add -A >/dev/null 2>&1 || true
        git -C "$dir" -c user.name=stub -c user.email=stub@localhost \
            commit -q -m "stub: implement the brief" >/dev/null 2>&1 || true
        emit '{"type":"text","part":{"text":"## RESULT\nStatus: DONE\nFiles changed: stub-output.txt\nCommits: stub\nCommands run and their outcome: none\nCould not complete: nothing\nAssumptions made: none\nConcerns or questions: none\n"}}'
        exit 0
        ;;
    esac
    ;;

  *)
    emit "stub-opencode: unsupported subcommand: ${1:-<none>}" >&2
    exit 127
    ;;
esac
```

- [ ] **Step 7: Write `tests/lib/fixture.sh`**

```bash
#!/usr/bin/env bash
# Throwaway git repos for the oc-task suite. Every fixture lives under a
# directory whose name contains a space, because that is the condition the
# field report's critical bug needed to reproduce.

FIXTURES_CREATED=()

new_fixture() { # $1 = optional label
  local label="${1:-fix}"
  FIX_ROOT=$(mktemp -d)/"with space"
  mkdir -p "$FIX_ROOT"
  FIXTURES_CREATED+=("$(dirname "$FIX_ROOT")")

  FIX_REPO="$FIX_ROOT/$label repo"
  FIX_BIN="$FIX_ROOT/bin"
  FIX_STUB_STATE="$FIX_ROOT/stub-state"
  mkdir -p "$FIX_REPO" "$FIX_BIN" "$FIX_STUB_STATE"

  ln -sf "$TESTS_DIR/lib/stub-opencode" "$FIX_BIN/opencode"

  git -C "$FIX_REPO" init -q
  git -C "$FIX_REPO" config user.email oc-test@localhost
  git -C "$FIX_REPO" config user.name oc-test
  printf 'seed\n' >"$FIX_REPO/seed.txt"
  git -C "$FIX_REPO" add -A
  git -C "$FIX_REPO" commit -q -m "seed"

  export OC_STUB_STATE="$FIX_STUB_STATE"
  export XDG_CONFIG_HOME="$FIX_ROOT/config"
}

fixture_cleanup() {
  local d
  for d in "${FIXTURES_CREATED[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}

# Run oc-task inside the current fixture with the stub on PATH. Captures
# stdout+stderr into $OUT and the exit status into $STATUS; never aborts.
run_oc() {
  set +e
  OUT=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$OC_TASK" "$@" 2>&1)
  STATUS=$?
  set -e
}

# Write a valid implement brief to $1.
write_brief() {
  cat >"$1" <<'BRIEF'
# Objective
Stub task.

# Files
Create:
- `stub-output.txt`

# Tasks
1. Write the file.

# Verification
Run `true`.

# Definition of done
- [ ] Done.

# Required output
End your final message with a block in exactly this form:
## RESULT
Status: DONE
BRIEF
}
```

- [ ] **Step 8: Write `tests/run.sh` with the sections that pass today**

```bash
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

section "helpers"
# Sourcing oc-task turns on `set -euo pipefail` in this shell; turn it back off
# immediately or the first failing assertion would abort the suite.
OC_TASK_SOURCE_ONLY=1 . "$OC_TASK"
set +eu +o pipefail
eq "fmt_duration 0"    "0m00s" "$(fmt_duration 0)"
eq "fmt_duration 65"   "1m05s" "$(fmt_duration 65)"
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
```

- [ ] **Step 9: Make the scripts executable and run the suite**

```bash
chmod +x plugins/opencode-delegate/tests/run.sh plugins/opencode-delegate/tests/lib/stub-opencode plugins/opencode-delegate/tests/lib/stub-server.py
bash plugins/opencode-delegate/tests/run.sh
```

Expected: every assertion passes and the final line reads `N passed, 0 failed`.
If an assertion fails, read it, fix the test or the hoist, and run again. Do not
change production behaviour in this task beyond Steps 1–2.

- [ ] **Step 10: Commit**

```bash
git add -A
git update-index --chmod=+x plugins/opencode-delegate/tests/run.sh
git update-index --chmod=+x plugins/opencode-delegate/tests/lib/stub-opencode
git update-index --chmod=+x plugins/opencode-delegate/tests/lib/stub-server.py
git commit -m "1: offline test harness for the oc-task bin scripts"
```

---

### Task 2: URL-encode the session directory; recover from a failed dispatch

Field report findings #1 (Critical) and #2 (Important).

**Files:**
- Modify: `plugins/opencode-delegate/bin/oc-task`
- Modify: `plugins/opencode-delegate/tests/run.sh`

**Interfaces:**
- Consumes: the harness from Task 1 (`run_oc`, `new_fixture`, assertions).
- Produces: `uri_escape VALUE` — a helper later tasks may reuse;
  `discard_new_worktree` and `die_fresh CODE MESSAGE...`.

- [ ] **Step 1: Write the failing tests**

Append to `plugins/opencode-delegate/tests/run.sh`, immediately before the
final `summary` line:

```bash
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

# And the recovery path: a worktree that exists with no run record.
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
```

- [ ] **Step 2: Run the tests and watch them fail**

```bash
bash plugins/opencode-delegate/tests/run.sh
```

Expected: the new assertions fail (the raw-interpolation check fails, the
dispatch under a spaced path fails with "opencode did not return a session id",
the teardown assertions fail because the worktree and branch survive, and
`--session new` on a recordless worktree exits 1). The Task 1 sections still pass.

- [ ] **Step 3: Add `uri_escape` to the helper block**

In `bin/oc-task`, inside the helper block created in Task 1 (after `die()`),
add:

```bash
# URL-encode a value for use in a query string. The worktree path routinely
# contains a space ("/Users/me/VS Code/repo"), which makes an unencoded query
# string invalid: opencode then returns no session id and the failure reads
# like an auth problem rather than a quoting one (field report #1). jq is
# already a hard dependency, so this costs nothing.
uri_escape() { jq -rn --arg s "${1-}" '$s|@uri'; }
```

- [ ] **Step 4: Use it in the session POST**

Replace this line:

```bash
  session=$(curl -sf -m 15 -X POST "$url/session?directory=$worktree" \
```

with:

```bash
  session=$(curl -sf -m 15 -X POST "$url/session?directory=$(uri_escape "$worktree")" \
```

Then audit the rest of the script for any other interpolation of a path into a
URL or an unquoted context. The only other uses of `$worktree` are
`--dir "$worktree"`, `git -C "$worktree"`, `cd "$worktree"` and `[[ -d
"$worktree" ]]` — all already quoted argv positions, which are safe. Make no
change to those.

- [ ] **Step 5: Add the failed-dispatch teardown**

Immediately after the `worktree="$wt_root/$branch"` assignment, add:

```bash
# Set to 1 only when this invocation created the worktree, so the teardown
# below can never remove one the caller already had.
created_wt=0
```

Add these two functions to the helper block (after `uri_escape`):

```bash
# A dispatch that dies after the worktree exists but before a run record is
# written leaves a branch and a worktree that every recovery path then refuses
# — there is no record to resume from, and a fresh dispatch refuses because the
# worktree exists (field report #2). Undo exactly what this invocation created
# so the operator can simply dispatch again.
discard_new_worktree() {
  [[ "${created_wt:-0}" -eq 1 ]] || return 0
  created_wt=0
  if [[ -n "${serve_pid:-}" ]]; then
    kill "$serve_pid" 2>/dev/null || true
    wait "$serve_pid" 2>/dev/null || true
    serve_pid=""
  fi
  git worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
  git worktree prune >/dev/null 2>&1 || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  return 0
}

# die(), but first undo a worktree this invocation created.
die_fresh() { discard_new_worktree; die "$@"; }
```

In the worktree block, set the flag after a successful create. Replace:

```bash
  git worktree add -q -b "$branch" "$worktree" HEAD 2>/dev/null || die "$EX_ERR" "git worktree add failed for $branch"
```

with:

```bash
  git worktree add -q -b "$branch" "$worktree" HEAD 2>/dev/null || die "$EX_ERR" "git worktree add failed for $branch"
  created_wt=1
```

- [ ] **Step 6: Use `die_fresh` on the two failures that strand a worktree**

Replace:

```bash
[[ -n "$url" ]] || die "$EX_ERR" "could not start opencode serve (last attempt on port $port):"$'\n'"$(tail -5 "$serve_log")"
```

with:

```bash
[[ -n "$url" ]] || die_fresh "$EX_ERR" "could not start opencode serve (last attempt on port $port):"$'\n'"$(tail -5 "$serve_log")"$'\n'"the branch and worktree this run created were removed; fix the cause and dispatch again."
```

Replace:

```bash
  [[ "$session" == ses_* ]] || die "$EX_ERR" "opencode did not return a session id"
```

with:

```bash
  [[ "$session" == ses_* ]] || die_fresh "$EX_ERR" "opencode did not return a session id (is opencode authenticated? does '$url' answer?). The branch and worktree this run created were removed; fix the cause and dispatch again."
```

- [ ] **Step 7: Let `--session new` adopt a recordless worktree**

Replace the whole `elif [[ "$session" == "new" ]]; then` branch with:

```bash
elif [[ "$session" == "new" ]]; then
  [[ -n "$branch" ]] || die "$EX_ERR" "--session new needs --branch <existing worktree branch>"
  rec=$(find_run ".branch == \"$branch\"") || true
  if [[ -n "$rec" ]]; then
    base_branch=$(jq -r .base_branch "$rec"); base_sha=$(jq -r .base_sha "$rec")
  elif [[ -d "$wt_root/$branch" ]]; then
    # A dispatch died before it could write a record (field report #2). The
    # worktree and its checkpoint commits are still good, so recover the fork
    # point from git rather than making the operator delete it by hand.
    base_branch=$(git symbolic-ref --short HEAD 2>/dev/null) || die "$EX_ERR" "HEAD is detached; check out a branch first"
    base_sha=$(git merge-base HEAD "$branch" 2>/dev/null) || base_sha=$(git rev-parse HEAD)
    echo "oc-task: no run record for branch $branch; adopting the existing worktree (base $base_branch @ ${base_sha:0:7})" >&2
  else
    die "$EX_ERR" "no run record in $RUNS_DIR for branch $branch, and no worktree at $WORKTREES_DIR/$branch — dispatch without --session to start a fresh one"
  fi
  session=""; reuse_wt=1
```

- [ ] **Step 8: Run the tests until green**

```bash
bash plugins/opencode-delegate/tests/run.sh
```

Expected: `N passed, 0 failed`. If it fails, read the failure, fix it, run again.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "2: url-encode the session directory; recover from a failed dispatch"
```

---

### Task 3: Idle watchdog, poisoned-session detection, process-group cleanup

Field report findings #4, #3 and #8.

**Files:**
- Modify: `plugins/opencode-delegate/bin/oc-task`
- Modify: `plugins/opencode-delegate/tests/run.sh`

**Interfaces:**
- Consumes: `die`, `find_run`, the harness, `OC_STUB_RUN_MODE=stall|poison`.
- Produces:
  - exit code `6` (`EX_STALL`) — "stalled; session dead, re-dispatch with
    `--session new`". Task 6 documents it.
  - `--idle-timeout SECONDS` flag, `$OC_DELEGATE_IDLE_TIMEOUT`, and
    `idle_timeout=` in `~/.config/oc-delegate/config`. `0` disables the watchdog.
  - Run-record fields `dead_reason` (string: `""`, `image-limit`, `stalled`,
    `encrypted-content`), `stalled` (bool), `idle_timeout` (number).

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh` before `summary`:

```bash
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
# And it is refused forever.
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
```

- [ ] **Step 2: Run them and watch them fail**

```bash
bash plugins/opencode-delegate/tests/run.sh
```

Expected: `--idle-timeout` is rejected as an unknown argument, the stall test
hangs the suite's stub for an hour unless the watchdog exists — so it will fail
fast on the unknown flag first. The poison test exits 1 instead of 4.

- [ ] **Step 3: Add the constants and the exit code**

In the exit-code comment header at the top of the script, after the line
`#   5  rate limited by the provider`, add:

```
#   6  stalled — no output for the idle timeout; the session is dead
```

Note the header is printed by `usage()` via `sed -n '2,21p'`; after adding a
line, change that range to `'2,22p'` so the new line is included.

Next to `DEFAULT_MODEL`, add:

```bash
# How long a run may produce no output at all before the watchdog kills it.
# The provider's *explicit* rate limit surfaces as an error and exits 5; the
# silent one just stops emitting, with no error and no end of turn, and used to
# hang until an operator noticed (field report #4). 0 disables the watchdog.
DEFAULT_IDLE_TIMEOUT=420
IDLE_POLL=5
```

Next to the other regexes, add:

```bash
# A session whose turn was interrupted (killed, or dropped mid-stream) loses the
# reasoning state the provider expects back on the next turn, and every
# subsequent turn fails instantly. Like the image limit, it is unrecoverable,
# so it gets the same treatment: mark the session dead and never retry it.
POISON_RE='encrypted_content'
```

Extend the exit-code constants line:

```bash
EX_OK=0; EX_ERR=1; EX_SPEC=2; EX_NOCHANGE=3; EX_IMAGES=4; EX_RATE=5; EX_STALL=6
```

- [ ] **Step 4: Parse `--idle-timeout` and resolve it**

Add `idle_arg=""` to the variable initialisation line above the `while` loop,
and this case to the argument loop, above the `-h|--help` case:

```bash
    --idle-timeout) idle_arg="${2:-}"; shift 2 ;;
```

In the config block, after the `config_model=` line, add:

```bash
config_idle=$(sed -n 's/^[[:space:]]*idle_timeout[[:space:]]*=[[:space:]]*//p' "$CONFIG_FILE" | tail -1 | tr -d '[:space:]')
```

and after the model-resolution `if/elif` chain, add:

```bash
if   [[ -n "$idle_arg" ]];                        then idle_timeout="$idle_arg"
elif [[ -n "${OC_DELEGATE_IDLE_TIMEOUT:-}" ]];    then idle_timeout="$OC_DELEGATE_IDLE_TIMEOUT"
elif [[ -n "$config_idle" ]];                     then idle_timeout="$config_idle"
else                                                   idle_timeout="$DEFAULT_IDLE_TIMEOUT"
fi
[[ "$idle_timeout" =~ ^[0-9]+$ ]] || die "$EX_ERR" "--idle-timeout takes whole seconds (0 disables), got: $idle_timeout"
```

Add a line to the generated config template, after the `#model=` line:

```
# Seconds a run may produce no output before the watchdog kills it. 0 disables.
#idle_timeout=$DEFAULT_IDLE_TIMEOUT
```

- [ ] **Step 5: Add `kill_run` and harden `cleanup`**

Add to the helper block:

```bash
# Kill the run and everything it spawned. `set -m` when launching made the
# child a process-group leader, so the negative pid reaches opencode's whole
# tree; without that, killing the wrapper left the run alive and committing
# while its server died with the parent (field report #8).
kill_run() {
  local pid="${run_pid:-}"
  [[ -n "$pid" ]] || return 0
  kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.5
  done
  kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  return 0
}
```

Replace the existing `cleanup`/`trap` pair:

```bash
serve_pid=""; serve_log=$(mktemp)
cleanup() { [[ -n "$serve_pid" ]] && kill "$serve_pid" 2>/dev/null; rm -f "$serve_log"; }
trap cleanup EXIT
```

with:

```bash
serve_pid=""; run_pid=""; serve_log=$(mktemp)
# A killed wrapper must mean a killed run. Previously the trap took the server
# down but left `opencode run` alive, so the run kept committing with nothing
# to talk to and no summary was ever written (field report #8).
cleanup() {
  kill_run
  [[ -n "${serve_pid:-}" ]] && { kill "$serve_pid" 2>/dev/null || true; }
  rm -f "$serve_log"
  return 0
}
trap cleanup EXIT
trap 'trap - EXIT; cleanup; exit 143' INT TERM HUP
```

- [ ] **Step 6: Run the dispatch under the watchdog**

Replace this block:

```bash
set +e
( cd "$worktree" && opencode run --attach "$url" --session "$session" --dir "$worktree" \
    "${agent_args[@]}" --model "$model" --format json --auto <"$spec_abs" >"$log" 2>&1 )
oc_exit=$?
set -e
```

with:

```bash
stalled=0
set +e
# Job control puts the background job in its own process group, which is what
# lets kill_run reach opencode's whole tree.
set -m
( cd "$worktree" && exec opencode run --attach "$url" --session "$session" --dir "$worktree" \
    "${agent_args[@]}" --model "$model" --format json --auto <"$spec_abs" >"$log" 2>&1 ) &
run_pid=$!
set +m
if [[ "$idle_timeout" -gt 0 ]]; then
  last_size=-1; last_change=$(date +%s)
  while kill -0 "$run_pid" 2>/dev/null; do
    sleep "$IDLE_POLL"
    size=$(wc -c <"$log" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [[ "$size" != "$last_size" ]]; then
      last_size="$size"; last_change="$now"
    elif (( now - last_change >= idle_timeout )); then
      stalled=1
      kill_run
      break
    fi
  done
fi
wait "$run_pid"
oc_exit=$?
run_pid=""
set -e
```

- [ ] **Step 7: Classify the new outcomes**

Replace the status-classification block. The new version keeps the existing
image-limit and rate-limit behaviour exactly and inserts the two new causes
*before* the generic error branch, because a stall and a poisoned session both
also produce a non-zero `oc_exit`:

```bash
status=$EX_OK; status_txt="success"; dead=false; dead_reason=""
resume_hint="re-dispatch with --session new --branch $branch (checkpoint ${head_sha:-${base_sha:0:7}})"
if grep -qiE "$IMAGE_LIMIT_RE" <<<"$errors" || { [[ $oc_exit -ne 0 ]] && grep -qiE "$IMAGE_LIMIT_RE" "$log"; }; then
  status=$EX_IMAGES; dead=true; dead_reason="image-limit"
  status_txt="session poisoned by image limit — not resumable. $resume_hint"
elif [[ $stalled -eq 1 ]]; then
  status=$EX_STALL; dead=true; dead_reason="stalled"
  status_txt="stalled — no output for ${idle_timeout}s, run killed. Killing a run poisons its session, so it is not resumable: $resume_hint"
elif grep -qiE "$POISON_RE" <<<"$errors" || { [[ $oc_exit -ne 0 ]] && grep -qiE "$POISON_RE" "$log"; }; then
  status=$EX_IMAGES; dead=true; dead_reason="encrypted-content"
  status_txt="session poisoned — the provider rejected this session's reasoning state (encrypted_content), which an interrupted turn always causes. Not resumable: $resume_hint"
elif [[ $oc_exit -ne 0 ]] || { [[ -n "$err_events" ]] && [[ -z "$result" ]]; }; then
  if grep -iqE "$RATE_LIMIT_RE" <<<"$errors"; then status=$EX_RATE; status_txt="rate limited by the provider — retry later, do not loop"
  else status=$EX_ERR; status_txt="opencode errored"; fi
elif [[ -z "$numstat" && $role == implement ]]; then
  status=$EX_NOCHANGE; status_txt="completed but produced zero changes"
elif [[ $role == review && -z "$result" ]]; then
  status=$EX_ERR; status_txt="review finished without a ## RESULT block"
fi
if [[ "$dead" == true ]]; then
  jq -cn --arg s "$session" --arg r "$run_id" --arg reason "$dead_reason" \
     '{type:"oc-task",event:"session-dead",reason:$reason,session_id:$s,run_id:$r}' >> "$log"
fi
```

Note this moves the `session-dead` log line out of the image-limit branch so all
three dead causes record it. Do not otherwise change the rate-limit or
zero-change branches.

- [ ] **Step 8: Record the new fields**

In the `jq -n ... '$ARGS.named' > "$rec_out"` call, add these arguments
alongside the existing ones:

```bash
      --arg dead_reason "$dead_reason" --argjson stalled "$stalled" \
      --argjson idle_timeout "$idle_timeout" \
```

- [ ] **Step 9: Report the reason when refusing a dead session**

Replace:

```bash
  dead=$(find_run ".session_id == \"$session\" and .dead == true")
  [[ -z "$dead" ]] || die "$EX_IMAGES" "session $session is recorded as dead (image limit) in $dead — it can never be retried. Start a fresh session: --session new --branch <branch>"
```

with:

```bash
  dead_rec=$(find_run ".session_id == \"$session\" and .dead == true")
  if [[ -n "$dead_rec" ]]; then
    die "$EX_IMAGES" "session $session is recorded as dead ($(jq -r '.dead_reason // "unrecoverable"' "$dead_rec")) in $dead_rec — it can never be retried. Start a fresh session: --session new --branch $(jq -r .branch "$dead_rec")"
  fi
```

- [ ] **Step 10: Run the tests until green, then commit**

```bash
bash plugins/opencode-delegate/tests/run.sh
git add -A && git commit -m "3: idle watchdog, poisoned-session detection, process-group cleanup"
```

---

### Task 4: Provision the worktree — `--copy-untracked` and `node_modules`

Field report findings #6 and #7.

**Files:**
- Modify: `plugins/opencode-delegate/bin/oc-task`
- Modify: `plugins/opencode-delegate/tests/run.sh`

**Interfaces:**
- Consumes: `die`, `created_wt`, the worktree block from Task 2.
- Produces:
  - `--copy-untracked PATH` (repeatable) — copies PATH from the base checkout
    into a freshly created worktree.
  - `--link-node-modules` / `--no-link-node-modules` — default is to link
    automatically when `node_modules` exists at the repo root.
  - A per-worktree provisioning list at
    `$(git -C "$worktree" rev-parse --git-dir)/oc-provisioned`, one relative
    path per line, consulted by every later run in the same worktree.
  - Run-record field `provisioned` (array of strings).

**Design note — why not `.git/info/exclude`:** git resolves `info/exclude` to
the *common* git dir, which every worktree and the main checkout share. Writing
there would make the user's own checkout start ignoring those paths, a side
effect outside the worktree. Verified: a file written to
`.git/worktrees/<name>/info/exclude` is **not** honoured. So provisioned paths
are kept out of the run instead by pathspec exclusion at `git add`/`git status`
time, which is worktree-local and leaves no residue. Verified working for
directories and for symlinks.

- [ ] **Step 1: Write the failing tests**

Append to `tests/run.sh` before `summary`:

```bash
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
  "$(basename "$(cat "$wt/node_modules/dep.js" 2>/dev/null | tr -d '\n')" 2>/dev/null || echo dep)"

# The point of provisioning: none of it may reach the branch.
tracked=$(git -C "$wt" log --name-only --pretty=format: | sort -u | grep -E '^(inputs|node_modules)' || true)
eq "nothing provisioned was committed" "" "$tracked"
rec=$(ls "$FIX_REPO/.oc-runs"/*.json | tail -1)
contains "the record lists what was provisioned" "inputs" "$(jq -c .provisioned "$rec")"
contains "including node_modules" "node_modules" "$(jq -c .provisioned "$rec")"

# A second run in the same worktree must keep honouring the list.
OC_STUB_RUN_MODE=ok run_oc --brief "$brief" --branch oc/prov --session new
eq "a second run in the same worktree succeeds" 0 "$STATUS"
tracked=$(git -C "$wt" log --name-only --pretty=format: | sort -u | grep -E '^(inputs|node_modules)' || true)
eq "and still commits nothing provisioned" "" "$tracked"

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
```

- [ ] **Step 2: Run them and watch them fail**

```bash
bash plugins/opencode-delegate/tests/run.sh
```

Expected: the new flags are rejected as unknown arguments.

- [ ] **Step 3: Parse the new flags**

Add `copy_untracked=(); link_nm=auto` to the initialisation line above the
argument `while` loop, and these cases above `-h|--help`:

```bash
    --copy-untracked) copy_untracked+=("${2:-}"); shift 2 ;;
    --link-node-modules)    link_nm=yes; shift ;;
    --no-link-node-modules) link_nm=no;  shift ;;
```

- [ ] **Step 4: Validate the copy paths early**

Right after the role check near the top (`case "$role" in implement|review`),
add:

```bash
# Fail before anything is created: a typo'd input path is much cheaper to
# report now than after a worktree exists.
for p in "${copy_untracked[@]:-}"; do
  [[ -n "$p" ]] || die "$EX_ERR" "--copy-untracked needs a path"
  [[ -e "$p" ]] || die "$EX_ERR" "--copy-untracked: no such path in the base checkout: $p"
done
```

- [ ] **Step 5: Provision a freshly created worktree**

Add to the helper block:

```bash
# Record a path as provisioned: present in the worktree but never part of the
# run's diff. The list lives in the worktree's own git dir (not the shared
# info/exclude, which every worktree and the main checkout read) so nothing
# leaks into the user's checkout.
provision_file() { git -C "$worktree" rev-parse --git-dir 2>/dev/null | sed 's|$|/oc-provisioned|'; }

provision_add() { # $1 = path relative to the worktree root
  local f; f=$(provision_file); [[ -n "$f" ]] || return 0
  grep -qxF "$1" "$f" 2>/dev/null || printf '%s\n' "$1" >> "$f"
}

# Pathspecs that keep every provisioned path out of `git status` and `git add`.
# Verified to work for directories and for symlinks.
provision_pathspec() {
  local f p; f=$(provision_file)
  printf '%s\n' "."
  [[ -f "$f" ]] || return 0
  while IFS= read -r p; do [[ -n "$p" ]] && printf ':(exclude)%s\n' "$p"; done < "$f"
}
```

In the worktree block, after `created_wt=1`, add:

```bash
  # The worktree forks from HEAD, so anything untracked — the very files a task
  # is often about — is simply missing from it, and node_modules is never there
  # at all (field report #6, #7). Provision both, and remember what we put
  # there so it never reaches the diff.
  for p in "${copy_untracked[@]:-}"; do
    [[ -n "$p" ]] || continue
    rel="${p#./}"; rel="${rel%/}"
    mkdir -p "$worktree/$(dirname "$rel")"
    cp -a "$repo_root/$rel" "$worktree/$rel"
    provision_add "$rel"
    echo "oc-task: copied untracked $rel into the worktree" >&2
  done
  if [[ "$link_nm" == yes || ( "$link_nm" == auto && -d "$repo_root/node_modules" && ! -e "$worktree/node_modules" ) ]]; then
    if [[ -d "$repo_root/node_modules" ]]; then
      ln -s "$repo_root/node_modules" "$worktree/node_modules"
      provision_add "node_modules"
      echo "oc-task: linked node_modules into the worktree" >&2
    elif [[ "$link_nm" == yes ]]; then
      die_fresh "$EX_ERR" "--link-node-modules: no node_modules in $repo_root"
    fi
  fi
```

- [ ] **Step 6: Keep provisioned paths out of the run's commits**

In the collect block, replace:

```bash
if [[ -n "$(git -C "$worktree" status --porcelain)" ]]; then
```

with:

```bash
mapfile -t wt_pathspec < <(provision_pathspec)
if [[ -n "$(git -C "$worktree" status --porcelain -- "${wt_pathspec[@]}")" ]]; then
```

and replace:

```bash
    git -C "$worktree" add -A >/dev/null 2>&1
```

with:

```bash
    git -C "$worktree" add -A -- "${wt_pathspec[@]}" >/dev/null 2>&1
```

The review branch's `reset --hard` / `clean -qfd` needs one change too, because
`clean -fd` would delete the provisioned paths. Replace:

```bash
    git -C "$worktree" reset -q --hard && git -C "$worktree" clean -qfd
```

with:

```bash
    git -C "$worktree" reset -q --hard
    git -C "$worktree" clean -qfd -- "${wt_pathspec[@]}"
```

- [ ] **Step 7: Record what was provisioned**

Before the `jq -n ... > "$rec_out"` call, add:

```bash
provisioned_json=$( { [[ -f "$(provision_file)" ]] && cat "$(provision_file)"; } 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))' )
[[ -n "$provisioned_json" ]] || provisioned_json='[]'
```

and add to the `jq -n` arguments:

```bash
      --argjson provisioned "$provisioned_json" \
```

- [ ] **Step 8: Run the tests until green, then commit**

```bash
bash plugins/opencode-delegate/tests/run.sh
git add -A && git commit -m "4: copy untracked inputs and link node_modules into the worktree"
```

---

### Task 5: Let the caller own the merge commit

Field report finding #10. The audit — dirty tree, non-zero run, `## RESULT`
block, `--verified`, no files outside the briefs, no conflicts — is the valuable
part and must apply to every mode.

**Files:**
- Modify: `plugins/opencode-delegate/bin/oc-task`
- Modify: `plugins/opencode-delegate/tests/run.sh`

**Interfaces:**
- Consumes: the existing merge mode.
- Produces:
  - `--merge -m "MESSAGE"` — merge with the caller's commit message, keeping
    the `oc-task-run:` trailer so `oc-undo` still finds it.
  - `--merge --no-commit` — run every check, merge into the index and working
    tree, and stop without committing.
  - `--merge --squash` — stage the branch's changes as one non-merge change
    set, leaving the commit to the caller. Implies `--no-commit`.

- [ ] **Step 1: Write the failing tests**

These need a merged-ready branch. Append to `tests/run.sh` before `summary`:

```bash
section "merge modes (finding #10)"
merge_fixture() { # sets $wt for a branch that is ready to merge
  new_fixture "$1"
  brief="$FIX_ROOT/brief.md"; write_brief "$brief"
  run_oc --brief "$brief" --branch "oc/$1"
  eq "[$1] setup dispatch succeeded" 0 "$STATUS"
}

merge_fixture custommsg
run_oc --merge --branch oc/custommsg --verified "true" -m "feat: my own subject"
eq "--merge -m succeeds" 0 "$STATUS"
subject=$(git -C "$FIX_REPO" log -1 --format=%s)
eq "the caller's subject is used" "feat: my own subject" "$subject"
body=$(git -C "$FIX_REPO" log -1 --format=%B)
contains "the oc-task-run trailer survives for oc-undo" "oc-task-run:" "$body"

merge_fixture nocommit
run_oc --merge --branch oc/nocommit --verified "true" --no-commit
eq "--merge --no-commit succeeds" 0 "$STATUS"
eq "it did not commit" "seed" "$(git -C "$FIX_REPO" log -1 --format=%s)"
staged=$(git -C "$FIX_REPO" diff --cached --name-only)
contains "the change is staged for the caller" "stub-output.txt" "$staged"
contains "the summary tells the caller to commit" "commit" "$OUT"

merge_fixture squash
run_oc --merge --branch oc/squash --verified "true" --squash
eq "--merge --squash succeeds" 0 "$STATUS"
eq "it did not commit either" "seed" "$(git -C "$FIX_REPO" log -1 --format=%s)"
staged=$(git -C "$FIX_REPO" diff --cached --name-only)
contains "the squashed change is staged" "stub-output.txt" "$staged"

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
```

- [ ] **Step 2: Run them and watch them fail**

```bash
bash plugins/opencode-delegate/tests/run.sh
```

Expected: `-m`, `--no-commit` and `--squash` are rejected as unknown arguments.

- [ ] **Step 3: Parse the new flags**

Add `merge_msg=""; no_commit=0; squash=0` to the initialisation line, and these
cases above `-h|--help`:

```bash
    -m|--message) merge_msg="${2:-}"; shift 2 ;;
    --no-commit)  no_commit=1; shift ;;
    --squash)     squash=1; no_commit=1; shift ;;
```

- [ ] **Step 4: Reject the new flags outside merge mode**

After the argument loop, add:

```bash
if [[ $do_merge -eq 0 ]]; then
  [[ -z "$merge_msg" && $no_commit -eq 0 && $squash -eq 0 ]] \
    || die "$EX_ERR" "-m, --no-commit and --squash only apply to --merge"
fi
```

- [ ] **Step 5: Apply the modes at the end of merge mode**

Replace the merge-and-report block — everything from the `msg=$(printf ...)`
assignment through the final `exit "$EX_OK"` of merge mode — with:

```bash
  # The audit above is the valuable part and has already run in full. All that
  # changes here is who writes the commit: the caller can supply the message,
  # or take the staged result and commit it themselves (field report #10).
  trailer=$(printf '%s %s\nmodel: %s\nspec: %s\nbranch: %s\nsession: %s\nverified: %s\n' \
        "$MERGE_MARKER" "$run_id" "$rmodel" "$rspec" "$branch" "$rsession" "$verified")
  subject="${merge_msg:-oc-task merge: $branch}"
  msg=$(printf '%s\n\n%s' "$subject" "$trailer")

  if [[ $squash -eq 1 ]]; then
    # --squash stages the branch's net change as an ordinary change set, so the
    # caller's commit has a single parent and can be rewritten freely.
    if ! git merge --squash "$branch" >/dev/null 2>&1; then
      git merge --abort >/dev/null 2>&1 || true
      refuse "merge conflicts between '$base' and '$branch' — resolve manually or re-dispatch"
    fi
  elif ! git merge --no-ff --no-commit "$branch" >/dev/null 2>&1; then
    git merge --abort >/dev/null 2>&1 || true
    refuse "merge conflicts between '$base' and '$branch' — resolve manually or re-dispatch"
  fi

  if [[ $no_commit -eq 1 ]]; then
    printf '%s\n' "$msg" > "$repo_root/.git/OC_TASK_MERGE_MSG"
    echo "staged:  $branch -> $base ($( [[ $squash -eq 1 ]] && echo --squash || echo --no-ff ), not committed)"
    echo "run:     $run_id  model: $rmodel  spec: $rspec"
    echo "audit:   passed — every changed file is named in a brief's # Files section"
    echo "next:    commit it yourself, e.g."
    echo "           git commit -F .git/OC_TASK_MERGE_MSG"
    echo "         keep the '$MERGE_MARKER $run_id' trailer if you want oc-undo to find it."
    echo "abort:   git merge --abort  (or: git reset --hard HEAD)"
    exit "$EX_OK"
  fi

  git commit -q --no-edit -m "$msg" || refuse "the merge staged cleanly but the commit failed"
  sha=$(git rev-parse --short HEAD)
  echo "merged:  $branch -> $base @ $sha ($( [[ $squash -eq 1 ]] && echo --squash || echo --no-ff ))"
  echo "run:     $run_id  model: $rmodel  spec: $rspec"
  echo "undo:    oc-undo"
  echo "branch '$branch' and worktree $WORKTREES_DIR/$branch were left in place."
  exit "$EX_OK"
```

Note `oc-undo` finds merges with `git log --merges --grep="^oc-task-run:"`. A
`--squash` commit is not a merge commit, so `oc-undo` will not list it — that is
correct and expected; Task 6 documents it.

- [ ] **Step 6: Run the tests until green, then commit**

```bash
bash plugins/opencode-delegate/tests/run.sh
git add -A && git commit -m "5: --merge -m, --no-commit and --squash keep the audit with a caller-owned commit"
```

---

### Task 6: Documentation and the 0.4.0 version bump

Field report findings #5 and #9, plus documenting everything Tasks 2–5 added.

**Files:**
- Modify: `README.md`
- Modify: `plugins/opencode-delegate/README.md`
- Modify: `plugins/opencode-delegate/skills/opencode-driven-development/SKILL.md`
- Modify: `plugins/opencode-delegate/skills/opencode-driven-development/implementer-brief.md`
- Modify: `plugins/opencode-delegate/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: every flag and exit code from Tasks 2–5.
- Produces: nothing later tasks read.

- [ ] **Step 1: Update the root README's `oc-task` command reference**

In `README.md`, under `### \`oc-task\``, document each new flag with one short
paragraph in the existing voice:

- `--idle-timeout SECONDS` — default 420, `0` disables; also settable as
  `idle_timeout=` in `~/.config/oc-delegate/config` or
  `$OC_DELEGATE_IDLE_TIMEOUT`.
- `--copy-untracked PATH` — repeatable; copies the path from the base checkout
  into a freshly created worktree and keeps it out of the run's diff. Explain
  why it exists: a worktree forks from `HEAD`, so files a user just dropped in
  are missing from it.
- `--link-node-modules` / `--no-link-node-modules` — automatic when
  `node_modules` exists at the repo root.
- `-m MESSAGE`, `--no-commit`, `--squash` on `--merge`.

- [ ] **Step 2: Update the exit-code lists**

In `README.md` and in `plugins/opencode-delegate/README.md`, add exit code 6 to
the list and revise 4's description to cover both causes:

```
0 success · 1 opencode/setup error · 2 brief rejected · 3 zero changes
(implement) · 4 session unrecoverable — image limit or a poisoned reasoning
state (never retried) · 5 rate limited · 6 stalled (no output for the idle
timeout; session dead). Non-zero exits leave the worktree in place, except a
dispatch that fails before a session exists, which removes what it created.
```

- [ ] **Step 3: Add two troubleshooting sections to the root README**

After `### Rate limited (exit 5)` in `README.md`, add:

```markdown
### "stalled — no output for Ns" (exit 6)

A run can stop producing output with no error at all: the assistant message
exists, has zero parts, and `error: null`. That is a silent provider throttle,
not a crash, and before v0.4.0 it hung until an operator noticed — one run
burned 54 minutes that way. oc-task now watches the run log and kills a run
that has produced nothing for `--idle-timeout` seconds (default 420).

Killing a run poisons its session (see below), so exit 6 also marks the session
dead. The checkpoint commits in the worktree are the recovered work: write a
continuation brief from the first incomplete step and dispatch it with
`--session new --branch NAME`. Raise `--idle-timeout` for tasks with genuinely
long silent stretches, or set `idle_timeout=0` to disable the watchdog.

### "session poisoned — encrypted_content" (exit 4)

An interrupted turn — a killed run, a dropped stream — loses the reasoning
state the provider expects back on the next turn, and every later turn in that
session fails instantly with `reasoning \`encrypted_content\` was not issued to
this caller`. Like the image limit, the session is unrecoverable rather than
merely errored, so oc-task exits 4, records the session dead with
`dead_reason: "encrypted-content"`, and refuses `--session THAT-ID` forever.
Re-dispatch with `--session new --branch NAME`.
```

Also add, under `### Worktree cleanup`, a short note that a dispatch which fails
before a session exists now removes the branch and worktree it created, so
recovery no longer needs `git worktree remove --force` by hand; and that
`--session new --branch B` will adopt a worktree that has no run record.

- [ ] **Step 4: Add the two brief-writing traps to `implementer-brief.md`**

In the notes under the template, in the **Verification** bullet, add:

```markdown
- **Verification** — VERBATIM shape. You re-run this same command; make it
  the real one. Write greps against the artifact *as it actually is*, not as
  you imagine it: a build step may rewrite what you are matching on (Hugo's
  `--minify` strips attribute quotes, so `grep 'id="x"'` fails on correct
  output and the implementer correctly reports BLOCKED). Check the real
  output once yourself before putting a grep in a brief.
- **node_modules in the worktree** — `oc-task` links the base checkout's
  `node_modules` into a fresh worktree automatically. Because it is a symlink,
  `npx <tool>` can fail with `Permission denied`; call the CLI entry point
  directly instead — e.g. `node node_modules/@playwright/test/cli.js test` —
  and put that exact form in the brief's Verification section.
```

- [ ] **Step 5: Update SKILL.md**

In `plugins/opencode-delegate/skills/opencode-driven-development/SKILL.md`:

- In the `## Tools` code block, extend the `oc-task` usage lines:

```
oc-task --brief PATH [--role implement|review] [--model M] [--branch B] [--session ID|new]
        [--idle-timeout S] [--copy-untracked PATH]... [--no-link-node-modules]
oc-task --branch-diff --branch B
oc-task --merge --branch B --verified "COMMAND" [-m MSG | --no-commit | --squash]
```

- In `## Setup`, add a step after the ledger step: "If the task's inputs are
  untracked files the user just added, dispatch Task 1 with `--copy-untracked
  <path>` for each — the worktree forks from `HEAD` and will not contain them
  otherwise. `node_modules` is linked automatically."

- In `### 2. Handle the result`, add to the non-zero exits paragraph: "**6**
  (stalled) the run produced no output for the idle timeout and was killed; the
  session is dead. Treat it exactly like 4: continuation brief from the first
  incomplete step, `--session new --branch B`. If the task legitimately has long
  silent stretches, re-dispatch with a larger `--idle-timeout`." Also extend
  the **4** sentence to "(image limit or a poisoned reasoning state)".

- In `## Finish`, add after the merge sentence: "When the user wants to own the
  final commit — a specific message, or a squash — use `--merge -m \"MSG\"`,
  `--merge --no-commit`, or `--merge --squash`; the file audit runs either way.
  A `--squash` commit is not a merge commit, so `oc-undo` will not find it."

- [ ] **Step 6: Bump the version to 0.4.0**

In `plugins/opencode-delegate/.claude-plugin/plugin.json` and in
`.claude-plugin/marketplace.json`, change `"version": "0.3.0"` to
`"version": "0.4.0"`. Both files must match or `claude plugin update` will not
refetch.

- [ ] **Step 7: Verify and commit**

```bash
bash plugins/opencode-delegate/tests/run.sh
jq -e '.version == "0.4.0"' plugins/opencode-delegate/.claude-plugin/plugin.json
jq -e '.plugins[0].version == "0.4.0"' .claude-plugin/marketplace.json
git add -A && git commit -m "6: document v0.4.0 and bump the version"
```

---

## Self-review

**Spec coverage:** #1 → Task 2 Steps 3–4. #2 → Task 2 Steps 5–7. #3 → Task 3
Steps 3, 7, 9. #4 → Task 3 Steps 3–7. #5 → Task 6 Step 4. #6 → Task 4. #7 →
Task 4. #8 → Task 3 Steps 5–6. #9 → Task 6 Step 4. #10 → Task 5. "Do not
regress" items are covered by explicit no-regression tests in Tasks 3 and 5.

**Type consistency:** `provision_file`/`provision_add`/`provision_pathspec`
(Task 4) are used only within Task 4. `uri_escape` (Task 2) and `kill_run`
(Task 3) are each defined once in the helper block. `die_fresh` is defined in
Task 2 and reused in Task 4 Step 5. Exit constant `EX_STALL=6` is defined in
Task 3 and referenced only there and in Task 6's docs. Record fields added:
`dead_reason`, `stalled`, `idle_timeout` (Task 3), `provisioned` (Task 4) —
no field is renamed or removed.
