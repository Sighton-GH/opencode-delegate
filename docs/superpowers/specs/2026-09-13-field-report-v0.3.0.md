# Field report: `opencode-delegate` v0.3.0

**Reporter:** Claude Opus 5 (controller session), 2026-09-13
**Workload:** a 6-task plan building a governance documentation section for a
Hugo site — a Node import pipeline with unit tests, five Hugo layouts, two
render hooks, four partials, ~1,050 lines of CSS, a Playwright suite, and 25
generated content pages. 97 files changed, +11,571 / −662, merged to `main` as
one commit.
**Usage:** 25 `oc-task` runs (16 implement, 9 review), 4h 04m of model time.
Exit codes: 20× 0, 4× 1, 1× 5. Implementer and task reviewers on
`muse-spark-1.3-contributor-free`; whole-branch review on `nemotron-3-ultra-free`.

## Verdict

The workflow works and the output quality was genuinely good. Every task reached
`Spec: PASS`, and the reviews were not rubber stamps — the final review caught a
real HTML-correctness bug that the build, 44 unit tests, 8 browser tests and an
axe pass had all missed.

What cost the most was not model quality. It was **operational fragility around
the run** — a path bug, no stall detection, and unrecoverable state after an
interrupted run. Roughly a third of wall-clock time went to babysitting
infrastructure rather than adjudicating work.

## Findings

### 1. Directory is not URL-encoded — any repo path with a space fails (Critical)

`oc-task` line 294 interpolates `$worktree` raw into a query string:

```bash
session=$(curl -sf -m 15 -X POST "$url/session?directory=$worktree" ...)
```

A repo at `/media/bryan/OptiData1/VS Code/...` makes the query string invalid,
`curl` gets no `.id` back, and the run dies with `oc-task: opencode did not
return a session id` — which reads as an opencode/auth problem, not a quoting
problem. Two dispatches were lost to this before bisecting it by hand against
`opencode serve` (confirmed: the same POST with an `@uri`-encoded directory
returns a session immediately).

Fix: `"$url/session?directory=$(jq -rn --arg d "$worktree" '$d|@uri')"`.
`jq` is already a hard dependency, so this costs nothing. Worth auditing the
other places the worktree path is interpolated into a URL or an unquoted context.

### 2. A failed dispatch leaves an unusable branch + worktree (Important)

When session-create fails, `oc-task` has already created the branch and worktree
but writes **no run record**. Every recovery path then refuses with `no run
record in .oc-runs for branch B`. `--session new --branch B` needs a record, and
a fresh dispatch refuses because the worktree exists. The only way out is
`git worktree remove --force` plus `git branch -D` by hand — exactly the kind of
destructive git the tool otherwise protects you from. It also left an orphaned
`opencode serve` process listening.

Fix: write the run record (even a stub with `exit_code`) before the session call,
or tear the worktree down on a failed dispatch, or make `--session new --branch
B` fall back to "worktree exists, no record → start fresh in it".

### 3. Killing a stalled run poisons the session permanently (Important)

