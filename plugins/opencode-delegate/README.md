# opencode-delegate (plugin)

Hand settled, mechanical implementation work to a fast free opencode model
inside a git worktree. Claude writes the spec, reviews the diff, re-runs
verification, and merges with one revert point.

Full docs, install steps, the worked example, and troubleshooting are in the
[repository README](../../README.md). This file is the short version for
someone who already has the plugin enabled.

## What you get

- `/delegate` — the skill. Fires on `/delegate` or when Claude judges a task
  fits. Runs a triage gate, writes a spec from
  `skills/delegate/spec-template.md`, waits for your approval, dispatches,
  reviews, merges or corrects.
- `oc-task` — dispatch a spec into `.oc-worktrees/BRANCH`, print a compact
  summary, write `.oc-runs/RUNID.{log,diff,json}`. `--merge` merges with
  `--no-ff` after refusing every unsafe case. `--dry-run` resolves without
  dispatching.
- `oc-models` — live model list, free first. `--free` filters, `--verbose`
  adds context/toolcall/reasoning/date columns for choosing a replacement.
- `oc-undo` — revert the newest oc-task merge. `--list` shows them.

## Prerequisites

bash, git, jq, curl, and an installed **and authenticated** opencode
(`opencode providers list` should show a provider). The plugin carries no
credentials.

## Model selection

`--model` > `$OC_DELEGATE_MODEL` > `model=` in `~/.config/oc-delegate/config`
> built-in `opencode/muse-spark-1.3-contributor-free`. Run `oc-models --free`
for what's currently free; nothing here hardcodes that list. If the default
is gone, Claude picks the best free tool-calling model (see the skill's
rules) and `oc-task` refuses any id not in the live catalog.

## Exit codes (`oc-task`)

0 success · 1 opencode/setup error · 2 spec rejected · 3 zero changes ·
4 image limit (session dead, never retried) · 5 rate limited.

Non-zero exits leave the worktree in place.

## Safety model

Permissions are auto-approved for the model's session only because it runs in
a throwaway worktree: the base branch is untouched until `--merge`, `--merge`
requires your `--verified "COMMAND"` attestation and refuses files outside the
spec, and `oc-undo` reverts a merge in one command.
