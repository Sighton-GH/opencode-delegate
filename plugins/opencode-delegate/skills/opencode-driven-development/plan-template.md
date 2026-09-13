# Plan template (fallback when `superpowers:writing-plans` is not installed)

Write the plan for an engineer with zero context for this codebase and
questionable taste: which files to touch for each task, the code, the tests,
how to run them. Bite-sized tasks, each independently committable and
reviewable. DRY, YAGNI, tests first where the codebase has tests. Save to
`docs/plans/YYYY-MM-DD-<slug>.md` and get the user's approval once; that
approval covers the whole run.

Every task becomes one implementer brief, so write each task with the level
of detail a brief needs: exact paths, exact signatures, the code where you
know it, the test cases by name.

---

```markdown
# <Feature name> — implementation plan

**Goal:** <one sentence>
**Spec / design:** <path or "settled in conversation: <three-line summary>">
**Branch:** oc/<slug>
**Verification command:** `<the one command that proves the branch works>`

## Global constraints
<Exact values, formats, and relationships every task must respect:
"IDs are ULIDs", "all handlers return the ApiError shape in src/errors.ts",
"same layout as the teams routes". The reviewer's attention lens — verbatim
into every brief.>

## File map
| File | Responsibility | Created/modified by |
|---|---|---|
| `src/...` | one clear responsibility | Task 1 |

## Tasks

### Task 1: <name>
**Files:** create `…`; modify `…`
**Interfaces produced:** <exact signatures later tasks will consume>
**Steps:**
1. <step with the code or test, verbatim where known>
2. <step>
**Tests:** `<test file>` — cases: <name each>
**Verify:** `<command>`
**Done when:** <checkable items>

### Task 2: <name>
…

## Out of scope
<files and areas no task may touch>
```

Right-sizing: a task is the smallest unit that carries its own test cycle
and is worth a reviewer's gate. Fold setup, config, and docs into the task
that needs them. Several identical one-line edits across files are one
batched task, not five.
