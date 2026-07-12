# Adoption rollout: opgg_umbrella (2026-07-12)

First real-world adoption of `mika_credo_rules` into a large, already-green Elixir umbrella
(`opgginc/opgg_umbrella`, 12 apps, 724 files, 4432 mods/funs).

- **PR:** https://github.com/opgginc/opgg_umbrella/pull/11 (opened, CI green, not merged)
- **Branch:** `add-mika-credo-rules`, cut from `origin/main` @ `07d5856`
- **Worktree:** `/Users/mika/GitHub/opgg-credo-wt`
- **Commits:**
  - `a8a9283` chore: add mika_credo_rules checks (mix.exs, mix.lock, .credo.exs)
  - `bed6fc3` fix: use is_nil for nil comparisons
  - `43d7b91` fix: rename single-letter variables
  - `d3cb8e8` fix: prefix and inspect Logger messages

## Headline numbers

255 violations, **all 255 from our checks** — the repo's pre-existing Credo config
(Credo defaults + `blitz_credo_checks`) was already at zero. That is the number to
internalize: **a repo can be fully green on stock Credo and still light up 255 issues
on ours.** Adoption is never a no-op.

| Check | Issues | Files | Disposition |
|---|---|---|---|
| NoApplicationEnvOutsideConfig | 137 | 75 | **deferred** |
| NoSingleLetterVariables | 48 | 10 | fixed |
| NoNilComparison | 24 | 17 | fixed |
| NoProcessSleepInTests | 17 | 10 | **deferred** |
| NoMixEnvAtRuntime | 10 | 8 | **deferred** |
| GenServerRequiresHandleContinue | 10 | 10 | **deferred** |
| NoBlanketRescue | 6 | 5 | **deferred** |
| LoggerModulePrefixAndInspect | 3 | 3 | fixed |
| ErrorMessageRequired, StrictEquality, RefuteOverAssertNot, TodosNeedTickets, NoMockingLibraries, NoReimplementedHelper | 0 | — | enabled free |

**9 of 14 checks enabled. 5 deferred. 75 fixed, 180 deferred.**

## The adoption shape (generalize this)

The checks sort cleanly into three tiers, and a future adopter should triage into these
tiers *before* editing a single line:

1. **Free** (0 issues) — turn on, no work. Six of ours landed here.
2. **Mechanical** (rename/rewrite, behavior-identical) — fix directly.
   NoNilComparison, NoSingleLetterVariables, LoggerModulePrefixAndInspect.
3. **Architectural** (fixing it changes behavior or design) — defer with a
   `# not yet adopted:` comment + one-line rationale. Never refactor someone's
   architecture on an adoption PR.

The tier is a property of *the check*, not of the repo. Expect this same split elsewhere.

### Triage cheaply with JSON, not eyeballs

`mix credo --strict --format=json` → group by `check` → count issues *and distinct files*.
Distinct-file count is the real cost signal (137 issues across 75 files is a very different
animal from 48 across 10). Do this before reading any source.

```bash
mix credo --strict --format=json > credo.json
python3 -c "
import json,collections
d=json.load(open('credo.json'))
c=collections.Counter(i['check'] for i in d['issues'])
for k,v in c.most_common(): print(v, k)"
```

## Gotchas

### 1. NoApplicationEnvOutsideConfig is the adoption boss fight (137 issues / 75 files)

This single check was 54% of all violations and touched 60% of the source files. Reading
`Application.get_env` at the call site is *the* default Elixir habit; a mature codebase
will be saturated with it. Going green means introducing a config module and rerouting
every read through it — a genuine architectural refactor, and absolutely not something to
smuggle into a "add a linter" PR.

**Deferred it.** Expect to defer it in essentially every brownfield repo. It is realistically
a greenfield-only check, or a dedicated follow-up PR of its own.

Its only tuning knob is `config_files` (default `["config.ex"]`), which whitelists *which
files may read env* — it does not help you scope the check away from the other 75.

### 2. Check params are much narrower than you'd hope — read the source before promising a tune

