### `NoLengthZeroComparison`

Comparing `length/1` (or `Enum.count/1`) against `0` must use `Enum.empty?/1`
instead. `length(list)` walks the entire list — `O(n)` — just to throw the
count away and keep only whether it was zero; `Enum.empty?/1` answers the
same question in `O(1)`.

```elixir
# BAD
def none?(list), do: length(list) === 0

# GOOD
def none?(list), do: Enum.empty?(list)
```

`0` on either side is caught by every equality operator (`===`, `==`, `!==`,
`!=`), and `length(list) > 0` / `length(list) >= 1` are caught too — both
mean "not empty", so the rewrite is `not Enum.empty?(list)`. `Enum.count/1`
(no predicate) is caught the same way as `length/1`. Guard clauses are
caught, with the message pointing at the guard-safe pattern match (`x !==
[]`) instead of `Enum.empty?/1`, which is not allowed in a guard.

`length(x) === 0` is also caught by Credo's own default-on
`Credo.Check.Warning.ExpensiveEmptyEnumCheck` (`EX5003`) — measured: its
operator list (`==`, `!=`, `===`, `!==`, `>`, `<`, `>=`, `<=`) is a strict
superset of this check's, so every comparison this check flags is flagged
twice by a repo running both. What this check adds instead: alias-awareness
(`alias Enum, as: E; E.count(x) === 0` fires here but evades the stock
check's hardcoded `Enum` pattern; `alias MyApp.Vendor.Enum` correctly stays
silent here, where the stock check false-positives since it never resolves
aliases), a `column:` on every issue instead of `line_no` only, and
configurable `local_functions`/`remote_functions`. Disable the stock check
if the double report is unwanted:

```elixir
checks: %{
  enabled: [{MikaCredoRules.NoLengthZeroComparison, []}],
  disabled: [{Credo.Check.Warning.ExpensiveEmptyEnumCheck, []}]   # superseded, minus <, <=, Enum.count/2
}
```

Disabling it also drops its `<`/`<=` coverage and its `Enum.count/2` advice
(`not Enum.any?/2`) — only disable it if that coverage isn't otherwise
wanted.

**Limitations:** only a comparison against the literal `0`/`1` is
understood — `length(list) === 3` and `length(list) === len` (a variable)
are left alone. `Enum.count/2` (with a predicate) has no `Enum.empty?/1`
equivalent and is never flagged. Only `>`/`>=` are matched, and only with
length on the left (`length(x) > 0`, `length(x) >= 1`) — `0 < length(x)`,
`1 <= length(x)`, `length(x) < 1`, and `length(x) <= 0` are not matched
here, regardless of which side `length(x)` is on, but this is not an
uncovered gap for a repo also running `Credo.Check.Warning.ExpensiveEmptyEnumCheck`,
which already flags all four forms (see above). A piped call (`list |> Enum.count() === 0`) is a false negative,
since the piped argument is not part of the call's own argument list in the
raw AST. Only `local_functions`/`remote_functions` calls are recognised, and
`local_functions` matches on the bare call name alone, not on which
function it resolves to — `import Kernel, except: [length: 1]` followed by
`import MyApp.Sizes, only: [length: 1]` makes `length(ring) === 0` fire with
the `Enum.empty?/1` / `=== []` advice even though `MyApp.Sizes.length/1` may
not return a list-like count at all. A single-segment `remote_functions` module (e.g. `Enum`) can be
shadowed by a `defmodule <Name>` of the same bare name anywhere in the
file, but the deregistration is file-scoped, not lexical — it silences
bare `Enum` for the entire file, including code above the nested
`defmodule`, not just from its definition onward. The guard-safe
alternative (`=== []`) is only offered for a `local_functions` match — a
`remote_functions` match such as `Enum.count/1` can never appear in a
guard and is not equivalent to `=== []` for every collection type.

| Param | Default | Meaning |
|---|---|---|
| `local_functions` | `[:length]` | Bare/imported 1-arity function names that count as a length computation |
| `remote_functions` | `[{Enum, :count}]` | `{Module, function}` pairs naming a remote 1-arity call that counts as a length computation (alias-aware). `Module` must be an Elixir module — an erlang module atom (e.g. `:maps`) raises `ArgumentError` and aborts the run |
