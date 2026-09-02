### `NoDirectFunWithFlags`

`FunWithFlags` must be read through the app's own feature-flag wrapper
module, never directly from application code. `FunWithFlags` matches a flag
by atom identity — a typo'd flag name scattered across call sites silently
returns `false` at every one of them, instead of being caught in the one
place a wrapper module would centralize the name.

```elixir
# BAD — reads FunWithFlags directly from a context
FunWithFlags.enabled?(:new_checkout, for: user)

# GOOD — routed through the app's own feature-flag wrapper module
MyApp.FeatureFlags.new_checkout_visible?(user)
```

An explicit `alias FunWithFlags` still fires, since the alias resolves the
bare name right back to the library it names. `FunWithFlags` is a
single-segment name, so unlike a namespaced module it can be shadowed by a
module locally defined in the same file — a nested `defmodule FunWithFlags do
... end` deregisters the bare name for the rest of that file, and every later
bare `FunWithFlags.enabled?(...)` then resolves to the local module instead.
Files under `:allowed_paths` (default `["feature_flags", "feature_flag"]`)
are exempt — that is where the wrapper module itself is expected to live,
whether as a single file (`lib/my_app/feature_flags.ex`), a directory
(`lib/my_app/feature_flags/manager.ex`), or any path segment merely ending
in one of the entries (`lib/my_app_feature_flag/manager.ex`,
`lib/my_app/legacy_feature_flags.ex`). Test files (`:excluded_paths`,
default `["_test.exs", "test/"]`) are exempt too.

**Limitations:** only a literal `FunWithFlags.function(...)` call,
alias-aware, is recognised. A `FunWithFlags` value held in a variable or
module attribute (`flags = FunWithFlags; flags.enabled?(:x)`),
`apply(FunWithFlags, :enabled?, [:x])`, and a bare call reached via `import
FunWithFlags` are all undetected. A project module is exempted purely by
module identity, never by name resemblance — `MyApp.FeatureFlags.enabled?(:x)`
stays silent regardless of what its own name contains. Aliases are resolved
from a flat, file-level table rather than a lexical scope stack, and an alias
injected by a macro (via `__using__`) is invisible to Credo. The default
`:functions` list covers only the read API — `enable/1,2`, `disable/1,2`, and
`clear/1,2` are not banned by default; add them via `:functions` if your app
wants writes routed through the wrapper too. Only the bare `FunWithFlags`
spelling can be shadowed by a local `defmodule` — the fully-qualified
`Elixir.FunWithFlags` spelling always still fires.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:enabled?, :get_flag, :all_flags, :all_flag_names]` | `FunWithFlags` read functions to flag. |
| `allowed_paths` | `["feature_flags", "feature_flag"]` | Paths where the app's own feature-flag wrapper module may call `FunWithFlags` directly. |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