After killing a hung `opencode run` (see #4) and resuming with `--session <id>`,
every subsequent turn failed instantly:

```
APIError: Error from provider (Console): Upstream request failed:
[invalid_request_error] reasoning `encrypted_content` was not issued to this caller
```

The session is dead forever but nothing in `oc-task` says so — it just surfaces
a provider error and exits 1. This is the same class of unrecoverable state as
the image-limit case that exit code 4 already handles, and deserves the same
treatment: detect the error string, mark the session `dead: true` in the record,
and tell the operator to re-dispatch with `--session new --branch B`.

### 4. No idle timeout — silent rate limits hang forever (Important)

Twice a run stopped producing output with no error at all. Inspecting the server
directly showed an assistant message created N minutes ago with **zero parts**
and `error: null`. `oc-task` has no idle detection, so it sits there until
killed. One such run burned 54 minutes before intervention; another 6m42s.

The provider's *explicit* rate limit is handled well — exit 5, clear message, no
retry loop. It is the *silent* one that hurts.

Fix: an idle watchdog. If no new event has been appended to the run log for N
minutes (configurable, default maybe 5–7), kill the run, mark the session dead
(see #3, because killing it poisons it anyway), and exit with a distinct code
meaning "stalled — re-dispatch with `--session new`". The reporter ended up
writing this watchdog as an external monitor; it should live in the tool.

### 5. `npx playwright` is broken inside the worktree (Minor, environment-specific)

`sh: 1: playwright: Permission denied`, because `node_modules/.bin` came from a
symlink (see #7). Direct invocation works: `node
node_modules/@playwright/test/cli.js test ...`. Worth a line in the docs, since
Playwright is a common verification command and the model burned turns
rediscovering the workaround.

### 6. Worktrees fork from `HEAD`, so untracked inputs vanish

25 source markdown files were untracked. The worktree forked from `HEAD` and did
not contain them, so the whole task was impossible inside it. Required a
throwaway WIP commit on `main` just to get the inputs into the worktree, then
unwinding that commit at merge time with `git reset --soft` + `git read-tree`.

This is a predictable situation: the very files a task is about are often the
files a user just dropped in. Suggestion: `--copy-untracked <path>...` (or
`--include-untracked`) that copies the named paths into the fresh worktree and
keeps them out of the diff.

### 7. `node_modules` is not available in the worktree

The worktree has no `node_modules`, so any task with a JS test or verification
step fails until you symlink it in and exclude it from git — two manual steps
before Task 1, repeated at every fresh worktree. Either symlink it automatically
when it exists in the base checkout, or document it prominently in SKILL.md's
setup section.

### 8. Killing the dispatch wrapper orphans the run

Twice the harness killed the backgrounded `oc-task` process (exit 144). The
`opencode run` child survived and kept committing, but its `opencode serve` died
with the parent — so the run was still making progress with no server to talk
to, and no summary was ever written. The work landed in git, but the tool had no
idea. The `cleanup()` trap should either kill the whole process group (so a dead
wrapper means a dead run) or detach the run fully (so a dead wrapper does not
take the server with it). Right now it is the worst of both.

### 9. `--minify` vs. greps in briefs

Not a tool bug, but a documentable trap that cost two review cycles: Hugo's
`--minify` strips attribute quotes, so a brief that says
`grep -c 'id="3-6-h"' public/...` fails on correct output and the implementer
dutifully reports `BLOCKED`. Both times the model was right and the brief was
wrong. A line in `implementer-brief.md` — "write verification greps against the
*built* artifact as it actually is" — would help.

### 10. The merge path assumes it owns the integration

`oc-task --merge` is the documented finish. It refuses a dirty tree and refuses
files outside every brief's `# Files` section — both sensible. But it commits
with its own message, and the reporter needed (a) a specific commit message and
(b) to erase a throwaway base commit from #6. So they integrated by hand with
`git reset --soft` + `git read-tree` + `git commit`. Everything still verified,
but the tool's safety checks — the "no files outside the briefs" audit in
particular, which is genuinely valuable — did not apply to that merge.

Suggestion: `--merge --no-commit` (stage only) and/or `--merge -m <msg>` /
`--merge --squash`, so the audit stays available to people who need to control
the final commit.

## Suggestions, ranked

1. URL-encode the worktree directory (#1). One line; unblocks every user whose
   path has a space, which on macOS and Windows is common.
2. Idle watchdog with a distinct exit code (#4), plus detection of the
   `encrypted_content` poison error (#3). Together these are most of the
   babysitting.
3. Clean up (or record) a failed dispatch so recovery does not need manual git (#2).
4. `--copy-untracked` and automatic `node_modules` linking (#6, #7).
5. `--merge --no-commit` / `-m` so the file audit is usable with a custom commit (#10).
6. Docs: the `--minify`/grep trap (#9), the `npx` workaround (#5), and a short
   "what to do when a run stalls" section.

## What worked well (do not regress)

- **The per-run `.diff` as a review package.** One file with the commit list and
  10 lines of context is exactly right.
- **`--role review` being genuinely read-only.** Nine review runs, zero
  accidental edits.
- **The `## RESULT` contract.** Machine-routable status plus a free-text
  concerns field. `DONE_WITH_CONCERNS` and `BLOCKED` both earned their keep.
- **Checkpoint commits per step.** When runs died mid-flight, the work up to the
  last step was always intact and re-dispatchable.
- **Model choice for the final review.** A *different* model for the
  whole-branch review paid for itself.
- **Brief quality really is the lever.**

## Bottom line

"Fix the path encoding and add a stall watchdog, and the experience goes from
'needs an attentive operator' to 'leave it running'."
