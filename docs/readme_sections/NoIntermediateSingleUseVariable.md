### `NoIntermediateSingleUseVariable`

A variable bound once and used exactly once, immediately after, adds a name
with no payoff — inline the right-hand side into the statement that consumes
it.

```elixir
# BAD — `provider` is bound once and used once, immediately after
def config_provider(opts) do
  provider = Keyword.get(opts, :provider, :ses)
  case provider do
    :ses -> MyApp.Mailer.SES
    :smtp -> MyApp.Mailer.SMTP
  end
end

# GOOD — the call moves into the `case` subject
def config_provider(opts) do
  case Keyword.get(opts, :provider, :ses) do
    :ses -> MyApp.Mailer.SES
    :smtp -> MyApp.Mailer.SMTP
  end
end
```

This is deliberately narrow, to keep false positives near zero. All of the
following must hold for the binding statement: the right-hand side is
call-shaped — a function call, a pipe chain, an operator expression, a
module attribute, or dot-field access all qualify — never a literal
(including sigils, binaries, unary-minus/-plus numbers like `-1`, and an
operator expression whose operands are themselves all literals, like
`1..10` or `1 + 2`), an `if`/`case`/`with`/`cond`, or a capture; the very
next statement in the same block consumes the variable as its sole use — a
`case` subject, the one argument of a call (`f(var)`, `Mod.f(var)`,
`fun.(var)`), or the source piped into a chain whose first stage is a
zero-arg call (`var |> f()`, `var |> f() |> g(3)`); the variable appears
nowhere else in the enclosing function clause — bound once, used once; and
the right-hand side's own text stays under `:max_inline_length` characters,
so inlining does not make the next line harder to read than the two lines
it replaces.

**Limitations:** only the function clause's own top-level block is scanned —
a bind-and-use pair nested inside an `if`/`case`/`cond` branch is not chased.
A variable used more than once, rebound later, or consumed alongside another
argument (`f(x, var)`) is untouched, as is an underscore-prefixed variable
(`_provider`). For a pipe consumer whose right-hand side is a call with
arguments (`var = f(a); var |> g()`), following the advice moves that call to
the head of the chain, which `Credo.Check.Refactor.PipeChainStart`, if
enabled, will separately ask to be extracted back out — this check does not
account for that other check's rule. This is a readability nudge
(`base_priority: :low`), not a correctness rule — and that low priority
means a plain `mix credo` run never reports it at all; `mix credo --strict`
(or a `min_priority` override) is required to see its issues.

| Param | Default | Meaning |
|---|---|---|
| `max_inline_length` | `60` | Exclusive upper bound on textual length (via `Macro.to_string/1`) of a right-hand side call or pipe chain — at or above this length, the check stays silent. |
