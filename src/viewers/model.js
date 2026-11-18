/*
 * Copyright (C) 2026 Kaiten contributors
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 *
 * 3D model previewer: renders STL files with three.js inside a
 * WebKitWebView. See web/main.js for the page side of the contract.
 */

const {Gio, GLib, GObject} = imports.gi;

var WebKit2;
try {
    imports.gi.versions.WebKit2 = '4.1';
    WebKit2 = imports.gi.WebKit2;
} catch(e) {
}

function _isAvailable() {
    return WebKit2 !== undefined;
}

const Renderer = imports.ui.renderer;

// Single named-constant definitions — grepped by
// tests/test-async-audit.sh's threshold-uniqueness check.
const OVERSIZED_THRESHOLD_BYTES = 100 * 1024 * 1024;
const LOAD_TIMEOUT_MS = 15000;

// SPEC-009 (external review, Medium): the timing log previously wrote
// the full previewed file URI on every entry — a silent record of what
// files/paths a user has browsed. Kept on (it's the primary tool this
// project has used for diagnosing timing/error-path bugs through
// SPEC-004-008), but anonymized: extension and size only,
// never the path or filename.
function _extensionOf(basename) {
    let m = /\.([a-zA-Z0-9]+)$/.exec(basename || '');
    return m ? m[1].toLowerCase() : 'unknown';
}

function _logTiming(line) {
    try {
        let path = GLib.build_filenamev(
            [GLib.get_user_runtime_dir(), 'kaiten-timing.log']);
        let stream = Gio.File.new_for_path(path)
            .append_to(Gio.FileCreateFlags.NONE, null);
        stream.write_all(`${line}\n`, null);
        stream.close(null);
    } catch (e) {
        logError(e, 'kaiten: failed to write timing log');
    }
}

// SPEC-007: WebKit's bwrap sandbox needs an unprivileged user
// namespace. AppArmor-hardened kernels (Ubuntu 24.04+) can deny that
// for an unprofiled binary via this sysctl, and the failure is fatal
// (SIGTRAP) — not something we can catch and fall back from. So the
// sandbox is only disabled when this specific precondition is actually
// present, not unconditionally: on hosts without the restriction the
// sandbox stays on (the safer default).
const APPARMOR_USERNS_RESTRICT_PATH =
    '/proc/sys/kernel/apparmor_restrict_unprivileged_userns';

// Cached at module load, not per-renderer-construction: the sysctl
// value can't change during our process lifetime, and every ShowFile
// constructs a fresh renderer/WebContext — computing it once avoids a
// sync procfs read on every single preview (external review, Low: this
// is a deliberate, explicit one-time exception to "no sync I/O in the
// model path", not an oversight — test-async-audit.sh only audits the
// per-preview path, which this no longer touches after the first call).
let _cachedShouldDisableSandbox = null;

function _shouldDisableSandbox() {
    // Dev/test escape hatch: KAITEN_FORCE_SANDBOX=0 forces disabled,
    // =1 forces enabled, unset auto-detects via the sysctl below.
    let override = GLib.getenv('KAITEN_FORCE_SANDBOX');
    if (override === '0')
        return true;
    if (override === '1')
        return false;

    if (_cachedShouldDisableSandbox !== null)
        return _cachedShouldDisableSandbox;

    let restricted = false;
    try {
        let [ok, contents] = GLib.file_get_contents(APPARMOR_USERNS_RESTRICT_PATH);
        restricted = ok && imports.byteArray.toString(contents).trim() === '1';
    } catch (e) {
        // No such sysctl on this kernel: nothing to work around.
    }
    _cachedShouldDisableSandbox =
        restricted || _inForeignSandbox() || !_sandboxProbeSucceeds();
    return _cachedShouldDisableSandbox;
}

