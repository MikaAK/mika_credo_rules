---
name: writing-credo-checks
description: Use when authoring or modifying a custom Credo check in this repo — writing run/2, traversing AST with Credo.Code.prewalk, matching module names or remote calls, scoping a check to test/lib files, or handling -> clauses. Catalogues the AST traps that shipped real false positives and false negatives here.
---

# Writing Credo Checks

Mirror the house skeleton in `lib/mika_credo_rules/no_application_env_outside_config.ex` —
`use Credo.Check` with `param_defaults` + `explanations`, `@moduledoc` with BAD/GOOD, `run/2` →
`IssueMeta.for/2` → `Credo.Code.prewalk/2` → `issue_for/2` → `format_issue/2`. Message format:
`"<trigger> found — <what must happen instead>"`. One check per file.

The existing checks are good exemplars — **copy their shape**. This skill documents the traps
that shape encodes, so you don't "simplify" a fix back into a bug.

For proving a check works, see **`verifying-credo-checks`**.

## Scoping: the guard goes in `run/2`, NOT in `files:`

`param_defaults[:files]` prunes at Credo's **pipeline** level, which `Credo.Test.Case` bypasses
entirely. `files:` is **inert under test** — a check scoped only that way passes its whole suite
while doing nothing in production.

Put the guard in `run/2` against `source_file.filename`, param-driven. **One scoping mechanism,
not two that can disagree** — don't also declare `files:`.

## Path fragments: boundary match, never `String.contains?`

`String.contains?(filename, "test/")` matches `lib/latest/helpers.ex` (inside `la-test/`).
`"mix/tasks/"` matches `lib/vendor/remix/tasks/thing.ex` — an ordinary module that ships in the
release. The check goes **silently dark on real source**.

```elixir
defp fragment_matches?(filename, fragment) do
  String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
    String.contains?(filename, "/#{fragment}")
end
```

Suffix matching (`String.ends_with?("_test.exs")`) is inherently boundary-safe. Only *fragment*
matching needs this.

## Three spellings of "module" — handle all three

| Spelling | AST |
|---|---|
| alias path | `{:__aliases__, _, [:Ecto, :Query]}` |
| Elixir-prefixed atom | `:"Elixir.Access"` |
| erlang atom | `:application` |

**`opts[:url]` desugars to `{{:., _, [Access, :get]}, _, [...]}`** — bare atom in the module
slot, not `__aliases__`. String interpolation (`Kernel.to_string`) is the same. An
`__aliases__`-only matcher silently misses these, or treats them as erlang atoms and FPs on
every bracket access.

Normalize all three to one representation at collection time; keep comparisons dumb.

## Module identity: don't wildcard, don't hardcode

Both errors shipped, in the same check, in consecutive rounds:

```elixir
# FALSE NEGATIVE — wildcard module slot. `:join` is in the Ecto ignore list,
# so Enum.join/2 silently exempts its arguments.
defp traverse({{:., _, [_, function]}, _, args}, ...)

# FALSE POSITIVE — literal paths only. Under `alias Ecto.Query` the AST module
# is [:Query] — matches neither entry. Legitimate Ecto code gets flagged, and
# `==` is the ONLY operator Ecto's query compiler accepts, so the advice is unfixable.
module in [[:Ecto, :Query], [Elixir, :Ecto, :Query]]
```

Match both spellings **and** fold in file-level aliases.

### Alias resolution has two halves; which you need depends on segment count

- **ADD** — `alias Ecto.Query` → `[:Query]` now means `Ecto.Query`, **joins** the match set.
- **REMOVE (shadowing)** — `alias MyApp.Application` → bare `[:Application]` no longer means
  Elixir's, **leaves** the match set.

Single-segment base paths (`[:Application]`) are shadowable → need **both**. Multi-segment
(`[:Ecto, :Query]`) cannot be shadowed by a one-segment alias → **ADD only**. A *shared* helper
must implement both, because it serves both callers. `no_mocking_libraries.ex` has the superset
(multi-alias + shadowing) — copy from there, not from a single-caller version.

