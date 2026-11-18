#!/bin/sh
# SPEC-005 test 4 / SPEC-006 test 1: fixture generator self-checks (no
# D-Bus/GUI needed). make-3mf.py output is a valid zip containing
# 3D/3dmodel.model; make-obj.py output parses to the expected
# vertex/face counts; make-bad-fixtures.py sizes/types match intent.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="${TMPDIR:-/tmp}/makimiru-fixture-selfcheck"
mkdir -p "$TMP"

python3 "$DIR/make-3mf.py" "$TMP/single.3mf"
python3 "$DIR/make-3mf.py" "$TMP/two.3mf" --two-object

python3 -m zipfile -l "$TMP/single.3mf" | grep -q '3D/3dmodel.model' \
    || { echo "FAIL: single.3mf missing 3D/3dmodel.model" >&2; exit 1; }
python3 -m zipfile -l "$TMP/single.3mf" | grep -q '\[Content_Types\].xml' \
    || { echo "FAIL: single.3mf missing [Content_Types].xml" >&2; exit 1; }
python3 -m zipfile -l "$TMP/single.3mf" | grep -q '_rels/.rels' \
    || { echo "FAIL: single.3mf missing _rels/.rels" >&2; exit 1; }

single_objects="$(python3 -c "
import zipfile
z = zipfile.ZipFile('$TMP/single.3mf')
print(z.read('3D/3dmodel.model').decode().count('<object '))
")"
[ "$single_objects" = "1" ] || { echo "FAIL: single.3mf has $single_objects objects, want 1" >&2; exit 1; }

two_objects="$(python3 -c "
import zipfile
z = zipfile.ZipFile('$TMP/two.3mf')
print(z.read('3D/3dmodel.model').decode().count('<object '))
")"
[ "$two_objects" = "2" ] || { echo "FAIL: two.3mf has $two_objects objects, want 2" >&2; exit 1; }
echo "ok: make-3mf.py (single=$single_objects, two-object=$two_objects)"

python3 "$DIR/make-obj.py" "$TMP/cube.obj"
v_count="$(grep -c '^v ' "$TMP/cube.obj")"
f_count="$(grep -c '^f ' "$TMP/cube.obj")"
[ "$v_count" = "8" ] || { echo "FAIL: cube.obj has $v_count vertices, want 8" >&2; exit 1; }
[ "$f_count" = "12" ] || { echo "FAIL: cube.obj has $f_count faces, want 12" >&2; exit 1; }
echo "ok: make-obj.py (vertices=$v_count, faces=$f_count)"

python3 "$DIR/make-bad-fixtures.py" "$TMP/bad"

trunc_size="$(stat -c '%s' "$TMP/bad/truncated.stl")"
[ "$trunc_size" -eq 184 ] || { echo "FAIL: truncated.stl is $trunc_size bytes, want 184" >&2; exit 1; }

garbage_size="$(stat -c '%s' "$TMP/bad/garbage.stl")"
[ "$garbage_size" -eq 2048 ] || { echo "FAIL: garbage.stl is $garbage_size bytes, want 2048" >&2; exit 1; }

empty_size="$(stat -c '%s' "$TMP/bad/empty.stl")"
[ "$empty_size" -eq 0 ] || { echo "FAIL: empty.stl is $empty_size bytes, want 0" >&2; exit 1; }

python3 -m zipfile -l "$TMP/bad/notreally.3mf" | grep -q '3D/3dmodel.model' \
    || { echo "FAIL: notreally.3mf missing 3D/3dmodel.model" >&2; exit 1; }
model_content="$(python3 -c "
import zipfile
z = zipfile.ZipFile('$TMP/bad/notreally.3mf')
print(z.read('3D/3dmodel.model').decode())
")"
case "$model_content" in
    *"<model"*) echo "FAIL: notreally.3mf's model part looks like valid 3MF XML, not garbage" >&2; exit 1 ;;
esac

big_size="$(stat -c '%s' "$TMP/bad/big.stl")"
[ "$big_size" -ge 105906176 ] || { echo "FAIL: big.stl is $big_size bytes, want >= 101 MB" >&2; exit 1; }

echo "ok: make-bad-fixtures.py (truncated=${trunc_size}B garbage=${garbage_size}B empty=${empty_size}B big=${big_size}B, notreally.3mf content is not valid 3MF XML)"

echo "PASS: test-fixture-generators"
