# Changelog

## 0.1.0

Initial release — 14 checks plus shared helpers.

### Checks

- `MikaCredoRules.ErrorMessageRequired` — flags `{:error, "string literal"}` tuples;
  use `%ErrorMessage{}`. Params: `:excluded_paths`, `:also_flag_atoms`.
- `MikaCredoRules.GenServerRequiresHandleContinue` — flags real work in `init/1`
  instead of `handle_continue/2`. Param: `:allowed_modules` (bare modules or
  surgical `{module, function}` grants).
- `MikaCredoRules.LoggerModulePrefixAndInspect` — Logger messages must start with
  the `#{__MODULE__}: ` prefix and wrap interpolated values in `inspect/1` (a bare
  `#{value}` crashes at runtime on non-`String.Chars` values). Params:
  `:logger_functions`, `:enforce_prefix`, `:allowed_interpolations`.
- `MikaCredoRules.NoApplicationEnvOutsideConfig` — flags any read or write of
  application env outside a config module. Catches every spelling, including
  aliases (with multi-alias and shadowing support), `Elixir.Application`, and
  `:application`. Params: `:config_files`, `:functions`, `:erlang_functions`.
- `MikaCredoRules.NoBlanketRescue` — flags catch-all rescue clauses that swallow
  exceptions without reraising, raising, or logging. Param:
  `:allowed_recovery_calls`.
- `MikaCredoRules.NoMixEnvAtRuntime` — flags `Mix.env()`/`Mix.target()` in compiled
  code (crashes in releases). `use Mix.Task` modules and `mix/tasks/` paths exempt.
  Params: `:functions`, `:excluded_paths`.
- `MikaCredoRules.NoMockingLibraries` — flags any reference to Mox, Hammox, Mock,
  Mimic, Patch, or `:meck`; use behaviours + dependency injection. Exact-segment
  matching with full alias resolution. Params: `:modules`, `:erlang_modules`.
- `MikaCredoRules.NoNilComparison` — flags `x == nil` in every operator spelling;
  use `is_nil/1`. Param: `:operators`.
- `MikaCredoRules.NoProcessSleepInTests` — flags `Process.sleep/1` and
  `:timer.sleep/1` in test files. Params: `:test_files`, `:functions`.
- `MikaCredoRules.NoReimplementedHelper` — flags local re-implementations of shared
  library helpers, pointing at the canonical implementation. Params: `:functions`
  (name → replacement map), `:excluded_paths`.
- `MikaCredoRules.NoSingleLetterVariables` — flags single-letter variable bindings
  at binding sites only; `_`-prefixed always allowed. Param: `:allowed_names`.
- `MikaCredoRules.RefuteOverAssertNot` — flags `assert !expr` / `assert not expr`
  in test files; use `refute`. Param: `:test_files`.
- `MikaCredoRules.StrictEquality` — flags `==`/`!=`; use `===`/`!==`. The Ecto
  query DSL is exempt, alias-aware, and scoped to the query call's own arguments;
  issues carry exact column numbers. Param: `:ignored_functions`.
- `MikaCredoRules.TodosNeedTickets` — flags TODO/FIXME comments without a ticket
  URL on the same or an adjacent line; per-todo, not per-file. Params: `:tags`,
  `:ticket_url`.

### Shared helpers

- `MikaCredoRules.SourceFilter` — filename predicates for `run/2` scoping guards:
  `matches_suffix?/2`, boundary-aware `matches_fragment?/2` (a `test/` fragment
  does not match `lib/latest/`), `script_file?/1`.
- `MikaCredoRules.AstHelpers` — `module_paths/1` (both AST spellings of a module)
  and `resolve_aliases/2` (alias folding with both the ADD and shadow-REMOVE
  halves).

### Notes

- Path-exclusion params are unified on `:excluded_paths` with boundary-aware
  matching; include-side params keep their domain names (`:config_files`,
  `:test_files`).
- When enabling `TodosNeedTickets`, disable Credo's built-in `TagTODO` to avoid
  double-reporting — see the README installation snippet.
