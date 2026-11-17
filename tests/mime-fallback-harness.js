#!/usr/bin/env gjs
// SPEC-009 follow-up (external review): deterministically exercises the
// actual mimeHandler.js dispatch code — not the host's live shared-mime-
// info database, which the original test depended on and which passed
// for the wrong reason (this host already resolves .obj -> model/obj, so
// the original test couldn't tell a working override from a dead one).
// Loads the real installed GResource (same pattern as
// uri-scheme-scope-harness.js) and calls MimeHandler.getKlass() directly
// with a forced mime value, proving the *code path* — the fallback for
// content-type resolving to exactly 'text/plain' — actually works,
// independent of what this specific host's mime database happens to do.
//
// Usage: gjs mime-fallback-harness.js PKGDATADIR
// Exit 0 if all cases pass, 1 otherwise (details on stdout either way).
imports.gi.versions.Gtk = '3.0';
const { Gio } = imports.gi;
const System = imports.system;

if (ARGV.length !== 2) {
    printerr('usage: mime-fallback-harness.js PREFIX LIBDIR');
    System.exit(2);
}
const [prefix, libdir] = ARGV;

// mimeHandler.js eagerly imports every viewer module to build its
// renderers list (src/ui/mimeHandler.js's top-level for-loop) —
// including viewers/evince.js, which needs the native Sushi GI typelib.
// uri-scheme-scope-harness.js's lighter globalThis.pkg stub is enough
// for importing viewers.model alone (no evince dependency), but not
// here — this needs the real imports.package.init() bootstrap (same as
// the installed libexec launcher) so GI_TYPELIB_PATH etc are set up
// correctly, not a hand-rolled substitute.
imports.package.init({
    name: 'sushi',
    version: '46.0',
    prefix,
    libdir,
});

const pkgdatadir = pkg.pkgdatadir;
const resourcePath = `${pkgdatadir}/org.gnome.NautilusPreviewer.src.gresource`;
const resource = Gio.Resource.load(resourcePath);
resource._register();
imports.searchPath.unshift('resource:///org/gnome/NautilusPreviewer/js');

const MimeHandler = imports.ui.mimeHandler;
const Model = imports.viewers.model;

let failed = false;
function check(label, got, expected) {
    const pass = got === expected;
    print(`${pass ? 'ok' : 'FAIL'}: ${label} -> ${pass ? 'as expected' : 'mismatch'}`);
    if (!pass)
        failed = true;
}

// Case 1: the documented risk — content-type misresolved to text/plain
// for a .obj file. The fallback must still route to the model viewer.
check(
    'text/plain content-type + .obj filename routes to model viewer',
    MimeHandler.getKlass('text/plain', Gio.File.new_for_path('/tmp/does-not-need-to-exist/cube.obj')),
    Model.Klass);

// Case 2: a genuine text file must NOT be hijacked by the fallback —
// only .obj-named files trigger it.
const Text = imports.viewers.text;
check(
    'text/plain content-type + .txt filename still routes to text viewer',
    MimeHandler.getKlass('text/plain', Gio.File.new_for_path('/tmp/does-not-need-to-exist/notes.txt')),
    Text.Klass);

// Case 3: correct content-type resolution (the normal, non-fallback
// case) still works — model/obj routes to the model viewer directly.
check(
    'model/obj content-type routes to model viewer (no fallback needed)',
    MimeHandler.getKlass('model/obj', Gio.File.new_for_path('/tmp/does-not-need-to-exist/cube.obj')),
    Model.Klass);

// Case 4: the fallback must be scoped to exactly 'text/plain' — an
// unrelated mime type with a .obj filename must not spuriously match.
check(
    'unrelated content-type + .obj filename does not spuriously fallback',
    MimeHandler.getKlass('image/png', Gio.File.new_for_path('/tmp/does-not-need-to-exist/cube.obj')) !== Model.Klass,
    true);

System.exit(failed ? 1 : 0);
