# opencode-delegate (plugin)

opencode-driven development: Claude brainstorms, writes the plan and every
brief, adjudicates reviews, and merges; opencode sessions on free models
(Muse Spark 1.3 by default) implement each task, review each task, and
review the whole branch. A mirror of superpowers' subagent-driven-development
with opencode in every subagent seat.

Full docs, install steps, the worked example, and troubleshooting are in the
[repository README](../../README.md). This file is the short version for
someone who already has the plugin enabled.

## What you get

- `/opencode-driven-development` — the skill. Fires on its own whenever a
  task is worth a 2+ task plan, or when you type it. Plan approved once,
  then continuous execution: implementer → your verification re-run →
  opencode reviewer → fix loop → next task → final whole-branch review →
  rulings report → merge/PR/leave.
- `oc-task` — dispatch a brief into `.oc-worktrees/BRANCH` (`--role
  implement` edits and commits; `--role review` is read-only via opencode's
  `plan` agent), print a compact summary, write `.oc-runs/RUNID.{log,diff,json}`.
  `--branch-diff` writes the whole-branch diff for the final review.
  `--merge` merges with `--no-ff` after refusing every unsafe case.
- `oc-models` — live model list, free first. `--free` filters, `--verbose`
  adds context/toolcall/reasoning/date columns for choosing a replacement.
- `oc-undo` — revert the newest oc-task merge. `--list` shows them.

## Prerequisites

bash, git, jq, curl, and an installed **and authenticated** opencode
(`opencode providers list` should show OpenCode Zen). The plugin carries no
credentials. The `superpowers` plugin is a recommended companion; the skill
falls back to built-in equivalents without it.

## Model selection

Free only. `--model` > `$OC_DELEGATE_MODEL` > `model=` in
`~/.config/oc-delegate/config` > built-in
`opencode/muse-spark-1.3-contributor-free`. If the default is gone, Claude
picks the best free tool-calling model per the skill's rules and `oc-task`
refuses any id not in the live catalog.

## Exit codes (`oc-task`)

0 success · 1 opencode/setup error · 2 brief rejected · 3 zero changes
(implement) · 4 image limit (session dead, never retried) · 5 rate limited.
Non-zero exits leave the worktree in place.

## Safety model

Permissions are auto-approved for implement sessions only because they run
in a throwaway worktree; reviewers run opencode's read-only agent. The base
branch is untouched until `--merge`, which requires your `--verified
"COMMAND"` attestation and refuses files outside the briefs. `oc-undo`
reverts a merge in one command. Tasks touching auth, secrets, crypto, or
payments get an explicit "send this to an opencode model?" question first.
