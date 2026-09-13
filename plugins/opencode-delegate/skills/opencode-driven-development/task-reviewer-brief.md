# Task reviewer brief template

Dispatched with `--role review` (opencode's read-only `plan` agent: it can
read, grep, and run commands; it cannot edit). It reads one task's diff and
returns two verdicts: spec compliance and code quality. Task-scoped — the
broad review happens once at the end.

Required headings: `# Objective`, `# Diff under review`, `# Required output`.
Save as `.oc-runs/<plan-slug>/task-N-review-brief.md`.

Do not tell the reviewer what not to flag, and do not ask it to re-run
tests the implementer already ran — the implementer's RESULT is the test
evidence, and you re-ran the verification command yourself.

---

```markdown
# Objective
Review Task N of <plan slug>: first whether the implementation matches its
brief (nothing more, nothing less), then whether it is well built.

# What was requested
Read the task brief first: <absolute path to task-N-brief.md>
It is the requirements. Exact values, signatures, and tests in it are binding.

Global constraints from the plan that bind this task:
<copy the plan's Global Constraints verbatim — exact values, formats, and the
stated relationships between components>

# What the implementer reports
<paste the implementer's ## RESULT block verbatim>

# Diff under review
Read this file once: <absolute path to .oc-runs/RUNID.diff>
It contains the commit list, then the full diff with 10 lines of context.
The context lines ARE the changed files; open a changed file separately only
if a hunk you must judge is cut off mid-function, and say so. Do not crawl
the codebase. Inspect code outside the diff only to evaluate a concrete risk
you can name — one focused check per named risk (call sites of a changed
signature, users of changed shared state) — and name both the risk and what
you checked.

This review is read-only. Do not edit, create, or delete any file. Do not
run git commands that change state. Do not spawn subagents or sub-tasks.

# Method
1. Spec compliance: walk the brief's Tasks and Definition of done item by
   item against the diff. Missing, extra, or different is a finding. Check
   the Files list: anything changed outside it is a finding.
2. Quality: names say what things do; no duplication of logic that already
   exists nearby; tests assert behaviour rather than mocks and cover the
   edge cases the brief names; no dead code, no YAGNI additions; follows
   the patterns of the files the brief named.
3. Severity: Critical (wrong behaviour, data loss, security), Important
   (spec gap, missing test, will break a later task), Minor (style, naming,
   nit). Give file:line for every finding.
4. Anything the brief requires that lives in unchanged code or spans tasks
   goes under "Cannot verify from diff", not under findings.

# Required output
End your final message with a block in exactly this form:
## RESULT
Spec: PASS | FAIL
Quality: APPROVED | NEEDS_WORK
Findings:
- [Critical|Important|Minor] <file:line> — <what is wrong> — <what would fix it>
Cannot verify from diff:
- <requirement> — <why it can't be judged from this diff>
Strengths: <one line>
Checked outside the diff: <risk → what you looked at, or "nothing">
```
