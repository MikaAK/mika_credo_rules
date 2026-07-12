# Shared Abstractions Plan — MikaCredoRules

**Date:** 2026-07-12
**Author:** architect-abstractions
**Status:** LANDED 2026-07-12 (same day, post-merge). Deviations from plan, with rationale:
- `resolve_aliases/2` gained a third adopter (`StrictEquality` — its local add-only fold
  replaced; multi-segment base makes the shared REMOVE half a no-op there, tests pin it).
- `NoProcessSleepInTests` adopted `module_paths/1` inside `expand_matcher/1` (its
  hand-rolled dual-spelling expansion was the same logic).
- **Step 4 NOT shipped:** the seven existing `traverse` heads were not converted —
  head-guard pattern matching over precomputed `module_paths/1` attributes is house style,
  the conversion had zero behavioral gain, and restructuring seven reviewed traversals
  risked exactly the bug class this plan kills. `remote_call/1` + `remote_call?/3` were
  built with full tests, then **held out of the public API at adversarial review**: zero
  adopters (the plan's own three-adopter gate), and `remote_call?/3`'s contract was
  alias-blind — freezing it at publish would hand the next check author the exact alias
  bug this plan exists to kill. The implementation lives in git history (commit
  `1ea1255`); resurrect it, alias-aware, when the first real adopter appears. The
  duplication that shipped bugs — module identity, alias resolution, path matching — is
  gone regardless.
- Param rename done: `ErrorMessageRequired`'s `excluded_files` → `excluded_paths`.
**Scope:** Extract duplicated AST/source-filtering logic from the 14 checks (13 new lanes + the canonical `NoApplicationEnvOutsideConfig`) into shared helpers.

---

## Why now

Thirteen checks were built in parallel worktrees with no cross-lane coordination — by design. That produced clean, independent lanes and one predictable cost: the same four patterns were hand-rolled up to seven times each.

This is not a style complaint. **The duplication has already shipped a bug.**

`StrictEquality` hand-rolled its Ecto-DSL exemption by matching the *function name* against a wildcard module:

```elixir
defp traverse({{:., _, [_, function]}, _, args} = ast, acc, ignored_functions)
```

`:join` is in the Ecto ignore list. `Enum.join/2` is therefore in the ignore list by accident, and every loose comparison inside an `Enum.join(...)` argument is silently exempted:

```elixir
Enum.join(names, if(x == y, do: ",", else: ";"))   # `x == y` NOT reported
```

The canonical check already solved this correctly — it matches `{:__aliases__, _, module}` against a known module path instead of wildcarding. `StrictEquality` couldn't reuse that because it wasn't extractable.

**Then the fix for that bug caused a second bug.** Replacing the wildcard with a literal path match (`module in [[:Ecto, :Query], [Elixir, :Ecto, :Query]]`) does not resolve aliases — so under `alias Ecto.Query`, the AST module is `[:Query]`, matches nothing, and legitimate Ecto code gets flagged:

```elixir
alias Ecto.Query
Query.where(query, [u], u.age == ^age)   # FALSE POSITIVE — `==` is the only operator Ecto accepts
```

A false positive on un-fixable code is strictly worse than the false negative it replaced. The canonical check *also* already solved this — it folds an alias table over the base module paths — and `NoMockingLibraries` independently built a superset of that same fold, with multi-alias support.

So: **one check, two production bugs, both from hand-rolling module identity that two other checks in this same package had already gotten right.** That is the entire ROI argument for this plan.

---

## Evidence — measured across all 14 checks

| Pattern | Checks using it | Files |
|---|---|---|
| **Remote-call matcher** `{{:., _, [{:__aliases__, _, mod}, fun]}, meta, args}` | **7 / 14** | canonical, strict_equality, no_mix_env, logger, no_process_sleep, no_blanket_rescue, no_mocking |
| **Filename-scoping guard** (`String.ends_with?` / `contains?` over a param list) | **6 / 14** | canonical, no_mix_env, error_message, no_process_sleep, no_reimplemented, refute_over_assert_not |
| **Dual-spelling module matcher** (`[:Mod]` **and** `[Elixir, :Mod]`) | **5 / 14** | canonical, strict_equality, no_mix_env, logger, gen_server |
| **Alias-resolution table** (`collect_aliases` / `apply_alias`) | **2 / 14** | canonical, no_mocking |
| `{nil, acc}` subtree prune | 4 / 14 | strict_equality, no_single_letter, todos_need_tickets, no_mocking |
| Collector-map → `issue_for/2` → `format_issue/2` | 14 / 14 | all |

Two helper pairs are **byte-identical** across lanes that never saw each other's code — `refute_over_assert_not.ex` and `no_process_sleep_in_tests.ex`:

```elixir
defp test_files(params), do: Params.get(params, :test_files, __MODULE__)

defp test_file?(filename, test_files) do
  Enum.any?(test_files, &String.ends_with?(filename, &1))
end
```

The canonical check has the same body under `config_files` / `config_module?`. Independent convergence on an identical implementation is the strongest possible signal for extraction.

---

## Proposed modules

Two modules, not one. Filename scoping does not touch the AST and should not live in a module named `AstHelpers`; keeping them separate keeps each one testable in isolation and stops `AstHelpers` becoming a grab-bag.

### `MikaCredoRules.SourceFilter`

Pure string predicates over `source_file.filename`. No AST, no Credo types.

```elixir
@doc "True when `filename` ends with any of `suffixes`."
@spec matches_suffix?(String.t(), [String.t()]) :: boolean()
def matches_suffix?(filename, suffixes)

@doc """
True when `filename` matches any of `fragments` at a PATH BOUNDARY.

A fragment matches when the path starts with it, ends with it, or contains it
immediately after a `/`. Naive `String.contains?/2` is WRONG here and has already
shipped a bug: `"lib/latest/helpers.ex"` contains the substring `"test/"` (inside
`"la-test/"`), so a naive exclusion on `"test/"` silently disables the check on a
real lib file. Same class: `"web/"` matches `webhooks/`, `"core/"` matches
`scorecard/`.

Take the implementation from `ErrorMessageRequired` — it is the only one of the
three hand-rolled copies that got this right.
"""
@spec matches_fragment?(String.t(), [String.t()]) :: boolean()
def matches_fragment?(filename, fragments)

@doc "True when `filename` is an Elixir script (`.exs`) — mix.exs, config, tests."
@spec script_file?(String.t()) :: boolean()
def script_file?(filename)
```

### Param naming — RELEASE GATE (ruled by team-lead, 2026-07-12)

The six scoping checks shipped four param names, two semantics, and two matchers.
These are **public API** — consumers write them into `.credo.exs`.

| Check | Param as shipped | Semantics | Matcher as shipped |
|---|---|---|---|
| `NoApplicationEnvOutsideConfig` | `config_files` | exempt | `ends_with?` |
| `NoProcessSleepInTests`, `RefuteOverAssertNot` | `test_files` | include-only | `ends_with?` |
| `ErrorMessageRequired` | `excluded_files` | exclude | boundary-aware ✓ |
| `NoMixEnvAtRuntime`, `NoReimplementedHelper` | `excluded_paths` | exclude | naive `contains?` ✗ (fixed in-lane) |

The two checks sharing the *name* `excluded_paths` were the two with the *wrong*
matcher, while the one with the odd name had the right logic. Nothing in the naming
told a consumer which matching rule they were getting.

**Ruling:** the package is unreleased (0.1.0, not on hex), so renames are free until
publish. Unification happens **with this extraction**, not by churning lanes
mid-verdict.

- **Exclude side** unifies on `excluded_paths` + the boundary-aware matcher.
- **Include side** keeps its domain names (`config_files`, `test_files`) — the
  include/exclude split is a real semantic difference, not an accident.
- **This migration + rename MUST land before any hex publish.** After publish these
  names are frozen and every fix becomes a breaking change. This is the pre-1.0
  window; there is not a second one.

### `MikaCredoRules.AstHelpers`

AST matching. Every function is total — returns `nil`/`false` rather than raising on shapes it doesn't recognise.

```elixir
@typedoc "An alias path as it appears in AST: `[:Ecto, :Query]` or `[Elixir, :Mix]`."
@type module_path :: [atom()]

@doc """
Every AST spelling of `module`.

    module_paths(Mix)        #=> [[:Mix], [Elixir, :Mix]]
    module_paths(Ecto.Query) #=> [[:Ecto, :Query], [Elixir, :Ecto, :Query]]

This is the fix for the class of bug that produced the `Enum.join` false-negative
in StrictEquality: never wildcard the module position, and never hand-roll the
`Elixir.`-prefixed variant.
"""
@spec module_paths(module()) :: [module_path()]
def module_paths(module)

@doc """
Destructures a remote call, or `nil` when `ast` is not one.

Handles Elixir calls (`Mix.env()`) and erlang calls (`:application.get_env/2`).

    remote_call(quote do: Mix.env())
    #=> {[:Mix], :env, []}

    remote_call(quote do: :application.get_env(:app, :key))
    #=> {:application, :get_env, [:app, :key]}
"""
@spec remote_call(Macro.t()) :: {module_path() | atom(), atom(), [Macro.t()]} | nil
def remote_call(ast)

@doc """
True when `ast` is a call to any of `modules` (in any spelling) naming any of `functions`.

    remote_call?(ast, [Mix], [:env, :target])
"""
@spec remote_call?(Macro.t(), [module()], [atom()]) :: boolean()
def remote_call?(ast, modules, functions)

@doc """
Every name in `source_file` that resolves to one of `modules`.

Folds `alias`, `alias ..., as:`, and multi-alias (`alias Foo.{Bar, Baz}`) over the
base spellings, and removes a base name that a project alias has shadowed.

Promote `NoMockingLibraries`' implementation — it is a strict superset of the
canonical check's (it already handles multi-alias and shadowing). Do not write a
third one.

## The two halves, and why both are load-bearing

Alias resolution has an ADD half and a REMOVE half, and which one a caller needs
depends on whether its base module path is single-segment:

  * **ADD** — `alias Ecto.Query` means the local name `[:Query]` now refers to
    `Ecto.Query`, so `[:Query]` joins the match set.
  * **REMOVE (shadowing)** — `alias MyApp.Application` means bare `[:Application]`
    no longer refers to Elixir's `Application`, so `[:Application]` must LEAVE the
    match set.

`NoApplicationEnvOutsideConfig` needs both: its base path `[:Application]` is
single-segment and therefore shadowable. `StrictEquality` needs only ADD: its base
path `[:Ecto, :Query]` is two-segment and cannot be shadowed by a one-segment
alias — which is why its add-only fold is correct, and why `alias MyApp.Query` is
still (correctly) flagged there.

A shared `resolve_aliases/2` MUST implement both halves, because it serves both
kinds of caller. An add-only implementation silently breaks the canonical check;
a remove-happy one would wrongly un-exempt `StrictEquality`. Test both.
"""
@spec resolve_aliases(Credo.SourceFile.t(), [module()]) :: [module_path()]
def resolve_aliases(source_file, modules)
```

---

## Adoption matrix

| Helper | Adopting checks |
|---|---|
| `SourceFilter.matches_suffix?/2` | `NoApplicationEnvOutsideConfig` (`config_files`), `NoProcessSleepInTests` (`test_files`), `RefuteOverAssertNot` (`test_files`), `ErrorMessageRequired` (`excluded_files`), `NoMixEnvAtRuntime` (`script_file?`) |
| `SourceFilter.matches_fragment?/2` | `NoReimplementedHelper` (`excluded_paths`), `NoMixEnvAtRuntime` (`excluded_paths`), `ErrorMessageRequired` (`excluded_files`) |
| `SourceFilter.script_file?/1` | `NoMixEnvAtRuntime` |
| `AstHelpers.module_paths/1` | `NoApplicationEnvOutsideConfig` (`Application`), `StrictEquality` (`Mix`, **`Ecto.Query` — the bug fix**), `NoMixEnvAtRuntime` (`Mix`, `Mix.Task`), `LoggerModulePrefixAndInspect` (`Logger`), `GenServerRequiresHandleContinue` (`GenServer`) |
| `AstHelpers.remote_call/1` + `remote_call?/3` | all 7 remote-call checks above |
| `AstHelpers.resolve_aliases/2` | `NoApplicationEnvOutsideConfig`, `NoMockingLibraries` |

---

## Migration order

Ordered by blast radius, ascending. **Every step keeps the adopting check's existing tests green with zero edits to those tests.** If a test has to change, the extraction changed behaviour — stop and review that separately.

### Step 1 — `SourceFilter` (zero risk)
No AST, no Credo coupling, 3 pure functions. Write it with its own unit tests, then adopt one check at a time. Six checks collapse ~5 lines each.

### Step 2 — `AstHelpers.module_paths/1` (fixes a live bug class)
Extract, then adopt in the 5 dual-spelling checks. **Do `StrictEquality` first** — its adoption is the `Enum.join` fix: replace the wildcard-module clause with `module in AstHelpers.module_paths(Ecto.Query)`. Land the regression test (`Enum.join(names, if(x == y, ...))` → flagged) in the same commit.

### Step 3 — `AstHelpers.resolve_aliases/2` (promote, don't rewrite)
Lift `NoMockingLibraries`' implementation verbatim into `AstHelpers` — it already handles multi-alias and shadowing, which the canonical's does not. Then have the canonical check adopt it. This is a *capability upgrade* for the canonical check, so it may legitimately need new tests (alias-shadowing cases it previously missed). That is the one place in this plan where new tests are expected.

### Step 4 — `AstHelpers.remote_call/1` (largest blast radius, do last)
Seven adopters. One check per commit, full suite green between each. Do not batch.

---

## Explicit non-goals

Naming what *not* to extract matters as much as what to extract — three tempting moves that would make the package worse:

1. **Do not extract `issue_for/2` / `format_issue/2`.** All 14 checks share the shape, but the message text *is* the check's product, and `format_issue/2` is injected by `use Credo.Check`. Factoring it out would fight the framework for no gain.

2. **Do not build a `use MikaCredoRules.Check` macro.** This is the obvious next step and it is a trap. `param_defaults` and `explanations` are each check's public API — they render into Credo's docs and into `.credo.exs` for consumers. Hiding them behind a project macro makes every check harder to read and harder for a consumer to configure. A framework on top of a framework.

3. **Do not extract `{nil, acc}` into a function.** It is a return value, not logic — `prune(acc)` would be strictly less clear than `{nil, acc}`. Document it as a house idiom (in `AstHelpers`' `@moduledoc`) so future checks reach for it: *returning `nil` as the AST from a `Credo.Code.prewalk/2` traversal stops the walk descending into that node's subtree.* Four checks discovered this independently; it deserves to be written down, not wrapped.

---

## Risks

- **`AstHelpers` becomes a dumping ground.** Mitigation: a function may only be added once **three** checks need it. Two is a coincidence; three is a pattern. `resolve_aliases/2` enters at two adopters only because it is being *promoted* from an existing superset implementation, not newly written.
- **Silent behaviour drift during adoption.** Mitigation: the zero-test-edit rule above. A green suite after extraction, with the test files untouched, is the proof that the extraction was behaviour-preserving.
- **Extraction churn while lanes are still being fixed.** As of writing, `StrictEquality` (alias false-positive) and `NoSingleLetterVariables` (receive-`after` false-positive) have open defect reports; `Logger` and `GenServer` are cleared. **This plan must not start until all lanes land**, or the extraction will be rebasing onto moving code.

- **The extraction is itself a behaviour change if done carelessly.** `StrictEquality`'s two bugs came from getting module identity subtly wrong twice. `AstHelpers.module_paths/1` and `resolve_aliases/2` must ship with their own direct unit tests — covering bare (`[:Mix]`), fully-qualified (`[Elixir, :Mix]`), aliased (`alias Ecto.Query` → `[:Query]`), renamed (`as: Q`), multi-alias (`alias Ecto.{Query, Changeset}`), and shadowed (`alias MyApp.Application`) spellings — *before* any check adopts them. Adopting an under-tested helper into seven checks at once would industrialise the exact bug class this plan exists to kill.

---

## Sequencing

**Blocked on:** all 13 lanes merged to `main` with their defects fixed.

**Blocking:** the hex publish. Per the naming ruling above, the param-name
unification rides along with this extraction, and those names freeze the moment the
package is published. So this plan is not the optional cleanup it looks like — it is
the last chance to fix the public API for free.

The engineering value is in the *next* check written against this package: it should
find `module_paths/1`, `resolve_aliases/2`, and `matches_fragment?/2` already there,
rather than hand-rolling an eighth, third, and fourth copy. Every hand-rolled copy so
far has been a coin flip:

| Concept | Copies | Correct | Bugs shipped |
|---|---|---|---|
| module identity matching | 5 | — | `Enum.join` false-negative; `alias Ecto.Query` false-positive |
| alias resolution | 2 | 1 superset (`NoMockingLibraries`) | (the FP above) |
| path-fragment matching | 3 | 1 (`ErrorMessageRequired`) | naive `contains?` in 2 checks |

Three concepts, ten hand-rolled copies, four production bugs — every one of them a
lane re-deriving something a sibling lane in the same package had already gotten
right. That is the cost this extraction removes, and it is why the plan is a
correctness fix rather than a tidy-up.
