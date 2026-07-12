# Adoption rollout — cheddar_flow_ex_umbrella (first real adopter)

**Date:** 2026-07-12
**Repo:** `cheddar_flow_ex_umbrella` (~40-app Elixir umbrella)
**PR:** [#1097](https://github.com/Cheddar-Flow/cheddar_flow_ex_umbrella/pull/1097) — `add-mika-credo-rules`, **not merged** (left for team review)
**Base:** `c9fbc533` · **Commits:** `df0867c1` (refactor: seed sim init via handle_continue), `a46192f4` (chore: add mika_credo_rules credo checks)
**Worktree:** `/Users/mika/GitHub/cfx-credo-wt`

## Headline

The repo was **100% credo-green before the change**, and the 14 new checks surfaced **1312 strict issues**. Only **3 of 14** were adoptable green on day one. This is the central fact a future adopter must internalize: on a mature codebase these checks do not go green by fixing a few files — most encode conventions the codebase never followed.

## The single most important technique: baseline-stash verification

Do **not** assume the issues credo reports after adding the package are all new — and do not assume they're all pre-existing either. Prove it:

```bash
git stash push .credo.exs mix.exs mix.lock
mix credo            # ← old config = the true baseline
git stash pop
```

Baseline came back `found no issues`. That single command turned "1312 issues, who knows whose" into "1312 issues, 100% mine", which is what made the triage defensible. Without it I'd have been guessing about which failures I owned. Run this **before** touching a single violation.

## Per-check violation profile (useful prior for any legacy repo)

| Check | Issues / Files | Call |
|---|---|---|
| StrictEquality | 0 | **enabled** (cleanly replaced `Blitz.StrictComparison`) |
| RefuteOverAssertNot | 0 | **enabled** |
| GenServerRequiresHandleContinue | 1 / 1 | **enabled** after a 6-line fix |
| LoggerModulePrefixAndInspect | 562 / 71 | deferred |
| NoSingleLetterVariables | 221 / 65 | deferred |
| NoProcessSleepInTests | 211 / 29 | deferred |
| NoNilComparison | 131 / 26 | deferred |
| NoApplicationEnvOutsideConfig | 94 / 44 | deferred |
| NoMixEnvAtRuntime | 46 / 42 | deferred |
| ErrorMessageRequired | 11 | deferred (behavioral) |
| NoBlanketRescue | 10 | deferred (behavioral) |
| TodosNeedTickets | 15 | deferred (can't invent tickets) |
| NoReimplementedHelper | 2 | deferred (intentional divergence) |
| NoMockingLibraries | — | **omitted entirely** (mox+mock used in 31 files) |

Get exact per-check counts with `--only`, which is cleaner than parsing the aggregate output or `--format json`:

```bash
mix credo --strict --only MikaCredoRules.LoggerModulePrefixAndInspect
```

## Gotchas

**Issue count is the wrong triage axis; "is the fix mechanical or behavioral?" is the right one.** The brief's ">20 files → defer" rule handled the mass checks fine, but it under-served the small ones. `ErrorMessageRequired` (11) and `NoBlanketRescue` (10) are both *under* any file threshold, yet fixing them means changing error-tuple shapes across auth middleware, GraphQL resolvers and channels, and changing rescue semantics. Those are behavioral changes that belong in their own focused, test-backed PRs — never smuggled into a "add the linter" PR. Deferred both despite low counts. Conversely `GenServerRequiresHandleContinue` had 1 violation in a dev-only simulator and the fix was mechanical and idiomatic (CLAUDE.md mandates `handle_continue` for init work anyway), so it was worth doing to buy a third enabled check.

**Removing a replaced check can silently drop coverage.** The brief said to swap `Blitz.StrictComparison → StrictEquality`. I *also* removed `Blitz.TodosNeedTickets` on the "they'd double-report" logic — correct in principle. But once I decided to **defer** `MikaCredoRules.TodosNeedTickets` (15 TODOs with no ticket URLs, and I can't invent tickets), that removal would have left the repo with **no** TODO enforcement at all — a regression, from a check that was green. Restored the Blitz one. **Rule: only remove the check you're replacing if the replacement actually ships enabled.** Re-check this after triage, not before.

**`NoReimplementedHelper` false-fires on intentional divergence.** It flagged `random_string/0` in `redis_lock` and a test factory, pointing at `SharedUtils.String.generate_random/1`. But the local impls deliberately emit **hex** (lock tokens); the SharedUtils helper has different output semantics, and `redis_lock` doesn't even depend on shared_utils. "Fixing" would have changed lock-token format and added a dep. The check is a heuristic pointer, not a proof of duplication — always read the two implementations before believing it.

**Secrets: use the repo's own CI escape hatch, never copy the secret.** `config/dev.exs` does `if System.get_env("IS_CI") !== "true", do: import_config "dev.secret.exs"`. So every command runs as `IS_CI=true mix ...` and no gitignored credential file is needed in the worktree. My first instinct — `cp config/dev.secret.exs` from the main checkout — was correctly blocked, and it was the wrong instinct: it stages a credentials-shaped file inside a tree about to be pushed. Also: stage with **explicit paths**, never `git add -A`, in a worktree that has (or may acquire) ignored secret files.

**Pre-existing red CI will be waiting for you — prove it's pre-existing, don't fix it.** Three checks failed and none were mine:
- `Security/Scan` — Paraxial `MatchError` in `Scan.make_hex` parsing `"Advisories:"` out of `hex.audit`. Fails identically on the parent commit; main had been red for days.
- `Coveralls (3/3)` — `apps/shared_feed_utils/test/shared_feed_utils/start_servers_task_test.exs` ("owns_feed? routes via SharedUtils.Cluster when distributed?"). The same test file fails on main's 3/3 shard.
- `codecov/project` — coverage threshold, purely downstream of that failing shard.

The way to prove it: `gh run list --branch main` (all recent runs red), then `gh run view <main-run-id>` to see the *same job* failing at the *same step*, and `gh api repos/.../check-runs/<id>/annotations` to get the actual failing test name when `--log-failed` returns empty (which it did for the coverage jobs). Don't reason from "my diff looks innocent" — get the parent-commit evidence.

**Shard numbers don't line up run to run.** Main failed Coveralls 2/3 *and* 3/3; my PR failed only 3/3 and passed 2/3. Partition boundaries shift, so match on **failing test identity**, not shard index.

## Patterns that worked

- **Deferral as config, not deletion.** Every unadopted check is present in `.credo.exs` as `{Check, false}` with a `# not yet adopted: N issues / M files` comment. The next person gets a ready-made, quantified backlog and can flip one on per cleanup PR. Far better than omitting them and losing the intel.
- **Two commits, split by kind.** The behavioral refactor (`df0867c1`) is separate from the tooling change (`a46192f4`), so a reviewer can see the one line of production-shaped change on its own.
- **Verify the gate CI actually runs.** CI runs plain `mix credo` (quality.yml), but `.credo.exs` sets `strict: true`, so strict is what gates. I held the local gate at `mix credo --strict` (exit 0) plus `mix compile --warnings-as-errors` — strictly stronger than CI.

## Anti-patterns avoided

- Hand-editing ~1300 violations across 70+ files to force a green board.
- Mass `excluded_paths` tuning to fake adoption — excluding 20–70 files per check isn't adoption, it's a check that does nothing while looking enabled.
- Chasing pre-existing red CI (Paraxial, Coveralls) and inflating the diff with unrelated fixes.
- Making behavioral error-handling changes inside a tooling PR.

## For the next adopter (and for the package itself)

1. Run the **baseline stash** first. Always.
2. Expect to enable a **minority** of checks on any mature repo. That's a successful adoption, not a failed one — the value is the ratchet plus the quantified backlog.
3. Triage on **mechanical vs behavioral**, then on file count.
4. `NoMockingLibraries` needs to be omittable without apology — mox/hammox are legitimate infrastructure in most real repos.
5. Package gap this exposed: there is **no incremental-rollout story**. Adopters need a documented "enable the green ones, defer the rest with counts" recipe (or a baseline/ratchet mode) — otherwise the first `mix credo` after install looks like a catastrophe and the package gets removed instead of adopted. Worth putting the table above in the README as an honest expectation-setter.

Relates to the release-gate note: this is the first adopter, which is the trigger condition for resurrecting the held-back `remote_call` helpers.
