### `NoDoPrefixedHelper`

A public/private pair split only by a `do_` prefix — `def process/1` calling
`defp do_process/1` — hides what the private half actually does behind a
name that just repeats the public one. Find a descriptive name instead.

```elixir
# BAD — the prefix says nothing the caller couldn't already guess
defmodule MyApp.Importer do
  def process(row) do
    do_process(row, [])
  end

  defp do_process(row, acc) do
    [row | acc]
  end
end

# GOOD — the name describes the work
defmodule MyApp.Importer do
  def process(row) do
    normalize_row(row, [])
  end

  defp normalize_row(row, acc) do
    [row | acc]
  end
end
```

Both `def name` + `defp do_name` and `defp name` + `defp do_name` pairs are
flagged, at the `defp do_name` head. A `defp do_name` with no sibling `name`
definition anywhere in the module is left alone — a recursion accumulator
with no public twin is legitimate. Definitions are collected per module in a
first pass, then compared, so the pair is found regardless of definition
order. A multi-clause `defp do_name` is flagged once, at its earliest
clause — not once per clause. Scoping is per module: a pair split across an
outer module and a nested one, or across two sibling modules in one file, is
not flagged. A `defimpl`, `defprotocol`, or `quote` block is likewise its
own scope, independent of the module it is written inside — a `def`
injected by a `__using__` macro's `quote` block pairs only with a `do_name`
also injected by that same `quote` block, never with an unrelated `do_name`
living in the module the `quote` happens to be written inside.

**Limitations:** matching is by name only, not arity — `def process/1` pairs
with `defp do_process/3` just as readily as `defp do_process/1`. Only `def`
and `defp` are considered; `defmacro`/`defmacrop` and `defdelegate` are
never collected, even though `defdelegate name(x), to: Other` does define
`name/1`. A `def do_name` head is never flagged directly, even when a
sibling `name` exists — a public function's name is part of its API, not a
naming choice this check can veto. A metaprogrammed head
(`def unquote(name)(args)`) has no static name and is invisible to this
check.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `[]` | Path fragments naming files this check skips. |
