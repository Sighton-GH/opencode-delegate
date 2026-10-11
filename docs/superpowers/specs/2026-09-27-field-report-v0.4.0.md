# Field report: `opencode-delegate` v0.4.0

**Reporter:** Claude Opus 5.5 (controller session c58862e4), 2026-09-27 (living document: appended as issues occur)
**Workload:** Bananasaurs (TypeScript monorepo). Assistant memory slice 1 (5 tasks) and a skills/reminders slice, run partly in parallel on separate branches.
**Models:** `opencode/muse-spark-1.3-contributor-free`, then `sketchy-tokenzap/gpt-astra` (custom provider) from 18:4xZ.

Severity: Critical = lost work or wrong status; Important = controller cannot tell what happened; Minor = friction.
"Cause" is marked **verified** only where checked against logs or code; otherwise it is a hypothesis.

## 1. A provider rate limit is not reported as exit 5 (Critical)

Three implement runs on three branches were started within ~70 s on the free Muse Spark model:
- `20260927T111150-oc_assistant-memory-slice1`
- `20260927T111253-oc_assistant-memory-typing`
- `20260927T111259-oc_assistant-memory-wizard-ui`

The global opencode log has `level=ERROR message="stream error" … error.error="AI_APICallError: Rate limit exceeded. Please try again later."` for all three sessions at 18:14:01Z, 18:14:02Z and 18:14:05Z (`~/.local/share/opencode/log/opencode.log`, lines ~147284–147304).

What oc-task did:
- slice1: exit 6 "stalled — no output for 420s", with no RESULT.
- typing and wizard-ui: the wrapper printed only `oc-task: linked node_modules into the worktree` and then nothing. It gave no summary, no exit code line and no `.json` run record.

Expected: exit 5 (rate limit) for all three, with the provider message.

Cause: rate limit **verified** from the log. Why two wrappers ended with no summary is **not verified**. They were launched through `… 2>&1 | tail -30` in a background shell, and a signal or pipe issue there is possible.

## 2. Idle timeout never fired on a run whose log stayed empty (Critical)

Run `20260927T112533-oc_skills-reminders` (Muse Spark) was rate-limited at 18:25:38Z, per the opencode log, right after it started.
- Its run log stayed **0 bytes**, and oc-task waited about 18 minutes (default idle timeout 420 s) without killing it.
- I killed the wrapper with SIGTERM. The trap cleaned up correctly: no stray `opencode run` or `opencode serve`, and the worktree was clean.

Cause: **not verified**. The idle loop sets `last_size=-1` and reads `wc -c <"$log"`. A 0-byte log should register one change and then stall at 420 s. Something in that path does not behave as written; worth a fixture test with a model that never emits.

## 3. Rate-limit errors are only in the global opencode log (Important)

Neither run log (`.oc-runs/RUNID.log`) held an error event for the rate limit. From the controller's side a rate limit looked identical to a hang, until I grepped `~/.local/share/opencode/log/opencode.log` by timestamp. Suggest: on a non-zero exit, or a stall, scan the opencode log for the session id and copy any `level=ERROR` lines into the summary's `errors:`.

## 4. A dead wrapper leaves no run record (Important)

After finding 1, the next dispatch on the typing branch said `oc-task: no run record for branch oc/assistant-memory-typing; adopting the existing worktree`. The recovery is good. But the dead run's session id and partial summary were lost, and the ledger had to be rebuilt from `git log`. Suggest writing a provisional `.json` record (run id, session id, branch, start sha) before starting `opencode run`, and updating it at the end.

## 5. Parallel runs against one rate-limited free model get no warning (Minor)

Concurrency across branches works: each run gets its own server, port, worktree and process group. But nothing warns when two or more live runs target the same free model, which is what tripped finding 1. Suggest: `oc-task` checks for other live runs using the same `--model` and warns, or refuses with a flag to override, when the model is on the free tier.

## 6. Continuation briefs must repeat every section (Minor)

After a dead session, the natural continuation brief is "the parent brief is X; steps 1–2 are done at commits A, B; start at step 3". The brief validator rejects it unless it repeats `# Files`, `# Verification`, `# Definition of done` and `# Required output` (two dispatches were rejected this way). Suggest `--continue-from PARENT_BRIEF --from-step N`, or accepting `# Files: see PARENT`.

## 7. Linked node_modules resolve workspace packages to the controller's checkout (Important, known)

In the worktree, `node_modules/@bananasaurs/core` → the controller checkout's `packages/core`, whose `dist/*.d.ts` predates the branch. Type-aware ESLint then reports false `no-unsafe-call` on a new export (`relativeAgo`, Task 2 of slice 1), and the implementer has to argue it away under Concerns. The controller had to fast-forward its own checkout and rebuild types to get a true result. Suggest: optionally link workspace packages to the *worktree's* own packages, or run a `tsc --build` of the changed workspaces in the worktree before verification.

## 9. The RESULT block is printed twice in the summary (Minor)

