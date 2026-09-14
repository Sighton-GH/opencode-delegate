# opencode-delegate

A Claude Code plugin that runs **opencode-driven development**: Claude
brainstorms, writes the plan, and writes every brief; [opencode](https://opencode.ai)
sessions on free models — Muse Spark 1.3 by default — implement each task,
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
| [opencode](https://opencode.ai) 1.18+ | runs the models | `opencode --version` |
| git 2.x | worktrees, merges, reverts | `git --version` |
| jq | parses opencode's JSON | `jq --version` |
| curl | talks to opencode's local server | `curl --version` |
| bash 4+ | the scripts | `bash --version` |

**opencode must be installed *and authenticated* separately.** Authentication
is machine state — a credential file in your home directory — and the plugin
does not carry it. Run `opencode providers list` and make sure `OpenCode
Zen` is listed (the free models live there). If it isn't, run
`opencode auth login` and pick it.

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

From inside Claude Code:

```
/plugin marketplace add Sighton-GH/opencode-delegate
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
claude plugin marketplace add "$PWD"
claude plugin install opencode-delegate@opencode-delegate
```

Edits to `bin/` take effect immediately (the scripts run from your clone).
Edits to `SKILL.md` take effect in the next session. Before committing:

```
claude plugin validate ./plugins/opencode-delegate --strict
```

To ship a change to people installed from GitHub, bump `version` in both
`plugins/opencode-delegate/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` — `claude plugin update` only refetches when
the version changes. Users then run:

```
claude plugin marketplace update opencode-delegate
claude plugin update opencode-delegate
```

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
model:    opencode/muse-spark-1.3-contributor-free
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
oc-task --brief PATH [--role implement|review] [--model PROVIDER/MODEL] [--branch NAME] [--session ID|new] [--dry-run]
        [--idle-timeout SECONDS] [--copy-untracked PATH]... [--no-link-node-modules]
oc-task --branch-diff --branch NAME
oc-task --merge (--branch NAME | --session ID) --verified "COMMAND" [-m MSG | --no-commit | --squash]
```

**Dispatch** (`--brief`): validates the brief, creates or reuses the
worktree, starts a private `opencode serve` on a random port, creates the
session over its HTTP API, runs `opencode run --attach … --auto` with the
brief on stdin, commits anything left uncommitted as a final checkpoint,
and prints the summary. Files:

- `.oc-runs/RUNID.diff` — this run's changes only (commit list + diff with
  10 lines of context) — the review package for that task
- `.oc-runs/RUNID.log` — raw JSON event stream; read only when a run fails
- `.oc-runs/RUNID.json` — run record (branch, base, session, role, exit, RESULT)

Worktree rules: the first run on a branch creates `.oc-worktrees/NAME` off
current HEAD. `--session ID` resumes that session in its worktree.
`--session new --branch NAME` starts a fresh session in the existing
worktree (every task after the first; continuation after an image-limit
death). Anything else with an existing worktree is refused.

`--role review` runs opencode's built-in read-only `plan` agent: it can read,
grep, and run commands, but every edit is denied. Required brief sections
differ per role:

| role | required `#` sections |
|---|---|
| implement | Objective, Files, Tasks, Verification, Definition of done, Required output |
| review | Objective, Diff under review, Required output |

Model precedence: `--model` > `$OC_DELEGATE_MODEL` > `model=` line in
`~/.config/oc-delegate/config` (respects `$XDG_CONFIG_HOME`; created on first
run) > built-in `opencode/muse-spark-1.3-contributor-free`. Any id not in
the live catalog is refused immediately with the current free list.

`--dry-run` prints the resolved model, branch, worktree, and section check
without creating anything.

`--idle-timeout SECONDS` sets how long a run may produce no output at all
before the watchdog kills it. Default 420 (7 minutes); `0` disables the
watchdog. Also settable as `idle_timeout=` in
`${XDG_CONFIG_HOME:-~/.config}/oc-delegate/config` or as
`$OC_DELEGATE_IDLE_TIMEOUT`. Precedence: flag, then environment, then config,
then built-in default — the same order as the model setting. The provider's
explicit rate limit surfaces as an error and exits 5; the silent throttle
stops emitting with no error and no end of turn, and before v0.4.0 it hung
until an operator noticed. A killed run poisons its session (the reasoning
state the provider expects back is lost), so exit 6 also records the session
dead.

`--copy-untracked PATH` (repeatable) copies a path from the base checkout into
a freshly created worktree and keeps it out of the run's diff. A worktree forks
from `HEAD`, so files a user just dropped in — often the very inputs a task is
about — are simply missing from it. The copy is recorded in the run record's
`provisioned` list and excluded from every git operation inside the worktree.

`--link-node-modules` / `--no-link-node-modules` controls whether `node_modules`
is symlinked from the base checkout into a fresh worktree. The default (`auto`)
links it when the repo root has a `node_modules` directory. Because it is a
symlink, `npx <tool>` can fail with `Permission denied`; call the CLI entry
point directly instead (e.g. `node node_modules/@playwright/test/cli.js test`)
and put that exact form in the brief's Verification section.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | success (implement: changes produced; review: RESULT block present) |
| 1 | opencode errored, or a setup problem |
| 2 | brief rejected — missing or malformed sections |
| 3 | implement run completed but produced zero changes |
| 4 | session unrecoverable — image limit or a poisoned reasoning state (never retried) |
| 5 | rate limited by the provider |
| 6 | stalled (no output for the idle timeout; session dead) |

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
exited 0 and has a parseable `## RESULT` block; you passed
`--verified "COMMAND"` (your attestation that you re-ran verification
yourself — oc-task does not trust the model); every changed file is named
in the `# Files` section of some brief dispatched to that branch; and there
are no conflicts. The commit carries `oc-task-run:`, `model:`, `spec:`,
`branch:`, `session:`, `verified:` trailers. The branch is never deleted.

The three merge modes exist because the six refusals above are a
genuine audit: before v0.4.0 a caller who needed a particular commit
message or a squash had to integrate by hand and lost the audit
entirely. All three run every refusal first, unchanged and in the
same order; only the commit step differs.

`-m MESSAGE` (`--message`) uses your subject instead of the generated
`oc-task merge: BRANCH`. The `oc-task-run:` trailer is still written,
so `oc-undo` still finds the merge. `--no-commit` runs every check,
merges into the index and working tree, and stops without committing.
The prepared message — subject and all trailers — is written to
`.git/OC_TASK_MERGE_MSG`, so `git commit -F .git/OC_TASK_MERGE_MSG`
reproduces exactly what the default path would have committed. A
conflict still aborts the merge and refuses, leaving the tree as it
was. `--squash` stages the branch's net change as an ordinary change
set rather than a merge. It implies `--no-commit`. A squashed commit
is not a merge commit, and `oc-undo` searches `git log --merges`, so
it will not find one: it is the one way to lose the undo path.

### `oc-models`

```
oc-models             all models, one provider/model per line, free ones first
oc-models --free      free only
oc-models --verbose   add columns: context window, toolcall, reasoning, release date
```

"Free" means the live catalog reports zero input and output cost. Nothing is
hardcoded — Zen's free tier rotates. Ask Claude "what can you delegate to
right now?" and it runs this.

**When the default model disappears.** The skill checks `oc-models --free`
once per plan. If `opencode/muse-spark-1.3-contributor-free` is gone Claude
picks the best free replacement using `--verbose`: a newer `muse-spark-*`
free variant first, otherwise the free model with `toolcall=yes` and the
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
long silent stretches, or set `idle_timeout=0` in the config to disable the
watchdog.

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

`.oc-runs/RUNID.log` is opencode's raw JSON event stream, one event per line:

```
jq -r 'select(.type=="text") | .part.text' .oc-runs/RUNID.log      # the model's prose
jq -r 'select(.type=="error")' .oc-runs/RUNID.log                    # errors
jq -r 'select(.type=="tool_use") | .part.tool' .oc-runs/RUNID.log    # tools called
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
  README.md
```

Dependencies: bash, git, opencode, jq, curl. Nothing else. No MCP server, no
daemon, no parallel dispatch.

## License

MIT
