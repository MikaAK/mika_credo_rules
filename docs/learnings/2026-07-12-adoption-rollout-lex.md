# Learnings — adoption rollout #2: learn_elixir_umbrella (lane lex-credo)

Second real-world adopter of mika_credo_rules, after [cheddar_flow_ex_umbrella PR #1097](2026-07-12-credo-rules-no-mocking.md)'s sibling rollout.

- Repo: `LearnElixirDev/learn_elixir_umbrella`, PR **#278**, branch `add-mika-credo-rules` (pushed, CI green, **not merged**)
- Worktree: `/Users/mika/GitHub/lex-credo-wt` (left in place)
- Commits (fixes first, config-enable LAST — see below):
  - `4661574` fix: use is_nil over direct nil comparison
  - `d6fd1fc` fix: inspect interpolated Logger values
  - `d1d2f99` test: refute over assert-not, rename Mock
  - `53118ef` chore: add mika_credo_rules checks

Outcome: baseline repo was 100% credo-green → the 14 new checks surfaced **383 issues**. **8 of 14 adopted** (4 already at zero, 4 green after 47 mechanical fixes), 6 deferred.

## Headline: per-check pain is repo-dependent — do NOT generalize adoptability from one repo

Side-by-side with cheddarflow (1312 issues, only 3/14 adoptable):

| Check | cheddarflow | learn_elixir | why the swing |
|---|---|---|---|
| LoggerModulePrefixAndInspect | **562 / 71f** (worst) | **11 / 3f** (fixed) | LEX already used the `#{__MODULE__}: ` prefix convention |
| NoNilComparison | 131 / 26f | 34 / 10f (fixed) | LEX AGENTS.md already mandates `is_nil` |
| NoSingleLetterVariables | 221 / 65f | 256 / 76f | equally hopeless in both |
| TodosNeedTickets | 15 | **0** | — |
| NoReimplementedHelper | 2 (FP) | **0** | — |

The single strongest predictor of adoption rate: **whether the repo already documents these conventions** (LEX's `AGENTS.md` literally lists `===`, `is_nil`, `refute`, no-`Mix.env`, `handle_continue`). A check that is a bloodbath in one repo can be a 3-file cleanup in the next. Profile before promising anything.

Confirmed two-for-two across both adopters: **ErrorMessageRequired and NoBlanketRescue are never day-one checks** — both are behavioral, not mechanical, in both repos. Document them as such.

## PACKAGE BUG — NoMockingLibraries flags a local `defmodule Mock`

The one NoMockingLibraries hit in LEX was a **false positive**, and the repo uses *no* mocking library at all:

```elixir
# apps/learn_elixir_rpc/test/learn_elixir_rpc_test.exs:4
defmodule LearnElixirRPCTest do
  defmodule Mock do                       # ← flagged
    def handle_call(:simple_return), do: "hello world"
  end
  # ... referenced as __MODULE__.Mock
```

This is a *different failure mode* from cheddarflow's (there, mox/mock were legitimately in use → omit the check). Here the check fires on a plain nested module that happens to be named `Mock`.

Root cause, precisely: `build_context/2` resolves an **alias** table via `AstHelpers.resolve_aliases/2`, so `alias MyApp.{Mock}` correctly shadows the banned name (that shadowing work is documented in the no-mocking lane learnings). But a **locally-defined** module gets no such treatment — `defmodule Mock do` emits `{:__aliases__, _, [:Mock]}`, which exact-matches banned `[:Mock]`, and nothing removes it from the banned set.

The moduledoc actively over-promises:

> "Banned modules are matched on their exact segments — `MyApp.MockingBird` and `MyApp.Mock` are project modules, not mocking libraries, and are never flagged."

True for the *qualified* spelling. **False** for a bare single-segment `defmodule Mock` / nested module referenced by its bare name — exactly the shape a legacy test helper takes.

**Suggested fix:** treat `defmodule <Name>` as shadowing, same as `alias` does — prune/deregister the defined name from the banned set for that file (and skip the `__aliases__` node that is the *name argument* of a `defmodule`, so the definition site itself never reports). Until then the moduledoc claim should be narrowed.

**What I did instead of disabling the check:** renamed the helper `Mock` → `TestHandler` (`d1d2f99`). Defensible here because it was 1 site, and the module genuinely is not a mock — it's a plain RPC call target. Kept a valuable check enabled. This only scales when the FP count is tiny; don't rename your way out of 50 hits.

## Gotcha — codecov/patch goes red on *reformatted* lines

`LoggerModulePrefixAndInspect` fixes **modify existing lines**. Codecov counts modified lines as new patch lines requiring coverage. Those Logger statements were already untested → patch coverage **21% vs a 60% target** → `codecov/patch` FAILURE, on a PR that introduces zero new logic.

Worse, second-order: wrapping `billing.ex:38` in `inspect/1` pushed it to 135 chars, over Credo's `MaxLineLength: 120`, forcing a multi-line `Logger.info(...)` — which **added a physical line** (`Lines +1, Misses +1`, project coverage −0.01%). A pure lint fix produced a measurable coverage *regression*.

Judgment call I made and stand by: **did not chase it.** It was non-required (nothing on that repo is a required check; PR is `MERGEABLE`, `UNSTABLE` only from this), and the two "fixes" available were both bad — write tests for pre-existing untested log lines (scope creep into an unrelated app), or back out correct `inspect/1` fixes to game a metric (defeats the check's entire purpose: `inspect/1` exists to stop `#{tuple}` crashing on missing `String.Chars`). Reported it for the reviewer to accept or retarget.

**Future adopters: expect this on any repo with a codecov patch gate.** Flag it in the PR body up front rather than letting a reviewer discover a red X.

## Gotcha — `git worktree add` + gitignored required config

`mix deps.get` hard-failed instantly in the fresh worktree:

```
** (File.Error) could not read file ".../config/config.secret.exs": no such file or directory
    (elixir) lib/config.ex:301: Config.__import__!/1
```

`config/config.exs` does `import_config "config.secret.exs"`; the file is gitignored (`**/config/*.secret.exs`) so the worktree doesn't get it. Nothing — not deps, not compile, not credo — runs until you copy it from the main checkout. It stays gitignored, so it never risks being committed (verified with `git ls-files | grep secret`).

Generalize: **before assuming a worktree is usable, check for gitignored-but-required config.** `grep -rn import_config config/` is the 5-second test. This will bite every worktree-based lane on this repo.

## Gotcha — NoProcessSleepInTests can't see "sleep IS the fixture"

`learn_elixir_rpc_test.exs:8` — `def handle_call(:sleep), do: Process.sleep(200)` — is a helper whose *entire job* is to block, so the suite can assert an RPC timeout at `timeout: 100`. The check is file-scoped (any `Process.sleep` in a test file), so it cannot distinguish "sleep as bad synchronization" from "sleep as the thing under test." Legitimate reason to defer the check; would benefit from a param or an allowance for sleeps inside helper modules rather than test bodies.

## Patterns that worked

**Triage on distinct-file count, not issue count.** `mix credo --strict --format json` piped into a small counter, grouping by check, emitting *both* issue count and **distinct files touched**. The file count is the adoption signal:

- NoSingleLetterVariables — 256 issues but **76 files** → hopeless, defer
- NoNilComparison — 34 issues but only **10 files** → tractable, fix

Raw issue count alone would have mis-ranked these. (Also: JSON format sidesteps the wall of dep-compilation noise the first `mix credo` run emits.)

**Read the check's source before fixing anything it reports.** Reading `logger_module_prefix_and_inspect.ex` revealed `interpolation_violations/3` emits **one violation per message if ANY segment is bare** — so you must wrap *every* interpolation on that line, not just the one you notice. It also confirmed `#{__MODULE__}` is an allowed interpolation. Guessing would have cost a fix→recheck→fix loop across 11 sites.

**Triage axis = "semantics-preserving?" not "how many files?".** `=== nil → is_nil`, `assert not → refute`, `#{x} → #{inspect(x)}` are equivalence-preserving → safe inside a "turn on the linter" PR. ErrorMessage shape changes, rescue narrowing, and app-env relocation change *behavior* → they belong in separate, tested PRs. This is cheddarflow takeaway (4), independently reconfirmed.

**Commit ordering: fixes first, config-enable commit LAST.** Every commit is green in isolation, and the commit that switches the checks on is precisely the one where they already pass. Bisect-safe, and reviewable as "here's the cleanup, here's the gate."

**Establish the baseline is green first.** Because LEX was credo-clean before, all 383 issues were unambiguously attributable to the new checks — zero argument about pre-existing debt.

## Anti-patterns avoided

- **Did not** write tests for pre-existing untested Logger lines just to turn `codecov/patch` green (scope creep into apps unrelated to the task).
- **Did not** revert correct `inspect/1` fixes to satisfy a non-blocking coverage metric.
- **Did not** attempt the NoSingleLetterVariables (76 files) or NoMixEnvAtRuntime (36 files) refactors — several `Mix.env()` hits are legitimate compile-time gates in `router.ex`/`endpoint.ex` and would need real thought, not a rename.
- **Did not** run `mix format` (repo + global rule), despite the formatting-adjacent nature of the work.
- **Did not** scatter `# credo:disable-for-this-file` comments to force green. Config-level omission with a `# not yet adopted: N / M files` comment is greppable, reviewable in one place, and doesn't rot in the source tree. Deferred checks are commented-out entries in `.credo.exs`, each with its reason.
- **Did not** mechanically convert `Process.sleep` → `assert_receive` — at least one sleep was load-bearing (above), and blind conversion is a flakiness generator.

## Recommended playbook for adopter #3

1. `git worktree add` → immediately check for gitignored required config (`grep -rn import_config config/`).
2. Confirm the repo's credo baseline is green *before* adding anything.
3. Pre-flight the conditional checks against actual deps: `error_message` (ErrorMessageRequired), SharedUtils (NoReimplementedHelper), mox/hammox/mock/mimic/patch/meck (NoMockingLibraries).
4. Add dep + enable **all** checks, run `mix credo --strict --format json`, group by check with **issue count AND distinct-file count**.
5. Split by *semantics-preserving vs behavioral*, then by file count. Fix the first bucket; defer the second with `# not yet adopted:` + reason.
6. Read the source of any check before fixing its findings.
7. Re-check line lengths after `inspect/1` wrapping (MaxLineLength collision).
8. Commit fixes first, config last. Gate on `mix credo --strict` = 0 and `mix compile --warnings-as-errors`.
9. Warn the reviewer about `codecov/patch` in the PR body if the repo has a coverage gate.

## Package TODOs this rollout surfaced

1. **NoMockingLibraries**: don't flag locally-defined `defmodule <BannedName>`; treat a `defmodule` as shadowing exactly as `alias` already is. Narrow the moduledoc claim until fixed. (Two adopters, two distinct FP/omission modes — this check needs the most work.)
2. **NoProcessSleepInTests**: escape hatch for intentional timing fixtures (param, or exempt helper modules vs test bodies).
3. **LoggerModulePrefixAndInspect**: doc-note that fixes lengthen lines and can breach `MaxLineLength`, and that they trip patch-coverage gates.
4. **Ship an incremental-adoption recipe** (this playbook + the JSON triage one-liner). Both adopters independently needed one; cheddarflow's takeaway (1) called for it and it's still the biggest gap between "package is done" and "package is adoptable."