Run `20260927T113110-oc_assistant-memory-wizard-ui` (gpt-astra): the summary printed `## RESULT`, then every line of the block twice (`Status: DONE` / `Status: DONE`, and so on). Cause **not verified**: either the model emitted two blocks, or the extractor matched twice. If a model repeats its block, the summary should keep only the last one.

## 10. A custom provider's "model unavailable" error is invisible to oc-task (Important)

At 18:38:40Z the opencode log has, for session `ses_f1bd9267affeSDJXlD38zUMzMV` on `sketchy-tokenzap/gpt-astra`, `error.error.message="The model is unavailable right now (unavailable)" error.error.type=upstream_error`. Nothing reached the run log or the summary (same gap as finding 3). Here opencode did retry: that session belonged to run `20260927T113544-oc_skills-reminder-targets`, which finished DONE. The run gave no sign it had hit an upstream error, so a controller can't tell a slow provider from a slow model.

## 12. A provider usage cap kills every run silently, again (Critical)

At 18:58:18–47Z every live session on `sketchy-tokenzap/gpt-astra` got `AI_APICallError: Usage limit reached. Resets in 3h 51m.` in the global opencode log. That was five sessions: fix rounds for three tasks, one implement run and one review. Each `oc-task` wrapper then exited with **no output at all**: no summary, no exit-code line, no `.json` record. One run (`oc_skills-reminders`) had staged but uncommitted work, which the controller committed by hand (b71b5fb). This is finding 1 again, on a paid provider. A usage cap with a known reset time is exactly what exit 5 is for, and the reset time should be in the summary so the controller can schedule the resume.

## 13. An implementer popped the user's stash from inside its worktree (Critical)

Run `20260927T122315-oc_skills-delivery` (Muse Spark). While verifying, the model ran `git stash` (a no-op on a clean tree) and then `git stash pop`. The stash stack is shared by every worktree of the repository, so the pop applied the **user's** unrelated WIP stash (`stash@{0}`, "On fix/mention-the-bot-user: wip…", 2026-09-23) into the oc worktree and produced conflicts. The model then ran `git reset --hard HEAD`. The user's stash survived only because a conflicting pop keeps the entry (verified afterwards with `git stash list`). A clean pop would have dropped it, and the `reset --hard` would have destroyed the user's work.

Suggest: deny `git stash*` for the implementer and reviewer in the session permission rules (`permission: [{ permission: "bash", pattern: "git stash*", action: "deny" }]`). Also say in the implementer brief template that the stash is shared across worktrees and must never be used.

## 14. opencode's own storage fails under concurrent runs: "Failed to execute statement" (Critical)

Run `20260927T123106-oc_skills-reminders` (Muse Spark) had four `oc-task` runs live at once: one implement run, plus two reviews and another implement run on other branches. It ended with a run-log event `{"type":"error","error":{"name":"UnknownError","data":{"message":"Failed to execute statement"}}}`, and the global log has `19:34:31Z level=ERROR … message=process … error="Failed to execute statement"`. That is opencode's own local database, not the provider. The wrapper exited with **no summary and no `.json`** (finding 1 again), after 8 per-change commits. Cause **not verified**, but the likely one is several `opencode serve` processes writing the shared `~/.local/share/opencode` storage at once. That would also explain "parallel works on a good day". Suggest:
- (a) report `type:"error"` run-log events as a failed run with the message;
- (b) test concurrent runs against one opencode data directory, and document a safe concurrency, or give each run its own `XDG_DATA_HOME`.

## 11. No way to choose the base of a new branch (Minor)

`oc-task --branch B` always forks B from the controller checkout's `HEAD`. When tasks run in parallel on several branches, a dependent task (here: removing slash commands, which must build on the typing task's changes to the same file) can't start from the sibling branch it depends on. The controller has to merge that sibling into its own checkout first. Suggest `--base REF` for a new branch.

## 8. `oc-models --free --verbose` prints a jq parse error (Minor)

`jq: parse error: Unfinished string at EOF at line 29304, column 0` printed before the model list; the list itself looked complete. Probably a truncated `opencode models --verbose` read.

## 15. A rate-limited session hangs instead of exiting 5 (Important)

At 20:04:30Z, B2a (`20260927T125610-oc_skills-chat-tools`, Muse Spark, session `ses_f1b8f84b9ffeT0qCTdDFgU0U0B`) got `AI_APICallError: Rate limit exceeded. Please try again later.` in the global log. A review run started at 20:06:49Z got the same error 4 s after its first stream. Neither session retried, and neither run log recorded the error (its last write was the moment of the error). Both `oc-task` wrappers stayed alive and silent until the controller killed them about 3 minutes later. Without the controller's own `tail -F … | grep level=ERROR` watcher, they would have sat until the idle timeout and then reported exit 6 ("stalled"), not 5. This is finding 1 again, but it shows the concrete fix: watch the global log for `level=ERROR` lines carrying the run's `session.id`, and exit 5 when the error is a rate or usage limit.

