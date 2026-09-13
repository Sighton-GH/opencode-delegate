# Final whole-branch reviewer brief template

Once, after every task is complete. Dispatched with `--role review --session
new --model <strongest free model, different from the implementer>`. It reads
the whole branch diff produced by `oc-task --branch-diff --branch B`.

Required headings: `# Objective`, `# Diff under review`, `# Required output`.
Save as `.oc-runs/<plan-slug>/final-review-brief.md`.

---

```markdown
# Objective
Whole-branch review of <plan slug> before merge: does the branch deliver the
plan, is it well built, and which deferred items must be fixed before merge.

# What was planned
Read the plan: <absolute path to the plan file>
Global constraints from the plan:
<verbatim>

# Deferred and parked items from the per-task reviews
<paste every `minor (deferred)` and `parked` ledger line, with their rulings>
Triage these: which must be fixed before merge, which can ship.

# Diff under review
Read this file once: <absolute path to the .branch.diff file>
It contains the branch's commit list, a stat summary, then the full diff
with 10 lines of context. The context lines are the changed files; open a
file separately only when a hunk you must judge is cut off, and say so.
Inspect code outside the diff only to evaluate a named risk — one focused
check per risk (call sites of changed signatures, users of shared state,
callers of changed error contracts) — and name what you checked.

This review is read-only. Do not edit, create, or delete any file. Do not
spawn subagents or sub-tasks.

# Method
1. Plan delivery: every task's outcome present; tasks compose — the
   interfaces one task produced are what the next consumed.
2. Cross-task defects the per-task reviews could not see: duplicated logic
   across tasks, inconsistent naming or error handling, a shared type
   defined twice, tests that only pass in isolation.
3. Quality and safety: correctness, error paths, resource handling,
   security-relevant code (auth, secrets, input at trust boundaries).
4. Severity as in task reviews: Critical, Important, Minor, with file:line.

# Required output
End your final message with a block in exactly this form:
## RESULT
Verdict: MERGEABLE | NEEDS_WORK
Findings:
- [Critical|Important|Minor] <file:line> — <what> — <fix>
Deferred items that must be fixed before merge:
- <item> — <why>
Deferred items that can ship:
- <item> — <why>
Checked outside the diff: <risk → what you looked at, or "nothing">
```
