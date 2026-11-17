#!/usr/bin/env gjs
// SPEC-010 test 2 support script: loads a model through the *same*
// offscreen-WebKit + 'kaiten://' scheme wiring kaiten-thumbnailer
// itself uses (not a reimplementation borrowed from the previewer), then
// reads window.kaiten.getBounds() at the same point the real CLI
// would snapshot — proving the thumbnailer's rendering path produces the
// identical framing contract (fillRatio, center) already established for
// the previewer by SPEC-004/005's selftest, not just "renders something."
//
// Usage: gjs thumbnailer-framing-probe.js MODEL_PATH PKGDATADIR FORMAT
// Prints one line of JSON: {"fillRatio":N,"center":[x,y,z]} then exits 0,
// or prints an error to stderr and exits 1.
imports.gi.versions.Gtk = '3.0';
imports.gi.versions.WebKit2 = '4.1';
const { Gtk, GLib, WebKit2, Gio } = imports.gi;
const System = imports.system;

if (ARGV.length !== 3) {
    printerr('usage: thumbnailer-framing-probe.js MODEL_PATH PKGDATADIR FORMAT');
    System.exit(2);
}
const [modelPath, pkgdatadir, format] = ARGV;
const webDir = GLib.build_filenamev([pkgdatadir, 'web']);
const modelFile = Gio.File.new_for_path(modelPath);

Gtk.init(null);

const context = new WebKit2.WebContext();
context.register_uri_scheme('kaiten', (request) => {
    let path = request.get_path() || '/';
    if (path === '/model') {
        modelFile.read_async(GLib.PRIORITY_DEFAULT, null, (f, res) => {
            try {
                request.finish(f.read_finish(res), -1, 'application/octet-stream');
            } catch (e) {
                request.finish_error(new GLib.Error(Gio.IOErrorEnum, Gio.IOErrorEnum.FAILED, 'read failed'));
            }
        });
        return;
    }
    let rel = path.replace(/^\/+/, '') || 'viewer.html';
    let target = GLib.build_filenamev([webDir, rel]);
    Gio.File.new_for_path(target).read_async(GLib.PRIORITY_DEFAULT, null, (f, res) => {
        try {
            let stream = f.read_finish(res);
            let mime = target.endsWith('.html') ? 'text/html'
                : target.endsWith('.js') ? 'text/javascript' : 'application/octet-stream';
            request.finish(stream, -1, mime);
        } catch (e) {
            request.finish_error(new GLib.Error(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND, 'not found'));
        }
    });
});

const contentManager = new WebKit2.UserContentManager();
contentManager.register_script_message_handler('kaiten');
const view = new WebKit2.WebView({ web_context: context, user_content_manager: contentManager });
view.set_size_request(256, 256);
const win = new Gtk.OffscreenWindow();
win.add(view);
win.show_all();

const loop = GLib.MainLoop.new(null, false);
let status = 3;

contentManager.connect('script-message-received::kaiten', (cm, jsResult) => {
    let msg;
    try {
        msg = JSON.parse(jsResult.get_js_value().to_string());
    } catch (e) { return; }
    if (msg.event === 'rendered') {
        view.run_javascript(
            'JSON.stringify(window.kaiten.getBounds())',
            null, (v, res) => {
                try {
                    let value = v.run_javascript_finish(res);
                    print(value.get_js_value().to_string());
                    status = 0;
                } catch (e) {
                    printerr('run_javascript failed: ' + e);
                    status = 1;
                }
                loop.quit();
            });
    } else if (msg.event === 'error') {
        printerr('page error: ' + msg.message);
        status = 1;
        loop.quit();
    }
});

view.connect('load-failed', (v, ev, uri, error) => {
    printerr('load-failed: ' + error.message);
    status = 1;
    loop.quit();
});

view.load_uri('kaiten://app/viewer.html?model=' +
    encodeURIComponent('kaiten://app/model') + '&format=' + format);

GLib.timeout_add(GLib.PRIORITY_DEFAULT, 15000, () => {
    printerr('timeout');
    status = 3;
    loop.quit();
    return GLib.SOURCE_REMOVE;
});

loop.run();
System.exit(status);