## 16. A killed run's session can't be resumed (Minor, follows from 4)

After the controller stopped the rate-limited B2a run (finding 15), `oc-task --session ses_f1b8f84b9ffeT0qCTdDFgU0U0B --branch oc/skills-chat-tools` printed `oc-task: no run record in .oc-runs for session …` and exited **0**. The session still exists in opencode, and its context was intact, so a resume would have been the cheap path. Suggest: (a) write the run record at start, not at exit; (b) exit non-zero when refusing.

## 17. opencode's file tools write `\u` escapes as raw control bytes (Important)

Slice 1 fix rounds 4–5 (Muse Spark, session `ses_f1b703a68ffewlDHuHNF03VQAP`). The task was to write the regex literal `/[\u0000-\u001f\u007f[\]]/g`. The model reported: "backslash-`u`/`x`/octal escape sequences cannot be transmitted through my file-editing tools — six attempts across rounds 4–5 each landed as raw control bytes in the file (verified with `od`/`file` showing binary `data`)." In round 4 it worked around this by building the pattern from string fragments (`const BS = '\\'`), which slipped past ESLint's `no-control-regex` and left an unused disable directive. In round 5 it wrote the bytes through a Node helper script in `/tmp/opencode`. The controller verified the final file is plain UTF-8. Cause **not verified**: either the model or opencode's edit tool decodes JSON string escapes a second time. Suggest: reproduce by asking a model to write `"\u0000"` literally via the edit tool, and document the workaround in the implementer brief template.

## 18. The same rate limit produces three different wrapper outcomes (Important)

At 23:15–23:23Z, Muse Spark hit its rate limit, and three live runs ended three different ways:
- `20260927T161119-oc_skills-routes` (E2) exited 0 with **no output at all**: no summary, no RESULT. It left one staged, uncommitted file.
- `20260927T161108-oc_skills-chat-tools` (B2b) exited 0 with a file summary and `## RESULT: (none — model did not emit a RESULT block)`. It did not mention the rate limit.
- `20260927T162255-oc_assistant-memory-slice1-fixes` was rejected on its first request, left a 0-byte run log, and hung until the controller killed it.

None of the three exited 5. A controller can only tell what happened by reading the global opencode log. This is findings 1 and 15 again. The inconsistency is the new part: one error class should produce one outcome.

## 19. The stall message blames the wrong cause (Minor)

Task D (`20260927T181100-oc_skills-chat-tools`) exited `6 (stalled — no output for 420s …)`. The global log shows `Rate limit exceeded` for that session (`ses_f1a6f499cffe8x6M84CkBnWmsQ`) at 01:12:32Z. A sibling run on another branch hit the same error 4 s later, exited 0, and printed no RESULT. The idle-timeout path works as designed, but its message tells the controller the model went quiet, not that the provider refused. Checking the global log for the session's last `level=ERROR` before printing "stalled" would turn this into an exit 5 with the reason.

## 20. A NEEDS_CONTEXT without the `## RESULT` heading is reported as exit 3, "no RESULT" (Minor)

Task D on `sketchy-tokenzap/sol-5.6` (`20260927T183421-oc_skills-chat-tools`) ended after 50 s with `Status: NEEDS_CONTEXT — repository guidance requires reading every document in docs/ …`, but without the `## RESULT` heading. The summary printed `exit: 3 (completed but produced zero changes)` and `## RESULT: (none — model did not emit a RESULT block)`, so the question was only visible in the raw run log. Suggest: when no heading is found, fall back to the last `Status:` line in the final text part, and surface NEEDS_CONTEXT or BLOCKED in the summary.

## 21. Tokenzap `sol-5.6` returns a non-retryable 400 in long sessions (Important, provider)

Two runs of the same continuation brief (`20260927T183401` and `20260927T183756`, `oc_skills-integration`) each died after about 1m50s and about 20 tool calls. Both got `APIError … The request could not be processed (bad_request)` (`req_d6bufcpkymz2`, `req_xleg6mfoog0e`), `isRetryable:false`, and 5-hour utilisation was 7.9%. The inputs had no raw control bytes. A narrow brief for the same work, with bounded offset reads and no `docs/` glob, finished in 1m15s. A parallel D run on the same model kept working. oc-task reported `exit: 1 (opencode errored)` with an empty `errors:` section, so the cause was only visible in the run log's `type:"error"` event. Suggest: print that event's message and request id under `errors:`.

## 22. Two parallel rate-limited runs vanish with no summary and no run artefacts (Important)

On 2026-09-28 at 14:38:47Z and 14:38:53Z, Muse Spark returned `Rate limit exceeded` for two live runs on separate branches: `20260928T072819-oc_skill-gate` (session `ses_f17954f2fffebUIZigl64C58Da`) and `20260928T072949-oc_slice2-panel` (session `ses_f1793f1ecffeTqfbu8HaPnVpnj`). Both `oc-task` processes exited. Neither printed a summary or a RESULT, and neither wrote the run's `.json` or `.diff`. The only stdout was `oc-task: linked node_modules into the worktree`. Each run log ends on an ordinary `step_finish`, so the cause is visible only in the global `~/.local/share/opencode/log/opencode.log`. One run left 12 uncommitted files in its worktree.

