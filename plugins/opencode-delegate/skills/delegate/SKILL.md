---
name: delegate
description: Delegate a large, already-designed implementation task to a fast free model via opencode, then review the diff and merge. Use when the design is settled and the work is mechanical across 3+ files or >100 lines (boilerplate, CRUD endpoints, migrations of a pattern across files, test suites for known behaviour) and a test/typecheck/build command exists to verify it. Not for design, debugging, or anything needing images.
disable-model-invocation: false
---

# /delegate

You are the planner and reviewer. A free opencode model (default: Muse Spark
1.3, see `oc-models --free` for the live list) does the typing inside a
throwaway git worktree. Three commands are on your PATH: `oc-task`,
`oc-models`, `oc-undo`. Read `oc-task --help` if you need the exit codes.

This skill can fire on its own judgment as well as on `/delegate`. Either
way, follow the five steps in order; step 1 may abort the whole thing, and
step 2 always waits for the user before anything is dispatched. When you
invoke it yourself, say so in one line ("This looks delegable — running the
triage gate.") so the user knows why the workflow changed.

## 1. Triage gate — runs first, may abort

Dispatch only if ALL of these hold:

- touches 3+ files, or >100 lines of new code
- the design is already decided — you can state exact paths and signatures
- a runnable verification command exists (tests, typecheck, build)
- it is mechanical execution of a settled design, not design discovery
- it can plausibly finish in under ~20 minutes of model time. Longer sessions
  accumulate images and die unrecoverably. Split anything larger.
- it does not require looking at images, screenshots, or design comps

If any fail: name the failing condition and implement it yourself. Do not
dispatch. If the only problem is size, propose a split into sequential
dispatches instead.

## 2. Write the spec

Use `${CLAUDE_PLUGIN_ROOT}/skills/delegate/spec-template.md` — read it, it
has the required section names, the verbatim constraint text, and a worked
example. Write the spec to a file in the repo (e.g. `.oc-runs/spec-<slug>.md`;
`.oc-runs/` is gitignored) so the model can be handed the exact same text.

Pick the model. Run `oc-models --free` first — Zen's free tier rotates and
the built-in default (`opencode/muse-spark-1.3-contributor-free`) may be gone.
Rules, in order:

1. The user named a model → use it.
2. The default is in the `--free` list → use it (pass nothing).
3. Otherwise choose the best free model yourself and pass it with `--model`.
   Run `oc-models --free --verbose` (columns: id, context window, toolcall,
   reasoning, release date) and prefer, in order: a newer `muse-spark-*`
   free variant; then any free model with `toolcall=yes` and the largest
   context window, breaking ties by newest release date. Never pick a model
   with `toolcall=no` — it cannot edit files. Tell the user which model you
   chose and why in one line when you show the spec.
4. Nothing free has toolcall → stop and tell the user; do not dispatch a paid
   model without being asked.

`oc-task` refuses a model id that is not in the live catalog, so a stale
choice fails fast rather than mid-run. Sanity-check with
`oc-task --spec <path> --dry-run` — it prints the resolved model and the
section check without dispatching.

Show the user the finished spec and the chosen model, and wait for approval
before dispatching.

> Temporary: this approval step exists while specs prove themselves. The user
> may remove it later. Until they do, always stop here.

## 3. Dispatch

```
oc-task --spec <path> [--model <provider/model>] [--branch <name>]
```

Run it with the Bash tool's timeout at its maximum (600000 ms). The run can
exceed that; if the harness moves it to the background, wait for its
completion notification. **While it runs, do nothing else** — do not start
other work, do not read files, do not poll. oc-task's stdout is the whole
report; it is deliberately compact.

## 4. Review

Read the `## RESULT` block first, then the `.diff` file oc-task printed. Do
NOT read the `.log` unless the run failed — it is the full JSON event stream
and costs a lot of context.

Then re-run the verification command yourself inside the worktree
(`.oc-worktrees/<branch>`). Do not trust the model's claim that tests pass —
run them.

Reject automatically if any of these are true:

- any file in the diff is absent from the spec's `# Files` section
- any dependency was added that the spec didn't list (check lockfiles and
  manifests in the diff)
- verification fails

## 5. Merge, correct, or hand back

**Clean pass** — you re-ran verification and it passed:

```
oc-task --merge --branch <branch> --verified "<the exact command you ran>"
```

`--verified` is your attestation; oc-task refuses to merge without it. It also
refuses on a dirty tree, a non-zero run, a missing RESULT block, files outside
the spec, or conflicts — each with a reason. Report the merge sha and the
`oc-undo` command it prints, and stop.

**Failure** (exit 1, exit 3, bad diff, verification failed): write a short
correction spec naming only what is wrong — it still needs every required
section, but each can be one line — and re-dispatch to the same session:

```
oc-task --spec <correction-path> --session <session id from the summary>
```

Maximum two correction rounds. After that, implement it yourself and note in
your summary that delegation failed, so the user can see the pattern.

**Exit 4 (image limit)**: the session is dead and can never be retried;
oc-task will refuse `--session <that id>`. Report the checkpoint sha from the
summary. Write a continuation spec starting from the first incomplete task and
dispatch it as a new session in the same worktree:

```
oc-task --spec <continuation-path> --session new --branch <branch>
```

**Exit 5 (rate limit)**: report it and stop. Do not retry automatically.

On any non-zero exit the worktree and its checkpoint commits stay in place;
never clean them up yourself.
