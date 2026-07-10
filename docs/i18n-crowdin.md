# Internationalization and Crowdin

AiOverviewControl is localized with runtime JSON bundles loaded by `AiOverviewControlI18n.qml`.

## Runtime files

- `i18n/en.json` — source language and fallback bundle.
- `i18n/pt_BR.json` — Portuguese (Brazil).
- `i18n/zh_CN.json` — Chinese Simplified.
- `i18n/es_ES.json` — Spanish.
- `i18n/de_DE.json` — German.
- `AiOverviewControlI18n.qml` — loads the selected bundle and falls back to English per key.
- `qmldir` — registers the i18n singleton for QML.

The UI language is stored in the plugin settings key `languageOverride`:

- `auto` follows `Qt.locale().name`.
- `en_US` forces English.
- `pt_BR` forces Portuguese (Brazil).
- `zh_CN` forces Chinese Simplified.
- `es_ES` forces Spanish.
- `de_DE` forces German.

## Crowdin project setup

Project URL: https://pt.crowdin.com/project/aioverviewcontrol

Required Crowdin language setup:

- Source language: English (`en`).
- Target languages:
  - Portuguese, Brazil (`pt-BR`).
  - Chinese Simplified (`zh-CN`).
  - Spanish (`es-ES`).
  - German (`de-DE`).

Do not add English as a target language; English is the source file.

## Crowdin CLI

The repository config is `.github/crowdin.yml`.

Validate config:

```bash
crowdin config lint --config .github/crowdin.yml
crowdin config sources --config .github/crowdin.yml
```

Upload source strings:

```bash
crowdin upload sources --config .github/crowdin.yml
```

Upload local translations after adding the target languages in Crowdin:

```bash
crowdin upload translations --language pt-BR --config .github/crowdin.yml
crowdin upload translations --language zh-CN --config .github/crowdin.yml
crowdin upload translations --language es-ES --config .github/crowdin.yml
crowdin upload translations --language de --config .github/crowdin.yml
```

Download translations:

```bash
crowdin download --config .github/crowdin.yml
```

If Crowdin downloads an unexpected locale file, fix the project languages before committing it. The shipped locale files are `en.json`, `pt_BR.json`, `zh_CN.json`, `es_ES.json`, and `de_DE.json`.

## GitHub integration

Recommended Crowdin GitHub integration settings:

- Source files: `/i18n/en.json`.
- Translation files: `/i18n/%locale_with_underscore%.json`.
- Translation PR branch: `l10n_main`.
- Commit translation updates to Pull Requests, not directly to `main`.
- Enable "Skip untranslated strings" only if you want missing keys to fall back to English locally. The plugin is safe either way because `AiOverviewControlI18n.qml` falls back per key.

CI validates:

- `plugin.json` JSON syntax.
- Every `i18n/*.json` file for JSON syntax.
- Translation key parity against `i18n/en.json`.
- `.github/crowdin.yml` syntax.
- QML files when `qmllint` is available.
