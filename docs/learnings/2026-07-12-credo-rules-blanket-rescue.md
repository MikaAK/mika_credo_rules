# Learnings — NoBlanketRescue (2026-07-12)

Worker: blanket-rescue. Check: `MikaCredoRules.NoBlanketRescue`. Zero refinement rounds.

## Single `{:rescue, clauses}` matcher covers both rescue forms

Both rescue forms carry clauses as a `rescue:` entry in the same block keyword list:

- explicit: `{:try, _, [[do: _, rescue: clauses]]}`
- implicit: `{:def | :defp, _, [head, [do: _, rescue: clauses]]}`

`Macro.prewalk` (what `Credo.Code.prewalk` delegates to) visits keyword-list entries as
plain 2-tuples. So ONE traverse clause matches everything:

```elixir
defp traverse({:rescue, clauses} = ast, acc, recovery) when is_list(clauses) do
```

No per-form handlers. Also free coverage of `defmacro`, nested `try`, anything else
that grows a rescue block. Probe first — write throwaway `Code.string_to_quoted` +
`Macro.prewalk` script, count visited `{:rescue, _}` nodes. 3 expected, 3 seen.

Data keyword lists (`opts = [rescue: true]`) also match the traverse head, but produce
zero issues: clause extraction requires the `{:->, _, [[pattern], body]}` shape, and
data values never have it.

## Typed vs untyped pattern — one structural predicate

Rescue clause patterns have exactly four shapes. Third AST element separates them:

| Pattern | AST | Third element |
|---|---|---|
| `error ->` / `_ ->` / `_err ->` | `{name, meta, nil}` | atom (`nil` is atom) |
| `error in File.Error ->` | `{:in, _, [var, alias]}` | list |
| `error in [A, B] ->` | `{:in, _, [var, [aliases]]}` | list |
| `ArgumentError ->` | `{:__aliases__, _, [:ArgumentError]}` | list |

So:

```elixir
defp untyped_pattern?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
defp untyped_pattern?(_pattern), do: false
```

No allowlist of operators, no special-casing the list form — `is_atom/1` on the third
element does all the work because variables are the only rescue pattern with an atom
there.

## Body-subtree recovery scan

Blanket pattern alone isn't a violation — clause must ALSO fail to handle the
exception (no `reraise`/`raise`/`Logger.*` anywhere in body). Scan is a boolean
`Macro.prewalk` accumulator over the clause body, so recovery calls nested inside
`if`/`case`/whatever still count.

Param entries split once in `run/2`, not per clause:

```elixir
Enum.split_with(entries, fn entry ->
  entry |> Atom.to_string() |> String.starts_with?("Elixir.")
end)
```

`Logger` is `:"Elixir.Logger"` — module entries and bare function-name atoms
(`:reraise`) live in one param list and split cleanly. Modules match remote calls via
`Module.concat(segments) in modules`; atoms match local calls `{fun, _, args}`.
Name-matched only — aliased/renamed `Logger` invisible (documented limitation, same
stance as the canonical check's macro-injected-alias limit).

## Why the check doesn't flag its own source

The check's source contains `{:rescue, clauses}` as a function-head pattern. Parsed,
that's the 2-tuple `{:rescue, {:clauses, meta, nil}}` — second element is a VAR node
(tuple), not a list, so the `when is_list(clauses)` guard rejects it. Smoke-ran the
check over all 7 of the repo's own files: 0 issues. Worth doing for every
meta-level check — a check whose own implementation trips its traverse head is easy
to write by accident.

## Process notes

- Mutate-then-restore proved test strength: flipping `untyped_pattern?` to `false`
  broke 9 of 21 tests with specific failures, restored green.
- RED for a new module = `UndefinedFunctionError ... module not available` across all
  tests. Correct failure reason for new-module TDD.
- `mix format --check-formatted <file1> <file2>` scopes formatting to owned files —
  satisfies "no repo-wide format" while keeping the formatter gate.
