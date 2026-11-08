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
- `translations/en.json`, `pt.json`, `zh.json`, `es.json`, `de.json` — the dash card title and options from `plugin.json`, which Dux Shell renders itself through `I18n.trFor()`. `en.json` maps each term to itself; it is the Crowdin source for these terms and changes nothing on screen.

The UI language is stored in the plugin settings key `languageOverride`:

- `auto` follows `Qt.locale().name`.
- `en_US` forces English.
- `pt_BR` forces Portuguese (Brazil).
- `zh_CN` forces Chinese Simplified.
- `es_ES` forces Spanish.
- `de_DE` forces German.

### Strings that come from the shell helpers

The adapters report errors in English: they are diagnostics, and a user who files an issue pastes the same text a maintainer reads. Readiness details shown in Settings (what a provider is missing, from `providers/get-provider-health`) are localized: the settings page looks up `health.detail.<slug>`, where the slug is the English detail lower-cased with every run of other characters turned into `_`, at most 60 characters. A detail that is only a variable name, such as `DEEPSEEK_API_KEY`, has no key and shows as is. `tests/test-i18n.sh` fails when the helper gains a prose detail without a key, so add the key to all five bundles in the same change.

## Crowdin project

Project URL: https://pt.crowdin.com/project/aioverviewcontrol

- Source language: English (`en`). Do not add English as a target language.
- Target languages: Portuguese, Brazil (`pt-BR`), Chinese Simplified (`zh-CN`), Spanish (`es-ES`) and German (`de`).

`.github/crowdin.yml` maps two sources:

| Source | Translations | Placeholder |
| --- | --- | --- |
| `/i18n/en.json` | `/i18n/%locale_with_underscore%.json` | `pt_BR`, `zh_CN`, `es_ES`, `de_DE` |
| `/translations/en.json` | `/translations/%two_letters_code%.json` | `pt`, `zh`, `es`, `de` |

## How the repository and Crowdin stay in step

Translations are reviewed in pull requests, so the repository is the source of truth for what ships, and Crowdin is where translators propose changes. The **Crowdin sync** workflow (`.github/workflows/crowdin.yml`) keeps both sides equal:

- On every push to `main` that touches `i18n/`, `translations/` or `.github/crowdin.yml`, it first downloads Crowdin's translations and compares them with the commit before the push (`scripts/crowdin-drift`). If they match, it uploads the sources and the repository's translations, approving them. If they do not, someone changed a translation in Crowdin that never reached the repository: the workflow uploads nothing, so that work is not overwritten, and fails with the list of differences.
- Every Monday it runs the same comparison against `main`, so a translation approved in Crowdin surfaces as a failed run.

To bring Crowdin's changes into the repository:

```bash
crowdin download --config .github/crowdin.yml --identity /tmp/crowdin-id.yml
git diff i18n translations       # review, then open a pull request
```

Then re-run the Crowdin sync workflow from the Actions tab.

## Crowdin CLI

The CLI reads the token from an identity file or `--token`; keep it off the command line:

```bash
umask 077
python3 -c 'import json, os; print(json.dumps({"api_token": os.environ["CROWDIN_PERSONAL_TOKEN"]}))' > /tmp/crowdin-id.yml
crowdin config lint --config .github/crowdin.yml --identity /tmp/crowdin-id.yml
crowdin status --config .github/crowdin.yml --identity /tmp/crowdin-id.yml
```

Upload sources and translations by hand (the workflow does this on merge):

```bash
crowdin upload sources --config .github/crowdin.yml --identity /tmp/crowdin-id.yml
crowdin upload translations --auto-approve-imported --import-eq-suggestions \
  --config .github/crowdin.yml --identity /tmp/crowdin-id.yml
```

Compare Crowdin with the working tree without touching it:

```bash
mkdir -p /tmp/export && cp -r .github i18n translations /tmp/export/
(cd /tmp/export && crowdin download --config .github/crowdin.yml --identity /tmp/crowdin-id.yml)
scripts/crowdin-drift /tmp/export
```

If Crowdin exports an unexpected locale file, fix the project languages before committing it.

## Checks

CI validates:

- `plugin.json` JSON syntax and semantic version format.
- Every `i18n/*.json` file for JSON syntax and exact key and placeholder parity with `i18n/en.json`, and every `t("key")` lookup in QML (`tests/test-i18n.sh`).
- Every provider note and every prose readiness detail has a key, and every `plugin.json` dash term is translated in each `translations/*.json` (`tests/test-i18n.sh`).
- `scripts/crowdin-drift` against fixture exports (`tests/test-crowdin-drift.sh`).
- `.github/crowdin.yml` with the checksum-verified Crowdin CLI as an offline hard gate; with `CROWDIN_API_TOKEN` it also confirms that Crowdin resolves every source and translation path.
- The QML files with `qmllint`.
