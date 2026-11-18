# Shared helper for thumbnailer tests. Source this file.
#
# External review (SPEC-010 follow-up): the thumbnailer tests hardcode
# $HOME/.local paths, same class of stale-install risk SPEC-009 fixed
# for the previewer's page-selftest tests. Unlike viewer.html (a loose
# file testable directly from the checkout), makimiru-thumbnailer is a
# meson configure_file() output (@GJS@ etc substituted) — there's no
# "raw checkout" equivalent to run directly. The fix here is a loud
# freshness check instead: fail immediately if the installed binary is
# older than the current source, or differs from the last real build
# output, rather than silently testing a stale copy.

assert_thumbnailer_fresh() { # repo_root
    repo="$1"

    # SPEC-011: a .deb install has no build-install/ dev-staging tree to
    # diff against (its own build/staging lives under deb-build/, a
    # separate pipeline) — MAKIMIRU_TEST_BIN opts into trusting that
    # pipeline's own freshness instead of re-deriving it here (build-
    # deb.sh recompiles from source every run, so "stale" isn't a
    # meaningful risk the way a hand-run install-user.sh's is).
    if [ -n "${MAKIMIRU_TEST_BIN:-}" ]; then
        [ -x "$MAKIMIRU_TEST_BIN" ] || {
            echo "FAIL: $MAKIMIRU_TEST_BIN not found or not executable" >&2
            exit 1
        }
        return
    fi

    installed="$HOME/.local/libexec/makimiru-thumbnailer"
    staged="$repo/build-install$HOME/.local/libexec/makimiru-thumbnailer"
    src="$repo/src/makimiru-thumbnailer.in"

    [ -f "$src" ] || { echo "FAIL: $src not found" >&2; exit 1; }
    [ -f "$staged" ] || {
        echo "FAIL: $staged not staged — run scripts/container-build.sh" >&2
        exit 1
    }
    [ -x "$installed" ] || {
        echo "FAIL: $installed not installed — run scripts/container-build.sh && scripts/install-user.sh" >&2
        exit 1
    }

    if [ "$src" -nt "$staged" ]; then
        echo "FAIL: $src is newer than the staged build output $staged — run scripts/container-build.sh" >&2
        exit 1
    fi
    if ! diff -q "$staged" "$installed" >/dev/null 2>&1; then
        echo "FAIL: installed $installed differs from the staged build output $staged — run scripts/install-user.sh" >&2
        exit 1
    fi
}