This is finding 18 again, with one new part: there are no run artefacts at all, so the controller has no `.diff` to hand a reviewer and must rebuild the review package from the branch. Suggest: on any exit, write the `.json` and `.diff` in a `finally` block, and map a provider `Rate limit exceeded` in the global log to exit 5.

## 23. The merge file audit reads only the last run's brief (Minor)

`oc/slice2-panel` had two runs: the original brief, whose `# Files` section lists five dashboard files, and a continuation brief whose `# Files` section says "As in the s2b brief" (after the finding 22 cut-off). `oc-task --merge` refused all five files as "not listed in the spec's # Files section". The audit seems to parse only the latest run's brief, not the union across the branch's runs. Suggest: audit against the union of every run's `# Files` on the branch, or let a continuation brief declare `# Files: inherit <path>`.

## 24. A usage limit produces "stalled" on one run and a silent exit 1 on another (Important)

On 2026-09-28 at 15:56Z, Tokenzap `sol-5.6` returned `Usage limit reached. Resets in 3h 52m` to two live runs. `20260928T080849-oc_slice3` exited 6 "stalled — no output for 420s" (finding 19). `20260928T084423-oc_slice2-data` exited 1 with no summary and no `.json` or `.diff` (finding 22). Neither run reported the reset time, which the provider had given. Suggest: detect `Usage limit reached` or `Rate limit exceeded` in the global log, exit 5, and print the reset time.

Addendum to 23 (2026-09-28): `oc/skill-prefs` had one run and one brief, and the merge was still refused. Its `# Files` line named one full path followed by bare sibling filenames (`packages/dashboard/src/pages/assistant.tsx`, `assistant-skills.tsx`, …). The audit seems to match only full paths. Suggest: resolve a bare filename against the directory of the previous full path on the same line, or say in the brief template that every path must be repo-relative.

## 25. The Muse Spark rate limit reports as "stalled" again (Minor, recurrence of 19)

On 2026-09-28 at 17:36:23Z and 17:36:46Z, `20260928T103607-oc_slice5` and `20260928T101152-oc_slice3b` each exited 6 "stalled — no output for 420s". In both cases the global log shows `Rate limit exceeded` for that session. This matches finding 19, now on Muse Spark as well as Tokenzap.

## 26. No node_modules is linked when the base checkout has none, and nothing says so (Important)

On 2026-09-29, `oc-task` was run from a Claude Code worktree (`.claude/worktrees/task-tracking-review`) that had no `node_modules` of its own. The first run, `20260929T132439-oc_task-loop-closure`, created `.oc-worktrees/oc/task-loop-closure` with no `node_modules` at all, and printed no warning. The implementer could not run `node node_modules/prettier/bin/prettier.cjs` (MODULE_NOT_FOUND). It fell back to `npx --yes prettier`, which downloads from the npm registry. That is an outbound fetch the brief did not allow. The controller then ran `npm ci` inside the oc worktree. As a side effect this fixes finding 7, because `@bananasaurs/*` then resolves to the worktree's own packages. Cause: verified (the base checkout had no `node_modules` to link). Suggest: when the base has no `node_modules`, warn and offer `--install` (run `npm ci` in the new worktree). Consider making that the default, since it also removes finding 7.

Addendum to 19/25 (2026-09-29): recurred. Run `20260929T135002-oc_task-loop-closure` exited 6 "stalled — no output for 900s" after 26m38s. The global log at 21:01:42Z shows `AI_APICallError: Rate limit exceeded` for session `ses_f11117960ffeNgVqWRBX32tjdY`. Another controller's Muse run (`assistant-memory-slice5`) was live at the same time. Expected exit 5. Recurred at 21:55:16Z: `20260929T144803-oc_task-loop-closure` exited 6 after 22m12s (session `ses_f10dc5c93ffeRS7VKg3IW6HGHP`), again `Rate limit exceeded` in the global log. Recurred on 2026-09-30 at 02:54:11Z on a review run: `20260929T195358-oc_task-loop-closure` (role review, session `ses_f0fc4494effeW2g5Ee2jjBqtjs`) exited 6 after 15m11s. The summary also printed a misleading checkpoint (`a33a868`, the branch base) for a read-only run that has no checkpoint.

Addendum to 8 (2026-09-29): still present. `oc-models --free --verbose` printed `jq: parse error: Unfinished JSON term at EOF at line 29500` and exited 5, although the model list printed in full. An exit of 5 here reads as "rate limited" (the `oc-task` meaning of 5).

Addendum to 8 (2026-09-29, second controller session "bananasaurs mcp forum threads"): recurred at line 22375. Output complete, exit 5. Cause not verified.

