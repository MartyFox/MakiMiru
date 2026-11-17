#!/bin/sh
# Release review (2026-11-17): the .deb's Depends once omitted every GI
# typelib package the GJS code imports (gir1.2-webkit2-4.1, gir1.2-gtk-3.0,
# ...). Never caught because every test machine also had gnome-sushi
# installed, which pulls them in. This test derives the GI namespaces
# imported anywhere under src/, maps each to the package owning its
# typelib on this machine, and asserts that package is in Depends.
#
# Requires: the typelibs installed locally (any machine that can run the
# previewer) and dpkg. LOKDocView is optional (libreoffice.js try/catch)
# and must be in Suggests instead.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONTROL="$REPO/debian/control.in"
GIDIR="/usr/lib/$(uname -m)-linux-gnu/girepository-1.0"
OPTIONAL="LOKDocView"

field() { # name -> comma list as one-per-line package names (alternatives split too)
    sed -n "s/^$1: //p" "$CONTROL" | tr ',|' '\n\n' | sed 's/^ *//; s/ *$//; s/ *(.*//' | grep -v '^$'
}
depends="$(field Depends)"
suggests="$(field Suggests)"

# Namespaces: destructured `const {A, B} = imports.gi` and `imports.gi.X`.
namespaces="$(grep -rhoE "const \{[^}]+\} *= *imports\.gi|imports\.gi\.[A-Za-z0-9]+" \
        "$REPO/src" --include='*.js' --include='*.in' |
    sed -E 's/const \{([^}]+)\}.*/\1/; s/imports\.gi\.//' |
    tr ',' '\n' | sed 's/ //g' | grep -v -e '^versions$' -e '^Sushi$' -e '^$' | sort -u)"

fail=0
for ns in $namespaces; do
    typelib="$(ls "$GIDIR/$ns"-*.typelib 2>/dev/null | head -n1)"
    if [ -z "$typelib" ]; then
        case " $OPTIONAL " in *" $ns "*) echo "skip: $ns (optional, not installed here)"; continue ;; esac
        echo "FAIL: no typelib for $ns under $GIDIR — cannot verify" >&2; fail=1; continue
    fi
    pkg="$(dpkg -S "$typelib" 2>/dev/null | cut -d: -f1 | head -n1)"
    case " $OPTIONAL " in
        *" $ns "*) list="$suggests"; where=Suggests ;;
        *) list="$depends"; where=Depends ;;
    esac
    if printf '%s\n' "$list" | grep -qxF "$pkg"; then
        echo "ok: $ns -> $pkg ($where)"
    else
        echo "FAIL: $ns typelib is in $pkg, not listed in $where" >&2; fail=1
    fi
done
[ $fail -eq 0 ] && echo "PASS: every imported GI namespace is covered by the package's dependencies"
exit $fail
