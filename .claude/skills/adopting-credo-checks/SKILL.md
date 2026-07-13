---
name: adopting-credo-checks
description: Use when integrating mika_credo_rules (or any strict check package) into a consumer repo — baseline proof, free/mechanical/architectural triage, deferral discipline, and proving pre-existing CI failures aren't yours. Distilled from the four-repo rollout of 2026-07-12.
---

# Adopting Credo Checks

Rolling `mika_credo_rules` (or any strict check package) into a consumer repo. Distilled from
four adoptions on one day (cheddar_flow #1097, learn_elixir #278, un_dev #49, opgg #11 —
full detail in `docs/learnings/2026-07-12-adoption-rollout-*.md`).

**The central fact:** a repo can be 100% green on stock Credo + blitz and still light up
255–1312 issues on these checks. That is a successful adoption in progress, not a failure —
the deliverable is enabled-what-passes plus a quantified backlog, never a mass rewrite.

## Pre-flight (before touching a violation)

1. **Baseline-stash proof.** `git stash push .credo.exs mix.exs mix.lock && mix credo && git stash pop`.
   Old-config green = every issue is attributable to the new checks. Removes all argument.
2. **Read the file count.** `running N checks on 0 files` = the `included` globs don't match
   (umbrella roots have no `lib/`; paths resolve relative to CWD, not the config file). A repo's
   Credo CI can pass vacuously for years this way (un_dev did). Fix `included` first — and budget
   for inheriting pre-existing stock-check violations the moment the glob works.
3. **Mirror the dep where `:credo` already lives** (root vs per-app). `only: [:dev, :test],
   runtime: false` — that spelling is also what later exonerates you on unrelated CI failures.
4. **Worktree usability:** `grep -rn import_config config/` — a gitignored `*.secret.exs` hard-fails
   `mix deps.get`. Prefer the repo's own escape hatch (`IS_CI=true`) over copying secrets; if you
   must copy, verify with `git check-ignore` and stage explicit paths only, never `git add -A`.
5. **Conditional checks vs actual deps:** no `:error_message` → drop ErrorMessageRequired; mocking
   lib in use → drop NoMockingLibraries; no SharedUtils → drop NoReimplementedHelper.

## Triage

- Run under **`MIX_ENV=test`** (several checks live almost entirely in test files) with
  `--format=json`; group by check counting **issues AND distinct files**. Or per-check:
  `mix credo --strict --only MikaCredoRules.<Check>`.
- **Tier every check before editing anything.** The tier is a property of the check, not the repo:
  - **Free** (0 issues) — enable; locks in existing behaviour at zero cost. Typically 4–6 of 14.
  - **Mechanical** (semantics-preserving rewrite) — fix: NoNilComparison, RefuteOverAssertNot,
    LoggerModulePrefixAndInspect, NoSingleLetterVariables (when file count is sane), StrictEquality.
  - **Architectural/behavioral** — defer, always: NoApplicationEnvOutsideConfig (the boss fight —
    54% of opgg's total, 75 files; realistically greenfield-only), ErrorMessageRequired and
    NoBlanketRescue (behavioral two-for-two across adopters), GenServerRequiresHandleContinue,
    NoProcessSleepInTests (sleeps that enforce concurrent ordering, or ARE the fixture, can't be
    mechanically converted), NoMixEnvAtRuntime (flags compile-time module-body/attr positions).
- **Semantics-preserving beats file count as the axis.** ErrorMessageRequired at 11 issues is
  harder than NoNilComparison at 131: error-shape changes ripple into `result.error =~ ...` tests
  and type-consistency of free-form string fields. Low count ≠ easy.
- **A pre-issued "defer this check" order is conditioned on it being non-zero.** Run the counts
  before honoring it — one lane was told to defer SingleModulePerFile, it came back 0/0, and
  deferring a free guardrail would have been strictly worse than enabling it.
- **Prove a zero is the check being RIGHT, not just non-vacuous.** Beyond `running 1 check on
  N files`, grep for what the check hunts and read the hits: finding near-misses the check
  correctly DECLINED to flag (different-name `||` fallbacks, cast with a literal list) is
  stronger evidence than finding nothing. A planted violating probe that fires completes the
  proof.
- **Ask of every defensive-read check: does it flag where the bug SHOWS UP or where the bug
  IS?** NoAtomStringKeyFallback flags read sites, but dual-keyed maps are made at producer
  boundaries — when the two differ, defer with that reason, honestly stated ("too much churn"
  would be a lie).
- **Wave-N inverts wave-1's ratio.** Wave-1 style-convention checks: 3/14 adoptable on a green
  mature repo. Wave-2 narrow anti-pattern checks: 3–4/5 landed free everywhere. Checks authored
  AFTER a rollout target what healthy repos already do right — budget triage accordingly, and
  don't rank by how alarming the check sounds (the security check landed 0; the boring
  `@derive` check was the biggest backlog).
