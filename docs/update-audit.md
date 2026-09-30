# Project dependency and workflow audit

Verified against official stable releases on 2026-09-30 UTC. This document
covers repository-managed tooling only, not the developer's host packages.

## GitHub Actions

All external action references use immutable commit SHAs matching these releases:

- [checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1):
  `3d3c42e5aac5ba805825da76410c181273ba90b1`. The QML smoke job's old `@v4`
  reference was replaced to match the other jobs.
- [labeler v7.0.0](https://github.com/actions/labeler/releases/tag/v7.0.0):
  `bf12e9b00b37c5c0ca2b87b79b2daf7891dbda13`.
- [action-gh-release v3.0.3](https://github.com/softprops/action-gh-release/releases/tag/v3.0.3):
  `efb35369e0ad2afab669f228072c1b0d510eae64` (resolved annotated tag).

## Downloaded CI tools

- [actionlint 1.7.12](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)
  and [ShellCheck 0.11.0](https://github.com/koalaman/shellcheck/releases/tag/v0.11.0)
  are current; pinned checksums match their official Linux artifacts.
- [Crowdin CLI 5.3.0](https://github.com/crowdin/crowdin-cli/releases/tag/5.3.0)
  replaces 4.15.0. Version 5 uses native `crowdin-linux-x64`, not a Java ZIP/JAR.
  SHA-256: `d3f8e74471b98d47c0964e85c992a04eb411d06138c4239118a4c94d29e3e9e4`.
  The verified executable passed the version check and offline configuration lint.
  Remote checks remain conditional on repository secrets. Identity files have
  private permissions and safe JSON encoding (valid YAML).

`tests/test-workflow-dependencies.sh` enforces immutable external action refs,
artifact checksums and the Crowdin native-launcher contract. This offline test
cannot detect future releases. Dependabot checks actions weekly; binary version
updates still require upstream release/checksum review and compatibility testing.

## Runtime and gate boundaries

The plugin is QML/bash and has no npm/Python/Rust application manifest or lockfile.
Runtime tools come from the installation environment. Ubuntu CI packages follow
the distribution channel; Quickshell smoke follows the Arch rolling channel.
The Qt5 syntax-only gate is not equivalent to Qt6 semantic validation with DMS
imports. Neither a floating runner image nor a successful older remote run proves
an unpushed change compatible; run the documented local gates and fresh remote CI
before releasing.