// We are already inside someone else's sandbox (e.g. GNOME's thumbnail
// factory bwrap) when our user namespace is not the initial one. WebKit's
// own bwrap sandbox assumes a full host view (/sys, /run, namespaces) and
// aborts the process when nested, in more ways than a probe can mimic
// (host: "No permissions to create new namespace"; VM: "Can't find source
// path /sys/block"). Flatpak is excluded: WebKit sandboxes itself there
// through the portal instead of bwrap.
function _inForeignSandbox() {
    if (GLib.file_test('/.flatpak-info', GLib.FileTest.EXISTS))
        return false;
    try {
        let [ok, contents] = GLib.file_get_contents('/proc/self/uid_map');
        let fields = imports.byteArray.toString(contents).trim().split(/\s+/);
        return ok && !(fields.length === 3 && fields[0] === '0' &&
            fields[1] === '0' && fields[2] === '4294967295');
    } catch (e) {
        return false;
    }
}

// Last check: ask bwrap directly whether it can create the namespaces
// WebKit's sandbox needs (catches userns disabled by other means, e.g.
// kernel.unprivileged_userns_clone=0). Duplicated in src/kaiten-thumbnailer.in
// (see test-thumbnailer-sandbox-parity.sh).
function _sandboxProbeSucceeds() {
    try {
        let [, , , status] = GLib.spawn_sync(null,
            ['/usr/bin/bwrap', '--unshare-all', '--ro-bind', '/', '/', '/usr/bin/true'],
            null,
            GLib.SpawnFlags.STDOUT_TO_DEV_NULL | GLib.SpawnFlags.STDERR_TO_DEV_NULL,
            null);
        return status === 0;
    } catch (e) {
        return false;
    }
}

// SPEC-007 regression, fixed here: once the page's model URL became the
// fixed 'kaiten://app/model' string (no real path/extension in it
// anymore), web/main.js's extensionOf() could no longer infer format
// from the URL and silently defaulted every file to STL parsing. The
// content type that got us dispatched here in the first place
// (mainWindow.js's fileInfo.get_content_type(), matched against our own
// mimeTypes list) is the authoritative source — use that, not a
// filename guess.
function _formatForContentType(contentType) {
    if (contentType === 'model/3mf' ||
        contentType === 'application/vnd.ms-package.3dmanufacturing-3dmodel+xml')
        return '3mf';
    if (contentType === 'model/obj')
        return 'obj';
    return 'stl';
}

function _assetMimeType(path) {
    if (path.endsWith('.html'))
        return 'text/html';
    if (path.endsWith('.js'))
        return 'text/javascript';
    return 'application/octet-stream';
}

