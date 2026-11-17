#!/bin/sh
# SPEC-007 test 2 (static): the WebKit sandbox is *always* explicitly
# set (never left at WebKitGTK's opt-in default of off), driven by
# _shouldDisableSandbox() (env override + AppArmor-userns-restriction
# sysctl check) — external review caught a real bug here: an earlier
# version only ever called set_sandbox_enabled(false) conditionally,
# with no true branch, so the sandbox was off unconditionally on every
# host regardless of the gate. This test requires the single call site
# to use the negated form (enabled on hosts that don't need it
# disabled), not a bare conditional disable-only call.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MODULE="$REPO/src/viewers/model.js"

fail=0

if ! grep -q 'function _shouldDisableSandbox' "$MODULE"; then
    echo "FAIL: _shouldDisableSandbox() not found in $MODULE" >&2
    fail=1
fi

if ! grep -q 'apparmor_restrict_unprivileged_userns' "$MODULE"; then
    echo "FAIL: AppArmor userns-restriction sysctl check not found in $MODULE" >&2
    fail=1
fi

# The only call to set_sandbox_enabled(...) must be the negated-gate
# form, always executed (not inside an if), so both branches (true and
# false) are actually reachable depending on _shouldDisableSandbox().
if ! grep -q 'set_sandbox_enabled(!_shouldDisableSandbox())' "$MODULE"; then
    echo "FAIL: set_sandbox_enabled(!_shouldDisableSandbox()) not found (unconditional, negated call) in $MODULE" >&2
    fail=1
fi

# Guard against a bare unconditional set_sandbox_enabled(false) or
# set_sandbox_enabled(true) literal anywhere — the gate function's
# return value must always be what decides it.
if grep -nE 'set_sandbox_enabled\((true|false)\)' "$MODULE"; then
    echo "FAIL: found a bare literal set_sandbox_enabled(true|false) call in $MODULE" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: test-sandbox-flag"
fi
exit $fail
