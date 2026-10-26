# Security requirements and assurance case

This document states what users can and cannot expect from AiOverviewControl
in terms of security, and argues why the implementation meets those
expectations. To report a vulnerability, follow
[SECURITY.md](../.github/SECURITY.md).

## Security requirements

### What you can expect

1. **Credentials stay with their provider.** Adapters read API keys and OAuth
   tokens from each tool's own configuration, environment variables or keyring
   (for example `~/.codex/auth.json`, `gh auth token`, `KIMI_CODING_API_KEY`).
   A credential is sent only to the API of the provider it belongs to. The
   plugin never copies credentials into its settings, caches, logs,
   notifications, history exports or test fixtures.
2. **Read-only access, with one confirmed exception.** The plugin reads quota,
   billing and usage data. It never changes provider settings, buys credits or
   writes into a tool's own configuration directory. The one write is redeeming
   a Claude or Codex **limit reset** the account already holds: it runs only
   after the user confirms it in the dashboard, sends one request per
   confirmation with an idempotency id, and is never retried or triggered by a
   poll (`providers/reset-provider-limits`).
3. **Encrypted network traffic.** Every remote request uses HTTPS with
   certificate verification left on (curl's default; no adapter disables it).
   The only plain HTTP endpoint is a local Ollama server on `localhost`.
4. **No hidden destinations.** Besides each selected provider's API, the
   plugin contacts three third parties, each with an opt-out:
   - the LiteLLM price table on `raw.githubusercontent.com`, to price local
     Hermes rows (`AIOC_NO_LITELLM=1`);
   - Google DNS-over-HTTPS (`dns.google`), only as a fallback when the system
     resolver cannot resolve the Copilot API (`AIOC_NO_DOH_FALLBACK=1`);
   - `api.frankfurter.dev` exchange rates, when a non-USD display currency is
     selected (`AIOC_NO_FX=1`).
   No usage data, credential or identifier is sent to any of them.
5. **Local data stays local.** Caches, usage history and notification state
   live under `${XDG_CACHE_HOME:-~/.cache}/AiOverviewControl/` in your home
   directory. They hold usage numbers, never credentials. History retention is
   bounded (`AIOC_HISTORY_MAX`).
6. **Untrusted input is validated.** Provider responses, local databases and
   transcript files are treated as untrusted and parsed with `jq` or bounded
   readers; malformed data yields an error card, not a crash or a command.
   Only plain provider ids (`[A-Za-z0-9_.-]+`) reach the IPC `focus` command.
7. **Verifiable releases.** Release tags are signed by the maintainer and the
   Release workflow publishes only a tag that verifies against the keys on
   `main`. Each release ships SHA-256 checksums and signed
   SLSA build provenance created by the tag's Release workflow (see
   [Verifying a Release](../.github/SECURITY.md#verifying-a-release)).

### What you cannot expect

- **Protection from your own user account.** The plugin runs as your user,
  like the tools it reads. Any process running as the same user can read the
  same credential files and caches. Several adapters still pass the
  `Authorization` header to `curl` as a command-line argument, which other
  local users can see in the process list on systems that do not mount `/proc`
  with `hidepid`. Moving every header to `curl --config` on a pipe is on the
  [roadmap](roadmap.md).
- **Provider-side guarantees.** Quota and billing numbers are whatever each
  provider reports. Some adapters rely on endpoints that the provider uses for
  its own clients but does not formally document; they can change without
  notice.
- **Protection against a compromised DankMaterialShell, Quickshell, `curl`,
  `jq` or provider CLI.** Those are trusted dependencies.
- **Confidentiality of what the bar displays.** Quota, plan and cost values
  are shown on screen and in desktop notifications.

## Assurance case

### Threat model

| Asset | Threat | Main controls |
| --- | --- | --- |
| Provider credentials | Leak to a third party, a log or a public issue | Credentials read on demand and sent only to their provider; secret scanning (GitHub push protection, gitleaks, TruffleHog) on every PR; offline tests with fake fixtures |
| User's machine | Command injection from a provider response, a setting or a notification click | Responses parsed as data with `jq`; QML runs helpers with argument arrays; provider ids allow-listed before IPC; shellcheck at warning level |
| Local caches and history | Tampering or disclosure through unsafe temporary files | `mktemp` for every temporary file, atomic rename on write, `umask 077` and `chmod 700` for notification state, caches under the user's XDG directory |
| Release archives | Tampered download or build, or a release pushed with a stolen token | Release built only by the tag's workflow on GitHub-hosted runners from a maintainer-signed tag; SHA-256 checksums; Sigstore-signed SLSA provenance; immutable `v*` tags |
| CI pipeline | Malicious action, template injection, credential theft | Actions pinned to commit SHAs; downloaded tools verified by checksum; workflows default to `contents: read` and never persist checkout credentials; zizmor audit on every PR |

### Trust boundaries

1. **Provider APIs and local tool files → adapters** (`providers/`): all data
   crossing here is untrusted and is validated before it is normalized into the
   adapter JSON contract described in [architecture.md](architecture.md).
2. **Adapters → QML widget**: the widget accepts only the normalized JSON
   contract and renders values as text; it does not evaluate provider data.
3. **Notifications → IPC**: a notification click can only call
   `focus <provider>` with an allow-listed id.
4. **Contributors → `main`**: every change passes the required checks in
   [repository-rules.md](repository-rules.md) and a DCO sign-off.

### Secure design principles applied

- **Least privilege**: read-only provider access, except a user-confirmed
  limit-reset redemption; workflows with minimal token
  permissions; no daemon, no elevated privileges.
- **Fail-safe defaults**: an unknown cost is `null`, never `0`; a provider
  error shows an error card; optional third-party calls can be disabled.
- **Economy of mechanism**: adapters are small `bash` + `jq` scripts behind one
  dispatcher and one JSON contract.
- **Complete mediation**: every provider goes through the same dispatcher and
  normalization path.
- **Open design**: all code, tests and CI are public; security does not rely
  on secrecy.
- **Separation of privilege and duties in delivery**: protected `main`,
  immutable release tags and provenance created by CI rather than by hand.

### Common weaknesses countered

| Weakness | How it is countered |
| --- | --- |
| CWE-78 OS command injection | Provider data never reaches a shell command; the single `eval` (Codex lock file descriptor) expands only constants; QML uses argument arrays; shellcheck enforced in CI |
| CWE-20 Improper input validation | `jq` parsing with type checks; bounded readers for transcripts and SQLite; allow-listed provider ids |
| CWE-200 / CWE-532 Information exposure through logs | Credentials never logged or cached; redacted secret scans; tests use fake credentials |
| CWE-377 Insecure temporary file | `mktemp`, atomic rename, cleanup traps, owner-only state directory |
| CWE-295 Improper certificate validation | `curl` certificate verification is never disabled |
| CWE-829 Untrusted functionality (supply chain) | SHA-pinned actions, checksum-verified CI tools, Dependabot, seven-day update quarantine ([update-audit.md](update-audit.md)) |
| CWE-94 Code injection in CI | zizmor fails PRs on template injection and over-broad permissions |

### Evidence

- Static analysis on every PR and push to `main`: CodeQL (actions,
  JavaScript/TypeScript, Python), shellcheck, qmllint, actionlint, zizmor.
- Secret scanning: GitHub push protection, gitleaks and TruffleHog over the full
  history ([security.yml](../.github/workflows/security.yml)).
- Fixture-backed tests for every provider adapter, the dispatcher, caches,
  notifications and the full widget under headless sway, with 80%+ statement
  coverage of the shell code enforced in CI
  ([ci.yml](../.github/workflows/ci.yml)).
- Weekly [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/bernardopg/AiOverviewControl)
  and the [OpenSSF Best Practices](https://www.bestpractices.dev/projects/15913)
  self-assessment.
- Dynamic analysis: atheris fuzzes every API-key adapter with arbitrary HTTP
  statuses and bodies on each PR, push to `main` and weekly
  ([fuzz_provider_responses.py](../tests/fuzz/fuzz_provider_responses.py)),
  directly and under ClusterFuzzLite ([.clusterfuzzlite/](../.clusterfuzzlite/)).
- Signed release tags and signed release provenance, verifiable with
  `git verify-tag` and `gh attestation verify`.

### Known gaps

- Fuzzing covers the API-key adapters; adapters that read local CLIs,
  databases or OAuth files are covered by fixture tests only.
- Some adapters pass credentials on the `curl` command line (see above).
- Only the notification state and exchange-rate cache are created owner-only;
  the other cache directories follow the user's `umask`.
- The project has a single maintainer; see
  [GOVERNANCE.md](../GOVERNANCE.md#continuity-and-bus-factor).

These gaps are tracked in the [roadmap](roadmap.md).
