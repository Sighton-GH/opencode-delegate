# opencode-delegate

A Claude Code plugin that runs **opencode-driven development**: Claude
brainstorms, writes the plan, and writes every brief; [opencode](https://opencode.ai)
sessions on free models — Big Pickle by default — implement each task,
review each task, and review the whole branch. It is a mirror of
superpowers' `subagent-driven-development` with opencode in every subagent
seat.

Claude thinks and adjudicates. opencode models do the engineering. You
approve the plan once.

This repo is also a Claude Code plugin marketplace, so it installs on any
machine and works in every project.

## How it works

1. You ask for something worth a plan — a feature, a refactor, a test
   suite. Claude invokes the skill itself (or you type
   `/opencode-driven-development`).
2. Claude brainstorms with you until the design is settled, writes an
   implementation plan (file map, bite-sized tasks with the code and tests
   spelled out), and shows it to you. **You approve the plan once.**
3. For each task, Claude writes a brief and runs `oc-task`. That creates a
   git worktree on branch `oc/<plan>` (first task) and dispatches a fresh
   opencode session per task inside it, permissions auto-approved because
   the worktree is the sandbox. The model implements, commits per step, runs
   the verification command, and ends with a `## RESULT` block.
4. Claude re-runs the verification command itself, then dispatches an
   opencode **reviewer** (`--role review`, opencode's read-only `plan` agent)
   with the task's diff. Findings go into a fix loop — resume the same
   session up to three times, then a fresh session on a different free
   model — with a scoped re-review after every fix. A ledger in `.oc-runs/`
   records every decision.
5. After the last task, a final whole-branch review on the strongest free
   model. Then Claude reports every ruling it made and offers: merge now
   (`oc-task --merge`, `--no-ff`, one revert point via `oc-undo`), open a
   PR, or leave the branch.

Nothing stops for you between plan approval and the end except the four
things that should: a destructive operation, a security-sensitive action, a
side effect outside the worktree (merge/push/publish), or a plan so broken
every path is a guess. Tasks touching **auth, secrets, crypto, or payments**
get one extra question: whether you're OK sending that code to an opencode
model.

## Prerequisites

Install these before the plugin. The plugin does not carry any of them.

| Tool | Why | Check |
|---|---|---|
| Claude Code 2.1+ | plugin host | `claude --version` |
| [opencode](https://opencode.ai) 1.18+ or 2.x | runs the models | `opencode --version` |
| git 2.x | worktrees, merges, reverts | `git --version` |
| jq | parses opencode's JSON | `jq --version` |
| curl | talks to opencode's local server | `curl --version` |
| bash 4+ | the scripts | `bash --version` |

**opencode must be installed *and authenticated* separately.** Authentication
is machine state — a credential file in your home directory — and the plugin
does not carry it. Run `opencode providers list` and make sure `OpenCode
Zen` is listed (the free models live there). If it isn't, run
`opencode auth login` and pick it.

opencode 1.18+ and 2.x are both supported; oc-task detects the major version
and speaks that API. Under 2.x it authenticates to opencode's local server
with a per-run password it generates itself — nothing extra to set up.

**Recommended companion:** the `superpowers` plugin. When it is installed
the skill uses `superpowers:brainstorming`, `superpowers:writing-plans`, and
`superpowers:finishing-a-development-branch` for those steps. Without it,
built-in fallbacks cover the same ground (a condensed plan template ships
in the skill).

If `jq` is missing on Linux and you can't `apt install` it, a static binary
works: download `jq-linux-amd64` from the
[jq releases page](https://github.com/jqlang/jq/releases) into a directory on
your PATH and `chmod +x` it.

## Install

From inside Claude Code 2.1.275 or later, one command adds the marketplace
and installs the plugin:

```
/plugin install opencode-delegate --marketplace Sighton-GH/opencode-delegate
```

On an older Claude Code, run these two commands one at a time — paste the
first, wait for it to finish, then paste the second.

1. Add the marketplace:

   ```
   /plugin marketplace add Sighton-GH/opencode-delegate
   ```

2. Install the plugin:

   ```
   /plugin install opencode-delegate
   ```

Then start a new Claude Code session (plugins load at startup). To confirm
it's live, ask Claude to run `oc-models --free` — you should see a list of
`provider/model` ids. If you get "command not found", the plugin is not
enabled for this session; check `/plugin`.

Plugins add `bin/` to the PATH the Bash tool uses, so `oc-task`, `oc-models`,
and `oc-undo` are bare commands for Claude in every project.

`claude plugin details opencode-delegate` shows the plugin's component
inventory and its projected per-session token cost.

### Local development install

To hack on the plugin itself, register your clone as a marketplace instead of
the GitHub one:

```
git clone https://github.com/Sighton-GH/opencode-delegate.git
cd opencode-delegate
```

Then, from the clone, register it (one command at a time):

```
claude plugin marketplace add "$PWD"
```

```
claude plugin install opencode-delegate@opencode-delegate
```

Edits to `bin/` take effect immediately (the scripts run from your clone).
Edits to `SKILL.md` take effect in the next session. Before committing:

```
bash plugins/opencode-delegate/tests/run.sh
```

```
claude plugin validate ./plugins/opencode-delegate --strict
```

```
claude plugin validate . --strict
```

To ship a change to people installed from GitHub, bump `version` in both
`plugins/opencode-delegate/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` — `claude plugin update` only refetches when
the version changes. Users then run these one at a time:

```
claude plugin marketplace update opencode-delegate
```

```
claude plugin update opencode-delegate
```

What changed in each version is in [CHANGELOG.md](CHANGELOG.md).

## When it fires

The skill fires whenever Claude would write a plan with two or more tasks —
the same moment superpowers' `subagent-driven-development` would fire — and
takes its place. One-line fixes, investigation, and questions stay with
Claude. You can also invoke it directly with `/opencode-driven-development`.

If you'd rather Claude never start it on its own, set
`disable-model-invocation: true` in
`plugins/opencode-delegate/skills/opencode-driven-development/SKILL.md`.

The skill's posture, in its own words: *opencode models are capable
engineers, not throwaway ones. Your leverage is the brief. When a run
disappoints, the first suspect is the brief, not the model.* Claude does
not decide work is "too hard for opencode" and do it itself; it writes a
better brief.

## Worked example

You, in a TypeScript/Express repo:

> Add soft-delete for projects: `DELETE /api/projects/:id`, owner-only,
> memberships go too, with tests.

**Brainstorm.** Claude asks the two questions that change the design (hard
vs soft delete of memberships; who counts as owner), proposes an approach,
you confirm.

**Plan.** Claude writes `docs/superpowers/plans/2026-09-12-project-soft-delete.md`:
a file map, global constraints ("errors use `HttpError` from
`src/errors.ts`"), and three tasks — service function, route + registration,
tests — each with exact signatures and the test cases named. You read it and
say "go". That is the last approval.

**Task 1.** Claude writes `.oc-runs/project-soft-delete/task-1-brief.md`
(objective, context naming `teamService.ts` as the pattern, constraints,
files, interfaces, numbered steps, verification, RESULT format) and runs:

```
oc-task --brief .oc-runs/project-soft-delete/task-1-brief.md --branch oc/project-soft-delete
```

```
run:      20260912T141530-oc_project-soft-delete  (role: implement)
session:  ses_f67fcd9c5ffeuPtAzaubTh8qph
model:    opencode/big-pickle
exit:     0 (success)
duration: 3m41s
branch:   oc/project-soft-delete  (worktree .oc-worktrees/oc/project-soft-delete, base main @ 9c1f2ab)
checkpoint: 3e9f99a
files:
  +38 -0  src/services/projectService.ts
## RESULT
Status: DONE
Files changed: src/services/projectService.ts
Commits: 3e9f99a Step 1: add softDeleteProject
Commands run and their outcome: npx tsc --noEmit (clean)
Could not complete: none
Assumptions made: none
Concerns or questions: none
log:  .oc-runs/20260912T141530-oc_project-soft-delete.log
diff: .oc-runs/20260912T141530-oc_project-soft-delete.diff
```

Claude re-runs `npx tsc --noEmit` in the worktree, writes a review brief
pointing at that `.diff`, and dispatches the reviewer:

```
oc-task --brief .oc-runs/project-soft-delete/task-1-review-brief.md --role review --branch oc/project-soft-delete --session new
```

```
## RESULT
Spec: FAIL
Quality: NEEDS_WORK
Findings:
- [Important] src/services/projectService.ts:31 — memberships updated outside the transaction — move the updateMany inside prisma.$transaction
Cannot verify from diff:
- none
```

**Fix round 1.** Claude resumes the implementer's session with a fix brief
(`--session ses_f67fcd9c5ffeuPtAzaubTh8qph`), re-runs the typecheck, and
dispatches a scoped re-review of the fix diff: `ALL ADDRESSED`. Ledger:
`Task 1: fix round 1/5 (1 addressed, 0 open; commits 3e9f99a..a41c0d2)`,
then `Task 1: complete`.

**Tasks 2 and 3** run the same way with `--session new`. **Final review**:
`oc-task --branch-diff --branch oc/project-soft-delete` → whole-branch diff
file → reviewer on a different free model → `MERGEABLE`.

**Finish.** Claude lists the rulings it made, re-runs the full verification
command on the branch, and offers merge / PR / leave. You say merge:

```
oc-task --merge --branch oc/project-soft-delete --verified "npx vitest run && npx tsc --noEmit"
merged:  oc/project-soft-delete -> main @ c37db3d (--no-ff)
undo:    oc-undo
```

## Command reference

All three live in `plugins/opencode-delegate/bin/`. Each prints usage with
`--help`. Replace `PATH`, `NAME`, `ID`, `COMMAND`, `PROVIDER/MODEL` with
real values.

### `oc-task`

```
oc-task --brief PATH [--role implement|review] [--model PROVIDER/MODEL] [--branch NAME] [--base REF]
        [--session ID|new] [--continue-from PARENT_BRIEF] [--idle-timeout SECONDS]
        [--copy-untracked PATH]... [--install | --link-node-modules | --no-link-node-modules]
        [--dry-run]
oc-task --branch-diff --branch NAME
oc-task --merge (--branch NAME | --session ID) --verified "COMMAND" [-m MSG | --no-commit | --squash]
```

**Dispatch** (`--brief`): validates the brief, creates or reuses the
worktree, starts a private `opencode serve` on a random port, creates the
session over its HTTP API, runs `opencode run --attach … --auto` with the
brief on stdin, commits anything left uncommitted as a final checkpoint,
and prints the summary. Files:

- `.oc-runs/RUNID.json` — run record (branch, base, session, role, exit,
  RESULT). Written at dispatch with `"state": "running"` and rewritten when
  the run ends, so a run whose wrapper died still leaves its session id,
  base and brief behind.
- `.oc-runs/RUNID.summary` — the printed summary, saved before it is printed
- `.oc-runs/RUNID.diff` — this run's changes only (commit list + diff with
  10 lines of context) — the review package for that task
- `.oc-runs/RUNID.log` — raw JSON event stream; read only when a run fails
- `.oc-runs/RUNID.serve.log` — the run's own server log (WARN and above).
  Provider errors — rate limits, usage caps, upstream failures — are written
  here and nowhere else; the summary's `errors:` section quotes them as
  `server:` lines.

Every path out of a dispatch writes the record and the summary: a normal
end, a signal (INT, TERM, HUP — exit 128+N, the run is stopped and its work
checkpointed), and a failure inside oc-task itself (exit 1, naming the line
that failed). The wrapper prints `oc-task: dispatched run RUNID (session ID)`
to stderr as the model starts, so a long run can be followed in its log.

Worktree rules: the first run on a branch creates `.oc-worktrees/NAME` off
current HEAD, or off `--base REF` — a sibling branch a task depends on, or
another tool's branch a review should read. The record keeps REF's commit as
the branch base, so `--branch-diff` shows only this branch's own changes;
merge the base branch first, or `--merge`'s audit sees its files too.
`--session ID` resumes that session in its worktree. `--session new --branch
NAME` starts a fresh session in the existing worktree (every task after the
first; continuation after a dead session). It also adopts a branch that has
no worktree or run record — one made by hand or by another tool — and gives
it a worktree; a branch oc-task did not create is never deleted. Anything
else with an existing worktree or branch is refused, with the command that
would work.

One run per worktree: a dispatch into a worktree where another oc-task run
is live is refused, because a review's cleanup resets the worktree it ran in
and would discard the live run's uncommitted work. Runs on different
branches may overlap, but a free tier limits per account, not per run;
oc-task warns when other live `opencode run` processes use the same model.

`--continue-from PARENT_BRIEF` is for continuation and follow-up briefs. The
brief then needs only the sections it changes: every required section it
lacks must be in the parent, the model receives the brief with the parent
below it, and `--merge` counts the parent's `# Files` as well.

Sessions are created with every permission allowed except `git stash`, which
is denied (`*git stash*`, `*git -C * stash*`). The stash is shared by every
worktree of a repository; a model's `git stash pop` once applied the user's
own WIP stash into its worktree.

`--role review` runs opencode's built-in read-only `plan` agent: it can read,
grep, and run commands, but every edit is denied. Required brief sections
differ per role:

| role | required `#` sections |
|---|---|
| implement | Objective, Files, Tasks, Verification, Definition of done, Required output |
| review | Objective, Diff under review, Required output |

Model precedence: `--model` > `$OC_DELEGATE_MODEL` > `model=` line in
`~/.config/oc-delegate/config` (respects `$XDG_CONFIG_HOME`; created on first
run) > built-in `opencode/big-pickle`. Any id not in
the live catalog is refused immediately with the current free list.

`--dry-run` prints the resolved model, branch, worktree, and section check
without creating anything. A rejected brief lists every missing section at
once.

`--idle-timeout SECONDS` sets how long a run may produce no output at all
before the watchdog kills it. Default 420 (7 minutes); `0` disables the
watchdog. Also settable as `idle_timeout=` in
`${XDG_CONFIG_HOME:-~/.config}/oc-delegate/config` or as
`$OC_DELEGATE_IDLE_TIMEOUT`. Precedence: flag, then environment, then config,
then built-in default — the same order as the model setting. A killed run
poisons its session (the reasoning state the provider expects back is lost),
so exit 6 also records the session dead.

The watchdog also reads the run's server log every few seconds, because a
provider's refusal lands there while the run itself just goes quiet. A usage
cap (`Usage limit reached. Resets in 3h 51m.`) stops the run at once with
exit 5 and the reset time. A rate limit gets `rate_limit_grace` seconds
(default 90; `rate_limit_grace=` in the config or
`$OC_DELEGATE_RATE_LIMIT_GRACE`) for opencode's own retry to recover — any
new output clears it — and then exits 5. An error event in the run's own
stream followed by 60 seconds of silence (`$OC_DELEGATE_ERROR_GRACE`) is
stopped as exit 1. A stall that coincides with a provider rate limit, or a
run that produced no model output at all, is reported as 5 rather than 6.

`--copy-untracked PATH` (repeatable) copies a path from the base checkout into
a freshly created worktree and keeps it out of the run's diff. A worktree forks
from `HEAD`, so files a user just dropped in — often the very inputs a task is
about — are simply missing from it. The copy is recorded in the run record's
`provisioned` list and excluded from every git operation inside the worktree.

Dependencies in a fresh worktree. By default (`auto`, when the repo root
has a `node_modules`) the worktree gets its **own** `node_modules`
directory whose entries are links to the base checkout's packages, and the
same for every workspace with an install of its own (`packages/x/node_modules`).
Workspace packages — npm's relative links into the repo — resolve to the
worktree's copies, so a cross-package typecheck reads the branch's code;
`.cache`, `.vite` and `.vite-temp` are left out. Because the directory is
real, an `npm ci` or `npm install` inside the worktree replaces the links
instead of writing through them. Before 0.5.0 the whole directory was one
symlink: workspace packages resolved to the base checkout, and an `npm ci`
in the worktree emptied the base checkout's `node_modules`.

- `--install` runs the lockfile's clean install in the new worktree instead
  (`npm ci`, `pnpm install --frozen-lockfile`, `yarn install
  --frozen-lockfile` or `bun install --frozen-lockfile`; log in
  `.oc-runs/RUNID.install.log`). Use it when the gates must see a
  dependency change, a new workspace package, or built workspace output.
- `--link-node-modules` links even when it would not by default, and fails
  if the base checkout has no `node_modules`.
- `--no-link-node-modules` leaves dependencies out entirely.
- When the base checkout has a `package.json` but no `node_modules` (a
  fresh clone, or a Claude Code worktree), oc-task warns and suggests
  `--install`.

Packages are still links, so `npx <tool>` can fail with `Permission
denied`; call the CLI entry point directly instead (e.g. `node
node_modules/@playwright/test/cli.js test`) and put that exact form in the
brief's Verification section.

The summary's `warning:` lines also flag what a reviewer should look at: a
checkpoint that failed (the run's last work is still uncommitted in the
worktree), a source file whose diff is binary or gained raw control bytes
(an escape sequence like `\u0000` written as the byte itself), other live
runs on the same model, and an opencode database over 5 GB (see "Disk
usage" below).

Exit codes:

| Code | Meaning |
|---|---|
| 0 | success (implement: changes produced; review: RESULT block present) |
| 1 | opencode errored, a setup problem, or a failure inside oc-task (the summary names the line) |
| 2 | brief rejected — missing or malformed sections |
| 3 | implement run completed but produced zero changes (the exit line says so when the model stopped with NEEDS_CONTEXT or BLOCKED) |
| 4 | session unrecoverable — image limit or a poisoned reasoning state (never retried) |
| 5 | rate or usage limited by the provider, or no model output at all (`limit:` and `reset:` lines say which and until when) |
| 6 | stalled (output, then none for the idle timeout; session dead) |
| 7 | opencode's local database was busy — another run, a bulk `opencode session delete`, a `VACUUM` |
| 128+N | the wrapper was killed by signal N (130 INT, 143 TERM); run stopped, work checkpointed, summary and record written |

Non-zero exits leave the worktree in place, except a dispatch that fails before
a session exists, which removes what it created. `.oc-worktrees/` and
`.oc-runs/` are added to `.gitignore` on first run (left uncommitted; the one
change `--merge` and `oc-undo` tolerate in an otherwise clean tree).

**`--branch-diff`** writes the whole-branch diff (base..branch, with commit
list and stat) to `.oc-runs/TIMESTAMP-NAME.branch.diff` and prints the path.
It is the final reviewer's input.

**`--merge`** merges the branch into the base it forked from with `--no-ff`.
It refuses, with a specific reason, unless all of these hold: you are on the
base branch with a clean tree; the latest *implement* run on the branch
finished, exited 0 and has a parseable `## RESULT` block; you passed
`--verified "COMMAND"` (your attestation that you re-ran verification
yourself — oc-task does not trust the model); every changed file is named
in the `# Files` section of some brief dispatched to that branch, or of its
`--continue-from` parent; and there are no conflicts. The commit carries `oc-task-run:`, `model:`, `spec:`,
`branch:`, `session:`, `verified:` trailers. The branch is never deleted.

The three merge modes exist because the six refusals above are a genuine
audit: before v0.4.0 a caller who needed a particular commit message or a
squash had to integrate by hand and lost the audit entirely. All three run
every refusal first, unchanged and in the same order; only the commit step
differs.

`-m MESSAGE` (`--message`) uses your subject instead of the generated `oc-task
merge: BRANCH`. The `oc-task-run:` trailer is still written, so `oc-undo`
still finds the merge. `--no-commit` runs every check, merges into the index
and working tree, and stops without committing. The prepared message — subject
and all trailers — is written to `.git/OC_TASK_MERGE_MSG`, so `git commit -F
.git/OC_TASK_MERGE_MSG` reproduces exactly what the default path would have
committed. A conflict still aborts the merge and refuses, leaving the tree as
it was. `--squash` stages the branch's net change as an ordinary change set
rather than a merge. It implies `--no-commit`. A squashed commit is not a
merge commit, and `oc-undo` searches `git log --merges`, so it will not find
one: it is the one way to lose the undo path.

### `oc-models`

```
oc-models             all models, one provider/model per line, free ones first
oc-models --free      free only
oc-models --verbose   add columns: context window, toolcall, reasoning, release date
```

"Free" means the live catalog reports zero input and output cost. Nothing is
hardcoded — Zen's free tier rotates. Ask Claude "what can you delegate to
right now?" and it runs this.

`oc-models` reads the catalog through a temporary file. opencode exits
without draining its output, so a pipe whose reader is slower than opencode
kept only the first ~50 KB of a ~600 KB catalog — the `jq: parse error:
Unfinished string at EOF` that 0.4.0 printed above a partial list. A catalog
that still does not parse now exits 3 and lists nothing.

**When the default model disappears.** The skill checks `oc-models --free`
once per plan. If `opencode/big-pickle` is gone Claude
picks the best free replacement using `--verbose`: the free model with
`toolcall=yes` and the
largest context window (newest release wins ties), and records the choice
in the ledger. It never picks a model without tool calling and never falls
back to a paid one. To pin a replacement yourself, put
`model=PROVIDER/MODEL` in `~/.config/oc-delegate/config`.

### `oc-undo`

```
oc-undo          revert the most recent oc-task merge
oc-undo --list   show recent oc-task merges (and whether each was reverted)
```

Finds the newest merge commit carrying the `oc-task-run:` trailer and runs
`git revert -m 1` on it, printing the run id, brief path, and model. Refuses
on a dirty tree and on a merge already reverted.

## Troubleshooting

### "session poisoned by image limit — not resumable" (exit 4)

opencode sessions die permanently at 50 images. Images accumulate across the
whole session history whenever the model screenshots something or reads an
image file; the full history is resent every turn; once the count crosses 50
every subsequent turn fails with a fatal 400. This is a known opencode bug —
[#48647](https://github.com/sst/opencode/issues/48647) and
[#39677](https://github.com/sst/opencode/issues/39677). The error is not
classified as a context overflow, so opencode's own compact-and-strip-media
auto-recovery never fires. The session is unrecoverable, not merely errored.

What oc-task does: exits 4, records the session id as dead in the run log and
run record, and refuses `--session THAT-ID` forever. The worktree and its
checkpoint commits are the recovered work. What Claude does: writes a
continuation brief from the first incomplete step and dispatches it with
`--session new --branch NAME` into the same worktree.

Prevention is the brief's job: the verbatim "Do not read, open, or
screenshot any image or binary file" constraint, and right-sized tasks.

### Rate limited (exit 5)

Free-tier throttling mid-task is an expected condition, not a bug. oc-task
exits 5 and Claude stops and tells you; it does not retry on its own. Wait,
or pick another model from `oc-models --free` and resume with `--session ID`.

A provider's refusal reaches oc-task through the run's own server log, not
the run's event stream: the run itself just goes quiet. 0.4.0 waited out the
idle timeout and called that a stall (exit 6), or sometimes exited with no
summary at all. Now the summary's `limit:` line quotes the provider, and a
`reset:` line gives the reset time when the provider names one. A usage cap
exits at once; a rate limit after `rate_limit_grace` seconds without
recovery. A run that produced no model output at all also exits 5: on the
free tier that is almost always a limit.

The limit is per account. Runs from other Claude sessions on the same
machine share it, and oc-task's warning about other live runs on the model
counts them.

### "stalled — no output for Ns" (exit 6)

A run can stop producing output with no error at all: the assistant message
exists, has zero parts, and `error: null`. That is a silent provider throttle,
not a crash, and before v0.4.0 it hung until an operator noticed — one run
burned 54 minutes that way. oc-task now watches the run log and kills a run
that has produced nothing for `--idle-timeout` seconds (default 420).

Killing a run poisons its session (see below), so exit 6 also marks the session
dead. The checkpoint commits in the worktree are the recovered work: write a
continuation brief from the first incomplete step and dispatch it with
`--session new --branch NAME --continue-from ORIGINAL_BRIEF`. Raise
`--idle-timeout` for tasks with genuinely long silent stretches, or set
`idle_timeout=0` in the config to disable the watchdog.

Since 0.5.0 a stall is exit 6 only when the run had produced output and no
provider error explains the silence; otherwise it is exit 5 (above).

### "opencode's local database was busy" (exit 7)

opencode keeps its sessions in one SQLite database
(`~/.local/share/opencode/opencode.db`). Writers contend for it: several
runs at once, a bulk `opencode session delete`, or a `VACUUM`. A run that
loses shows `Failed to execute statement` under `errors:`. Nothing is wrong
with the provider or the brief: wait for the other work to finish and
re-dispatch `--session new`.

### Killed by a signal (exit 128+N)

Interrupting or killing `oc-task` (INT, TERM, HUP) stops the model's whole
process tree, checkpoints whatever it left uncommitted, and still writes the
summary and the run record. Resume with `--session ID`, or `--session new` if
that exits 4. A SIGKILL cannot be caught: then the run record still says
`"state": "running"`, the session id in it is good for a resume, and any
`opencode` process it left behind shows in `ps`.

### Disk usage

opencode stores every event of every session in its database, and a long
oc-task run can add gigabytes. oc-task warns when the database passes 5 GB
(`$OC_DELEGATE_DB_WARN_GB` changes the threshold). To reclaim space, delete
the sessions of runs you have merged — run records name them, and oc-task
titles its sessions `oc-task RUNID` — with `opencode session delete ID`,
then compact the database with no opencode run live:

```
sqlite3 ~/.local/share/opencode/opencode.db 'VACUUM;'
```

```
sqlite3 ~/.local/share/opencode/opencode.db 'PRAGMA wal_checkpoint(TRUNCATE);'
```

The checkpoint matters: until it runs, the vacuumed copy sits in a
`-wal` file as large as the database. Do not copy the database first on a
nearly full disk — the copy plus the vacuum can fill it. Worktrees are the
other large item: each carries its own `node_modules` once installed;
remove merged ones with `git worktree remove`.

### "session poisoned — encrypted_content" (exit 4)

An interrupted turn — a killed run, a dropped stream — loses the reasoning
state the provider expects back on the next turn, and every later turn in that
session fails instantly with ``reasoning `encrypted_content` was not issued to
this caller``. Like the image limit, the session is unrecoverable rather than
merely errored, so oc-task exits 4, records the session dead with
`dead_reason: "encrypted-content"`, and refuses `--session THAT-ID` forever.
Re-dispatch with `--session new --branch NAME`.

### "opencode did not return a session id" / "could not start opencode serve"

opencode isn't authenticated, or something is wrong with the install. Run
`opencode providers list` and `opencode run "say hi" < /dev/null` by hand.
The `< /dev/null` matters: `opencode run` reads stdin to EOF whenever stdin is
not a terminal, so inside an agent's shell (where stdin is a socket that
never closes) it hangs silently without it. oc-task always redirects stdin.

### Worktree cleanup

oc-task never deletes worktrees or branches. When you're done with one:

```
git worktree remove .oc-worktrees/NAME
git branch -D NAME
```

`git worktree list` shows what's there. `.oc-runs/` is plain files; delete
old runs whenever you like (a run record is needed for `--merge` and
`--session` on that branch, and the plan's ledger lives there until the
branch is finished).

A dispatch that fails before a session exists (the server will not start, or
session-create is refused) now removes the branch and worktree it created,
so recovery no longer needs `git worktree remove --force` by hand.
`--session new --branch B` will also adopt a worktree that exists but has no
run record, instead of refusing.

### Undoing a merge

`oc-undo`. It reverts only the newest oc-task merge; run `oc-undo --list`
first if you're not sure which that is. For an older one, use the sha from
`--list` with `git revert -m 1 SHA` yourself.

### Reading a failed run's log

`.oc-runs/RUNID.log` is opencode's raw JSON event stream, one event per line,
with opencode's own stderr mixed in. `jq -R 'fromjson?'` skips the lines that
are not JSON; plain `jq` stops at the first one:

```
jq -rR 'fromjson? | select(.type=="text") | .part.text' .oc-runs/RUNID.log      # the model's prose
jq -cR 'fromjson? | select(.type=="error")' .oc-runs/RUNID.log                  # errors
jq -rR 'fromjson? | select(.type=="tool_use") | .part.tool' .oc-runs/RUNID.log  # tools called
```

An error event that says only "Unexpected server error. Check server logs
for details." has its cause in `.oc-runs/RUNID.serve.log`:

```
grep 'level=ERROR' .oc-runs/RUNID.serve.log
```

## Layout

```
.claude-plugin/marketplace.json                      registers the plugin
plugins/opencode-delegate/
  .claude-plugin/plugin.json
  bin/oc-task  oc-models  oc-undo                    on PATH when the plugin is enabled
  skills/opencode-driven-development/
    SKILL.md                                         the process (mirror of subagent-driven-development)
    implementer-brief.md                             per-task brief template (+ fix-round variant)
    task-reviewer-brief.md                           per-task review
    re-review-brief.md                               scoped re-review after a fix round
    final-reviewer-brief.md                          whole-branch review
    plan-template.md                                 fallback when superpowers:writing-plans is absent
  tests/run.sh  tests/lib/                           offline suite; a stub stands in for opencode
  README.md
docs/superpowers/specs/                              field reports the releases were built from
docs/superpowers/plans/                              what each release changed for each finding
CHANGELOG.md
```

Dependencies: bash, git, opencode, jq, curl. Nothing else. No MCP server, no
daemon, no parallel dispatch.

## License

MIT
