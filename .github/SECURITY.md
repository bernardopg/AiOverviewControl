# Security Policy

## Supported Versions

Security fixes are applied to the latest release and the `main` branch.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| `main` | Yes |
| Older releases | No |

## Reporting a Vulnerability

Please do not report security vulnerabilities in public issues, discussions, or pull requests.

Use GitHub's **private vulnerability reporting** for this repository (Security tab → "Report a vulnerability") as the primary channel. If private reporting is unavailable for some reason, contact the maintainer directly on GitHub ([@bernardopg](https://github.com/bernardopg)) asking to coordinate privately — do not include exploit details, tokens, logs with secrets, or proof-of-concept payloads in any public communication.

Useful details for a private report:

- Affected version or commit.
- Affected file, provider, or helper script.
- Clear reproduction steps.
- Impact assessment and any known workaround.

Valid reports are acknowledged within 7 days and coordinated through a private security advisory when appropriate.

## Response Process

1. **Acknowledge** the report within 7 days and confirm whether it is in scope.
2. **Assess** severity (CVSS) and affected versions in a private GitHub
   security advisory, inviting the reporter as a collaborator.
3. **Fix** in a private fork of the advisory. A fix for a medium or higher
   severity issue ships in a release within 60 days of the report; critical
   issues ship as soon as a fix is verified.
4. **Release** a new patch version, with the advisory linked from
   `CHANGELOG.md` and the release notes, and request a CVE through GitHub when
   the issue warrants one.
5. **Disclose** by publishing the advisory once the fixed release is available,
   or after 90 days if no fix is possible, with mitigations.

## Credit

Reporters are credited by name or handle in the published advisory, the
`CHANGELOG.md` entry and the release notes, unless they ask to stay anonymous.

## Verifying a Release

Every release since 1.22.0 publishes a `.zip`, a `.tar.gz`, a `.sha256` checksum
file and a signed [SLSA build provenance](https://slsa.dev/) attestation for both
archives, created by the tag's Release workflow on GitHub-hosted runners. The
signed Sigstore bundle is also attached as `.intoto.jsonl`, so the archives can be
verified without querying GitHub's attestation API.

```bash
VERSION=1.22.0
gh release download "v$VERSION" --repo bernardopg/AiOverviewControl --dir aioc && cd aioc
sha256sum -c "AiOverviewControl-v$VERSION.sha256"
gh attestation verify "AiOverviewControl-v$VERSION.zip" --repo bernardopg/AiOverviewControl
gh attestation verify "AiOverviewControl-v$VERSION.tar.gz" --repo bernardopg/AiOverviewControl
# Same check against the attached bundle instead of the attestation API:
gh attestation verify "AiOverviewControl-v$VERSION.zip" --repo bernardopg/AiOverviewControl \
  --bundle "AiOverviewControl-v$VERSION.intoto.jsonl"
```

A passing `gh attestation verify` proves the archive was built by this
repository's Release workflow from the tagged commit, not uploaded by hand.

Release tags from 2.0.2 on are also signed with the maintainer's OpenPGP key,
published in [`.github/release-signing-keys.asc`](release-signing-keys.asc), and
the Release workflow refuses to publish a tag that does not verify against it:

```bash
gpg --import .github/release-signing-keys.asc
git verify-tag "v$VERSION"
```

## Repository Safeguards

- **Secret scanning**: GitHub secret scanning with push protection, plus the
  **Secret scan** check on every PR, push to `main` and weekly: gitleaks over the
  full history (pattern based, redacted output) and TruffleHog reporting only
  credentials that their issuer still accepts. The optional pre-push hook
  (`git config core.hooksPath .githooks`) runs gitleaks on outgoing commits when
  it is installed.
- **Workflow hardening**: the **Workflow security audit** check runs
  [zizmor](https://docs.zizmor.sh/) and fails on medium or higher findings
  (template injection, persisted credentials, over-broad secrets or permissions,
  impostor or mismatched action pins). Workflows default to `contents: read`,
  pin every action to a commit SHA, never persist checkout credentials and pass
  reusable workflows only the secrets they read.
- **Dynamic analysis**: the **Fuzz provider responses** check feeds arbitrary
  HTTP statuses and bodies to every API-key adapter with
  [atheris](https://github.com/google/atheris) (2 minutes per PR and push, 15
  minutes weekly) and fails when the adapter contract breaks or a credential
  appears in the output. The same harness runs under
  [ClusterFuzzLite](https://google.github.io/clusterfuzzlite/) on each pull
  request and in a weekly batch.
- **Static analysis**: CodeQL code scanning, and the weekly
  [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/bernardopg/AiOverviewControl)
  for supply-chain practices.
- **Dependencies**: Dependabot security updates and weekly action updates. New
  upstream releases, including the checksum-pinned CI binaries, are adopted only
  after a seven-day quarantine (see [docs/update-audit.md](../docs/update-audit.md)).
- **Protected delivery**: `main` accepts changes only through PRs with all
  required checks green, and published `v*` tags cannot be moved or deleted
  ([docs/repository-rules.md](../docs/repository-rules.md)).
- **Runtime data**: provider credentials are read from each tool's own config
  and sent only to that provider's API. They are never stored in plugin
  settings, caches, logs, notifications or test fixtures.
