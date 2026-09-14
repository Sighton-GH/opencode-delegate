#!/usr/bin/env bash
# Assertions for the oc-task suite. Sourced, never executed. Every helper
# prints one line and bumps a counter; nothing exits, so one failure does not
# hide the rest of the suite.

PASS=0
FAIL=0

section() { printf '\n== %s ==\n' "$1"; }
ok()      { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
no()      { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$1" "$2" "$3"; }

eq()       { [[ "$2" == "$3" ]]   && ok "$1" || no "$1" "$2" "$3"; }
neq()      { [[ "$2" != "$3" ]]   && ok "$1" || no "$1" "anything but: $2" "$3"; }
contains() { [[ "$3" == *"$2"* ]] && ok "$1" || no "$1" "contains: $2" "$3"; }
lacks()    { [[ "$3" != *"$2"* ]] && ok "$1" || no "$1" "does not contain: $2" "$3"; }

summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [[ $FAIL -eq 0 ]]
}