Addendum to 7 (2026-09-29): a workaround that needs no network. Before the first gate, `.oc-runs/mcp-v2-s1/relink.sh` (in the `mcp-connector-v2` worktree) replaces the worktree's `node_modules` symlink with a real directory. Every third-party entry in it links to the main checkout's `node_modules`. `@bananasaurs/*` holds relative links, so they resolve to the worktree's own packages. `npm run typecheck` passed in a worktree prepared this way. Suggest `oc-task --link-node-modules=workspace-aware`, which would do the same.

## 27. A rate-limited implement run exits 1 with no summary and leaves staged, uncommitted work (Important, recurrence of 18/22)

On 2026-09-29 (04:21:56Z UTC on the 30th), run `20260929T211125-oc_mcp-v2-s1` (session `ses_f0f7d60aaffeJlG44ZRlKnYbq7`, Muse Spark) ended with wrapper exit 1. It printed nothing: no summary, no RESULT, no .diff or .json. The global log shows `Rate limit exceeded` for that session at 04:21:56Z, and for another controller's session 3 s earlier. The worktree held 8 files staged but not committed (the implementer's step 6). The controller committed them by hand as a checkpoint. Expected exit 5 with a summary, and an automatic checkpoint commit like the one exit 6 gets. Cause: verified (the rate limit); the silent exit 1 path is not verified.

