# Project dependency and workflow audit

Verified against official stable releases on 2026-10-22 UTC. This document
covers repository-managed tooling only, not the developer's host packages.

## Update policy

New upstream releases are adopted only after a **seven-day quarantine**, so a
compromised or quickly retracted release has time to be pulled before it reaches
this repository. Dependabot applies the same rule (`cooldown: default-days: 7` in
`.github/dependabot.yml`). That is why some pins below trail the newest upstream
tag on the audit date.

## GitHub Actions

All external action references use immutable commit SHAs matching these releases.
Annotated tags are resolved to the commit they point at, and `zizmor` checks that
each version comment matches its SHA.

- [checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1):
  `3d3c42e5aac5ba805825da76410c181273ba90b1`. Every checkout sets
  `persist-credentials: false`.
- [labeler v7.0.0](https://github.com/actions/labeler/releases/tag/v7.0.0):
  `bf12e9b00b37c5c0ca2b87b79b2daf7891dbda13`.
- [attest-build-provenance v4.2.2](https://github.com/actions/attest-build-provenance/releases/tag/v4.2.2):
  `4d101475d8b20a2381f78447822ac1eab6504dd8`. Signs SLSA provenance for the
  release `.zip` and `.tar.gz`.
- [scorecard-action v2.5.0](https://github.com/ossf/scorecard-action/releases/tag/v2.5.0):
  `fa7117db83c52d787ae5a89f350999701505d78e` (resolved annotated tag).
- [codeql-action/upload-sarif v4.38.3](https://github.com/github/codeql-action/releases/tag/v4.38.3):
  `24c54180a607b1449ed407dd24f251e4e9147c8d` (resolved annotated tag). Newer
  v4.39.x releases were still inside the quarantine window.
- `softprops/action-gh-release` was removed: the runner's own `gh release create
  --verify-tag` publishes the release, so no third-party action holds
  `contents: write`.

## Downloaded CI tools

Each binary is downloaded from its official GitHub release and checked against a
pinned SHA-256 before it runs.

- [actionlint 1.7.12](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)
  and [ShellCheck 0.11.0](https://github.com/koalaman/shellcheck/releases/tag/v0.11.0)
  are current.
- [Crowdin CLI 5.3.0](https://github.com/crowdin/crowdin-cli/releases/tag/5.3.0):
  native `crowdin-linux-x64`, SHA-256
  `d3f8e74471b98d47c0964e85c992a04eb411d06138c4239118a4c94d29e3e9e4`. 5.4.0 and
  5.5.0 were inside the quarantine window. Remote checks remain conditional on
  repository secrets; identity files have private permissions.
- [gitleaks 8.30.1](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1):
  `gitleaks_8.30.1_linux_x64.tar.gz`, SHA-256
  `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`.
- [TruffleHog 3.99.2](https://github.com/trufflesecurity/trufflehog/releases/tag/v3.99.2):
  `trufflehog_3.99.2_linux_amd64.tar.gz`, SHA-256
  `3c7b0d1dc4278294269bfdd7594bca8bb28c78da0a4a06ad202ded37b48deca4`.
- [zizmor 1.30.1](https://github.com/zizmorcore/zizmor/releases/tag/v1.30.1):
  `zizmor-x86_64-unknown-linux-gnu.tar.gz`, SHA-256
  `e65324f4430c2717591937edcec90ccbefaf14c174f8ec9415e03ca875b46e1a`.

The native UI smoke checks out
[DankMaterialShell v1.6.3](https://github.com/AvengeMedia/DankMaterialShell/releases/tag/v1.6.3)
(`4a87e8227daf0840b3376fd5e7f891f5900165a6`) with submodules. DMS 2.0.0 was
published on 2026-10-20; moving to it is a separate compatibility change, not a
version bump.

`tests/test-workflow-dependencies.sh` enforces immutable external action refs,
artifact checksums, the Crowdin native launcher, the secret/workflow scans, scoped
reusable-workflow secrets, non-persisted checkout credentials and release
provenance. This offline test cannot detect future releases. Dependabot covers
the action pins; the downloaded binaries above still need a manual release,
checksum and compatibility review.

## Runtime and gate boundaries

The plugin is QML/bash and has no npm/Python/Rust application manifest or lockfile,
so GitHub Actions is the only package ecosystem Dependabot can track.
Runtime tools come from the installation environment. Ubuntu CI packages follow
the distribution channel; Quickshell smoke follows the Arch rolling channel and
installs `jq`, which the widget requires before it enables provider refreshes.
The Qt5 syntax-only gate is not equivalent to Qt6 semantic validation with DMS
imports. Neither a floating runner image nor a successful older remote run proves
an unpushed change compatible; run the documented local gates and fresh remote CI
before releasing.
