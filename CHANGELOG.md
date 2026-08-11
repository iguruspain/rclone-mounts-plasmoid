# Changelog

## [1.1.0] - 2026-08-11
### Added
- Internationalization support for KDE Plasma
- Spanish translation (es) for UI strings and metadata
- Translation workflow with gettext: `translate/template.pot`, `translate/es.po`, `translate/build.sh`, `translate/merge.sh`
- Localized metadata: `Name[es]` and `Description[es]` in `metadata.json`
- All user-visible strings wrapped with `i18n()` in QML files

### Changed
- `metadata.json` updated with localized fields

### How to translate
1. Run `translate/merge.sh` to update `template.pot` from QML sources
2. Copy `template.pot` to `translate/<lang>.po` and translate `msgstr`
3. Run `translate/build.sh` to compile `.mo` into `contents/locale/<lang>/LC_MESSAGES/`
4. Add `Name[<lang>]` and `Description[<lang>]` to `metadata.json`

### Testing
- Verify translation with: `LANGUAGE="es:es" LANG="es_ES.UTF-8" plasmoidviewer --applet org.kde.plasma.rclone-mounts`
- Test without installing: `LANGUAGE="es:es" LANG="es_ES.UTF-8" plasmoidviewer --applet /home/iguruspain/VSCode/rclone-mounts-plasmoid`
- Verify .mo content: `msgunfmt contents/locale/es/LC_MESSAGES/plasma_applet_org.kde.plasma.rclone-mounts.mo | head -n 50`
- Check metadata: `jq '.KPlugin.Name[es], .KPlugin.Description[es]' metadata.json`
