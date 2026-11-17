#!/usr/bin/env gjs
// Loads viewer.html?selftest=1 in a bare WebView and exits by result:
// 0 = selftest-pass, 1 = selftest-fail/error, 3 = timeout.
// Usage: gjs page-selftest-runner.js /path/to/viewer.html

imports.gi.versions.Gtk = '3.0';
imports.gi.versions.WebKit2 = '4.1';
const {GLib, Gio, Gtk, WebKit2} = imports.gi;
const System = imports.system;

Gtk.init(null);

if (ARGV.length !== 1) {
    printerr('usage: page-selftest-runner.js VIEWER_HTML');
    System.exit(2);
}

let contentManager = new WebKit2.UserContentManager();
contentManager.register_script_message_handler('kaiten');

let view = new WebKit2.WebView({user_content_manager: contentManager});
let settings = view.get_settings();
settings.set_allow_file_access_from_file_urls(true);
settings.set_allow_universal_access_from_file_urls(true);

let win = new Gtk.Window({default_width: 400, default_height: 400});
win.add(view);
win.show_all();

let status = 2;
let loop = GLib.MainLoop.new(null, false);

contentManager.connect('script-message-received::kaiten', (cm, jsResult) => {
    let msg;
    try {
        msg = JSON.parse(jsResult.get_js_value().to_string());
    } catch (e) {
        return;
    }
    if (msg.event === 'selftest-case') {
        print(`case ${msg.case}: ${msg.pass ? 'pass' : 'FAIL'} — ${msg.detail}`);
    } else if (msg.event === 'selftest-pass') {
        print('selftest-pass');
        status = 0;
        loop.quit();
    } else if (msg.event === 'selftest-fail' || msg.event === 'error') {
        print(`${msg.event}: ${msg.message}`);
        status = 1;
        loop.quit();
    }
});

view.connect('load-failed', (v, ev, uri, error) => {
    print(`load-failed: ${error.message}`);
    status = 1;
    loop.quit();
    return false;
});

view.load_uri(Gio.File.new_for_path(ARGV[0]).get_uri() + '?selftest=1');

GLib.timeout_add(GLib.PRIORITY_DEFAULT, 15000, () => {
    print('timeout');
    status = 3;
    loop.quit();
    return GLib.SOURCE_REMOVE;
});

loop.run();
System.exit(status);