- Recurrence (#19/#25), run 20260929T211855 (bananasaurs, oc/task-loop-closure Task 11): exit 6 "stalled" after 18m02s; the cause was a provider "Rate limit exceeded" at 04:21:53Z in opencode.log, not silence. oc-task still reports it as a stall (exit 6) rather than a rate limit (exit 5). The checkpoint committed an in-progress `git merge` as a two-parent merge commit — correct; worth documenting as intended behaviour.

Addendum to 19/25 (2026-09-30, second recurrence today): `20260930T095545-oc_mcp-v2-s2` exited 6 "stalled — no output for 420s" after 17m17s. The global log shows `Rate limit exceeded` for session `ses_f0cc19decffebvoxjVWvBit1fv` at 17:06:04Z, while another controller's Muse session (`ses_f0cc27e1affeXBS4igiesKcjGG`) had logged "Output token rate limit exceeded" since 17:03:25Z. Expected exit 5.

- Recurrence (#19/#25), run 20260930T095448 (bananasaurs Task 12): rate limit at 17:06:02Z mid-run; oc-task kept waiting for the 900 s idle timeout instead of detecting the provider error. The controller found it by grepping opencode.log for the session id and stopped the run by hand. A log watcher that maps "Rate limit exceeded" to exit 5 immediately would save up to 15 minutes per occurrence.

Addendum to 27 (2026-09-30 18:10Z): recurred on slice 2 Task 3 of the same project. The wrapper exited 1 and printed nothing — no summary, .diff or .json — with two files staged but not committed. The global log shows `Rate limit exceeded` at 18:09:53Z and 18:10:15Z. A concurrent controller's Muse sessions logged "Output token rate limit exceeded" from 18:02Z.

- Recurrence (#19/#25), run 20260930T110734 (bananasaurs Task 13): rate limit at 18:09:53Z, ~2 min into the run; oc-task again waited the full 900 s idle timeout and reported exit 6. A controller-side `tail -n 0 -F ~/.local/share/opencode/log/opencode.log | grep "Rate limit exceeded"` Monitor armed at dispatch did not emit the line, although grep finds it in the file afterwards — suggests opencode rotates/replaces the log file or buffers writes; a watcher inside oc-task (reading the opencode event stream it already captures) would be more reliable.

Addendum to 19/25 (2026-09-30 19:11Z, fourth today): `20260930T121053-oc_mcp-v2-s2` exited 6 ("stalled") with no commits. The global log shows `Rate limit exceeded` for its session `ses_f0c45d950ffe1wlR2C2aa3loHh` at 19:11:49Z, and for two other controllers' sessions at 19:11:47–48Z. Expected exit 5.

## 28. The Muse Spark rate limit reports as "stalled" again, on a review run (Minor, recurrence of 19/25)

- Run `20260930T121140-oc_tavily-web-search` (bananasaurs, `--role review`), 2026-09-30.
- Observed: exit 6 "stalled — no output for 420s", no RESULT block.
- Expected: exit 5 (rate limit).
- The opencode log at 19:11:47.395Z shows `stream error … AI_APICallError: Rate limit exceeded` for session `ses_f0c452e64ffe82TGz0D9xKaYD9`. After that, oc-task waited the full 420 s idle timeout.
- Cause: verified (from the opencode log).

- 2026-09-30 (bananasaurs mcp-v2-s2 T4, run 20260930T132321): #19/#25 recurrence — exit 6 stall after 24m42s; log shows socket-closed x2, invalid upstream JSON, output-token rate limit, backend overloaded on Muse Spark. Wrapper still reports only "no output for 420s"; surfacing the last provider error in the summary would save a log grep.

## 29. A rate-limited implement run exits 0 with no summary, no run JSON, and staged work (Important, recurrence of 27)

- Run log `20260930T140351-oc_tavily-web-search.log` (bananasaurs, implement role, Task 5), session `ses_f0bde78e8ffePZo2KoJSqXmUyZ`, 2026-09-30.
- The opencode log shows `Rate limit exceeded` at 21:22:55Z. Another controller's Muse session, `ses_f0bd80150ffeQowsGLnpK9OdeE`, was running in the task-tracking-review worktree at the same time.
- Observed:
  - `oc-task` printed nothing at all to stdout or stderr (no summary block) and exited 0.
  - No `.json` run record was written; the newest one was the previous run's.
  - Step 3's edits were left staged but uncommitted in the worktree.
- Expected: exit 5, a summary, a run JSON, and a checkpoint commit.
- The controller committed the staged work by hand as a WIP checkpoint.
- Cause: rate limit verified from the opencode log. Why oc-task wrote no output: not verified.

## 30. Rate limit again reported as "stalled", after the full idle timeout (Minor, recurrence of 19/25/28)

- Run `20260930T154132-oc_tavily-web-search`, implement role, `--idle-timeout 900`.
- The opencode log shows `Rate limit exceeded` at 22:45:04Z, about 4 minutes into the run. oc-task then waited the full 900 s and exited 6 (stalled), not 5.
- The run made no changes, and nothing was lost.
- Cause: verified (opencode log).

- 2026-10-01 (bananasaurs mcp-v2-s2 T6): pre-created worktree for a branch based on another oc branch. `--session new --dry-run` said "no run record … dispatch without --session"; dispatching without --session then failed "worktree already exists. Pass --session new to reuse it". `--session new` (non-dry-run) worked and adopted it. The dry-run message is wrong for an adopted worktree. Feature ask: `--base <ref>` to branch an oc run off another oc branch.

## 31. `oc-models --free --verbose` prints a jq parse error, exits 0, and its list may be partial (Minor)

**When:** 2026-09-30 ~19:55 PDT, bananasaurs session (automod-switch plan setup).
**Observed:** `oc-models --free --verbose` printed `jq: parse error: Unfinished string at EOF at line 13888, column 0` first, then 71 model lines, and **exited 0**. A second run, redirected to a file, also exited 0 and listed `opencode/muse-spark-1.3-contributor-free`.
**Expected:** a JSON parse failure should either be impossible (the full catalog is read) or make `oc-models` exit non-zero. As it is, a silently truncated catalog would make the skill's "pick the newest free toolcall model" rule choose from a partial list. Exit 0 also hides the failure from callers that check `$?`.
**Cause:** not verified. Line 13888 ending mid-string suggests the `opencode models --verbose` output was cut off before the final JSON object closed (pipe closed early, or opencode flushing). It is also unclear whether the 71 lines were complete. `bin/oc-models:35` pipes into `jq -r` without `set -o pipefail`, which would explain the exit 0.

## 32. Rate limit again reported as "stalled" (exit 6), on an implement run, with three other Muse Spark sessions live (Minor, recurrence of 19/25/28/30)

**When:** run `20260930T203709-oc_automod-switch`, session `ses_f0a766327ffew2dH2xErYlMWnh`, bananasaurs automod-switch Task 3. Started 03:37Z on 2026-10-01; killed after 12m01s.
**Observed:** `exit: 6 (stalled — no output for 420s …)` with no RESULT block. `opencode.log` line ~239225 at 2026-10-01T03:42:09.903Z shows `AI_APICallError: Rate limit exceeded. Please try again later.` for this session. `oc-task` waited the full idle timeout, then reported a stall. The checkpoint commit `86caa5a5` correctly preserved the uncommitted work.
**Expected:** exit 5 (rate limited) soon after the provider error, so the controller follows the "stop and tell the user" path instead of the "re-dispatch a fresh session" path for exit 6. Following exit 6's advice here would have hit the same limit again.
**Context:** `pgrep -af "opencode run"` showed three other Muse Spark runs from other jobs (logging-routes, channel-permissions, mcp-v2-s2) on the same free seat. The plugin has no view of cross-job concurrency; a shared-seat warning in `oc-task` would help.
**Cause:** verified that the provider rate-limited this session. Not verified why `oc-task` misses the error event in the stream: same symptom as 19/25/28/30.

## 33. Rate limit reported as "stalled" twice more, with the idle timeout raised to 1200s (Minor, recurrence of 32)

**When:** 2026-10-01. Run `20261001T082038`, session `ses_f07f25773ffekNO7OY3QtltgUd` (implement): stream error 15:21:21Z, exit 6 after 20m47s. Run `20261001T084827`, session `ses_f07d8e06bffeWpXDH2IQcKRw1r` (review): `Rate limit exceeded` at 15:48:33Z, 6 seconds after start, exit 6 after 20m07s.
**Observed:** with `--idle-timeout 1200`, every rate limit now costs 20 minutes before `oc-task` gives up, and both runs are labelled "stalled" rather than exit 5. A separate run the same day (`20261001T081221`) did get exit 5 ("The backend is temporarily overloaded"), so detection works for some error shapes and not others: `errors:` lines vs a `stream error` event in the log.
**Expected:** a `stream error` with `Rate limit exceeded` → exit 5 promptly, whatever the idle timeout.
**Cause:** not verified in the plugin. The provider error is verified in `opencode.log` for both sessions.

## 2026-10-01 — no way to start a run on a branch based on a non-default commit

- What happened: to start slice 4 on top of an unmerged sibling branch, the controller pre-created `oc/mcp-v2-s4` at a chosen commit.
  - `oc-task --branch oc/mcp-v2-s4` (no `--session`) refused with "branch already exists; choose another --branch".
  - `--session new` refused with "no run record ... and no worktree".
  - It only worked after a manual `git worktree add .oc-worktrees/oc/mcp-v2-s4 oc/mcp-v2-s4`, then `--session new`. That run "adopted the existing worktree" but recorded its base as the controller's HEAD (89e99dc), not the branch's real fork point, so the per-run diff base is wrong.
- Ask: a `--base <ref>` flag for fresh runs, or let a fresh run adopt an existing branch with no worktree, recording `merge-base` as the base.

### 2026-10-02 — concurrent 'opencode session delete' breaks oc-task runs
Three oc-task runs (2 implement, 1 review) dispatched at 16:12 all exited 1 within 30 s with `UnknownError: Failed to execute statement` (opencode log: error="Failed to execute statement" on message processing). Cause: another session was bulk-deleting opencode sessions (`xargs -n1 opencode session delete`) against the same ~/.local/share/opencode/opencode.db (11.9 GB, disk 96% full) — SQLite write contention. No checkpoint, no files touched.
Suggestion: oc-task could classify this error as transient (distinct exit code, 'retry after the DB is free') instead of the generic exit 1; and a large opencode.db is worth a doctor warning.

## 34. `oc-models --free --verbose` now exits 5 on its jq parse error, the code `oc-task` uses for "rate limited"; `--help` omits `--no-link-node-modules` (Minor, follows 31)

**When:** 2026-10-04 ~05:05Z, bananasaurs resource-leaks plan setup.
**Observed:** `oc-models --free --verbose` printed `jq: parse error: Unfinished string at EOF at line 27603, column 0`, then 92 model lines (Muse Spark among them), and **exited 5**. Item 31 (2026-09-30) saw the same parse error with exit 0. Separately, `oc-task --help` does not list `--no-link-node-modules`, though the skill documents it and `--dry-run` accepts it.
**Expected:** a distinct non-zero exit for a truncated catalog. 5 means "rate limited by the provider" in `oc-task`, so a controller that checks the code could stop the plan and tell the user to wait for a reset that is not needed. `--help` should list every accepted flag.
**Cause:** not verified. Same truncation symptom as 31; the exit code change suggests a pipefail fix that now passes through jq's own status (jq exits 5 on a parse error).

## 35. Rate limit again reported as "stalled" (exit 6), implement run, no RESULT (Minor, recurrence of 19/25/28/30/32/33)

**When:** run `20261003T230929-oc_resource-leaks`, session `ses_efa77d6d1ffeNASk7YFy42JfNn`, bananasaurs resource-leaks Task 1, 2026-10-04 06:09Z–06:33Z.
**Observed:** `exit: 6 (stalled — no output for 420s …)` after 23m44s. `opencode.log` line 304710 at 06:26:12.234Z: `stream error … AI_APICallError: Rate limit exceeded. Please try again later.` for this session. Two other Muse Spark runs from other jobs were live at the time. Steps 2–5 were committed and the end-of-run checkpoint `1da16255` kept a one-file leftover, so no work was lost.
**Expected:** exit 5 promptly after the stream error.
**Cause:** provider rate limit verified in the log; why `oc-task` misses the stream-error event is not verified (same as 33).

## 36. `oc-models --free --verbose` jq parse error and exit 5 again (Minor, recurrence of 31/34)

**When:** 2026-10-06 ~21:15Z, bananasaurs ai-observability plan setup.
**Observed:** `jq: parse error: Unfinished string at EOF at line 24049, column 0`, then a partial model list (Muse Spark present), exit 5.
**Expected:** as in 34, a distinct exit code for a truncated catalog, not the "rate limited" code.
**Cause:** not verified; same symptom as 31/34.

## 37. `npm ci` inside a linked oc worktree empties the source checkout's `node_modules` (Important)

2026-10-06, bananasaurs ai-observability, `oc-task --brief task-2-fix1-brief.md --branch oc/aiobs-t2-fix`, launched from a Claude worktree. `oc-task` printed "linked node_modules into the worktree". The brief's step 0 told the implementer to run `npm ci`. npm deleted the packages through the symlink, then replaced the link with a real directory. The launching worktree was left with an empty `node_modules`, and the controller's concurrent `npm run test` failed on every worker with `Cannot find module …/node_modules/vitest/suppress-warnings.cjs` (49 of 406 files ran). Recovered by re-running `npm ci` in the launching worktree. Suggest: link read-only or warn in the run output that installs must use `--no-link-node-modules`; at minimum document in SKILL.md that an implementer brief must never run `npm ci`/`npm install` in a linked worktree.

## 38. Implement run stalled (exit 6) right after a passing `npm run lint`, no RESULT (Minor, recurrence of 35)

2026-10-07, bananasaurs ai-observability Task 5, run `20261007T182934-oc_aiobs-t5`, Muse, `--no-link-node-modules`. 25m55s; the last event is a completed `npm run lint` (exit 0), then no output for 420 s → `session-dead stalled`. Checkpoint `639980a4` holds 184 lines of uncommitted `run-events.ts` work. Two other Muse runs were active at the time (owner cap 3). Same shape as 35: likely a provider-side stall or limit, reported as exit 6 with no diagnostic.

## 39. Review run stalled (exit 6) with zero model events (Minor, recurrence of 35/38)

2026-10-07 ~19:04 PDT, run `20261007T185720-oc_aiobs-review-t5`, Muse, `--role review --no-link-node-modules`. The log holds only the oc-task line: the model never emitted a single event in 7m06s, and then "stalled". It started 30 s after #38's stall. A zero-event stall is very likely a provider limit; reporting it as exit 5 (rate limited), or at least naming "no model output at all" in the summary, would let a controller stop at once instead of re-dispatching.

## 40. Rate limit reported as "stalled" (exit 6) after 51 min, implement run, no RESULT (Minor, recurrence of 35/38/39)
- Run `20261007T180925-oc_mcp-tools-guide`, session `ses_ee6f11c6cffeTaS9o57RZBJKoa`, Muse Spark 1.3, Bananasaurs worktree `mcp-text-mention-pings`. Exit 6 "no output for 420s"; checkpoint commit `a342e0de` written.
- opencode.log at 2026-10-08T01:53:27Z shows `stream error … AI_APICallError: Rate limit exceeded` for that session. The follow-up `--session new` run (`ses_ee6c1abafffeOGIqR7ZONButYK`, opencode run id 8c764d60) hit the same error at 02:01:23Z on step 0. The controller killed it at ~02:10Z instead of waiting for the 1200s idle timeout.
- Expected: exit 5 (rate limit) as soon as the provider returns 429/"Rate limit exceeded", so the controller stops and does not spend a re-dispatch. Observed: the error is only in opencode.log, and oc-task waits out the idle timeout and reports a stall.
- Cause: verified from opencode.log (the rate-limit error message). Other Muse runs from another job (sessions ses_ee6deaff…, ses_ee6c5440…) failed with the same error in the same window, so the free-tier limit is shared across jobs.

## 41. Four of five implement runs stalled (exit 6) in one evening; the re-dispatch had zero model events (Minor, recurrence of 35/38/39/40)

2026-10-07, bananasaurs ai-observability, Muse, `--no-link-node-modules`. T5 (25 min, stalled after lint), T8 (stalled mid-gates), T9 (stalled mid-gates) and T10 (23 read-only steps, then stall) all died with exit 6 and no RESULT. T10's `--session new` re-dispatch (`20261007T225651`) produced zero model events. Reviews and fix rounds in the same window completed. Checkpoint commits made the stalled work recoverable by cherry-pick every time. A zero-event run should be reported as exit 5.

## 42. `oc-models --free --verbose` prints a jq parse error part-way through the list (Minor)

2026-10-09 ~23:35 PDT, bananasaurs job-lanes. `oc-models --free --verbose` printed `jq: parse error: Unfinished string at EOF at line 22167, column 0` as its first line. It then listed models, including the `opencode/*` free models, so the model choice still worked. Expected: no parse error; if the catalog JSON is truncated, say so and exit non-zero. Cause: not verified. It looks like a truncated catalog read (the input ends inside a string), possibly a partial cache file or a size-limited fetch.

Recurrence 2026-10-10 ~19:25Z (bananasaurs capability-truth): `jq: parse error: Unfinished JSON term at EOF at line 22222, column 0`. This time the list printed only `nvidia/*` entries in the first 30 lines and the `opencode/muse-spark-1.3-contributor-free` id had to be confirmed with `opencode models` instead. Cause: not verified.

### 2026-10-10 — reviewing a non-oc branch (Cline) with oc-task
- `oc-task --role review --branch B` refuses an existing B ("already exists; choose another --branch") and always forks a new B from the caller's HEAD; there is no `--base`. Reviewing a Cline task branch therefore needs a throwaway oc branch whose checkout does NOT contain the code under review; the brief must point the reviewer at the Cline worktree for full files. A `--base <ref>` (or accepting an existing branch for --role review) would fix it.
