### `AsyncTrueRequired`

A `use`d test case module must declare `:async` explicitly. Leaving `async:`
unstated hides sandbox misuse a concurrent run would surface — a test that
only passes because it never races another test — and, for a project's own
case module, means the *effective* default (serial or async) lives wherever
that macro's body decides it, not at the call site. Every test case should
state its concurrency choice on purpose, not depend on an implicit default.

```elixir
# BAD — async left to ExUnit's serial default
defmodule MyApp.OrdersTest do
  use ExUnit.Case
end

# GOOD — the choice is explicit
defmodule MyApp.OrdersTest do
  use ExUnit.Case, async: true
end
```

`:case_suffixes` matches the last segment of the `use`d module as written, so
`use MyApp.DataCase` and `use MyApp.ConnCase` are caught by the default
`"Case"` suffix, without this check needing to name every project's case
module. Only a literal keyword list is inspected — `use MyApp.DataCase,
@data_case_opts` cannot be reasoned about statically and is left alone. The
check only scans files matching `:test_files` (a `run/2` guard, not a
`files:` param).

**Limitations:** an explicit `async: false` opt-out is never flagged here —
deliberately turning concurrency off for a test case that cannot run in
parallel is a different, narrower problem than never having stated a choice
at all. `use ExUnit.CaseTemplate` is not itself a test case, it defines one —
its last segment, `"CaseTemplate"`, does not end in the default `"Case"`
suffix, so it is correctly never flagged. `Wallaby.Feature` is deliberately
not a default `:case_suffixes` target either — `Wallaby.Feature.__using__/1`
ignores every option it is given and never itself calls `use ExUnit.Case`, so
flagging it would recommend `use Wallaby.Feature, async: true`, an option
Wallaby silently discards; the real fix belongs to the case module declared
above it, which the default `"Case"` suffix already covers. This check
cannot see through a `use`d macro's own body, so it cannot tell whether an
omitted `:async` actually falls back to a serial run (plain `ExUnit.Case`)
or an async one (some house case modules default the other way) — the
message asks for an explicit choice either way, rather than asserting what
the implicit one is.

| Param | Default | Meaning |
|---|---|---|
| `case_suffixes` | `["Case"]` | Suffixes identifying a test case module by the last segment of the `use`d module, as written |
| `test_files` | `["_test.exs"]` | Filename suffixes this check runs on |
