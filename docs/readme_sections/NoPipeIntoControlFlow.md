### `NoPipeIntoControlFlow`

Piping directly into `case`/`if`/`unless`/`cond`/`with` obscures the piped
subject — bind it to a name first, then branch on the name. `|> case do`
buries the branched-on value on the far side of a pipe operator, so a reader
has to hold the whole pipeline in their head before they can even see what is
being matched.

```elixir
# BAD — the branched-on value never gets a name
defmodule MyApp.Orders.Pricing do
  def apply_discount(order) do
    order
    |> calculate_total()
    |> case do
      total when total > 100 -> total * 0.9
      total -> total
    end
  end
end

# GOOD — bind the pipeline's result, then branch on the name
defmodule MyApp.Orders.Pricing do
  def apply_discount(order) do
    total = order |> calculate_total()

    case total do
      total when total > 100 -> total * 0.9
      total -> total
    end
  end
end
```

**Limitations:** only a bare pipe into the construct itself is flagged — a
construct nested inside a piped anonymous function (`x |> Enum.map(fn y ->
case y do ... end end)`) is left alone, since the pipe's actual target is the
function receiving it, not the construct. `cond` is kept in `constructs` for
parity with its siblings, but a real `|> cond do ... end` does not compile —
`cond` only accepts a do-block, so piping into it produces a call to a
nonexistent `cond/2`. A construct reached via a prefix-form `Kernel.|>/2`
call evades the AST shape this check keys on.

| Param | Default | Meaning |
|---|---|---|
| `constructs` | `[:case, :if, :unless, :cond, :with]` | Control-flow construct atoms that count as a violation when piped into directly |
