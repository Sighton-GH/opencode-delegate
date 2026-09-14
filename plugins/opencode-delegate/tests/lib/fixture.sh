#!/usr/bin/env bash
# Throwaway git repos for the oc-task suite. Every fixture lives under a
# directory whose name contains a space, because that is the condition the
# field report's critical bug needed to reproduce.

FIXTURES_CREATED=()

new_fixture() { # $1 = optional label
  local label="${1:-fix}"
  FIX_ROOT=$(mktemp -d)/"with space"
  mkdir -p "$FIX_ROOT"
  FIXTURES_CREATED+=("$(dirname "$FIX_ROOT")")

  FIX_REPO="$FIX_ROOT/$label repo"
  FIX_BIN="$FIX_ROOT/bin"
  FIX_STUB_STATE="$FIX_ROOT/stub-state"
  mkdir -p "$FIX_REPO" "$FIX_BIN" "$FIX_STUB_STATE"

  ln -sf "$TESTS_DIR/lib/stub-opencode" "$FIX_BIN/opencode"

  git -C "$FIX_REPO" init -q
  git -C "$FIX_REPO" config user.email oc-test@localhost
  git -C "$FIX_REPO" config user.name oc-test
  printf 'seed\n' >"$FIX_REPO/seed.txt"
  git -C "$FIX_REPO" add -A
  git -C "$FIX_REPO" commit -q -m "seed"

  export OC_STUB_STATE="$FIX_STUB_STATE"
  export XDG_CONFIG_HOME="$FIX_ROOT/config"
}

fixture_cleanup() {
  local d
  for d in "${FIXTURES_CREATED[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
  return 0
}

# Run oc-task inside the current fixture with the stub on PATH. Captures
# stdout+stderr into $OUT and the exit status into $STATUS; never aborts.
run_oc() {
  set +e
  OUT=$(cd "$FIX_REPO" && PATH="$FIX_BIN:$PATH" bash "$OC_TASK" "$@" 2>&1)
  STATUS=$?
  set -e
}

# Write a valid implement brief to $1.
write_brief() {
  cat >"$1" <<'BRIEF'
# Objective
Stub task.

# Files
Create:
- `stub-output.txt`

# Tasks
1. Write the file.

# Verification
Run `true`.

# Definition of done
- [ ] Done.

# Required output
End your final message with a block in exactly this form:
## RESULT
Status: DONE
BRIEF
}
