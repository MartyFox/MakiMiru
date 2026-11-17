#!/bin/sh
# SPEC-004 test 2: SPEC-003's smoke matrix still passes with the model
# viewer registered — no regression from adding the module.
set -eu
exec sh "$(dirname "$0")/test-preview-smoke.sh"
