#!/bin/sh
# SPEC-010 acceptance criterion: the thumbnailer applies the same
# SPEC-007 sandbox-gating posture as the previewer — no weaker path for
# unattended use. The two implementations are a deliberate, documented
# duplication (see kaiten-thumbnailer.in's header comment), not a
# shared import, so this test statically checks they stay in structural
# sync rather than trusting the comment alone.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
MODEL="$REPO/src/viewers/model.js"
THUMB="$REPO/src/kaiten-thumbnailer.in"

fail=0

for f in "$MODEL" "$THUMB"; do
    if ! grep -q 'function _shouldDisableSandbox' "$f"; then
        echo "FAIL: _shouldDisableSandbox() not found in $f" >&2
        fail=1
    fi
    if ! grep -q 'apparmor_restrict_unprivileged_userns' "$f"; then
        echo "FAIL: AppArmor userns-restriction sysctl check not found in $f" >&2
        fail=1
    fi
    if ! grep -q 'set_sandbox_enabled(!_shouldDisableSandbox())' "$f"; then
        echo "FAIL: unconditional, negated set_sandbox_enabled call not found in $f" >&2
        fail=1
    fi
    if grep -nE 'set_sandbox_enabled\((true|false)\)' "$f"; then
        echo "FAIL: bare literal set_sandbox_enabled(true|false) found in $f" >&2
        fail=1
    fi
done

# The two APPARMOR_USERNS_RESTRICT_PATH string values must be identical,
# not just both present — a typo'd path in one copy would silently make
# it always fall through to "sandbox stays on", masking a real divergence.
model_path="$(grep -o '/proc/sys/kernel/apparmor_restrict_unprivileged_userns' "$MODEL" | head -1)"
thumb_path="$(grep -o '/proc/sys/kernel/apparmor_restrict_unprivileged_userns' "$THUMB" | head -1)"
if [ "$model_path" != "$thumb_path" ] || [ -z "$model_path" ]; then
    echo "FAIL: sysctl path string differs or missing between $MODEL and $THUMB" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: test-thumbnailer-sandbox-parity"
fi
exit $fail
