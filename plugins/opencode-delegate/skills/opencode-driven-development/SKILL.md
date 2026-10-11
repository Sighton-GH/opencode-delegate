---
name: opencode-driven-development
description: Execute implementation work by dispatching opencode sessions (free models, Muse Spark 1.3 by default) as implementers and reviewers, exactly the way subagent-driven-development dispatches subagents. Use for any task worth a plan with 2+ tasks — features, refactors, test suites, multi-file changes — instead of subagent-driven-development or doing the typing yourself. Claude brainstorms, writes the plan and every brief, adjudicates reviews, and merges.
disable-model-invocation: false
---

# opencode-driven development

This is `superpowers:subagent-driven-development` with opencode sessions in
every subagent seat. You are the controller: you brainstorm, write the plan,
write each task brief, read each review, rule on conflicts, and merge. An
opencode model implements each task, reviews each task, and reviews the whole
branch. Free models only.

**Announce at start:** "I'm using opencode-driven development to execute this."
When you chose this skill yourself rather than being asked, say that too, in
one line.

## Posture

opencode models are capable engineers, not throwaway ones. Muse Spark 1.3 in
particular does excellent work when the brief is detailed, concrete, and
written in the same register you'd want a brief in: exact paths, exact
signatures, the code where the plan has it, the test cases, the command to
run. Your leverage is the brief. When a run disappoints, the first suspect is
the brief, not the model — tighten it and re-dispatch before concluding
anything.

Do not decide work is "too hard for opencode" and do it yourself. The only
work you keep is: writing the plan and briefs, answering an implementer's
questions, rulings, re-running the verification command, and the merge. If
you catch yourself implementing a task, stop and write the brief instead.

**Sensitive code is the one exception.** Before dispatching a task that
touches authentication, session handling, secrets or credentials,
cryptography, or payments/billing, tell the user in one line what the task
is and that it would go to an opencode model, and wait for a yes. Ask once
per plan, not per task. Everything else dispatches without asking.

## When to use

Any time you would write a plan with two or more tasks — a feature, a
refactor across files, a test suite, a migration of a pattern. That is the
same moment `superpowers:subagent-driven-development` would fire; use this
instead of it. One-line fixes, pure investigation, and answering questions
stay with you.

## Companions and fallbacks

Check your available skills list once at the start:

- Brainstorming: if `superpowers:brainstorming` is available, use it to get
  from the request to a settled design. Otherwise ask the user the two or
  three questions whose answers change the design, propose one approach, and
  confirm it — do not start planning against an unsettled design.
- Planning: if `superpowers:writing-plans` is available, use it and save the
  plan where it says (`docs/superpowers/plans/`). Otherwise write the plan
  with `${CLAUDE_PLUGIN_ROOT}/skills/opencode-driven-development/plan-template.md`
  to `docs/plans/YYYY-MM-DD-<slug>.md`.
- Worktrees: `oc-task` creates and manages the worktree itself
  (`.oc-worktrees/<branch>`). Do not use `superpowers:using-git-worktrees`.
- Finishing: if `superpowers:finishing-a-development-branch` is available,
  use it at the end; when the user chooses to merge, do it with
  `oc-task --merge`. Otherwise offer the three options yourself: merge now
  (`oc-task --merge`), open a PR from the branch, or leave the branch for
  the user.

## Tools

Three commands are on your PATH; `oc-task --help` has the exit codes.

```
oc-task --brief PATH [--role implement|review] [--model M] [--branch B] [--base REF]
        [--session ID|new] [--continue-from PARENT_BRIEF] [--idle-timeout S]
        [--copy-untracked PATH]... [--install | --no-link-node-modules] [--dry-run]
oc-task --branch-diff --branch B
oc-task --merge --branch B --verified "COMMAND" [-m MSG | --no-commit | --squash]
oc-models --free [--verbose]
oc-undo [--list]
```

- The first `oc-task --brief` on a plan creates the branch and worktree.
  Every later task in the same plan is `--session new --branch B`: a fresh
  session, the same worktree. Fix rounds resume with `--session ID`.
