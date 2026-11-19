gnome = import('gnome')

# Compile libsushi and its introspection data
subdir('libsushi')

conf_src = configuration_data()
conf_src.set('object_path', object_path)

sushi_src_resources = gnome.compile_resources(
    '@0@.src'.format(app_id),
    configure_file(
      input: 'org.gnome.NautilusPreviewer.src.gresource.xml.in',
      output: '@BASENAME@',
      configuration: conf_src
    ),
    gresource_bundle: true,
    install: true,
    install_dir: pkgdatadir,
)

sushi_data_resources = gnome.compile_resources(
    '@0@.data'.format(app_id),
    'org.gnome.NautilusPreviewer.data.gresource.xml',
    gresource_bundle: true,
    install: true,
    install_dir: pkgdatadir,
)

conf = configuration_data()
conf.set('GJS', gjs.full_path())
conf.set('PACKAGE_NAME', meson.project_name())
conf.set('PACKAGE_VERSION', meson.project_version())
conf.set('prefix', get_option('prefix'))
conf.set('libdir', libdir)
conf.set('pkgdatadir', pkgdatadir)
conf.set('app_id', app_id)
conf.set('object_path', object_path)

nautilus_previewer_bin = configure_file(
  input: 'org.gnome.NautilusPreviewer.in',
  output: app_id,
  configuration: conf,
)

install_data(
  nautilus_previewer_bin,
  install_mode: 'rwxr-xr-x',
  install_dir: libexecdir,
)

sushi_bin = configure_file(
  input: 'sushi.in',
  output: 'sushi',
  configuration: conf,
)

install_data(
  sushi_bin,
  install_mode: 'rwxr-xr-x',
  install_dir: bindir,
)

# SPEC-010: standalone thumbnailer CLI, invoked by tumbler per the
# freedesktop Thumbnail Managing Standard. Plain gjs script (not
# gresource-compiled like the previewer's JS) — self-locates web/ assets
# via the same imports.package.init() pkgdatadir mechanism.
makimiru_thumbnailer_bin = configure_file(
  input: 'makimiru-thumbnailer.in',
  output: 'makimiru-thumbnailer',
  configuration: conf,
)

install_data(
  makimiru_thumbnailer_bin,
  install_mode: 'rwxr-xr-x',
  install_dir: libexecdir,
)

# makimiru-pregen: user-facing command for the thumbnailer's batch mode
# (pre-generates a folder's thumbnails into GNOME's cache).
pregen_conf = configuration_data()
pregen_conf.set('libexecdir', libexecdir)
makimiru_pregen_bin = configure_file(
  input: 'makimiru-pregen.in',
  output: 'makimiru-pregen',
  configuration: pregen_conf,
)

if get_option('pregen')
  install_data(
    makimiru_pregen_bin,
    install_mode: 'rwxr-xr-x',
    install_dir: bindir,
  )
endif
