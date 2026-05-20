# Internationalization and Crowdin

AiOverviewControl is localized with runtime JSON bundles loaded by `AiOverviewControlI18n.qml`.

## Runtime files

- `i18n/en.json` — source language and fallback bundle.
- `i18n/pt_BR.json` — Portuguese (Brazil).
- `i18n/zh_CN.json` — Chinese Simplified.
- `AiOverviewControlI18n.qml` — loads the selected bundle and falls back to English per key.
- `qmldir` — registers the i18n singleton for QML.

The UI language is stored in the plugin settings key `languageOverride`:

- `auto` follows `Qt.locale().name`.
- `en_US` forces English.
- `pt_BR` forces Portuguese (Brazil).
- `zh_CN` forces Chinese Simplified.

## Crowdin project setup

Project URL: https://pt.crowdin.com/project/aioverviewcontrol

Required Crowdin language setup:

- Source language: English (`en`).
- Target languages:
  - Portuguese, Brazil (`pt-BR`).
  - Chinese Simplified (`zh-CN`).

Do not add English as a target language; English is the source file. Remove Spanish (`es-ES`) unless it is intentionally added later.

## Crowdin CLI

The repository config is `crowdin.yml`.

Validate config:

```bash
crowdin config lint
crowdin config sources
```

Upload source strings:

```bash
crowdin upload sources
```

Upload local translations after adding the target languages in Crowdin:

```bash
crowdin upload translations --language pt-BR
crowdin upload translations --language zh-CN
```

Download translations:

```bash
crowdin download
```

If Crowdin downloads `i18n/en_US.json` or `i18n/es_ES.json`, the Crowdin target languages are still wrong. Fix the project languages, delete those files, then download again.

## GitHub integration

Recommended Crowdin GitHub integration settings:

- Source files: `/i18n/en.json`.
- Translation files: `/i18n/%locale_with_underscore%.json`.
- Translation PR branch: `l10n_main`.
- Commit translation updates to Pull Requests, not directly to `main`.
- Enable "Skip untranslated strings" only if you want missing keys to fall back to English locally. The plugin is safe either way because `AiOverviewControlI18n.qml` falls back per key.

CI validates:

- `plugin.json` JSON syntax.
- `i18n/en.json`, `i18n/pt_BR.json`, `i18n/zh_CN.json` JSON syntax.
- Translation key parity against `i18n/en.json`.
- `crowdin.yml` syntax.
- QML files when `qmllint` is available.
