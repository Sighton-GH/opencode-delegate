# Scoped re-review brief template

After a fix round. Dispatched with `--role review --session new`. The
re-reviewer verdicts each open finding and flags new breakage in the fix
diff only — it does not wander into a fresh full review.

Required headings: `# Objective`, `# Diff under review`, `# Required output`.
Save as `.oc-runs/<plan-slug>/task-N-rereview-R-brief.md`.

---

```markdown
# Objective
Re-review fix round R of Task N in <plan slug>: verify each open finding
below was addressed, and check the fix diff for new breakage. Nothing else.

# Open findings
<paste the open findings verbatim, numbered, each with file:line>

# Context
Task brief: <absolute path to task-N-brief.md>
The implementer's fix report:
<paste the fix run's ## RESULT block verbatim>

# Diff under review
Read this file once: <absolute path to the fix run's .oc-runs/RUNID.diff>
It is only the fix round's changes (commit list, then the diff with context).
Judge each finding against it. Open a file outside the diff only when a
finding cannot be judged from the diff alone, and say so.

This review is read-only. Do not edit, create, or delete any file. Do not
spawn subagents or sub-tasks.

# Method
For each open finding: ADDRESSED (say where, file:line) or NOT ADDRESSED
(say what is still missing). Then scan the fix diff for anything it broke or
regressed — only Critical or Important new breakage counts; out-of-scope
observations go under "Observations", not "New breakage".

# Required output
End your final message with a block in exactly this form:
## RESULT
Verdict: ALL ADDRESSED | OPEN
Findings:
- <n>. ADDRESSED | NOT ADDRESSED — <file:line or what is missing>
New breakage in fix diff:
- [Critical|Important] <file:line> — <what> — <fix>   (or "none")
Observations: <out-of-scope notes, or "none">
```