The task brief assumed `excluded_paths` was broadly available. It is not. Actual params:

- `NoProcessSleepInTests` → `test_files`, `functions`. **No `excluded_paths`.** So you cannot
  exempt just the integration/timing tests; it is all-or-nothing per repo.
- `NoApplicationEnvOutsideConfig` → `config_files` only.
- `GenServerRequiresHandleContinue` → `allowed_modules`.
- `NoSingleLetterVariables` → `allowed_names`.
- `NoMixEnvAtRuntime` → `excluded_paths` (default `["mix/tasks/"]`) — one of the few that has it.

**Lesson:** "tune the check's params" is only a real option for some checks. Read
`lib/mika_credo_rules/<check>.ex` `param_defaults` before committing to a tuning plan.
Deferral (`{Check, false}` + comment) is the universal fallback.

### 3. NoMixEnvAtRuntime over-reports against its own name

All 10 hits were **compile-time** `Mix.env()` uses, which are legitimate:

```elixir
@env Mix.env()                                           # module attribute
if Mix.env() === :test do ... end                        # module-level, compile-time
use Cache, sandbox?: Mix.env() === :test                 # macro opt
@prod? Application.compile_env(:app, :env, Mix.env())    # compile_env default arg
```

The check flags every `Mix.env()` regardless of compile/runtime context. The repo's own rule
(and ours) is *never `Mix.env()` **at runtime***, and none of these violate that. Converting
them "properly" means plumbing an `:env` config key through every app — behavior risk for zero
correctness gain.

**Deferred.** Worth considering upstream: can the check distinguish module-attribute /
module-body / macro-arg position from a function body? If not, the name overpromises and it
will over-report on every mature repo.

### 4. NoBlanketRescue's hits were all *intentional* degrade-to-default

Every one of the 6 was a deliberate catch-all-and-fall-back, including one with a paragraph
comment explaining exactly why it swallows everything:

