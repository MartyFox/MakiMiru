conf = configuration_data()

conf.set('libexecdir', libexecdir)
conf.set('app_id', app_id)

configure_file(
  input: 'org.gnome.NautilusPreviewer.service.in',
  output: '@0@.service'.format(app_id),
  configuration: conf,
  install_dir: join_paths(datadir, 'dbus-1', 'services'),
)

i18n.merge_file(
  input: configure_file(
    input: 'org.gnome.NautilusPreviewer.appdata.xml.in.in',
    output: '@BASENAME@',
    configuration: conf
  ),
  output: '@0@.appdata.xml'.format(app_id),
  po_dir: '../po',
  install: true,
  install_dir: join_paths(datadir, 'metainfo')
)

install_data(
  'builder-dark.style-scheme.xml',
  install_dir: join_paths(pkgdatadir, 'gtksourceview-4/styles')
)

# SPEC-009: explicit .obj -> model/obj shared-mime-info override — don't
# rely on the host's own database classifying it correctly (see the XML
# file's own header comment for why).
install_data(
  'org.gnome.NautilusPreviewer-model.xml',
  install_dir: join_paths(datadir, 'mime', 'packages')
)

# SPEC-010: register src/makimiru-thumbnailer with tumbler per the
# freedesktop Thumbnail Managing Standard. libexecdir isn't set in this
# subdir's conf — reuse the shared `conf` from data/meson.build's own
# top (libexecdir/app_id already set there for the D-Bus service file).
configure_file(
  input: 'makimiru-model.thumbnailer.in',
  output: 'makimiru-model.thumbnailer',
  configuration: conf,
  install_dir: join_paths(datadir, 'thumbnailers'),
)

# "Generate 3D Thumbnails" in Files' folder right-click menu, via
# nautilus-python (python3-nautilus); does nothing if that isn't installed.
nautilus_conf = configuration_data()
nautilus_conf.set('bindir', bindir)
configure_file(
  input: 'makimiru-nautilus.py.in',
  output: 'makimiru-nautilus.py',
  configuration: nautilus_conf,
  install: get_option('pregen'),
  install_dir: join_paths(datadir, 'nautilus-python', 'extensions'),
)
