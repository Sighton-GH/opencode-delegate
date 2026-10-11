# Changelog

## 0.5.0 — 2026-10-10

Built from the v0.4.0 field report
(`docs/superpowers/specs/2026-09-27-field-report-v0.4.0.md`) and a second
project's evaluation log. Each finding and what became of it is in
`docs/superpowers/plans/2026-10-10-v0.5.0-field-report-fixes.md`.

**Provider limits are reported as limits.** The per-run `opencode serve` now
logs WARN and above to `.oc-runs/RUNID.serve.log`, which is the only place a
provider's refusal is written. The watchdog reads it as the run goes:
- A usage cap stops the run at once with exit 5 and the reset time.
- A rate limit opencode does not recover from within `rate_limit_grace`
  (90 s) also exits 5.
- A stall behind a rate limit, or a run with no model output at all, exits 5
  instead of 6.
- An error event followed by 60 s of silence is stopped as exit 1.
- New exit 7: opencode's own database was busy.

**Every exit path reports.** The run record is written at dispatch
(`"state": "running"`) and rewritten at the end. The summary is saved to
`.oc-runs/RUNID.summary` and printed after a normal end, after INT, TERM or
HUP (exit 128+N, with the run stopped and its work checkpointed), and after
a failure inside oc-task (which names the line). A failed checkpoint is
reported instead of ending the wrapper.

**Parsing.**
- The run log is read line by line, so a stderr line no longer hides every
  event after it.
- A RESULT block with every line doubled prints once.
- A NEEDS_CONTEXT or BLOCKED status with no heading is surfaced.
- Server-side errors appear under `errors:` as `server:` lines.

**node_modules.** A fresh worktree gets its own `node_modules` directory of
per-entry links, nested workspace installs included. Workspace packages
resolve to the worktree, and an install inside the worktree no longer
writes through into the base checkout. New `--install` runs the lockfile's
clean install instead. oc-task warns when the base has no `node_modules`.

**Branches and briefs.**
- `--base REF` forks a new branch from REF.
- `--session new --branch B` adopts an existing branch with no worktree and
  never deletes a branch it did not create.
- `--continue-from PARENT` lets a continuation brief carry only what
  changed; the merge audit counts the parent's `# Files`.
- A bare filename after a full path in `# Files` resolves as its sibling.

**Safety.**
- `git stash` is denied to every session; the stash is shared across
  worktrees.
- One live run per worktree.
- A warning when other live runs use the same model.
- A warning when a diff adds raw control bytes to a source file.
- A warning when opencode's database passes 5 GB.

**Fixes.**
- The model check no longer refuses a listed model when `grep -q` cut
  opencode off mid-write.
- `oc-models` reads the catalog from a file, never a pipe. A slow pipe
  truncated it, causing the `jq: parse error`. An unparseable catalog now
  exits 3, not jq's 5.
- `--help` lists every flag.
- `--session ID` with no record says how to start fresh.
- Killing a group no longer waits 5 s on an already-dead child.
- The lock is taken atomically before the worktree is touched, and a lock left
  by a dead wrapper is replaced.
- A signal during provisioning (`--install`, `--copy-untracked`) removes the
  worktree and branch it just made.
- A worktree deleted by hand is re-created for its surviving branch
  (`git worktree prune` first).
- Errors from opencode's title agent (`small=true`) never count as the run's
  rate limit.

## 0.4.0 — 2026-09-13

Idle watchdog (exit 6), poisoned-session detection, worktree provisioning
(`--copy-untracked`, linked `node_modules`), merge modes (`-m`,
`--no-commit`, `--squash`), merge audit over every brief on a branch.

## 0.3.0 — 2026-09-12

opencode-driven development: the subagent-driven-development mirror.

## 0.2.0 — 2026-09-12

Claude may invoke the skill itself; replacement model when the default is gone.
