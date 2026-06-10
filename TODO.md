# TODO

## Providers — Data & Auth

- [x] Remove the global source mode; every provider now owns one explicit adapter path.
- [x] MiniMax: remove the undocumented quota call and report configured status until a public read-only endpoint exists.
- [x] GLM: remove the undocumented quota call and retain regional console/base metadata only.
- [ ] Cloudflare: add documented GraphQL Workers AI analytics when a stable dataset/query contract is available.
- [x] Ollama: poll `/api/ps` for running-model status and supplement `/api/tags`.
- [ ] NVIDIA: surface specific quota window info if NVIDIA adds a balance endpoint (monitor NIM changelog).
- [ ] Mistral: surface `is_default_key` flag and rate-limit headers when Mistral adds a quota endpoint.
- [ ] BytePlus/Ark: surface `remaining_tokens` per model when the API exposes per-model quotas.
- [x] Qwen/DashScope: add optional `DASHSCOPE_WORKSPACE_ID` request scoping.
- [x] Vertex AI: add `GOOGLE_CLOUD_PROJECT` env-based project labeling alongside `gcloud` authentication check.
- [x] Copilot: add prerequisite health and preserve the authenticated quota adapter used by the GitHub session.
- [ ] OpenRouter: surface `usage.by_model` breakdown in the secondary/tertiary windows when available.

## Providers — New / Unimplemented

- [x] **Together AI** (`together`): `GET https://api.together.xyz/v1/credits` with `TOGETHER_API_KEY`.
- [x] **Groq** (`groq`): no public quota endpoint; show note-card directing to console.groq.com.
- [x] **Cohere** (`cohere`): `GET https://api.cohere.ai/v1/users` with `COHERE_API_KEY`; check `trial_credits`.
- [x] **Replicate** (`replicate`): `GET https://api.replicate.com/v1/account` with `REPLICATE_API_TOKEN`.
- [x] **Fireworks AI** (`fireworks`): `GET https://api.fireworks.ai/v1/account/billing` with `FIREWORKS_API_KEY`.
- [x] **AI21** (`ai21`): `GET https://api.ai21.com/studio/v1/usage` with `AI21_API_KEY`.

## Dashboard — UX

- [x] Add compact/expanded density modes.
- [x] Add stale-data indicator per card when provider has not refreshed within 2× the refresh interval.
- [x] Add provider filter row when more than 8 providers are selected.
- [ ] Add screenshot assets for documentation and marketplace listing.
- [x] Surface `updatedAt` timestamp in card footer for providers that return it.

## Claude Analytics

- [x] Show today's token count separately from today's estimated cost in the summary row.
- [x] Add cache-status and local-only messaging for Claude subscription data.
- [x] Add optional EUR display when the Frankfurter exchange-rate lookup succeeds.
- [x] Expose a per-project breakdown toggle for the top 5 projects by estimated monthly cost.

## Settings

- [x] Add manual custom provider list text field in settings.
- [x] Add per-provider prerequisite health rows in settings.

## Quality

- [x] Add `shellcheck` to CI workflow for all `get-*` scripts.
- [x] Add lightweight integration tests for `get-claude-usage` (KEY=VALUE output validation).
- [x] Add lightweight integration tests for `get-provider-usage` (JSON array smoke test, stub delegation check).
- [x] Pin GitHub Actions to SHA for supply-chain hardening (`actions/checkout@<sha>`, `softprops/action-gh-release@<sha>`).

## Packaging

- [ ] Add release checklist for DankMaterialShell plugin registry submission.
- [ ] Add plugin marketplace metadata when DMS plugin registry format is finalized.
- [ ] Add `assets/` directory with widget screenshots for README and marketplace.
