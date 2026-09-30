# Repository branch rules and rulesets

The desired GitHub policies are versioned in
`.github/repository-rules/main.json` and `release-tags.json`. They are repository
rulesets, not workflows that silently grant themselves administrative access.
Applying or changing them requires repository admin permission; review both the
committed policy and the live GitHub policy after any administrative change.

## Main branch

`main: reviewed delivery and complete changelog` applies to `refs/heads/main`:

- Pull request required: no direct delivery to main, including administrator pushes.
- Force pushes and deletion forbidden; no bypass actors are configured.
- All review conversations must be resolved.
- The branch must be up to date and pass the nine named checks in the policy,
  including **Changelog integrity**. Checks are bound to the GitHub Actions app
  (integration ID 15368), not a same-named status posted by an arbitrary actor.
- Required approving-review count is **zero**: this repository permits a sole
  maintainer to merge their own release PR after gates pass. This is not a claim
  of independent human approval. Set it to one when another eligible reviewer is
  available; requiring self-approval would deadlock the release workflow.

These are the branch protection rules, enforced by a modern branch-target
ruleset. Do not duplicate them with an independently drifting legacy branch
protection policy. The policy deliberately permits merge commits so the source
commits and their CI evidence remain in the release's ancestry.

## Changelog contract

`scripts/check-changelog` is the common executable interface for PR CI, metadata,
packaging and release-body extraction. It rejects missing/duplicate version
sections, empty headings, comments, fenced snippets and placeholder-only notes.

- No version bump: add a substantive new bullet to **Unreleased**, compared with
  the PR base. Reordering/removing old bullets or modifying comments is not enough.
- Version bump: advance `plugin.json` beyond the base and create a unique,
  substantive matching version section. Leave Unreleased available for future PRs.
- Release publication: validate the tag against the manifest and emit only its
  section, with relative documentation links bound to that immutable tag.
- Archives: validate their own manifest/changelog, not uncommitted local text.

All PRs, including docs/tooling PRs, have the same notes contract. This avoids
path-based exceptions that would allow important release behavior to go undocumented.
GitHub rulesets themselves cannot understand Markdown: the mandatory check is
what makes the content rule enforceable. Required checks only protect the
workflow code actually running; administrators can still edit repository settings.

## Release tags

`release tags: immutable` applies to `refs/tags/v*`: updates/deletion are forbidden
without changing the policy. GitHub rejected a tag-name-pattern rule for this
repository, so semantic naming is enforced by the release gate rather than claimed
as a tag-creation restriction. Publication requires `vMAJOR.MINOR.PATCH` matching
the manifest. Tag creation alone does not prove CI: the release workflow separately
enforces tag/manifest agreement, main ancestry, full reusable CI and validated
release notes before publishing assets.

## Apply and audit

Use admin-authenticated GitHub tooling, preserving any unrelated rulesets. For a
new policy:

```bash
gh api --method POST repos/OWNER/REPO/rulesets --input .github/repository-rules/main.json
gh api --method POST repos/OWNER/REPO/rulesets --input .github/repository-rules/release-tags.json
gh api repos/OWNER/REPO/rulesets
# Read each returned ID and compare the enforcement, scope and complete rule set.
gh api repos/OWNER/REPO/rulesets/RULESET_ID
```

Do not use an admin bypass or disable checks to fix an empty changelog. Repair the
notes on the PR branch, rerun the check, then merge the verified head. For a
mistaken published version, make a new version/tag rather than rewriting the old one.
