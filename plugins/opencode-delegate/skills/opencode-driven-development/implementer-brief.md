# Implementer brief template

The brief is the implementer's entire world: it never sees your session, the
plan file, or earlier briefs. Everything it needs is in here — the task's
full text from the plan (code, tests, exact values, verbatim), the interfaces
earlier tasks produced, your rulings. Write it the way you'd want a brief
written for you: concrete, imperative, self-verifying.

`oc-task` requires the six `#` headings marked required; blocks marked
VERBATIM are copied as-is. Save as `.oc-runs/<plan-slug>/task-N-brief.md`.

---

```markdown
# Objective                                                     (required)
Task N of M in <plan slug>: <one sentence — what exists when this is done>.

# Context
<Where this task fits. The repo, stack, and conventions. Name the existing
files whose patterns to imitate. Interfaces and decisions from earlier tasks
that this task consumes — exact signatures, not descriptions. Rulings that
bind this task.>

# Constraints
Do not read, open, or screenshot any image or binary file. Reference image
assets by path only. If a task appears to require viewing an image, stop and
report it rather than opening it.
Do not spawn subagents or sub-tasks; do all of this work yourself. Review
arrives from the controller after you report.
No new dependencies unless listed here: <none | list>.
Out of scope — do not touch: <files and areas that must not change>.
Follow the existing patterns in the files named under Context. Improve code
you touch the way a good engineer would; do not restructure outside this task.
<Global constraints from the plan, verbatim.>

# Files                                                         (required)
Create:
- `<exact/path>`
Modify:
- `<exact/path>`
Nothing outside this list may change.

# Interfaces
<Exact signatures, types, exported names this task must produce. If the plan
has the code, put the code here.>

# Tasks                                                         (required)
1. <step — with the code or test the plan specifies, verbatim>
2. <step>
3. <step>
Run `git add -A && git commit` after completing each numbered step, with the
step number in the commit message. Run the focused test for what you are
changing while you iterate; run the full verification command once before
your final commit.

# Verification                                                  (required)
Run `<command>`. If it fails, read the failure, fix it, and run it again.
Repeat until it passes. Do not report completion until it passes.

# Definition of done                                            (required)
- [ ] <acceptance item, checkable>
- [ ] <acceptance item>
- [ ] Every file changed is in the Files list (`git status` confirms).

# Questions and escalation
If anything in this brief is ambiguous, contradictory, or missing — the
requirements, the approach, an interface you need — do not guess. Stop and
report with Status: NEEDS_CONTEXT and the specific question. If the task
turns out to need architectural decisions with several valid answers, or
restructuring the plan did not anticipate, report Status: BLOCKED with what
you found. Asking costs one round trip; guessing costs a review loop.

# Self-review
Before reporting, read your own diff once: everything in the spec done and
nothing extra; names say what things do; tests assert behaviour, not mocks;
test output is clean. Fix what you find, then report.

# Required output                                               (required)
End your final message with a block in exactly this form:
## RESULT
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Files changed: ...
Commits: <short sha — subject, one per line>
Commands run and their outcome: ...
Could not complete: ...
Assumptions made: ...
Concerns or questions: ...
```

Notes:

- **Objective** one sentence. If it needs two, the task is not settled.
- **Context** is where you earn the run. "Follow the pattern in
  `src/api/users.ts`" beats a paragraph. Paste earlier tasks' interfaces
  exactly.
- **Constraints** — the image sentence and the no-subagents sentence are
  VERBATIM. An opencode session dies permanently at 50 images.
- **Files** — `oc-task --merge` refuses if the branch touches anything not
  listed in *some* brief's Files section. Directories end in `/`; globs work.
- **Tasks** — the commit-per-step instruction is VERBATIM; checkpoints are
  what survive an image-limit death.
- **Verification** — VERBATIM shape. You re-run this same command; make it
  the real one.
- **Required output** — VERBATIM. `oc-task` extracts the block; `Status:` is
  how you route the result.

## Fix-round brief (rounds 1–3, resuming the same session)

Short, but still every required heading:

```markdown
# Objective
Fix round R for Task N: address the review findings below.

# Files
<the files the findings touch — same paths as the original brief>

# Tasks
1. <finding 1, verbatim from the reviewer, with file:line>
2. <finding 2>
Run `git add -A && git commit` after completing each numbered step, with the
step number in the commit message.

# Verification
Run `<covering tests for the amended code>`. If it fails, read the failure,
fix it, and run it again. Repeat until it passes. Do not report completion
until it passes.

# Definition of done
- [ ] Every finding above addressed or explicitly disputed with a reason.

# Required output
End your final message with a block in exactly this form:
## RESULT
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Files changed: ...
Commits: ...
Commands run and their outcome: ...
Could not complete: ...
Assumptions made: ...
Concerns or questions: ...
```

For rounds 4–5 (fresh session, different model) use the full template again,
add under Context: "A prior implementer attempted this task R times. Read
`.oc-runs/<plan-slug>/task-N-brief.md` for the original requirements; the
open findings are the Tasks below. You own it now."