var Klass = _isAvailable() ? GObject.registerClass({
    Implements: [Renderer.Renderer],
    Properties: {
        fullscreen: GObject.ParamSpec.boolean('fullscreen', '', '',
                                              GObject.ParamFlags.READABLE,
                                              false),
        ready: GObject.ParamSpec.boolean('ready', '', '',
                                         GObject.ParamFlags.READABLE,
                                         false)
    },
}, class ModelRenderer extends WebKit2.WebView {
    get ready() {
        return !!this._ready;
    }

    get fullscreen() {
        return !!this._fullscreen;
    }

    _init(file, fileInfo) {
        let webDir = GLib.build_filenamev([pkg.pkgdatadir, 'web']);
        this._webDir = webDir;
        this._file = file;
        this._fileUri = file.get_uri();
        this._basename = fileInfo ? fileInfo.get_display_name() : file.get_basename();
        this._logExt = _extensionOf(file.get_basename());
        this._logSize = fileInfo ? fileInfo.get_size() : -1;
        this._failed = false;
        this._timeoutId = 0;

        // External review, High: WebKitGTK's sandbox is opt-in — a fresh
        // WebContext's get_sandbox_enabled() defaults to disabled
        // (verified against this WebKit2 4.1 build), so a call that only
        // ever *disabled* it conditionally left it off unconditionally
        // everywhere, defeating the whole point of the gate below. Must
        // call this explicitly either way, negating the gate's result.
        let context = new WebKit2.WebContext();
        context.set_sandbox_enabled(!_shouldDisableSandbox());

        // SPEC-007: the page and the model file are both served through
        // this custom scheme instead of raw file://, so the page never
        // gets (or needs) broad file:// privilege. The 'model' path is
        // reserved and always resolves to *this renderer's own* file,
        // ignoring whatever the request asks for — there is no way for
        // page-side code to name a different path and get a different
        // file. Registered before super._init() — the context must be
        // holding the scheme before it starts serving any resource.
        context.register_uri_scheme('kaiten', this._onSchemeRequest.bind(this));

        let contentManager = new WebKit2.UserContentManager();
        contentManager.register_script_message_handler('kaiten');

        super._init({
            web_context: context,
            user_content_manager: contentManager,
        });

        this.connect('context-menu', function() {return true;});
        this.connect('destroy', () => this._clearTimeout());

        contentManager.connect('script-message-received::kaiten',
                               this._onPageMessage.bind(this));

        // SPEC-006: unreadable — WebView failed to even load our page
        // (not the model bytes inside it — that's a page-side 'error').
        this.connect('load-failed', (view, loadEvent, uri, error) => {
            this._fail('unreadable', _("Couldn't open %s.").format(this._basename));
        });

        // SPEC-006: renderer/web-process crash mid-preview. The web
        // process can die well after a successful render (e.g. killed,
        // or a driver crash) — not just during initial load.
        this.connect('web-process-terminated', (view, reason) => {
            this._fail('crashed', _("The preview of %s stopped working.").format(this._basename));
        });

        // SPEC-006: size check uses the fileInfo mainWindow.js
        // already fetches async before constructing us — no extra I/O,
        // no parse attempt, so this fires immediately for huge files.
        let size = fileInfo ? fileInfo.get_size() : -1;
        if (size >= OVERSIZED_THRESHOLD_BYTES) {
            this._fail('oversized',
                // TRANSLATORS: %s is a formatted size, e.g. "128 MB"
                _("This model is %s — too large for quick preview.")
                    .format(GLib.format_size(size)));
            return;
        }

        this._startLoadTimeout();
        let format = _formatForContentType(fileInfo ? fileInfo.get_content_type() : null);
        this.load_uri('kaiten://app/viewer.html?model=' +
            encodeURIComponent('kaiten://app/model') +
            '&format=' + format);
        // isReady() is deferred to the page's 'rendered' event so the
        // window keeps its loading spinner until the model is on screen.
    }

    _startLoadTimeout() {
        this._timeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, LOAD_TIMEOUT_MS, () => {
            this._timeoutId = 0;
            this._fail('timeout', _("%s is taking too long to load.").format(this._basename));
            return GLib.SOURCE_REMOVE;
        });
    }

    _clearTimeout() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = 0;
        }
    }

    // Single point of failure handling for every category (SPEC-006:
    // unreadable / corrupt / oversized / crashed / timeout). Emitting via
    // GLib.idle_add — not synchronously — matters: for the 'oversized'
    // case this runs from inside _init(), before mainWindow.js's
    // `renderer.connect('error', ...)` (wired right after `new klass()`
    // returns) has had a chance to attach. A synchronous emit there would
    // fire on zero listeners and the error would be silently lost.
    // Deferring to idle keeps every call site safe without having to
    // reason about which ones are "safe" to emit from directly.
    _fail(category, message) {
        if (this._failed)
            return;
        this._failed = true;
        this._clearTimeout();
        _logTiming(`${new Date().toISOString()} error ${category} ` +
                   `ext=${this._logExt} size=${this._logSize}`);

        // mainWindow.js's ErrorBox (upstream, unmodified) never calls
        // isReady() itself, and the window is only resized/shown from its
        // initial zero size inside _onRendererReady() when ready is true.
        // Without this, mainWindow._reportError()'s swap to ErrorBox still
        // sets Visible=true over D-Bus, but the window is never actually
        // sized — invisible on screen despite "succeeding". Calling
        // isReady() here (safe even from inside _init(), before
        // mainWindow.js's own notify::ready listener is connected — it
        // re-checks the `ready` property value directly right after wiring
        // up, not just the transient signal) sizes/shows the window on
        // *our* renderer before the swap, so ErrorBox displays inside an
        // already-correctly-sized window.
        this.isReady();

        GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this.emit('error', new GLib.Error(
                Gio.IOErrorEnum, Gio.IOErrorEnum.FAILED, message));
            return GLib.SOURCE_REMOVE;
        });
    }

    // SPEC-007: 'kaiten://app/model' always serves *this renderer's*
    // file, regardless of query string or any other path a compromised
    // or buggy page might request — there is no parameter here that
    // selects which file to read. Everything else under 'app/' is
    // resolved against our bundled webDir, with a startsWith guard as
    // defense in depth (the URI layer already collapses '..' segments
    // before get_path() sees them — verified against this WebKit2 4.1
    // build — but the guard costs nothing and doesn't rely on that).
    _onSchemeRequest(request) {
        let path = request.get_path() || '/';
        if (path === '/model') {
            this._serveModel(request);
            return;
        }
        this._serveAsset(request, path);
    }

    _serveAsset(request, path) {
        let rel = path.replace(/^\/+/, '');
        if (rel === '')
            rel = 'viewer.html';
        let target = GLib.build_filenamev([this._webDir, rel]);
        if (target !== this._webDir && !target.startsWith(this._webDir + '/')) {
            request.finish_error(new GLib.Error(
                Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND, 'out of bounds'));
            return;
        }
        Gio.File.new_for_path(target).read_async(GLib.PRIORITY_DEFAULT, null, (f, res) => {
            try {
                let stream = f.read_finish(res);
                // -1: unknown/streamed length — WebKit reads until EOF.
                // Avoids a synchronous file-info lookup on the main thread.
                request.finish(stream, -1, _assetMimeType(target));
            } catch (e) {
                request.finish_error(new GLib.Error(
                    Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND, 'asset not found'));
            }
        });
    }

    _serveModel(request) {
        this._file.read_async(GLib.PRIORITY_DEFAULT, null, (f, res) => {
            try {
                let stream = f.read_finish(res);
                request.finish(stream, -1, 'application/octet-stream');
            } catch (e) {
                request.finish_error(new GLib.Error(
                    Gio.IOErrorEnum, Gio.IOErrorEnum.FAILED, 'model read failed'));
            }
        });
    }

    _onPageMessage(contentManager, jsResult) {
        let msg;
        try {
            msg = JSON.parse(jsResult.get_js_value().to_string());
        } catch (e) {
            logError(e, 'kaiten: bad page message');
            return;
        }

        if (this._failed)
            return;

        if (msg.event === 'rendered') {
            this._clearTimeout();
            _logTiming(`${new Date().toISOString()} rendered ` +
                       `${Math.round(msg.ms)}ms ext=${this._logExt} size=${this._logSize}`);
            this.isReady();
        } else if (msg.event === 'error') {
            // Raw page exception (msg.message) is logged for developers,
            // never shown to the user — SPEC-006 requires a human message,
            // not an exception dump.
            log(`kaiten viewer error: ${msg.message}`);
            this._fail('corrupt',
                _("Couldn't read %s. It may be corrupted or in an unsupported format.")
                    .format(this._basename));
        }
    }

    get moveOnClick() {
        return false;
    }
}) : undefined;

var mimeTypes = [];
if (_isAvailable())
    mimeTypes = [
        'model/stl',
        'application/sla',
        // SPEC-005: 3MF + OBJ. gio's shared-mime-info on Ubuntu 24.04
        // resolves .3mf -> model/3mf and .obj -> model/obj directly (no
        // text/plain collision observed for .obj), so plain
        // MIME registration is enough; no dispatch-order override needed.
        'model/3mf',
        'application/vnd.ms-package.3dmanufacturing-3dmodel+xml',
        'model/obj'
    ];

// SPEC-009: filename-extension fallback, consulted by mimeHandler.js
// only when content-type resolves to exactly 'text/plain' — the one
// documented cross-distro dispatch-fragility risk (a host classifying
// .obj as text/plain instead of model/obj). Scoped to .obj specifically,
// matching that documented risk; .stl/.3mf have no equivalent ambiguity
// observed on any reference machine so far — extend this
// list if that ever changes.
var filenameFallback = [];
if (_isAvailable())
    filenameFallback = [/\.obj$/i];
