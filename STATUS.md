# Status

## Current Goal
Diagnose the CI failure and switch CI to use mise for env setup, validated against the github-actions skill.

## Steps & Progress
- [x] Reproduce CI steps locally — all 3 (format/check/test) pass locally
- [x] **Root cause found: missing rebar3 in CI.** `esqlite` 0.9.0 (transitive dep via `sqlight`) is `build_tools = ["rebar3"]` — a native C NIF requiring rebar3 to compile. CI used `erlef/setup-beam@v1` with no `rebar3-version`.
- [x] **Fix 1 — rewrite CI to use mise** (`jdx/mise-action`), which reads mise.toml and provides gleam + erlang + rebar3 together
- [x] **Fix 2 — pin versions in mise.toml**: `gleam = "1.16.0"`, `erlang = "28.3.1"`, `rebar = "3.27.0"`
- [x] Validate: full CI-equivalent passes → 82 tests, 0 failures
- [x] **Review against github-actions skill** — found 4 issues, all fixed
- [x] actionlint validation passes clean (exit 0)

## Unknowns
- (none)

## Discovered Issues
- **CI had no rebar3** → esqlite (rebar3/C NIF) couldn't compile → `gleam check` failed.
- **`mise.toml` used `latest` for all tools** — non-reproducible. Pinned exact proven-good versions.

### github-actions skill review — issues found and fixed
1. **`actions/checkout@v4` was stale** → bumped to latest `v7.0.0` and pinned to SHA `9c091bb...` with version comment. (v4 → v7 is 3 majors behind.)
2. **`jdx1/mise-action@v2` referenced a 404 repo** → the action moved to `jdx/mise-action` (jdx1 → jdx). Fixed to `jdx/mise-action@e6a8b397...` # v4.2.0 (pinned to SHA). This would have failed immediately in CI — the repo doesn't exist at the old path.
3. **Missing `persist-credentials: false`** on checkout → added per skill requirement (no later step needs to push).
4. **Missing concurrency group** → added `concurrency` with `cancel-in-progress: true` so new commits cancel in-progress runs on the same branch.
- Removed unnecessary `experimental: true` input from mise-action (confirmed via action.yml it's still a valid input, but not needed here).
- actionlint v1.7.7 validates clean (go 1.25 requirement bypassed by using binary release).
