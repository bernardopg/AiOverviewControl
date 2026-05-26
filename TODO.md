# TODO

## Providers — Data & Auth

- [ ] Add per-provider source override (individual `source` per provider, not one global mode).
- [ ] MiniMax: verify `coding_plan` balance field — current endpoint returns `token_plan` but schema may vary by account tier.
- [ ] GLM: add `GLM_API_BASE` override support for international endpoint (`open.bigmodel.cn` vs `bigmodel.cn`).
- [ ] Cloudflare: expand analytics beyond `neurons_used/neurons_limit` using GraphQL Analytics Engine when `CLOUDFLARE_ANALYTICS_TOKEN` is available.
- [ ] Ollama: poll `/api/ps` for running-model status (available since Ollama 0.1.33); supplement `/api/tags` model list.
- [ ] NVIDIA: surface specific quota window info if NVIDIA adds a balance endpoint (monitor NIM changelog).
- [ ] Mistral: surface `is_default_key` flag and rate-limit headers when Mistral adds a quota endpoint.
- [ ] BytePlus/Ark: surface `remaining_tokens` per model when the API exposes per-model quotas.
- [ ] Qwen/DashScope: add `DASHSCOPE_WORKSPACE_ID` scoping so enterprise accounts can isolate workspace usage.
- [ ] Vertex AI: add `GOOGLE_CLOUD_PROJECT` env-based project scoping alongside `gcloud` authentication check.
- [ ] Copilot: add token-status hint in the card when neither `gh auth token` nor any `*_TOKEN` env var is set.
- [ ] OpenRouter: surface `usage.by_model` breakdown in the secondary/tertiary windows when available.

## Providers — New / Unimplemented

- [x] **Together AI** (`together`): `GET https://api.together.xyz/v1/credits` with `TOGETHER_API_KEY`.
- [x] **Groq** (`groq`): no public quota endpoint; show note-card directing to console.groq.com.
- [x] **Cohere** (`cohere`): `GET https://api.cohere.ai/v1/users` with `COHERE_API_KEY`; check `trial_credits`.
- [x] **Replicate** (`replicate`): `GET https://api.replicate.com/v1/account` with `REPLICATE_API_TOKEN`.
- [x] **Fireworks AI** (`fireworks`): `GET https://api.fireworks.ai/v1/account/billing` with `FIREWORKS_API_KEY`.
- [x] **AI21** (`ai21`): `GET https://api.ai21.com/studio/v1/usage` with `AI21_API_KEY`.

## Dashboard — UX

- [ ] Add compact/expanded density modes (toggle in settings or per-card).
- [x] Add stale-data indicator per card when provider has not refreshed within 2× the refresh interval.
- [ ] Add provider filter row (search/filter chip bar) when more than 8 providers are selected.
- [ ] Add screenshot assets for documentation and marketplace listing.
- [x] Surface `updatedAt` timestamp in card footer for providers that return it.

## Claude Analytics

- [x] Show today's token count separately from today's estimated cost in the summary row.
- [ ] Add cache-status and API-fallback messaging when `get-claude-usage` falls back to local JSONL only.
- [ ] Add optional EUR display when Frankfurter exchange-rate lookup succeeds.
- [ ] Expose per-project breakdown toggle (top 5 projects by cost today).

## Settings

- [ ] Add manual custom provider list text field in settings when DMS dropdowns support editable values.
- [ ] Add per-provider env-var hint row in settings (shows which env var is missing for API-key providers).

## Quality

- [x] Add `shellcheck` to CI workflow for all `get-*` scripts.
- [ ] Add lightweight integration tests for `get-claude-usage` (mock `~/.claude` fixtures).
- [ ] Add lightweight integration tests for `get-provider-usage` (mock API responses with `curl` shim).
- [ ] Pin GitHub Actions to SHA for supply-chain hardening (e.g. `actions/checkout@<sha>`).

## Packaging

- [ ] Add release checklist for DankMaterialShell plugin registry submission.
- [ ] Add plugin marketplace metadata when DMS plugin registry format is finalized.
- [ ] Add `assets/` directory with widget screenshots for README and marketplace.
