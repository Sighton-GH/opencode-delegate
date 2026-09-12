# Spec template for oc-task

Write specs in the register the Claude Code harness uses: imperative,
tool-shaped, explicitly self-verifying. Free models do well on exactly that.
Every `#` heading below is required by `oc-task` (it rejects specs missing
`Objective`, `Files`, `Tasks`, `Verification`, `Definition of done`, or
`Required output` with exit 2). Text marked VERBATIM must be copied as-is.

Keep specs short enough to finish in under ~20 minutes of model time. If it
is bigger, split it into sequential specs.

---

```markdown
# Objective
<One sentence.>

# Context
<Repo, stack, conventions to follow, and the specific existing files whose
patterns should be imitated. Name them.>

# Constraints
Do not read, open, or screenshot any image or binary file. Reference image
assets by path only. If a task appears to require viewing an image, stop and
report it rather than opening it.
No new dependencies unless listed here: <none | list>.
Out of scope — do not touch: <files and areas that must not change>.

# Files
Create:
- `<exact/path>`
Modify:
- `<exact/path>`
Nothing outside this list may change.

# Interfaces
<Exact signatures, types, exported names.>

# Tasks
1. <first task>
2. <second task>
3. <...>
Run `git add -A && git commit` after completing each numbered task, with the
task number in the commit message.

# Verification
Run `<command>`. If it fails, read the failure, fix it, and run it again.
Repeat until it passes. Do not report completion until it passes.

# Definition of done
- [ ] <acceptance item>
- [ ] <acceptance item>

# Required output
End your final message with a block in exactly this form:
## RESULT
Files changed: ...
Commands run and their outcome: ...
Could not complete: ...
Assumptions made: ...
```

Notes on each section:

- **Objective** — one sentence. If it needs two, the task is not settled.
- **Context** — name the files to imitate. "Follow the pattern in
  `src/api/users.ts`" beats a paragraph about conventions.
- **Constraints** — the image sentence is VERBATIM and non-negotiable: an
  opencode session dies permanently at 50 images. The out-of-scope list is
  what stops the model "helpfully" refactoring neighbours.
- **Files** — `oc-task --merge` refuses if the diff touches anything not
  listed here. Directories may be listed with a trailing `/`; globs work.
- **Interfaces** — exact. The model should never have to invent a name.
- **Tasks** — numbered, ordered, each independently committable. The commit
  instruction is VERBATIM; the checkpoints are what survive an image-limit
  death.
- **Verification** — VERBATIM shape with your command substituted. The
  reviewer re-runs this same command; make it the real one.
- **Required output** — VERBATIM. oc-task extracts this block and it is the
  first thing the reviewer reads.

---

## Worked example

```markdown
# Objective
Add a `DELETE /api/projects/:id` endpoint that soft-deletes a project and its memberships.

# Context
Express + TypeScript + Prisma repo. Routes live in `src/routes/`, one file per
resource, registered in `src/routes/index.ts`. Service logic lives in
`src/services/`. Tests are Vitest + supertest in `tests/routes/`. Imitate
`src/routes/teams.ts` (route shape, error handling via `HttpError`),
`src/services/teamService.ts` (Prisma transaction pattern), and
`tests/routes/teams.test.ts` (fixture setup with `createTestUser`).
Soft delete means setting `deletedAt = new Date()`; `Project` and
`ProjectMembership` already have that column.

# Constraints
Do not read, open, or screenshot any image or binary file. Reference image
assets by path only. If a task appears to require viewing an image, stop and
report it rather than opening it.
No new dependencies unless listed here: none.
Out of scope — do not touch: `prisma/schema.prisma`, `prisma/migrations/`,
`src/routes/teams.ts`, `src/auth/`, any file under `web/`.

# Files
Create:
- `tests/routes/projects.delete.test.ts`
Modify:
- `src/routes/projects.ts`
- `src/services/projectService.ts`
- `src/routes/index.ts`
Nothing outside this list may change.

# Interfaces
```ts
// src/services/projectService.ts
export async function softDeleteProject(
  projectId: string,
  actorId: string,
): Promise<{ id: string; deletedAt: Date }>;
// throws HttpError(404) when the project does not exist or is already deleted
// throws HttpError(403) when actorId is not an OWNER member of the project

// src/routes/projects.ts — new handler
// DELETE /api/projects/:id  -> 204 on success, 404 / 403 via HttpError
```

# Tasks
1. Add `softDeleteProject` to `src/services/projectService.ts`. Use a
   `prisma.$transaction` that sets `deletedAt` on the project and on every
   membership with that `projectId`, exactly like `archiveTeam` in
   `teamService.ts`.
2. Add the `DELETE /:id` handler to `src/routes/projects.ts` using
   `requireAuth` and the service function; respond `204` with no body. Ensure
   the router is exported and registered in `src/routes/index.ts` (it may
   already be — check).
3. Write `tests/routes/projects.delete.test.ts` covering: owner deletes → 204
   and `deletedAt` set on project and memberships; non-owner → 403; unknown id
   → 404; deleting twice → 404.
Run `git add -A && git commit` after completing each numbered task, with the
task number in the commit message.

# Verification
Run `npx vitest run tests/routes/projects.delete.test.ts && npx tsc --noEmit`.
If it fails, read the failure, fix it, and run it again. Repeat until it
passes. Do not report completion until it passes.

# Definition of done
- [ ] All four cases in the new test file pass.
- [ ] `npx tsc --noEmit` is clean.
- [ ] No file outside the Files list changed (`git status` confirms).
- [ ] Three checkpoint commits exist, one per task.

# Required output
End your final message with a block in exactly this form:
## RESULT
Files changed: ...
Commands run and their outcome: ...
Could not complete: ...
Assumptions made: ...
```