- health controller → `rescue _error -> 0`
- REST cache → `rescue _error -> %{}`
- pipeline retry ladder → `rescue error -> {:error, {:resolve_ids, error}}` (tags *any* failure
  so the connector's `retry_class/1` can absorb an RDS failover)

A health check that *must never crash* is a correct blanket rescue. Narrowing these to specific
exceptions would be a behavior regression. **Deferred.** Expect this check to be low-yield /
high-friction on any service with real degradation paths.

### 5. LoggerModulePrefixAndInspect: "bare value" is stricter than "bare variable"

`allowed_interpolations` defaults to `[:__MODULE__, :inspect]`, and the allow-check matches on
*function name*. So **any** interpolated call that isn't `inspect` is flagged:

```elixir
# all three of these are "bare"
"periods: #{length(periods)}"
"players: #{map_size(m)}"
"matches: #{match_count}"
```

Fix is to wrap even integer-valued calls: `#{inspect(length(periods))}`. It reads slightly
ugly for integers but it's what the check wants. Also note the check reports **one issue per
Logger call**, not per bad interpolation (it's an `Enum.any?`) — so you must fix *every* bare
interpolation on a line to clear a single reported issue. Don't fix one and assume you're done.

### 6. StrictEquality found 0 — and that made the StrictComparison swap safe

The brief had us drop `BlitzCredoChecks.StrictComparison` in favor of `MikaCredoRules.StrictEquality`.
The repo was already `===`-clean under the old check, and the new one also reported 0. That
concordance is the *evidence* the swap is behavior-neutral — worth explicitly checking and
stating rather than asserting. Same reasoning applied to disabling `Credo.Check.Design.TagTODO`
in favor of `TodosNeedTickets` (both would double-report).

## Single-letter renames at 48-violation scale

This was the largest mechanical batch and the one with real regression risk, because renaming a
binding means renaming **every usage in its scope** — miss one and you get a compile error (loud,
fine) or, worse, capture a different in-scope variable (silent, bad).

**What the check actually flags:** bindings only — in `=`, `<-`, `->` clause patterns, and function
heads. Not `&1` captures. Not `_`-prefixed vars (`_v` is length 2, so it survives). Typespec
subtrees are dropped, so `@spec take(bucket :: t, n :: pos_integer(), ...)` is *not* flagged even
though the `def take(..., n, ...)` below it is.

**What worked:**

- **Read the whole enclosing function before renaming.** Line-level edits are a trap here. Case in
  point, `SharedUtils.Enum.deep_transform/2` has a *shadowing* pair:

  ```elixir
  Enum.reduce(map, %{}, fn {k, v}, acc ->     # outer binding
    case transform_fn.({k, v}) do
      {k, v} -> Map.put(acc, k, deep_transform(v, transform_fn))   # NEW binding, shadows
      :delete -> acc
    end
  end)
  ```

  Two distinct `{k, v}` bindings, both flagged, and they mean different things. Renamed to
  `{key, value}` outer / `{new_key, new_value}` inner. A naive global `k → key` in that function
  would have compiled fine and been semantically wrong-ish/misleading.

- **Match names to the file's own existing conventions.** `SharedUtils.Enum` already had
  `concat_uniq_by(enum_a, enum_b, mapper)`, so `difference(a, b)` / `intersection(a, b)` became
  `(enum_a, enum_b)` — not an invented `first`/`second`. Grep the file for how it already names
  things before choosing.

- **Rename the `@spec` param name too** when you rename the `def` param (e.g. `bucket.ex`
  `n :: pos_integer()` → `token_count :: pos_integer()`) and **update the `@doc`** if it references
  the old name by name (`rate_budget.ex` `@doc "...deducts \`n\` tokens..."`). The check won't
  force this — typespecs are skipped — but leaving them stale is a docs regression.

- **Doctests are the safety net.** `shared_utils` renames were validated by 82 doctests + 24 tests,
  all passing. Renaming inside a heavily-doctested utility lib is much safer than it looks.

**Names used:** `k`/`v` → `key`/`value`; `a`/`b` → `enum_a`/`enum_b` (or `date_a`/`date_b` for a
comparator); `e` → `error`; `n` → `token_count`/`count`; `i` → `index`.

## The NoNilComparison batch: script it, but verify the transform

All 24 were the same shape (`assert X === nil`, plus one `val === nil` in a filter lambda), so a
scripted per-line regex transform → `assert is_nil(X)` was safe and fast. Two guardrails that
mattered:

- Drive the script from the **credo JSON line numbers**, not from a blind grep — you only touch
  lines the check actually flagged.
- Make the script **report unmatched lines** rather than silently skipping. It printed
  `changed=24, unmatched=0`, which is the proof the transform covered every flagged site. A script
  that silently no-ops on a line it doesn't understand is how you ship a half-fix and a red gate.

## Anti-patterns avoided

- **Did not refactor to satisfy a linter.** 180 of 255 issues were deferred. An adoption PR that
  rewrites 75 files' config access, restructures 10 GenServers' init, and rips synchronization out
  of timing tests is not an adoption PR — it's five risky PRs wearing a trenchcoat. Deferral with a
  documented reason is the correct, honest outcome.
- **Did not rip `Process.sleep` out of tests.** The sleeps in the rate-limiter/queue-depth tests
  aren't lazy waits — they *enforce concurrent-task ordering* (enqueue backfill, sleep, enqueue user,
  to prove priority beats insertion order; or let a waiter reach the GenServer before `GenServer.stop`).
  Replacing them requires synchronization hooks **in the code under test**, not just in the test.
  Ripping them out mechanically would have produced flakier tests than it fixed.
- **Did not run `mix format`.** Repo/global rule. Matched surrounding style by hand.
- **Did not assume a green local run means a green CI** — and conversely, did not assume a red CI
  means my fault (see below).

## The CI flake, and how to actually prove it isn't yours

First CI run: Credo/Dialyzer/both Compiles green, **Coverage/Coveralls red** — 4 failures in
`GenericGameWeb.RefreshParityTest`. The tempting moves are both wrong: (a) shrug "flaky, merge it",
or (b) start "fixing" unrelated tests. Do neither until you've *established* provenance.

The failures looked alarmingly plausible-as-mine: one was a **log-prefix mismatch**
(`Elixir.GenericGameService.Refresh:` vs expected `GenericGameWeb.Refresh.Real:`) — and I had just
been editing Logger prefixes. That is exactly the coincidence that panics an agent into breaking
unrelated code.

The chain of evidence that settled it:

1. **Did I touch the file?** `git log origin/main..HEAD -- '*refresh_parity*'` → empty. I never
   touched the test or the `Refresh` modules. My only `generic_game_web` change was an `is_nil` in
   an unrelated `schemas_test.exs`.
2. **Could I reach it indirectly?** My one piece of *shared* test infrastructure was
   `shared_utils/test/support/http_sandbox.ex`. Grepped: `RefreshParityTest` doesn't use HTTPSandbox
   at all. No path from my diff to that test.
3. **Is the code even different from what passed on main?**
   `git log 07d5856..origin/main -- '*efresh*'` → empty. My branch carried the **identical** Refresh
   code and test that passed on `main`'s run 12 minutes earlier. Same code, same test, opposite result
   ⇒ non-deterministic by definition.
4. **Re-run the failed job with zero code changes** (`gh run rerun <id> --failed`) → **passed.**

Step 4 is the one that converts "I believe it's flaky" into "it is flaky." Steps 1–3 are what earn
you the right to re-run instead of it being wishful thinking. Report all four, don't just say "flaky."

(Corroborating context: `main` itself had 2 red runs in its last 5, and recent main commits are
literally `fix(tests): harden ErrorSink rate-limit tests against minute-boundary races` and
`fix(tests): make pair-buffer pin actually failable`. The repo has a known flaky-async-test problem.
Our PR walked into it, it didn't create it.)

## Process notes for the next adopter

- **`mix deps.get` + first `mix credo` compiles the whole dep tree** — budget for it (long timeout or
  background + poll). Subsequent runs are ~3s.
- **Run credo under `MIX_ENV=test`** so `test/` files are in scope; several checks (NoNilComparison,
  NoProcessSleepInTests, RefuteOverAssertNot) live almost entirely in test code. Under `dev` you'd
  under-report and then get surprised in CI.
- **Commit hygiene:** config commit first, then one commit per fix-type. Intermediate commits are red
  (config lands before fixes) — that's fine, only HEAD must be green. One caveat: a file with *two*
  kinds of fix (here `enum.ex` had 1 nil fix + 15 renames) can't be cleanly split without `git add -p`,
  which isn't available non-interactively. Just keep the file whole in its dominant commit and move on;
  perfect commit purity isn't worth a fight with the tooling.
- **Final gate is two commands, both must be clean:** `mix credo --strict` (exit 0) and
  `mix compile --warnings-as-errors`. Then run the tests for the apps whose *lib* code you touched —
  not the full umbrella suite (CI covers that).
- **A skill-check hook may block an edit** whose hunk merely *contains* an `ErrorMessage` construction,
  even when your change is a pure variable rename that preserves it. Load the named skill, re-attempt.
  Also: when a batch of parallel Edits partially fails, **re-verify which one actually failed** — I
  re-applied against the wrong clause first because I assumed the error was positional. Grep for the
  leftover pattern instead of guessing.

## Suggested upstream follow-ups

1. `NoProcessSleepInTests` should grow an `excluded_paths` param. Without it, any repo with legitimate
   timing/integration tests must disable it wholesale — which is what happened here.
2. `NoMixEnvAtRuntime` should not flag compile-time positions (module attributes, module bodies, macro
   args), or should be renamed to reflect that it flags all uses. As-is it will be deferred by every
   brownfield adopter for reasons that aren't really violations.
3. Consider shipping a documented **"adoption profile"**: the free/mechanical/architectural tiering
   above, so an adopter can enable tiers 1–2 on day one and schedule tier 3 deliberately. The realistic
   day-one number for a mature repo is ~9/14 checks, and saying so up front sets honest expectations.