- Every run prints a compact summary — session id, exit, duration, files
  changed, `warning:` and `errors:` lines, the model's `## RESULT` block —
  and writes `.oc-runs/RUNID.diff` (that run's changes, with commit list and
  10 lines of context: the review package), `.oc-runs/RUNID.log` (raw event
  stream) and `.oc-runs/RUNID.serve.log` (the run's own server log, where a
  provider's refusal is written). Read the logs only on failure.
- The summary is also saved as `.oc-runs/RUNID.summary`, and the run record
  `.oc-runs/RUNID.json` exists from the moment of dispatch (`state: running`
  until it ends). A wrapper that is killed, or that fails inside itself,
  still writes both. Never pipe `oc-task` through `tail` or `head`: the
  summary is short, and a pipe can hide the exit code.
- One run per worktree: `oc-task` refuses a dispatch into a worktree where
  another run is live, because a review's cleanup resets the worktree it ran
  in. Runs on separate branches can overlap, but they share the provider's
  per-account limit; `oc-task` warns when other live runs use the same model.
- `--role review` runs opencode's read-only `plan` agent: it can read, grep,
  and run commands but cannot edit. Its `## RESULT` is the verdict.
- Run `oc-task` with the Bash tool's maximum timeout (600000 ms). If the
  harness moves it to the background, wait for the completion notification.
  While a run is in flight, do only bookkeeping: ledger, the next brief.

## Model selection

Free models only. Run `oc-models --free --verbose` once per plan and record
the choice in the ledger.

- Implementer: `opencode/muse-spark-1.3-contributor-free` when listed;
  otherwise a newer `muse-spark-*` free variant; otherwise the free model
  with `toolcall=yes` and the largest context, newest release breaking ties.
  Never a model with `toolcall=no`.
- Task reviewer and re-reviewer: the same model as the implementer is fine.
- Final whole-branch reviewer: the strongest free model available, and a
  *different* model from the implementer when one with `toolcall=yes`
  exists — fresh eyes are the point.
- Fix rounds 4–5: a different free model from the one that got stuck.
- Nothing free with tool calling → stop and tell the user. Never pick a paid
  model without being asked; `oc-task` refuses ids not in the live catalog.

## Setup

1. Brainstorm, then write the plan (see Companions). Show the plan to the
   user and get a yes. **That is the single approval for the whole run.**
   After it, execute every task without check-ins.
2. Pick the branch name `oc/<plan-slug>` and the workspace
   `.oc-runs/<plan-slug>/` (gitignored; `oc-task` adds `.oc-runs/` and
   `.oc-worktrees/` to `.gitignore` on first run — create the directory
   yourself). Everything for this plan lives there: ledger, briefs, reports.
3. Ledger: `.oc-runs/<plan-slug>/progress.md`, first line
    `# ODD ledger — plan: <plan path> — branch: oc/<plan-slug>`. If it already
    exists and names this plan, tasks with a `Task N: complete` line are DONE;
    resume at the first task without one. A task whose last line is a fix
    round is mid-loop — resume at the next round. Conversation memory does
    not survive compaction; the ledger and `git log` do. Trust them over
    recollection.
 4. If the task's inputs are untracked files the user just added, dispatch
    Task 1 with `--copy-untracked <path>` for each, because the worktree
    forks from `HEAD` and will not contain them otherwise. Dependencies:
    by default the worktree gets its own `node_modules` directory linked
    entry by entry to the base checkout's (nested workspace installs too),
    with workspace packages resolving to the worktree's own copies. Dispatch
    Task 1 with `--install` instead when the plan changes dependencies or
    adds a workspace package, or when the base checkout has no
    `node_modules` (`oc-task` warns). A task that depends on an unmerged
    sibling branch starts from it with `--base oc/<sibling>`; merge the
    sibling first, or the merge audit sees its files too.
 5. Read the plan once. Create a todo per task. Scan for conflicts before
    Task 1 — one row per pair of tasks sharing a file or interface, one row
    per task for internal consistency — write the table to the ledger, rule
    on anything it surfaces (`Ruling: <decision> — <why> — <cost if wrong>`),
    and proceed.
 6. Sensitive-code check (see Posture). Ask now if any task qualifies.

## The task loop

**Batch small same-shape work.** Several tasks that are each the same tiny
edit across files → one brief listing every file and its change, one run,
one review.

**Never run two sessions at once on the same branch** — implement or
review. `oc-task` refuses the second; write the next brief while a run is
in flight instead.

### 1. Dispatch the implementer

Write `.oc-runs/<plan-slug>/task-N-brief.md` from
`${CLAUDE_PLUGIN_ROOT}/skills/opencode-driven-development/implementer-brief.md`.
The brief is the single source of requirements: paste the task's full text
from the plan (code, tests, exact values) into it; add the interfaces and
rulings from earlier tasks the plan cannot know; resolve any ambiguity you
noticed. Do not paste session history or "state after tasks 1–3". Keep the
verbatim blocks (image rule, commit-per-task, verification, RESULT).

Dispatch:

```
oc-task --brief .oc-runs/<plan-slug>/task-N-brief.md --branch oc/<plan-slug>           # task 1
oc-task --brief .oc-runs/<plan-slug>/task-N-brief.md --branch oc/<plan-slug> --session new   # tasks 2..N
```

(add `--model M` when the default isn't the chosen model). Record the
session id and the run id from the summary in the ledger as
`Task N: dispatched run <run id> session <id>`.

### 2. Handle the result

Read the summary's `## RESULT` block. Its `Status:` line is one of:

- **DONE** → review it (step 3).
- **DONE_WITH_CONCERNS** → read the concerns. Correctness or scope concerns:
  resolve them (a ruling, or a fix round with the resolution) before review.
  Observations: note in the ledger, review.
- **NEEDS_CONTEXT** → answer in a short follow-up brief and resume:
  `--session ID --continue-from <original brief>` (the follow-up then needs
  only the sections it changes; without the flag, every required section,
  each can be one line).
- **BLOCKED** → context problem: supply it and resume. Task too large: split
  it into two briefs. Plan wrong: rule, ledger it, resume with the ruling.
  Never resume with nothing changed.

Non-zero exits: **1** read the `errors:` lines — `server:` lines come from
the run's own opencode server — and only then the logs; fix the cause,
resume or re-dispatch. **3** (zero changes) with a DONE status is a brief
problem — the model thought it was done; tighten and resume. A 3 whose exit
line says the model stopped with NEEDS_CONTEXT or BLOCKED is that status:
handle it as above. **4** (image limit or a poisoned reasoning state) the
session is dead: write a continuation brief and dispatch `--session new
--branch B --continue-from <original brief>`; the checkpoint commits are
kept. **5** (rate or usage limit, or a run that produced no model output at
all) stop and tell the user, quoting the `limit:` and `reset:` lines; do not
retry on your own. After the reset, resume with `--session ID` (if that
exits 4, use `--session new`). **6** (stalled) the run produced output, then
nothing for the idle timeout, and was killed; the session is dead. Treat it
exactly like 4. If the task legitimately has long silent stretches,
re-dispatch with a larger `--idle-timeout`. **7** opencode's own database
was busy (another opencode run, a bulk `opencode session delete`, a
`VACUUM`): wait for that to finish, then re-dispatch `--session new`.
**128+N** the wrapper was killed by a signal (143 = TERM); the summary,
record and checkpoint were still written — resume as for 4.

Read every `warning:` line. "checkpoint failed" means the run's last work is
still uncommitted in the worktree — commit it there before the next
dispatch. "gained raw control bytes" or "diffs as binary" on a source file
is a finding for the review.

### 3. Review the task

Re-run the task's verification command yourself inside the worktree
(`.oc-worktrees/<branch>`) before anything else — cheap, and it catches a
report that overstates. If it fails, that is a finding; go to the fix loop
without a review dispatch. Run it with the worktree as the working
directory: a formatter or linter run from your own checkout against
`.oc-worktrees/...` paths may skip them silently, because ignore files
(`.prettierignore`, `.eslintignore`) commonly list `.oc-worktrees`.

Then write `.oc-runs/<plan-slug>/task-N-review-brief.md` from
`${CLAUDE_PLUGIN_ROOT}/skills/opencode-driven-development/task-reviewer-brief.md`
with: the brief path, the run's `.diff` path from the summary (the review
package — commits, stat, full diff), and the plan's global constraints
copied verbatim. **The `.diff` path must be absolute**, because reviewers
execute inside `.oc-worktrees/<branch>` where `.oc-runs/` does not exist. Do
not pre-judge findings ("don't flag X") and do not ask it to re-run tests.
Dispatch:

```
oc-task --brief .oc-runs/<plan-slug>/task-N-review-brief.md --role review --branch oc/<plan-slug> --session new
```

To review a branch another tool made (not an `oc/` branch), fork a fresh
review branch from it: `--role review --base <that branch>` (no
`--session`), so the reviewer's checkout holds the code under review.

The reviewer returns `Spec: PASS|FAIL`, `Quality: APPROVED|NEEDS_WORK`,
findings with severity, and `Cannot verify` items. Resolve each
`Cannot verify` item yourself (you hold the plan); a confirmed gap is a
failed spec review.

### 4. The fix loop

Triggers on `Spec: FAIL`, any Critical or Important finding, or a
`Cannot verify` you confirmed. Minor findings never enter the loop: ledger
them as `Task N: minor (deferred): <one-liner>` for the final review.
A finding that conflicts with the plan's text is yours to rule on first;
ledger the ruling, then act.

Five rounds maximum per task. A round is one fix dispatch + one scoped
re-review.

- **Rounds 1–3:** resume the implementer — `--session <implementer id>` with
  a short fix brief (all required sections; Tasks = the open findings
  verbatim; Verification = the covering tests). Its context is intact.
- **Rounds 4–5:** fresh session on a *different* free model
  (`--session new --model M`), with the original brief path, the findings,
  and "A prior implementer attempted this N times; read
  `.oc-runs/<plan-slug>/task-N-brief.md` and the open findings; you own it
  now."
- **Every round:** re-run the covering tests yourself, then dispatch a
  scoped re-review from `re-review-brief.md` (`--role review --session new`)
  with the findings list and the fix run's `.diff`. It verdicts each finding
  ADDRESSED / NOT ADDRESSED and flags new breakage in the fix diff only.
- **After each round** ledger:
  `Task N: fix round R/5 (X addressed, Y open — <one-liners>; commits a..b)`

Never fix findings yourself in the controller session.

**The breaker.** Round 5 still open → stop dispatching and adjudicate each
finding: reviewer wrong or contestable → park with a ruling; real but
nothing depends on it → park as real-and-deferred; real and load-bearing →
rule on the smallest unblocking change, ledger it, carry it into the next
task's brief. Adjudicate only at the cap.

### 5. Complete the task

`Task N: complete (commits base..head, review clean)` or `(…, K parked)`.
Mark the todo done. Never move on with open Critical/Important findings that
are neither fixed nor parked-with-ruling at the cap.

## Final review

```
oc-task --branch-diff --branch oc/<plan-slug>
```

prints a whole-branch diff file. Write
`.oc-runs/<plan-slug>/final-review-brief.md` from `final-reviewer-brief.md`
with that path, the plan path, and the ledger's deferred-minor and parked
lines; dispatch `--role review --session new --model <strongest different
free model>`.

Findings → ONE fix dispatch with the complete list (fresh session,
implementer model), one scoped re-review, then adjudicate residuals as in
the breaker. No second fix wave.

## Finish

Collect every ledger line containing `Ruling:` into your final message under
"Rulings I made", in order, each with its cost if wrong. Then use
`superpowers:finishing-a-development-branch` if available, else offer:
merge now, PR, or leave the branch.

Merging is `oc-task --merge --branch oc/<plan-slug> --verified "<the
verification command you re-ran on the final branch>"` — run that command
first. `oc-task` refuses a dirty tree, a non-zero last implement run, files
outside every brief's `# Files` section, or conflicts. It prints the sha;
`oc-undo` reverts it. When the user wants to own the final commit — a
specific message, or a squash — use `--merge -m "MSG"`, `--merge --no-commit`,
or `--merge --squash`; the file audit runs either way, and a `--squash` commit
is not a merge commit so `oc-undo` will not find it. Never delete the worktree
or branch yourself; the user does that.

## Stops

Only these stop a running plan: an irreversible or destructive operation; a
security-sensitive action; a side effect outside the worktree (merge, push,
publish); a plan so broken every path is a guess. Everything else is a
ruling in the ledger and you keep going.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "This part is too subtle for a free model" | It is too subtle for a vague brief. Write the exact code and tests into the brief. |
| "Faster if I just do it" | You skip review and burn your own context. Write the brief. |
| "Close enough on spec" | Spec FAIL = not done. Fix or hit the cap and adjudicate. |
| "One more round will converge" | Past the cap rounds don't converge. Adjudicate. |
| "Skip the re-review, the fix was small" | Unreviewed fixes are how regressions land. |
| "I'll drop this obviously wrong finding" | Adjudicate only at the cap, always in the ledger. |
| "I'll check in with the user first" | They approved the plan. Rule, ledger, continue. |
