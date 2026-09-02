### `NoFunWithFlagsMutationInTests`

`FunWithFlags.enable/disable/clear` mutate GLOBAL flag state — never call them
directly in a test. `FunWithFlags` persists flags in a store shared by the
whole test run (often Redis- or Ecto-backed), not per-process, so a test that
flips a flag leaks that change into whatever else runs concurrently and
poisons any other `async: true` test that happens to check the same flag.

```elixir
# BAD — leaks into every other async test
defmodule MyApp.BannerTest do
  test "shows the beta banner" do
    FunWithFlags.enable(:beta_banner)
    assert MyApp.Banner.visible?()
  end
end

# GOOD — the code under test takes the flag as an argument
defmodule MyApp.BannerTest do
  test "shows the beta banner" do
    assert MyApp.Banner.visible?(beta_banner: true)
  end
end
```

A project's own flag facade (`MyApp.FeatureFlags.enable/1`, say) mutates the
same underlying store and is caught too, via the `:wrapper_suffixes` param —
a module is a wrapper when the last segment named at the call site ends with
one of those suffixes, aliased or fully qualified. Only test files are in
scope, identified via `:included_paths` — unlike the checks scoped by
`excluded_paths`, and in line with the `test_files` scoping of the other
test-only checks, since a `FunWithFlags` mutation in `lib/` code (an admin
action, a migration task) is the library doing its job, not a violation.

A suite that installs its own per-process flag sandbox — a mock adapter
keyed on the test's `self()`, the pattern a flag facade's own test suite
typically uses to test its own `enable/1`/`disable/1`/`clear/1` wrappers —
never reaches the shared store this check exists to protect. Add that file,
or its directory, to `:excluded_paths` to silence it there.

**Limitations:** A suite that installs its own per-process flag sandbox (a
mock adapter keyed on `self()`) is a known false positive — the mutation is
process-local, so it never poisons another async test, and "inject the flag
value into the code under test instead" does not apply when the flag store
itself is the code under test. This is the shape of a flag facade's own
test suite, testing its own `enable/1`/`disable/1`/`clear/1` wrappers. Add
the file, or its directory, to `:excluded_paths`, or use `#
credo:disable-for-this-file MikaCredoRules.NoFunWithFlagsMutationInTests`
inline. `apply(FunWithFlags, :enable, [:foo])` is invisible — this check
only matches the `Module.function(args)` call shape, not dynamic dispatch.
Module identity is a naming heuristic on the last segment written at the
call site, not full alias resolution — a wrapper injected as a dependency
(`@flags.enable(:foo)`) or renamed via `as:` to drop its suffix is
invisible, and an unrelated local module that happens to share a wrapper
suffix would be a false positive. A call rooted in `__MODULE__` or
`unquote/1` (e.g. `__MODULE__.FeatureFlags.enable(:x)`, or
`unquote(mod).FeatureFlags.enable(:x)` inside a `quote` block) is invisible,
as is the Elixir-prefixed atom spelling
(`:"Elixir.FunWithFlags".enable(:foo)`).

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:enable, :disable, :clear]` | Mutating `FunWithFlags` functions to flag. |
| `included_paths` | `["_test.exs", "test/"]` | Path fragments identifying test files. The check runs ONLY on a match. |
| `wrapper_suffixes` | `["FeatureFlags"]` | Suffixes identifying a project's own flag facade by its last call-site segment, in addition to `FunWithFlags` itself. |
| `excluded_paths` | `[]` | Path fragments naming test files to skip even though they match `included_paths` — the escape hatch for a suite that installs its own per-process flag sandbox. |
