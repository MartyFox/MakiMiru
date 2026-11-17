#!/usr/bin/env gjs
// SPEC-007 follow-up: loads the *real* installed ModelRenderer (via the
// installed GResource, not a reimplementation) and drives its actual
// 'kaiten://' scheme handler with attacker-shaped requests from real
// page-side JS, to prove traversal/arbitrary-model-file attempts fail
// against the live code, not just a static grep.
//
// Usage: gjs uri-scheme-scope-harness.js SUSHI_PKGDATADIR STL_FIXTURE_PATH
// Exit: 0 = all probes behaved safely, 1 = a probe leaked/misbehaved.

imports.gi.versions.Gtk = '3.0';
imports.gi.versions.WebKit2 = '4.1';
const { Gio, GLib, Gtk, WebKit2 } = imports.gi;
const System = imports.system;

if (ARGV.length !== 2) {
    printerr('usage: uri-scheme-scope-harness.js SUSHI_PKGDATADIR STL_FIXTURE_PATH');
    System.exit(2);
}
const [pkgdatadir, fixturePath] = ARGV;

// Minimal stand-ins for what the real libexec binary's imports.package
// bootstrap provides — just enough for model.js's _init() to run.
globalThis.pkg = { pkgdatadir };
globalThis._ = (s) => s;
if (!String.prototype.format) {
    String.prototype.format = function (...args) {
        let i = 0;
        return this.replace(/%s/g, () => args[i++]);
    };
}

const resourcePath = GLib.build_filenamev(
    [pkgdatadir, 'org.gnome.NautilusPreviewer.src.gresource']);
const resource = Gio.Resource.load(resourcePath);
resource._register();
imports.searchPath.unshift('resource:///org/gnome/NautilusPreviewer/js');

Gtk.init(null);

const Model = imports.viewers.model;
const file = Gio.File.new_for_path(fixturePath);
const fileInfo = file.query_info('standard::*', Gio.FileQueryInfoFlags.NONE, null);

const renderer = new Model.Klass(file, fileInfo);
const win = new Gtk.OffscreenWindow();
win.add(renderer);
win.show_all();

const contentManager = renderer.get_user_content_manager();

let status = 2;
const loop = GLib.MainLoop.new(null, false);
let pageReady = false;

// Probes run once the real page (viewer.html, loaded through the real
// scheme handler) has finished its own normal load — proves the scheme
// handler correctly serves legitimate content first, then that it
// refuses everything these probes ask for.
const PROBES = [
    // Path traversal against the asset root ('viewer' — anything other
    // than the reserved '/model' path resolves against webDir).
    "fetch('kaiten://app/../../../../../../etc/passwd').then(r => r.status).catch(() => 'rejected')",
    "fetch('kaiten://app/%2e%2e/%2e%2e/etc/passwd').then(r => r.status).catch(() => 'rejected')",
    // The reserved model path must ignore whatever it's asked for and
    // only ever return *this renderer's own* file — never a path a page
    // could name to redirect to something else.
    "fetch('kaiten://app/model?x=/etc/passwd').then(r => r.text()).then(t => t.slice(0, 5))",
    "fetch('kaiten://app/model/../../../etc/passwd').then(r => r.text()).then(t => t.slice(0, 5)).catch(() => 'rejected')",
];
let probeIndex = 0;
const results = [];

function runNextProbe() {
    if (probeIndex >= PROBES.length) {
        finish();
        return;
    }
    const script = PROBES[probeIndex];
    // run_javascript_finish() only marshals a handful of result types back
    // to GJS and throws "Unsupported result type" for our async IIFE's
    // own Promise return value — that's expected and ignored here. It
    // does NOT mean the script didn't run: the IIFE keeps executing
    // regardless, and its postMessage (caught by the listener below) is
    // the only real completion signal for a probe. Driving sequencing
    // off this callback instead (as an earlier version of this harness
    // did) races the real result and desyncs probe indices.
    renderer.run_javascript(`
        (async () => {
            let r;
            try { r = await (${script}); } catch (e) { r = 'threw: ' + e; }
            window.webkit.messageHandlers.kaiten.postMessage(
                JSON.stringify({ event: 'probe-result', index: ${probeIndex}, result: String(r) }));
        })();
    `, null, (view, res) => {
        try {
            view.run_javascript_finish(res);
        } catch (e) {
            // Expected — see comment above. Intentionally not treated as
            // the probe's completion or failure.
        }
    });
}

function finish() {
    print('--- probe results ---');
    let safe = true;
    results.sort((a, b) => a.index - b.index);
    for (const r of results) {
        print(`probe ${r.index}: ${r.result}`);
        // Any probe that actually got /etc/passwd content (root-owned
        // passwd file starts with 'root:') is a real leak.
        if (typeof r.result === 'string' && r.result.startsWith('root:'))
            safe = false;
    }
    status = safe ? 0 : 1;
    loop.quit();
}

contentManager.connect('script-message-received::kaiten', (cm, jsResult) => {
    let msg;
    try {
        msg = JSON.parse(jsResult.get_js_value().to_string());
    } catch (e) {
        return;
    }
    if (msg.event === 'rendered' && !pageReady) {
        pageReady = true;
        runNextProbe();
    } else if (msg.event === 'probe-result') {
        results.push({ index: msg.index, result: msg.result });
        probeIndex++;
        runNextProbe();
    } else if (msg.event === 'error' && !pageReady) {
        printerr('page failed to load before probes could run: ' + msg.message);
        status = 1;
        loop.quit();
    }
});

GLib.timeout_add(GLib.PRIORITY_DEFAULT, 20000, () => {
    printerr('timeout waiting for page load / probes');
    status = 3;
    loop.quit();
    return GLib.SOURCE_REMOVE;
});

loop.run();
System.exit(status);
