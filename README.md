# opencode-delegate

A Claude Code plugin that hands settled, mechanical implementation work to
[opencode](https://opencode.ai)'s fast free models — Muse Spark 1.3 by
default — while Claude keeps doing the planning, prompting, and reviewing.

Free fast models do the typing. Claude does the thinking and the reviewing.

This repo is also a Claude Code plugin marketplace, so it installs on any
machine and works in every project.

## How it works

1. You type `/delegate` in Claude Code and describe the task.
2. Claude runs a triage gate. If the task isn't a good fit (see
   [When it fires](#when-it-fires)), Claude says which condition failed and
   does the work itself.
3. Claude writes a spec from a fixed template and shows it to you for
   approval.
4. `oc-task` creates a git worktree on a new branch, runs opencode in it with
   permissions auto-approved (safe only because the worktree is a sandbox),
   and prints a compact summary: session id, exit status, duration, files
   changed, the model's own `## RESULT` block, the last checkpoint commit,
   and paths to the full log and diff.
5. Claude reads the diff, re-runs the verification command itself in the
   worktree (it never trusts the model's claim), and either merges with
   `oc-task --merge`, sends a short correction spec back to the same session,
   or hands the task back to you.
6. Every merge is `--no-ff`, so `oc-undo` reverts it in one command.

## Prerequisites

Install these before the plugin. The plugin does not carry any of them.

| Tool | Why | Check |
|---|---|---|
| Claude Code 2.1+ | plugin host | `claude --version` |
| [opencode](https://opencode.ai) 1.18+ | runs the model | `opencode --version` |
| git 2.x | worktrees, merges, reverts | `git --version` |
| jq | parses opencode's JSON | `jq --version` |
| curl | talks to opencode's local server | `curl --version` |
| bash 4+ | the scripts | `bash --version` |

**opencode must be installed *and authenticated* separately.** Authentication
is machine state — a credential file in your home directory — and the plugin
does not carry it. Run `opencode providers` (alias `opencode auth`) and make
sure a provider is listed. The default model uses the OpenCode Zen provider;
`opencode providers list` should show `OpenCode Zen`. If it doesn't, run
`opencode auth login` and pick it.

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
and `oc-undo` are bare commands for Claude in every project, and for you if
you run them from Claude's shell.

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

## When it fires

`/delegate` is user-invoked only (`disable-model-invocation: true` in the
skill's frontmatter). Claude will not propose delegation on its own. Flip that
field to `false` in `plugins/opencode-delegate/skills/delegate/SKILL.md` if
you later trust the specs enough to let Claude suggest it.

Once invoked, Claude dispatches only if ALL of these hold — verbatim from the
skill:

- touches 3+ files, or >100 lines of new code
- the design is already decided — you can state exact paths and signatures
- a runnable verification command exists (tests, typecheck, build)
- it is mechanical execution of a settled design, not design discovery
- it can plausibly finish in under ~20 minutes of model time. Longer sessions
  accumulate images and die unrecoverably. Split anything larger.
- it does not require looking at images, screenshots, or design comps

If any fail, Claude names the failing condition and implements it itself. If
the only problem is size, it proposes a split into sequential dispatches.

## Worked example

You, in a TypeScript/Express repo where the design is already agreed:

> /delegate Add `DELETE /api/projects/:id` — soft-delete the project and its
> memberships, owner-only, with tests. Same shape as the teams routes.

**Triage.** Claude checks the gate: 4 files, settled design, `vitest` +
`tsc` exist, no images, well under 20 minutes. Passes.

**Spec.** Claude writes `.oc-runs/spec-project-delete.md` from the template
(the full example is at the bottom of
[`spec-template.md`](plugins/opencode-delegate/skills/delegate/spec-template.md)),
runs `oc-task --spec .oc-runs/spec-project-delete.md --dry-run` to confirm the
model and section check, and shows you both:

```
model:    opencode/muse-spark-1.3-contributor-free  (from built-in default)
branch:   oc/spec-project-delete-141502  (base: main @ 9c1f2ab)
worktree: .oc-worktrees/oc/spec-project-delete-141502
session:  <new>
spec:     .oc-runs/spec-project-delete.md
sections: ok (Objective Files Tasks Verification Definition of done Required output)
```

You say "go".

**Dispatch.** Claude runs `oc-task --spec .oc-runs/spec-project-delete.md
--branch oc/project-delete` and waits. Nothing else happens until it returns:

```
run:      20260912T141530-oc_project-delete
session:  ses_f67fcd9c5ffeuPtAzaubTh8qph
model:    opencode/muse-spark-1.3-contributor-free
exit:     0 (success)
duration: 4m12s
branch:   oc/project-delete  (worktree .oc-worktrees/oc/project-delete, base main @ 9c1f2ab)
checkpoint: 3e9f99a
files:
  +38 -0  src/services/projectService.ts
  +21 -1  src/routes/projects.ts
  +2 -0   src/routes/index.ts
  +71 -0  tests/routes/projects.delete.test.ts
## RESULT
Files changed: src/services/projectService.ts, src/routes/projects.ts, src/routes/index.ts, tests/routes/projects.delete.test.ts
Commands run and their outcome: npx vitest run tests/routes/projects.delete.test.ts (4 passed); npx tsc --noEmit (clean)
Could not complete: none
Assumptions made: none
log:  .oc-runs/20260912T141530-oc_project-delete.log
diff: .oc-runs/20260912T141530-oc_project-delete.diff
```

**Review.** Claude reads the RESULT block, then the `.diff`. Every file is in
the spec's Files list; no dependency changed. It runs the verification
command itself:

```
cd .oc-worktrees/oc/project-delete && npx vitest run tests/routes/projects.delete.test.ts && npx tsc --noEmit
```

**Merge.** It passes, so:

```
oc-task --merge --branch oc/project-delete --verified "npx vitest run tests/routes/projects.delete.test.ts && npx tsc --noEmit"
```

```
merged:  oc/project-delete -> main @ c37db3d (--no-ff)
run:     20260912T141530-oc_project-delete  model: opencode/muse-spark-1.3-contributor-free  spec: .oc-runs/spec-project-delete.md
undo:    oc-undo
branch 'oc/project-delete' and worktree .oc-worktrees/oc/project-delete were left in place.
```

Claude reports the sha and that `oc-undo` reverses it, and stops.

Had the diff touched a file outside the spec, or had the tests failed, Claude
would have written a one-screen correction spec and re-dispatched with
`--session ses_f67fcd9c5ffeuPtAzaubTh8qph` — at most twice — before doing the
work itself and telling you delegation failed.

## Command reference

All three live in `plugins/opencode-delegate/bin/`. Each prints usage with
`--help`.

### `oc-models`

```
oc-models          all models, one provider/model per line, free ones first
oc-models --free   free only
```

"Free" means the live opencode catalog reports zero input and output cost.
Nothing is hardcoded — Zen's free tier rotates, so ask Claude "what can you
delegate to right now?" and it runs this.

### `oc-task`

```
oc-task --spec PATH [--model PROVIDER/MODEL] [--branch NAME] [--session ID|new] [--dry-run]
oc-task --merge (--branch NAME | --session ID) --verified "COMMAND"
```

Replace `PATH`, `NAME`, `ID` and `COMMAND` with real values; don't type them
literally.

Model precedence: `--model` > `$OC_DELEGATE_MODEL` > `model=` line in
`~/.config/oc-delegate/config` (respects `$XDG_CONFIG_HOME`; created on first
run) > built-in default `opencode/muse-spark-1.3-contributor-free`.

What a dispatch does, in order:

1. Validates the spec: exists, non-empty, has `# Objective`, `# Files`,
   `# Tasks`, `# Verification`, `# Definition of done`, `# Required output`.
2. Adds `.oc-worktrees/` and `.oc-runs/` to `.gitignore` if absent. This
   edit is left uncommitted; commit it whenever convenient. It is the one
   change `--merge` and `oc-undo` tolerate in an otherwise clean tree.
3. Creates `.oc-worktrees/NAME` on new branch `NAME` off current HEAD
   (default name `oc/SPEC-BASENAME-HHMMSS`). An existing worktree is reused
   only with `--session ID` (resume that session) or `--session new --branch
   NAME` (fresh session, same worktree — for continuing after an image-limit
   death).
4. Starts a private `opencode serve` on a random port, creates the session
   over its HTTP API with an allow-all permission ruleset, and runs
   `opencode run --attach ... --session ID --auto` with the spec on stdin.
5. Commits anything the model left uncommitted as a final checkpoint.
6. Writes `.oc-runs/RUNID.log` (raw JSON event stream), `.oc-runs/RUNID.diff`
   (branch vs base), `.oc-runs/RUNID.json` (run record), and prints the
   summary.

`--dry-run` prints the resolved model, branch, worktree, and section check,
then exits without creating anything.

Exit codes:

| Code | Meaning |
|---|---|
| 0 | success, changes produced |
| 1 | opencode errored (generic), or a setup problem |
| 2 | spec rejected — missing or malformed |
| 3 | completed but zero changes |
| 4 | session poisoned by image limit — unrecoverable |
| 5 | rate limited by the provider |

On any non-zero exit the worktree stays in place. oc-task never cleans up
after a failure.

`--merge` merges the branch into the base it forked from with `--no-ff`. It
refuses, with a specific reason, unless all of these hold: you are on the base
branch with a clean tree (oc-task's own `.gitignore` edit is exempt); the
latest run on that branch exited 0; that run has a parseable `## RESULT`
block; you passed `--verified "COMMAND"` (your attestation that you re-ran
the verification command yourself — oc-task does not trust the model);
every changed file is named in the `# Files` section of a spec dispatched to
that branch; and the merge has no conflicts. The commit message carries
`oc-task-run:`, `model:`, `spec:`, `branch:`, `session:`, and `verified:`
trailers. The branch is never deleted.

### `oc-undo`

```
oc-undo          revert the most recent oc-task merge
oc-undo --list   show recent oc-task merges (and whether each was reverted)
```

Finds the newest merge commit carrying the `oc-task-run:` trailer and runs
`git revert -m 1` on it, printing the run id, spec path, and model so it's
obvious what was undone. Refuses on a dirty tree (with the same `.gitignore`
exemption as `--merge`) and on a merge that was already reverted.

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
checkpoint commits are the recovered work. What Claude does (per the skill):
reports the checkpoint sha, writes a continuation spec from the first
incomplete task, and dispatches it with `--session new --branch NAME` into the
same worktree.

Prevention is the spec's job: the verbatim "Do not read, open, or screenshot
any image or binary file" constraint, and the under-20-minutes rule.

### Rate limited (exit 5)

Free-tier throttling mid-task is an expected condition, not a bug. oc-task
exits 5 and Claude stops; it does not retry automatically. Wait, or pick
another model from `oc-models --free` and re-dispatch with `--session ID` to
continue where it stopped.

### "opencode did not return a session id" / "could not start opencode serve"

opencode isn't authenticated, or something is wrong with the install. Run
`opencode providers list` and `opencode run "say hi" < /dev/null` by hand.
The `< /dev/null` matters: `opencode run` reads stdin to EOF whenever stdin is
not a terminal, so inside an agent's shell (where stdin is a socket that never
closes) it hangs silently without it. oc-task always redirects stdin for you.

### Worktree cleanup

oc-task never deletes worktrees or branches. When you're done with one:

```
git worktree remove .oc-worktrees/NAME
git branch -D NAME
```

`git worktree list` shows what's there. `.oc-runs/` is plain files; delete
old ones whenever you like (but a run record is needed for `--merge` and
`--session` on that branch).

### Undoing a merge

`oc-undo`. It reverts only the newest oc-task merge; run `oc-undo --list`
first if you're not sure which that is. To undo an older one, use the sha from
`--list` with `git revert -m 1 SHA` yourself.

### Reading a failed run's log

`.oc-runs/RUNID.log` is opencode's raw JSON event stream, one event per line.
Useful extracts:

```
jq -r 'select(.type=="text") | .part.text' .oc-runs/RUNID.log      # the model's prose
jq -r 'select(.type=="error")' .oc-runs/RUNID.log                    # errors
jq -r 'select(.type=="tool_use") | .part.tool' .oc-runs/RUNID.log    # tools called
```

## Layout

```
.claude-plugin/marketplace.json          registers the plugin
plugins/opencode-delegate/
  .claude-plugin/plugin.json
  bin/oc-task  oc-models  oc-undo        on PATH when the plugin is enabled
  skills/delegate/SKILL.md               the /delegate skill
  skills/delegate/spec-template.md       the spec shape, with a worked example
  README.md
```

Dependencies: bash, git, opencode, jq, curl. Nothing else. No MCP server, no
daemon, no parallel dispatch.

## License

MIT