- Which tier a mechanical check lands in per-repo tracks whether the repo already **documents**
  the convention (AGENTS.md listing `is_nil`/`===` predicts a 3-file cleanup; its absence predicts
  a 70-file bloodbath). Profile before promising.

## Fix mechanics

- Script bulk fixes **off the credo JSON line numbers**, not blind sed; process line numbers
  descending when edits change line counts; make the script **print unmatched lines** — a silent
  skip is an invisible half-fix.
- **Checks interact:** `!== nil` → `refute is_nil(x)` (NOT `assert not is_nil(x)`, which trips
  RefuteOverAssertNot). Fix toward the idiom the whole suite wants.
- Logger fixes: the check emits **one issue per Logger call** — wrap every bare interpolation on
  the line or the issue survives. `inspect/1` wrapping lengthens lines → re-check MaxLineLength,
  and expect `codecov/patch` to go red on reformatted-but-untested lines (warn the reviewer in the
  PR body; don't write tests for old log lines or revert correct fixes to game the metric).
- Single-letter renames: read the **whole enclosing function** first (shadowed `{k, v}` pairs
  rename differently); match the file's existing names; rename `@spec`/`@doc` mentions too.
- **Read the check's source before fixing or promising a param tune** — params are narrower than
  you hope (NoProcessSleepInTests has NO excluded_paths; NoApplicationEnvOutsideConfig only has
  `config_files`). Deferral is the universal fallback.
- **Fix ALL sites or defer — never half.** A check with 1 remaining issue is exactly as deferred
  as one with 2; partial fixes are churn with zero adoption payoff. The question is "can I get
  this check to zero?", not "is this site fixable?".
- **NoIdentityRewrap removals: the catch-all clause is the mechanical safety discriminator.**
  `error -> error` present → the case asserts nothing, removal provably safe. Absent → the case
  asserts shape; removal widens accepted input. Also: a map "identity" isn't — `%{a: x}` as a
  PATTERN matches supersets but as a CONSTRUCTOR drops extra keys; trace the producer before
  removing.

## Deferral discipline

- Defer as `{Check, false}` + `# not yet adopted: N issues / M files` + one-line reason, in place
  in `.credo.exs`. Greppable, quantified backlog; never scatter `# credo:disable-for-this-file`.
- Never mass-tune `excluded_paths` to fake adoption — an enabled check that skips 70 files is
  worse than an honest `false`.
- **Only remove a check you're replacing if the replacement ships ENABLED.** Removing
  Blitz.TodosNeedTickets while deferring ours would have silently dropped all TODO enforcement.
  Re-check replacements after triage, not before.
- Swap evidence: old check green + new check 0 issues = the swap is behavior-neutral. State it.

## PR / CI

- Commits: fixes first, config-enable **last** — every commit green in isolation, bisect-safe.
  Split behavioral fixes from the tooling commit.
- Gates: `mix credo --strict` exit 0 + `mix compile --warnings-as-errors`; run tests only for apps
  whose lib code changed (CI covers the rest).
- **Pre-existing red CI — prove it, don't fix it.** The chain, weakest to decisive:
  (1) no path from your diff to the failure; (2) passes locally; (3) the base commit's own run
  fails at the identical crash site (`gh run list --branch main`); (4) `gh run rerun --failed`
  with zero changes passes. Match on failing-test identity, never shard index or failure count.
- Log access: `gh run view --log-failed` truncates/comes back empty for some jobs —
  `gh api repos/<o>/<r>/actions/jobs/<id>/logs` (grep -a) is reliable.
- **A PR can merge mid-adoption — and `gh pr checks <n>` keeps serving the OLD merged head's
  runs as if current** (two lanes nearly reported a stale green wall as their own). Always match
  CI results on head SHA: `git rev-parse HEAD` vs the run's `headSha` / the PR's `headRefOid`.
  If the PR merged under you: cherry-pick onto current main as a `-wave-N` branch, open a fresh
  PR (minimal diff), and leave the dead branch alone — remote branch deletion trips the
  permission classifier for agents and belongs to the user.
- **`gh pr checks` lies three more ways even without a merge:** (a) right after a push it serves
  the PREVIOUS head's finished runs and exits 0 while your SHA's runs are still queued — a stale
  green is worse than a red; (b) codecov/project can read FAIL then settle to PASS once all
  shard uploads land — `gh api repos/<o>/<r>/commits/<sha>/check-runs` gives the settled
  conclusion plus `output.title`; (c) a red "Coverage" job may contain ZERO test failures (dies
  on the coverage threshold, exit 2) — grep the log for `N tests, N failures` before treating it
  as a test break. And for flaky suites, match failing-test identity at MODULE granularity —
  individual case names shuffle between runs.
- `gh pr edit --body-file` can silently no-op (projectCards GraphQL deprecation) —
  `gh api -X PATCH repos/<o>/<r>/pulls/<n> -F body=@file` and **read the body back**.
- Repo CI gates (scope gates, body-format checks) override external instructions like "no
  headings" — CI wins, keep everything else light, report the deviation.