**`defmodule` is a third shadowing source that alias resolution does NOT cover.** A locally
nested `defmodule Mock do` emits the same `{:__aliases__, _, [:Mock]}` as a reference to a banned
single-segment name — it exact-matches, and nothing removes it from the match set, so the check
FPs on the definition and every bare-name reference (shipped: a plain RPC test helper named
`Mock` in learn_elixir, PR #278). If the check bans single-segment names, either treat
`defmodule <Name>` as shadowing (deregister the name for that file and skip the `__aliases__`
node that is the defmodule's name argument) or scope the moduledoc's "project modules are never
flagged" claim to qualified spellings only.

## `->` is overloaded: five constructs, three semantics

One `{:->, _, [lhs, _body]}` clause serves:

| Construct | Semantics |
|---|---|
| `case` / `fn` / `receive`-do / `rescue` heads | PATTERNS — bind |
| `cond` heads, `receive`-`after` heads | EXPRESSIONS — use, don't bind |
| typespec arrows `(a -> b)` in `@spec`/`@type`/`@callback` | TYPE VARIABLES — neither |

Collecting `cond`/`after` heads double-reports already-bound vars. Collecting typespec arrows
false-positives on idiomatic code. `::` is second-worst (binary segment vs typespec).

**When a check keys on an AST operator, enumerate every construct that produces it before
writing the traverse.**

## Pass `column:` when a trigger can repeat on one line

Without it, Credo locates the issue by searching the line for the trigger string and pins the
**first** occurrence:

```elixir
where(query, [u], u.age == 18) && flag == true
#                        ^col 29         ^col 44 — the real violation
```

The issue renders at col 29 — inside the *exempt* Ecto comparison, i.e. pointing at the one
comparison the dev must not touch. Operator AST meta already carries `column:`; thread
`meta[:column]` through.

## Prune subtrees with `{nil, acc}`

Returning `nil` as the AST from a `prewalk` stops the walk descending into that node. Use it to
exempt a call's *arguments* (not its whole line), or to skip `@spec`/`@type` bodies.

## Smaller AST facts

- **Both rescue forms share one keyword entry.** `try/rescue` and `def ... rescue` both expose
  `rescue:` in the same block kw-list — one `{:rescue, clauses}` matcher covers both.
- **Guards come free.** `prewalk` descends into `:when`, so `def f(x) when x == nil` is caught
  by the same clause as a body comparison.
- **2-tuple literals carry no AST metadata.** `{:error, "msg"}` has no line info — track the
  nearest enclosing line in the accumulator.
- **`TagHelper.tags/3`** returns `[{line_no, line, trigger}]` and has no concept of adjacency.
  Per-item adjacency rules need a raw-source scan via `Credo.SourceFile.source/1` — **not**
  `clean_charlists_strings_and_sigils/1`, which blanks the URLs you're looking for.
- **`apply(Mod, :fun, [])` evades dot-call matchers.** Decide explicitly: catch it, or document
  it as a limitation. Don't leave it implicit.

## Heuristic checks: contract-correct ≠ right outcome

A rule can satisfy its spec and still be wrong in practice.
`GenServerRequiresHandleContinue` flagged `Process.flag(:trap_exit, true)` — technically "a
remote call in `init/1`", but neither blocking nor expensive, and it would fire on most real
GenServers.

Prefer **function-level grants** (`{Process, :flag}`) over module-wide (`Process`) — granting
the module would also permit `Process.sleep/1`, which genuinely blocks.

**Never ship advice that breaks the code.** Before flagging a construct, confirm the suggested
replacement actually compiles in that context.

## If your check flags its own source

Some checks unavoidably reference what they ban. Add a file-scoped disable:

```elixir
# credo:disable-for-this-file MikaCredoRules.NoMockingLibraries
```

Suppression is **runner-level**, not `run/2`-level — the check still fires under
`Credo.Test.Case`. Prefer root-fixing where possible (`TodosNeedTickets` reworded its own
moduledoc rather than suppressing).
