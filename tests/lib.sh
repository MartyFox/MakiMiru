# Shared helpers for fork D-Bus tests. Source this file.
#
# Note: upstream Sushi 46.0 exports Visible/ParentHandle without JS getters,
# so org.freedesktop.DBus.Properties.Get/GetAll return an error/empty dict.
# Nautilus only consumes PropertiesChanged emissions, so tests assert
# visibility by watching those signals rather than polling Get.

DEST=org.gnome.NautilusPreviewer
PATH_OBJ=/org/gnome/NautilusPreviewer

show_v2() { # uri
    gdbus call --session --dest "$DEST" --object-path "$PATH_OBJ" \
        --method org.gnome.NautilusPreviewer2.ShowFile "$1" "" false >/dev/null
}

show_v1() { # uri
    gdbus call --session --dest "$DEST" --object-path "$PATH_OBJ" \
        --method org.gnome.NautilusPreviewer.ShowFile "$1" 0 false >/dev/null
}

close_preview() {
    gdbus call --session --dest "$DEST" --object-path "$PATH_OBJ" \
        --method org.gnome.NautilusPreviewer2.Close >/dev/null
}

# Run "$2" (a shell command) and assert a PropertiesChanged emission sets
# Visible to $1 (true|false) within 5 s.
assert_visible_change() {
    expected="$1"; action="$2"
    mon="$(mktemp)"
    gdbus monitor --session --dest "$DEST" > "$mon" 2>/dev/null &
    mon_pid=$!
    sleep 0.7
    eval "$action"
    ok=1
    i=0
    while [ $i -lt 10 ]; do
        if grep -q "'Visible': <$expected>" "$mon"; then
            ok=0
            break
        fi
        sleep 0.5
        i=$((i + 1))
    done
    kill "$mon_pid" 2>/dev/null || true
    rm -f "$mon"
    if [ $ok -ne 0 ]; then
        echo "FAIL: no PropertiesChanged Visible=$expected after: $action" >&2
        exit 1
    fi
}

owner_cmdline() {
    pid_out="$(gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$DEST")"
    pid="$(echo "$pid_out" | sed -n 's/.*uint32 \([0-9]*\).*/\1/p')"
    tr '\0' ' ' < "/proc/$pid/cmdline"
}
