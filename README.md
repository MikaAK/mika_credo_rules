# MikaCredoRules

Custom [Credo](https://github.com/rrrene/credo) checks used across Mika's Elixir
projects. Built so automated tooling and AI agents get mechanical feedback on house
conventions from `mix credo --strict` instead of relying on prompt adherence —
several checks catch real runtime bug classes, not just style.

## Installation

```elixir
def deps do
  [
    {:mika_credo_rules, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

Then add the checks you want to `.credo.exs`:

```elixir
%{
  configs: [
    %{
      # The config MUST be named "default" — Credo silently ignores configs with
      # any other name unless --config-name is passed, and falls back to its own
      # stock checks, reporting a green run that executed none of yours.
      name: "default",
      checks: [
        {MikaCredoRules.StrictEquality, []},
        {MikaCredoRules.NoNilComparison, []}
        # ...
      ]
    }
  ]
}
```

Entries in `checks:` are **additive** — they merge with Credo's default check set
rather than replacing it. If you enable `TodosNeedTickets`, disable Credo's
built-in `TagTODO` and `TagFIXME` (both default-on, flagging every TODO/FIXME even
ticketed ones — you'd get two issues per todo):

```elixir
checks: %{
  enabled: [{MikaCredoRules.TodosNeedTickets, []}],
  disabled: [
    {Credo.Check.Design.TagTODO, []},    # superseded by TodosNeedTickets
    {Credo.Check.Design.TagFIXME, []}    # superseded by TodosNeedTickets
  ]
}
```

Three checks scope themselves to `mix.exs` and `.credo.exs`, not `lib/`/`test/`:
`InUmbrellaDepsNoVersion`, `TestOnlyDepsScoped`, and `CredoConfigNamedDefault`. Most
of Mika's per-project configs narrow `files.included` down to `["lib/", "test/"]` —
add `"mix.exs"` and `".credo.exs"` to that list (as this package's own `.credo.exs`
does) or these three checks will never see a file to run against.

## Checks

| Check | Category | What it catches |
|---|---|---|
| [`EnsureLoadedBeforeExported`](#ensureloadedbeforeexported) | `:warning` | `function_exported?`/`macro_exported?`/`Code.loaded?/1` not guarded by `Code.ensure_loaded?/1` |
| [`DistributionRequiresBuckets`](#distributionrequiresbuckets) | `:warning` | `distribution/2` whose literal opts omit `:reporter_options` |
| [`EctoMetricsRequiresAppAtom`](#ectometricsrequiresappatom) | `:warning` | `PrometheusTelemetry.Metrics.Ecto.metrics/0` — pass the app atom |
| [`CredoConfigNamedDefault`](#credoconfignameddefault) | `:warning` | A `.credo.exs` with no config named `"default"` — Credo silently falls back to its own stock checks |
| [`AbsintheDataloaderPluginRequired`](#absinthedataloaderpluginrequired) | `:warning` | A schema that builds a `Dataloader` but omits `Absinthe.Middleware.Dataloader` from `plugins/0` |
| [`CacheOptsNoHardcodedUri`](#cacheoptsnohardcodeduri) | `:warning` | A literal `uri`/`file_path` inside `use Cache, ..., opts: [...]` |
| [`CacheRequiresSandboxOption`](#cacherequiressandboxoption) | `:warning` | `use Cache, ...` without `sandbox?: Mix.env() === :test` |
| [`ErrorMessageRequired`](#errormessagerequired) | `:design` | `{:error, "string literal"}` tuples — use `%ErrorMessage{}` |
| [`ExceptionNamesEndInError`](#exceptionnamesendinerror) | `:readability` | An exception module whose name does not end in `Error` |
| [`GenServerRequiresHandleContinue`](#genserverrequireshandlecontinue) | `:refactor` | Real work in `init/1` instead of `handle_continue/2` |
| [`InUmbrellaDepsNoVersion`](#inumbrelladepsnoversion) | `:readability` | `{:app, "~> x", in_umbrella: true}` — a version requirement on an in_umbrella dep |
| [`LiveViewSubscribeRequiresConnected`](#liveviewsubscriberequiresconnected) | `:warning` | A PubSub subscribe in `mount/3` not guarded by `connected?/1` |
| [`HologramCookieKeysMustBeStrings`](#hologramcookiekeysmustbestrings) | `:warning` | An atom key literal passed to `get_cookie`/`put_cookie`/`delete_cookie` — cookie keys must be strings |
| [`LoggerModulePrefixAndInspect`](#loggermoduleprefixandinspect) | `:warning` | Logger messages missing the `#{__MODULE__}: ` prefix or interpolating values without `inspect/1` |
| [`NoAccessOnStructSubject`](#noaccessonstructsubject) | `:warning` | `changeset[:name]` — `Access` on a struct raises `UndefinedFunctionError` |
| [`MigrationExecuteInChange`](#migrationexecuteinchange) | `:warning` | `execute/1` inside `def change` — irreversible, Ecto cannot roll it back |
| [`MigrationFlushBetweenExecuteAndQuery`](#migrationflushbetweenexecuteandquery) | `:warning` | A direct `repo().query` after `execute/1,2` with no `flush()` between them |
| [`MigrationForeignKeyNeedsIndex`](#migrationforeignkeyneedsindex) | `:warning` | A `references(...)` foreign key column with no covering index in the same migration |
| [`MonolithicTemplateComponent`](#monolithictemplatecomponent) | `:refactor` | A `~H`/`~F` body spanning too many lines — decompose into smaller function components |
| [`NoApplicationEnvOutsideConfig`](#noapplicationenvoutsideconfig) | `:design` | Any read or write of application env outside a config module |
| [`NoAtomStringKeyFallback`](#noatomstringkeyfallback) | `:warning` | `m["key"] \|\| m[:key]` mixed-key fallback reads — normalize keys at the boundary |
| [`NoBarePatternMatchOnFallible`](#nobarepatternmatchonfallible) | `:warning` | `{:ok, x} = call()` — a bare match with no handling for the failure path |
| [`NoBinaryPatternForStringPrefix`](#nobinarypatternforstringprefix) | `:readability` | `<<"GET ", rest::binary>>` instead of `"GET " <> rest` |
| [`NoBlanketRescue`](#noblanketrescue) | `:warning` | Catch-all rescue clauses that swallow exceptions |
| [`NoBooleanLiteralComparison`](#nobooleanliteralcomparison) | `:readability` | `x == true` / `x != false` — use the value directly (Ecto query DSL exempt) |
| [`NoCastAllKeys`](#nocastallkeys) | `:warning` | `cast(data, params, Map.keys(params))` — a mass-assignment hole |
| [`NoCondElseAtom`](#nocondelseatom) | `:readability` | A `cond`'s last clause falling through on `:else` instead of `true` |
| [`NoForWithDiscardedResult`](#noforwithdiscardedresult) | `:warning` | A `for` comprehension in statement position whose built result is thrown away |
| [`NoDirectErlangRpc`](#nodirecterlangrpc) | `:design` | Direct `:rpc`/`:erpc` calls and `Node.spawn*` — route through your app's RPC wrapper |
| [`NoDirectHttpClient`](#nodirecthttpclient) | `:design` | Direct `Finch`/`HTTPoison`/`Tesla`/`Req` calls — route through your app's HTTP wrapper |
| [`NoContinueFromLiveViewMount`](#nocontinuefromliveviewmount) | `:warning` | `mount/3` returning `{:ok, socket, {:continue, term}}` — a GenServer shape, not a LiveView one |
| [`NoEctoSchemaInWebApp`](#noectoschemainwebapp) | `:design` | `use Ecto.Schema` inside a web app instead of the dedicated `_pg`/`schemas` app |
| [`NoClickHandlerOnNonInteractiveElement`](#noclickhandleronnoninteractiveelement) | `:design` | A click binding on `<span>`/`<div>`/... with no `role`/`tabindex` escape hatch |
| [`NoHeexSigilInHologramModule`](#noheexsigilinhologrammodule) | `:warning` | `~H` sigils or `use Phoenix.LiveView`/`use Phoenix.Component` inside a Hologram module |
| [`NoIdentityRewrap`](#noidentityrewrap) | `:refactor` | `case` expressions whose every clause returns its pattern unchanged |
| [`NoInspectModuleInMigrationSql`](#noinspectmoduleinmigrationsql) | `:warning` | `inspect/1` or string interpolation of a module alias in a migration |
| [`NoJasonDeriveOnEctoSchema`](#nojasonderiveonectoschema) | `:design` | `@derive Jason.Encoder` inside Ecto schema modules |
| [`NoKernelPrefix`](#nokernelprefix) | `:readability` | `Kernel.inspect(value)` — `Kernel` is auto-imported, drop the prefix |
| [`NoMixEnvAtRuntime`](#nomixenvatruntime) | `:warning` | `Mix.env()`/`Mix.target()` in compiled code — crashes in releases |
| [`NoMockingLibraries`](#nomockinglibraries) | `:design` | Any reference to Mox, Hammox, Mock, Mimic, Patch or `:meck` |
| [`NoNilComparison`](#nonilcomparison) | `:readability` | `x == nil` / `x != nil` — use `is_nil/1` |
| [`NoObanInsertBang`](#nobaninsertbang) | `:warning` | `Oban.insert!`/`Oban.insert_all!` in application code — prefer the non-bang form and handle `{:error, _}` |
| [`NoPhxBindingsInHoloTemplate`](#nophxbindingsinholotemplate) | `:warning` | `phx-*` attributes or EEx tags inside a `~HOLO` template |
| [`NoProcessSleepInTests`](#noprocesssleepintests) | `:warning` | `Process.sleep/1` and `:timer.sleep/1` in test files |
| [`NoRawEts`](#norawets) | `:design` | Raw `:ets` calls — wrap in `Cache.ETS` from elixir_cache |
| [`NoRawMarkupInTemplates`](#norawmarkupintemplates) | `:design` | Literal `style="..."`, hardcoded hex colors, inline `<svg>`, and banned raw tags inside `~H`/`~F` bodies |
| [`NoReimplementedHelper`](#noreimplementedhelper) | `:design` | Local re-implementations of shared library helpers |
| [`NoRepoWritesInTests`](#norepowritesintests) | `:design` | Write-side `Repo` calls (`insert!`, `update!`, `delete!`, ...) in test files — use `FactoryEx` |
| [`NoSelfSendZeroDelay`](#noselfsendzerodelay) | `:refactor` | `Process.send_after(self(), _, 0)` and `send(self(), _)` in `init/1` — use `{:continue, term}` instead |
| [`NoServerCodeInHologramAction`](#noservercodeinhologramaction) | `:warning` | DB/IO/server calls, session/cookie access, or unimplemented client forms inside a Hologram action |
| [`NoSingleLetterVariables`](#nosinglelettervariables) | `:readability` | Single-letter variable bindings |
| [`NoVacuousAssert`](#novacuousassert) | `:warning` | `assert true` / `assert <literal>` / `refute false` / `assert x === x` — placeholder assertions that can never fail |
| [`NoWordSigilLists`](#nowordsigillists) | `:readability` | `~w`/`~W` sigils — use a list literal instead |
| [`NoTruthyAndOr`](#notruthyandor) | `:warning` | `and`/`or`/`not` on a provably-nilable operand (`opts[:key]`, `Map.get/2`, ...) — use `&&`/`\|\|`/`!` |
| [`ObanWorkerRequiresMaxAttempts`](#obanworkerrequiresmaxattempts) | `:design` | `use Oban.Worker` whose literal opts omit `:max_attempts` |
| [`NoStaticNotLoadedDropList`](#nostaticnotloadeddroplist) | `:design` | `Map.drop(map, [:__meta__, ...])` — a static drop-list scrubbing `%Ecto.Association.NotLoaded{}` |
| [`NoTaskAsyncInGenServer`](#notaskasyncingenserver) | `:warning` | `Task.async`/`Task.Supervisor.async` inside a GenServer/GenStage callback — a crashing task takes the server down |
| [`NoUnsupervisedTaskStart`](#nounsupervisedtaskstart) | `:warning` | `Task.start` — a crash inside it is silently discarded |
| [`NoTelemetrySupervisorModule`](#notelemetrysupervisormodule) | `:design` | A `*Telemetry` module using `Supervisor` — add a `PrometheusTelemetry` child spec instead |
| [`PrometheusExporterMustBeGated`](#prometheusexportermustbegated) | `:warning` | `exporter: [enabled?: true]` — the metrics endpoint must be gated to prod |
| [`PhxValueNoDashes`](#phxvaluenodashes) | `:warning` | A dashed multiword `phx-value-*` key — LiveView never converts it, so a `%{"foo_bar" => _}` handler clause won't match |
| [`RefuteOverAssertNot`](#refuteoverassertnot) | `:readability` | `assert !expr` / `assert not expr` — use `refute` |
| [`SingleModulePerFile`](#singlemoduleperfile) | `:design` | More than one top-level `defmodule` per file (nested modules allowed) |
| [`SqlSandboxPlugMustBeCompileGated`](#sqlsandboxplugmustbecompilegated) | `:warning` | `plug Phoenix.Ecto.SQL.Sandbox` not gated on `Application.compile_env/2,3` |
| [`StrictEquality`](#strictequality) | `:warning` | `==`/`!=` — use `===`/`!==` (Ecto query DSL exempt) |
| [`TestOnlyDepsScoped`](#testonlydepsscoped) | `:warning` | A dev/test-only mix.exs dep missing `only:` or `runtime: false` |
| [`TaskAsyncStreamRequiresTimeout`](#taskasyncstreamrequirestimeout) | `:warning` | `Task.async_stream`/`Task.Supervisor.async_stream` missing an explicit `:timeout` |
| [`TodosNeedTickets`](#todosneedtickets) | `:design` | TODO/FIXME comments without an adjacent ticket URL |

---

### `EnsureLoadedBeforeExported`

`function_exported?/3`, `macro_exported?/3`, and `Code.loaded?/1` must be
guarded by `Code.ensure_loaded?/1` in the same clause body. `function_exported?/3`
returns `false` for a module that has not yet been loaded into the current
process's code table — not an error, just silently wrong — which flakes
intermittently across ExUnit seeds instead of failing deterministically. Each
guard scope (a `def`/`defp`/`defmacro` clause body, or an ExUnit
`test`/`setup`/`setup_all` block) is checked independently.

```elixir
# BAD — returns false on first access before the code table loads
def compile(graph_module, opts) do
  if function_exported?(graph_module, :compile, 1) do
    graph_module.compile(opts)
  end
end

# GOOD
def compile(graph_module, opts) do
  if Code.ensure_loaded?(graph_module) and function_exported?(graph_module, :compile, 1) do
    graph_module.compile(opts)
  end
end
```

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:function_exported?, :macro_exported?, {Code, :loaded?}]` | Module-capability checks that must be guarded — bare atoms match local/imported/`Kernel.`-qualified calls, `{module, function}` tuples match calls qualified on that module (alias-resolved) |
| `guard_functions` | `[{Code, :ensure_loaded?}, {Code, :ensure_loaded}, {Code, :ensure_compiled}, {Code, :ensure_compiled!}]` | `{module, function}` calls that satisfy the guard anywhere in the same clause body |
| `excluded_paths` | `[]` | Path fragments exempt from the check (segment-boundary matched) |

Bare-atom-qualified calls (`:"Elixir.Code".ensure_loaded?(mod)`) and a bare
`ensure_loaded?(mod)` reached through `import Code` are not recognized as
guards, and `apply(Kernel, :function_exported?, [...])` evades the check
entirely.

### `DistributionRequiresBuckets`

`Telemetry.Metrics.distribution/2` must set `:reporter_options` with `:buckets`.
A Prometheus histogram with no configured buckets has nothing to sort observations
into — the reporter emits no usable data for the metric.

```elixir
# BAD
distribution("my_app.job.duration.microseconds", event_name: @stop, measurement: :duration)

# GOOD
distribution("my_app.job.duration.microseconds",
  event_name: @stop,
  measurement: :duration,
  reporter_options: [buckets: @buckets]
)
```

Both the imported local call (behind `import Telemetry.Metrics` in the same file)
and the qualified `Telemetry.Metrics.distribution(...)` are caught, including
aliases of the module. A bare local `distribution/2` call with no
`import Telemetry.Metrics` in the file is left alone — a local function that
happens to share the name is not this library's `distribution/2`, and a
`distribution/2` function definition head is never mistaken for a call. Only a
literal opts keyword list is inspected; opts built by a helper or held in a
variable are silently skipped. `reporter_options: [buckets: [...]]` is checked
too — `reporter_options: []` still fires, since a histogram with no buckets
emits no usable data either way.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:distribution]` | `Telemetry.Metrics` functions checked |
| `required_keys` | `[:reporter_options]` | Options that must be present in the literal opts |
| `excluded_paths` | `[]` | Path fragments exempt from the check |

### `EctoMetricsRequiresAppAtom`

`PrometheusTelemetry.Metrics.Ecto.metrics/0` must not be called — pass the app
atom. `metrics/1` takes exactly one argument (an app atom, used as the telemetry
event-name prefix and the metric's label tag) and has no `metrics/0` clause —
calling it with no arguments does not compile.

```elixir
# BAD — metrics/0 has no clause; this does not compile
metrics: [PrometheusTelemetry.Metrics.Ecto.metrics()]

# GOOD — the app atom is the telemetry event-name prefix and label
metrics: [PrometheusTelemetry.Metrics.Ecto.metrics(:my_app)]
```

Every spelling of the module is caught, including
`alias PrometheusTelemetry.Metrics` + `Metrics.Ecto.metrics()` and the
fully-qualified `Elixir.PrometheusTelemetry.Metrics.Ecto.metrics()`. It
deliberately never matches a bare `Ecto.metrics()` — even one reached via
`alias PrometheusTelemetry.Metrics.Ecto` — because `Ecto` is too common a name
to trust a bare alias for on its own; that spelling is a known false negative,
accepted to avoid flagging an unrelated module that happens to be named `Ecto`.

| Param | Default | Meaning |
|---|---|---|
| `module_functions` | `[{PrometheusTelemetry.Metrics.Ecto, :metrics}]` | `{module, function}` pairs whose zero-arity call is banned |
| `excluded_paths` | `[]` | Path fragments exempt from the check |

### `CredoConfigNamedDefault`

A `.credo.exs` must have a config named `"default"` (or one of
`:allowed_names`). `mix credo` selects the config named `"default"` unless
`--config-name` is passed. If no config in the file has that name, Credo
silently falls back to its own stock checks — printing a green run that
executed none of the checks this file defines.

```elixir
# BAD — no config is named "default"; Credo silently runs its own defaults
%{
  configs: [
    %{
      name: "mika",
      checks: []
    }
  ]
}

# GOOD — a config named "default" exists
%{
  configs: [
    %{
      name: "default",
      checks: []
    }
  ]
}
```

Only the literal `%{configs: [...]}` shape is inspected. A `.credo.exs` that
builds its config dynamically (e.g. `Code.eval_file/1`, a function call) is
skipped — this check can only verify what it can parse statically. A `name:`
that isn't a string literal counts as a possible `"default"` rather than
being flagged, since the check cannot evaluate it.

**Limitations:** a `configs:` key is matched wherever it appears in the
file, not only at the top level, so an unrelated nested map with its own
`configs:` key is treated as the real config. A `configs:` list built with
the cons operator (`[%{name: "default"} | rest]`) is not walked into, so a
`"default"` hidden behind `|` goes unseen and the file is flagged as missing
one even though it isn't — write `configs:` as a plain list literal.

| Param | Default | Meaning |
|---|---|---|
| `config_files` | `[".credo.exs"]` | Path suffixes treated as Credo config files |
| `allowed_names` | `["default"]` | Config names Credo will actually select without `--config-name` |

### `AbsintheDataloaderPluginRequired`

A `use Absinthe.Schema` module that builds a `Dataloader` must list
`Absinthe.Middleware.Dataloader` in `plugins/0`. Absinthe never runs the
Dataloader batches unless the middleware is registered — without it, every
`dataloader/1,2` field compiles and runs fine but silently returns `nil`.

```elixir
# BAD — no plugins/0, so the loader never batches
defmodule MyAppWeb.Schema do
  use Absinthe.Schema

  def context(ctx) do
    loader = Dataloader.new() |> Dataloader.add_source(MyApp.Accounts, source())
    Map.put(ctx, :loader, loader)
  end
end

# GOOD — the plugin is registered alongside the framework defaults
def plugins, do: [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
```

Only fires when the module actually builds a loader (`Dataloader.new` or
`Dataloader.add_source`, alias-aware) — a schema with no Dataloader usage is
left alone regardless of `plugins/0`. `plugins/0` is accepted in any shape as
long as every required module appears somewhere in its body — a bare list or a
`++` chain in either order. Scoped per module, not per file, the same way as
[`NoJasonDeriveOnEctoSchema`](#nojasonderiveonectoschema).

| Param | Default | Meaning |
|---|---|---|
| `required_plugins` | `[Absinthe.Middleware.Dataloader]` | Modules that must all appear in `plugins/0` when the schema builds a Dataloader |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `CacheOptsNoHardcodedUri`

A `use Cache, ..., opts: [...]` definition must not hardcode a connection
secret or address — use runtime config instead. A literal `uri:`
(`Cache.Redis`) or `file_path:` (`Cache.DETS`) in `opts:` bakes the
connection target (and, for `uri:`, often a credential) into compiled code,
shared by every environment the release ships to.

```elixir
# BAD — hardcoded in every environment, including the compiled release
use Cache,
  adapter: Cache.Redis,
  name: :c,
  sandbox?: Mix.env() === :test,
  opts: [uri: "redis://localhost:6379"]

# GOOD — resolved at runtime
use Cache,
  adapter: Cache.Redis,
  name: :c,
  sandbox?: Mix.env() === :test,
  opts: {MyApp.Config, :redis_opts, []}
```

Only a literal `opts:` keyword list is inspected — an MFA tuple, an
`{app, key}` tuple, an application-env atom, a zero-arity function reference,
or a variable are all `elixir_cache`'s documented runtime-config forms and are
never flagged. `Cache` is alias-aware, the same way as `CacheRequiresSandboxOption`.

| Param | Default | Meaning |
|---|---|---|
| `cache_modules` | `[Cache]` | Modules that count as `elixir_cache`'s `Cache` in a `use` expression (alias-aware) |
| `literal_keys` | `[:uri, :file_path]` | `opts:` keys that must not carry a string or integer literal — `uri` (`Cache.Redis`) and `file_path` (`Cache.DETS`) are the only two `elixir_cache` adapter options that carry an address or path; `elixir_cache` validates `opts:` against each adapter's own closed `NimbleOptions` schema, so an unlisted key like `host`/`port`/`password` is rejected before it ever reaches a real connection — set `literal_keys` explicitly for a project's own adapter with those option names |
| `excluded_paths` | `["elixir_cache/"]` | Path fragments exempt from the check (segment-boundary matched) — a vendored or umbrella copy of the library (`apps/elixir_cache/`, `deps/elixir_cache/`) legitimately constructs literal connection opts in its own tests and fixtures. This cannot match at the `elixir_cache` repository's own root (`lib/cache/...` has no `elixir_cache` path segment) — that repo should disable this check in its own `.credo.exs` instead. |

**Known limitations:** a charlist (`opts: [uri: ~c"redis://localhost:6379"]`),
string interpolation, and concatenation all evade the check — only a plain
string or integer literal is recognised. A multi-line `use Cache, ...`
reports the issue at the `use` line, not the line the hardcoded `opts:`
entry is written on. A locally nested `defmodule Cache do ... end` is not
recognised as shadowing the way a project-level `alias` is, so a `use Cache,
...` inside it (referring to the local `Cache`) can still be matched against
`elixir_cache`'s `Cache` and flagged incorrectly.

The original spec's `flag_literal` param was deliberately not implemented —
`literal_keys` already controls which keys are inspected, and a second
boolean toggle for whether literals are flagged at all would be redundant
with simply setting `literal_keys: []`.

### `CacheRequiresSandboxOption`

A `use Cache, ...` module definition must set `sandbox?: Mix.env() === :test` —
without it, tests hit the real backend (Redis, ETS) and break async safety.

```elixir
# BAD — tests hit the real Redis backend
defmodule MyApp.UserCache do
  use Cache, adapter: Cache.Redis, name: :my_app_user_cache, opts: :my_app
end

# GOOD
defmodule MyApp.UserCache do
  use Cache,
    adapter: Cache.Redis,
    name: :my_app_user_cache,
    sandbox?: Mix.env() === :test,
    opts: :my_app
end
```

Only a literal `use Cache, ...` keyword list is inspected — `use Cache, @opts`
is left alone, since the check cannot reason about what an attribute holds.
`Cache` is alias-aware: a project module shadowing the bare name
(`alias MyApp.Cache`) is correctly not treated as `elixir_cache`'s `Cache`.
`NoMixEnvAtRuntime` only flags `Mix.env()`/`Mix.target()` inside a `def`/`defp`
body, so the module-body `sandbox?: Mix.env() === :test` this fix requires
never conflicts with that check.

| Param | Default | Meaning |
|---|---|---|
| `cache_modules` | `[Cache]` | Modules that count as `elixir_cache`'s `Cache` in a `use` expression (alias-aware) |
| `required_keys` | `[:sandbox?]` | Keys that must be present in the `use Cache, ...` literal keyword list |
| `excluded_paths` | `["elixir_cache/"]` | Path fragments exempt from the check (segment-boundary matched) — a vendored or umbrella copy of the library (`apps/elixir_cache/`, `deps/elixir_cache/`) legitimately constructs a cache without `:sandbox?` in its own tests and fixtures. This cannot match at the `elixir_cache` repository's own root (`lib/cache/...` has no `elixir_cache` path segment) — that repo should disable this check in its own `.credo.exs` instead. |

**Known limitations:** a locally nested `defmodule Cache do ... end` is not
recognised as shadowing the way a project-level `alias` is — a `use Cache,
...` inside that nested module, which really refers to the local `Cache`,
can still be matched against `elixir_cache`'s `Cache` and flagged
incorrectly.

### `ErrorMessageRequired`

Error tuples must carry a structured `%ErrorMessage{}`
([`elixir_error_message`](https://github.com/MikaAK/elixir_error_message)), not a
bare string literal. `{:error, "something went wrong"}` gives callers nothing to
match on.

```elixir
# BAD — unmatchable, unstructured reason
def find(nil), do: {:error, "user id is required"}

# GOOD — structured, matchable, carries a code
def find(nil), do: {:error, ErrorMessage.bad_request("user id is required")}
```

Variables, atoms and structs pass — only string literals are flagged.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files to skip (matched on segment boundaries) — `{:error, "..."}` literals are legitimate fixture data in tests |
| `also_flag_atoms` | `false` | When `true`, atom reasons like `{:error, :timeout}` are flagged too |

### `ExceptionNamesEndInError`

A module defining an exception must end its name with `Error`. `raise BadHTTPCode`
reads like raising a value, not an error, until the reader already knows it is an
exception — a shared suffix makes that visible at every call site.

```elixir
# BAD
defmodule BadHTTPCode do
  defexception [:message]
end

# GOOD
defmodule BadHTTPCodeError do
  defexception [:message]
end
```

Scoped per module, not per file — only a `defmodule` whose own body (nested
`defmodule`s excluded) contains `defexception` is inspected. Only the last
segment of the module name is checked, so `MyApp.Errors.BadHTTPCode` is flagged
the same as a top-level `BadHTTPCode`. A `defexception` generated inside a
`quote` block is not flagged, including a whole `defmodule` generated inside
one.

Stock Credo's `Consistency.ExceptionNames` only infers the dominant suffix used
across the codebase, so a repo with a single, differently-named exception module
passes it clean — this check enforces a specific, fixed suffix instead.

An exception generated by a `use`/macro (`use MyApp.Exceptions`) is
undetected — the `defexception` call is not textually present. A
`defexception` written inside a `def` body still flags the enclosing module.

| Param | Default | Meaning |
|---|---|---|
| `suffix` | `"Error"` | The suffix an exception module's last name segment must end with |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `GenServerRequiresHandleContinue`

GenServer `init/1` must defer real work to `handle_continue/2`. `init/1` blocks the
supervisor and risks the five-second init timeout — build the state, return
`{:ok, state, {:continue, term}}`, do the work in `handle_continue/2`.

```elixir
# BAD — blocks the supervisor while the query runs
def init(opts), do: {:ok, MyApp.Repo.all(Job)}

# GOOD — state now, work deferred
def init(opts), do: {:ok, [], {:continue, :load}}
def handle_continue(:load, _state), do: {:noreply, MyApp.Repo.all(Job)}
```

| Param | Default | Meaning |
|---|---|---|
| `allowed_modules` | `[Access, Enum, Keyword, Kernel, List, Logger, Map, NimbleOptions, String, {Process, :flag}, {Process, :monitor}, {Process, :send_after}]` | Callable from `init/1` without deferring. A bare module allows every function on it; a `{module, function}` tuple grants one function surgically — the defaults allow `Process.flag/2` while a blocking `Process.sleep/1` in `init/1` stays flagged. The list replaces the default. Erlang modules are plain atoms (`:ets` or `{:ets, :new}`). |

### `InUmbrellaDepsNoVersion`

An `in_umbrella: true` dependency must not also pin a version requirement. An
in-umbrella dependency is resolved from the sibling app's own `mix.exs`, never
from Hex — a version requirement on it is dead weight that can drift from the
sibling's actual version and never gets enforced.

```elixir
# BAD — the version requirement is never checked against anything
defp deps do
  [
    {:shared_utils, "~> 0.1", in_umbrella: true}
  ]
end

# GOOD — the sibling app's own mix.exs is the only source of truth
defp deps do
  [
    {:shared_utils, in_umbrella: true}
  ]
end
```

Only the 3-tuple form can trigger this — a 2-tuple `{:app, in_umbrella: true}`
has no version slot to remove. `mix.exs` is matched by **basename**, not path
suffix, so `lib/remix.exs` is never mistaken for a project file.

| Param | Default | Meaning |
|---|---|---|
| `mix_files` | `["mix.exs"]` | Filenames (matched by basename) treated as mix.exs files |

Cross-reference: [`NoContinueFromLiveViewMount`](#nocontinuefromliveviewmount)
covers the same `{:continue, term}` shape from the opposite side — it *forbids*
that return from LiveView's `mount/3`, a different callback this check has
nothing to do with.

### `LiveViewSubscribeRequiresConnected`

A PubSub subscribe inside `mount/3` must be guarded by `connected?/1`. LiveView
calls `mount/3` twice per navigation — once for the static render, once for the
live render after the socket upgrades — so an unguarded subscribe leaks a
subscription from the discarded static render.

```elixir
# BAD — subscribes on the static render too
def mount(_params, _session, socket) do
  MyApp.PubSub.subscribe("topic")
  {:ok, socket}
end

# GOOD — only the live render subscribes
def mount(_params, _session, socket) do
  if connected?(socket), do: MyApp.PubSub.subscribe("topic")
  {:ok, socket}
end
```

Only presence of the guard call is checked, not its polarity — `if`, `unless`,
`case`, `cond`, `&&` and `and` are all recognised as guards as long as their
condition (or left side) calls a `guard_functions` entry somewhere in it. Only
`def mount/3` clauses are inspected; `mount/2` is not a LiveView callback and is
left alone.

| Param | Default | Meaning |
|---|---|---|
| `subscribe_functions` | `[:subscribe]` | Function names that count as a PubSub subscribe (local or any-module remote) |
| `subscribe_modules` | `[]` | Modules a *remote* call must resolve to in order to count (alias-aware); `[]` means any module. Local calls are unaffected |
| `guard_functions` | `[:connected?]` | Function names that count as guarding the subscribe when called in the condition |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

Scoping is by function head shape only — any `def mount/3` calling a
subscribe-named function fires whether or not the enclosing module actually
`use`s `Phoenix.LiveView`. `apply(Phoenix.PubSub, :subscribe, [pubsub, topic])`
is undetected — only a literal remote or local call shape is matched.

### `HologramCookieKeysMustBeStrings`

A Hologram cookie key must be a string — an atom key errors at runtime. Session
keys accept either atoms or strings, but cookie keys accept strings only, and
passing an atom compiles fine and fails only when the call actually runs.

```elixir
# BAD — runtime error, cookie keys must be strings
defmodule MyApp.ProductPage do
  use Hologram.Page

  def command(:save, _params, server) do
    put_cookie(server, :theme, "dark")
  end
end

# GOOD
defmodule MyApp.ProductPage do
  use Hologram.Page

  def command(:save, _params, server) do
    put_cookie(server, "theme", "dark")
  end
end
```

Scoped per module, not per file — only a `defmodule` whose own body contains
`use Hologram.Page`/`use Hologram.Component` is inspected. Only a literal atom
in the key position (always the 2nd positional argument) is flagged; a
variable is left alone since its runtime value is unknown to a static check.

| Param | Default | Meaning |
|---|---|---|
| `hologram_modules` | `[Hologram.Page, Hologram.Component]` | Modules whose `use` marks a `defmodule` as a Hologram module |
| `functions` | `[:get_cookie, :put_cookie, :delete_cookie]` | Local cookie function names to check |

### `LoggerModulePrefixAndInspect`

Logger messages must literally start with the `#{__MODULE__}` interpolation and wrap
every interpolated value in `inspect/1`. A bare `#{value}` **crashes at runtime**
whenever the value has no `String.Chars` implementation — a tuple, a map, a pid.

```elixir
# BAD — crashes when reason is a tuple like {:error, :timeout}
Logger.error("failed: #{reason}")

# BAD — safe, but no source module on the log line
Logger.error("failed: #{inspect(reason)}")

# GOOD
Logger.error("#{__MODULE__}: failed, reason: #{inspect(reason)}")
```

Both the direct string form and the lazy `fn -> "..." end` form are checked.
Qualified spellings of allowed functions match on the function name, so
`Kernel.inspect(value)` is covered by `:inspect`.

| Param | Default | Meaning |
|---|---|---|
| `logger_functions` | `[:debug, :info, :warning, :warn, :error, :critical]` | Logger functions whose messages are checked |
| `enforce_prefix` | `true` | Require the `__MODULE__` interpolation as the very first segment |
| `allowed_interpolations` | `[:__MODULE__, :inspect]` | What may appear inside an interpolation — add your own formatting helpers |

### `NoAccessOnStructSubject`

`Access` bracket reads must not be used on a struct. `changeset[:name]` compiles,
but raises `UndefinedFunctionError` at runtime unless the struct's module
implements the `Access` behaviour — most structs, including `Ecto.Changeset`,
`Plug.Conn` and `Phoenix.LiveView.Socket`, do not. This is a runtime crash class,
not a style preference.

```elixir
# BAD — raises UndefinedFunctionError at runtime
changeset[:name]
conn[:assigns]
socket[:assigns]

# GOOD
Ecto.Changeset.get_field(changeset, :name)
conn.assigns
socket.assigns

# GOOD — not flagged, these are maps/keywords
params["id"]
opts[:timeout]
```

Two shapes count as a struct subject: a struct literal (`%MyApp.User{}`), or a
variable whose name is in the configured `:subject_names` list. Full struct-type
inference from a single-file AST check is out of reach, so the name heuristic is
the only tractable form. A nested access such as `opts[:a][:b]` is only ever
checked at the inner read — the outer read's subject is the *result* of the
inner access, not a variable or struct literal, so it is never flagged.

Because the variable check is a name heuristic, not type inference, any
variable named `conn` — even a plain keyword list in a test
(`conn = [status: 200]` then `conn[:status]`) — is flagged too. Rename the
variable, or use `:subject_names`/`:excluded_paths` to scope the check for
that file.

`%__MODULE__{}[:x]`, `Access.get(changeset, :x)` and `get_in(changeset,
[:a])` are the same runtime-crash class and are also undetected — none of
them matches the bracket-access shape this check keys on.

| Param | Default | Meaning |
|---|---|---|
| `subject_names` | `[:changeset, :conn, :socket]` | Variable names treated as known-struct subjects |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `MigrationExecuteInChange`

`execute/1` inside `def change` is irreversible — Ecto cannot roll it back. `change/0`
serves both `up` and `down`; a single-argument `execute/1` has no down side, so
`mix ecto.rollback` either does nothing for that statement or raises
`Ecto.MigrationError`.

```elixir
# BAD — no way to roll this back
def change do
  execute "UPDATE users SET role = 'student' WHERE role IS NULL"
end

# GOOD — moved to up/down
def up, do: execute("UPDATE users SET role = 'student' WHERE role IS NULL")
def down, do: :ok

# ALSO GOOD — reversible two-arg form
def change, do: execute("CREATE EXTENSION citext", "DROP EXTENSION citext")
```

`execute/2` is fine everywhere — the second argument is the down statement, so the
operation is reversible by construction. `execute/1` inside `def up` or `def down` is
fine too — those functions already commit to irreversibility.

| Param | Default | Meaning |
|---|---|---|
| `migration_paths` | `["migrations/"]` | Path fragments (segment-boundary match) treated as migration directories |

### `MigrationFlushBetweenExecuteAndQuery`

A direct `repo().query`/`query!`/`query_many` call must not follow `execute/1,2` in
the same migration body without a `flush()` between them. `execute/1,2` is DSL —
Ecto queues it to run at the end of the migration, on the migration runner's
connection. A direct query runs immediately, on a separate connection from the
pool, so without `flush()` it sees the pre-`execute` state.

```elixir
# BAD — the SELECT runs before the UPDATE has committed
def up do
  execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
  repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
end

# GOOD — flush() forces the UPDATE to run first
def up do
  execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
  flush()
  repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
end
```

Only the top-level statements of a `def up`/`down`/`change` body are read — a plain,
in-order scan for `execute`, `flush()` and a direct query call. An `execute`/query
pair nested inside a conditional branch is invisible to this check.

| Param | Default | Meaning |
|---|---|---|
| `migration_paths` | `["migrations/"]` | Path fragments (segment-boundary match) treated as migration directories |
| `direct_query_functions` | `[:query, :query!, :query_many]` | `repo()` functions that run immediately |
| `flush_function` | `:flush` | The function that forces deferred `execute/1,2` statements to run |

### `MigrationForeignKeyNeedsIndex`

A `references(...)` foreign key column needs a covering index in the same
migration file. An unindexed foreign key forces a sequential scan on every join
and on every cascading delete or update from the referenced table — Postgres
does not create one automatically for a `references/1,2` column the way it does
for a primary key.

```elixir
# BAD
create table(:users) do
  add :organization_id, references(:organizations), null: false
end

# GOOD
create table(:users) do
  add :organization_id, references(:organizations), null: false
end

create index(:users, [:organization_id])
```

Any index whose column list includes the foreign key column covers it — a
composite index counts regardless of the column's position, and a
`concurrently: true` index counts the same as a plain one. Coverage is only
checked within the same file; an index added in a different migration is
invisible to this check.

| Param | Default | Meaning |
|---|---|---|
| `migration_paths` | `["migrations/"]` | Path fragments (segment-boundary match) treated as migration directories |
| `index_functions` | `[:index, :unique_index]` | `create`/`create_if_not_exists` functions that count as an index |

### `MonolithicTemplateComponent`

A `~H`/`~F` template body that spans too many lines almost certainly contains
multiple logical phases that should be their own function components. A single
sprawling template is harder to read top-to-bottom and hides how many distinct
concerns it actually renders.

```elixir
# BAD — one sigil, three phases (header / groups / rows), 90 lines
def progress(assigns), do: ~H"""
  ...90 lines...
"""

# GOOD
def progress(assigns) do
  ~H"""
  <.progress_header {assigns} />
  <.lesson_group_card :for={g <- @groups} group={g} />
  """
end
```

This is a decomposition nudge, not a strict correctness rule. `max_lines`
defaults to 60, buying headroom over a stricter "over ~40 lines with 2+ phases"
prose guideline — only the line-count half of that is mechanically checkable.

| Param | Default | Meaning |
|---|---|---|
| `max_lines` | `60` | Physical lines a `~H`/`~F` body may span before it is flagged |
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies |
| `excluded_paths` | `[]` | Path fragments whose files are skipped entirely |

**Limitations.** Same as `NoRawMarkupInTemplates` — only `~H`/`~F` sigils
colocated inside a `.ex`/`.exs` module are covered; a `.html.heex` file is never
read by Credo (which also means a legitimately long, single-purpose whole-page
`.html.heex` template isn't the false-positive risk it would otherwise be). The
issue is reported at the sigil's own opening line, and `trigger:` reflects the
actual sigil letter matched (`~H` or `~F`). Because of that, this check
suppresses with an ordinary `# credo:disable-for-next-line` placed directly
above the `~H`/`~F` line — unlike the other sigil checks, whose issues report
from inside the body and need `# credo:disable-for-lines:N` or
`# credo:disable-for-this-file` (see `NoRawMarkupInTemplates`'s Limitations
section).

### `NoApplicationEnvOutsideConfig`

Application environment must only be read or written from a config module. Scattered
`Application.get_env/2` and `Application.put_env/3` calls make configuration
unauditable and untestable — one config module per app gives you one place to see
what the app is configured by, and one place to stub in tests.

```elixir
# BAD — env read in a service module
defmodule MyApp.Worker do
  def provider, do: Application.get_env(:my_app, :provider)
end

# GOOD — config.ex owns the env, the worker calls it
defmodule MyApp.Config do
  @app :my_app

  def provider, do: Application.get_env(@app, :provider)
end
```

Config modules are identified **by filename**, so this works the same in an umbrella
(`apps/my_app/lib/my_app/config.ex`) and a single app (`lib/my_app/config.ex`). The
one other exemption is `test_helper.exs` — env access there is boot-time
configuration that runs before any test, not the scattered runtime access this rule
exists to catch. Ordinary test files and `application.ex` are still checked; a test
reaching for `Application.put_env/3` in its own body is exactly the case this rule
exists to catch. Env access is caught through every spelling, including
`alias Application, as: App` and `:application.get_env/2`.

| Param | Default | Meaning |
|---|---|---|
| `config_files` | `["config.ex"]` | Path suffixes treated as config modules |
| `functions` | every `Application` env function | Which `Application` functions count as env access |
| `erlang_functions` | `[:get_env, :get_all_env, :set_env, :unset_env]` | Which `:application` functions count as env access |
| `excluded_paths` | `["/test_helper.exs"]` | Path fragments exempt from the check (segment-boundary matched). The leading `/` matters — it exempts a file named exactly `test_helper.exs`, never a lookalike such as `my_test_helper.exs`. |

### `NoAtomStringKeyFallback`

Reading the same key under both spellings must not be used — normalize the map's
keys at its boundary instead. A map with mixed atom/string keys has no reliable
shape: every read site has to guess, the fallback gets copy-pasted everywhere the
map is read, and any site that forgets it becomes a bug.

```elixir
# BAD — every read site guesses at the map's shape
Map.get(payload, "link") || Map.get(payload, :link)
params["id"] || params[:id]

# GOOD — normalize once at the context boundary, read plainly after
def handle_webhook(payload) do
  payload = payload_keys_to_strings(payload)

  payload["link"]
end
```

A fallback is reported when both sides of a `||` read the same subject with
literal counterpart keys — one atom and one string spelling the same name — in
either order. `Map.get/2`, `Map.get/3` and bracket access all count, in any
combination, including adjacent reads inside a chained fallback. Different key
names, same-type keys, different subjects and plain lookup-or-default
(`params["id"] || %{}`) are never flagged.

### `NoBarePatternMatchOnFallible`

A bare `=` match against a fallible-tagged call must be handled explicitly with
`case` or `with`, not left to crash with an opaque `MatchError`. `{:ok, user} =
Accounts.fetch(id)` works right up until `Accounts.fetch/1` returns
`{:error, reason}`, at which point it crashes with no context about why the call
failed.

```elixir
# BAD — a MatchError with no context if the call fails
def sync(id) do
  {:ok, user} = Accounts.fetch(id)
  broadcast(user)
end

# GOOD
def sync(id) do
  with {:ok, user} <- Accounts.fetch(id) do
    broadcast(user)
  end
end
```

Only a match whose right-hand side is an actual call — a local call, a remote
call, or a pipe — is flagged. Rebinding an already-tagged value
(`{:ok, user} = result`) reads as a shape assertion and is left alone, and a
`case`/`fn` clause head that binds a shape (`{:ok, _} = result -> ...`) is a
pattern, not a statement, so only its body is inspected. `<-` in `with` and
`for` is a different construct entirely and is never matched. A parenless
dot-read (`state.result`), an Access bracket read (`opts[:result]`), a
module-attribute read (`@cfg`), and a `||` fallback (`cached || other`) are
rebinds too, not calls — a parenless *remote* call (`Accounts.fetch`) and an
anonymous function call (`fun.()`) still count.

| Param | Default | Meaning |
|---|---|---|
| `tags` | `[:ok, :error]` | Atoms that mark a 2-tuple as fallible. |
| `excluded_paths` | `["_test.exs", "test/", "/application.ex", "priv/repo/"]` | Path fragments exempt from the check — tests use the bare match as an assertion, and a boot-time `{:ok, pid} = Supervisor.start_link(...)` in `application.ex` or a broken seed script under `priv/repo/` is deliberate. |

**Limitations.** Only a literal local call, remote call, or pipe on the
right-hand side counts as a call. A control-flow expression (`case`, `if`,
`cond`, `for`, a `fn`) on the right-hand side is never flagged, even when it
ultimately returns a fallible-tagged tuple. A `=` inside a `quote do ... end`
body is flagged even though it is macro-generated AST, not a runtime match.

### `NoBinaryPatternForStringPrefix`

Match a string prefix with concatenation, not a binary pattern.
`<<"GET ", rest::binary>>` and `"GET " <> rest` match the same values, but the
binary-pattern spelling reads like real byte-level parsing (sizes, bit widths,
encodings) when nothing here needs any of that.

```elixir
# BAD
<<"my", rest::binary>> = "my string"
def parse(<<"GET ", path::binary>>), do: path

# GOOD
"my" <> rest = "my string"
def parse("GET " <> path), do: path
```

Only a `<<>>` pattern with exactly two segments — a plain string literal
first, and a `::binary`/`::bytes`-typed variable (or `_`) second — is
flagged. A bare variable with no explicit type (`<<"GET ", rest>>`) binds a
single byte as an integer, not a string tail, so rewriting it to `<>` would
change what the code matches, and is left alone, same as genuine binary
parsing (`<<size::32, rest::binary>>`, `<<"GET", _::8, path::binary>>`). A
`<<>>` used as a constructor rather than a pattern is never flagged — only
pattern positions are inspected: the left-hand side of `=`, function-clause
heads, and `case`/`fn`/`with`/`for` pattern heads. A `<<>>` compared inside a
`case`/`fn` clause guard is a constructor too and is never inspected.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `[]` | Path fragments exempt from the check, matched at a path-segment boundary. |

### `NoBlanketRescue`

A rescue clause must not catch every exception only to swallow it. A blanket
`rescue _ ->` that neither reraises, raises, nor logs converts every crash — typos,
match errors, genuine bugs — into a silent wrong value.

```elixir
# BAD — swallows every exception, bugs included
def read_file(path) do
  File.read!(path)
rescue
  _ -> :error
end

# GOOD — rescues the specific exception it can handle
def read_file(path) do
  File.read!(path)
rescue
  error in File.Error -> {:error, error}
end
```

Typed rescues (`error in File.Error`, `error in [File.Error, ArgumentError]`) always
pass. Both explicit `try/rescue` and the implicit `def ... rescue` form are checked.

| Param | Default | Meaning |
|---|---|---|
| `allowed_recovery_calls` | `[:reraise, :raise, Logger]` | Calls that count as handling — module entries allow any call on the module, atom entries allow local/imported calls. Replaces the default when supplied. |

### `NoBooleanLiteralComparison`

Comparing a value to `true`/`false` must use the value directly, not an equality
operator. The comparison itself already evaluates to a boolean, so comparing it to
a boolean literal is redundant and invites `==`/`===` inconsistency.

```elixir
# BAD
def admin?(user), do: user.admin === true
Enum.filter(users, &(&1.active === true))

# GOOD
def admin?(user), do: user.admin
Enum.filter(users, & &1.active)
Enum.reject(users, & &1.archived)
```

Ecto queries are exempt because the query DSL only compiles `==`/`!=`
(`where(query, [u], u.active == true)` is allowed). A boolean literal on either
side is caught, including the mirrored `true == x` form.

`_test.exs` and `test/` are excluded by default — `assert x === true` /
`assert state.timeout === false` is the dominant shape in tests, and its
exact-value strictness is deliberate and *stricter* than the suggested rewrite.

The rewrite assumes the operand is strictly boolean — `!=`/`!==` against
`false` on a nilable/non-boolean operand is NOT equivalent to using the value
directly (`nil != false` is `true`, but `nil` is falsy), and exact-value
collection helpers (`Enum.count(&(&1 === true))`) hit the same trap the other
direction. The check still fires, but the message is softened for the
`!=`/`!==` `false` direction. `Kernel.==(x, true)` (the qualified call form) is
a false negative — only the bare operator AST node is matched.

| Param | Default | Meaning |
|---|---|---|
| `operators` | `[:==, :===, :!=, :!==]` | A subset of these four that counts as a boolean literal comparison when either operand is `true`/`false` — other operators are silently ignored |
| `ignored_functions` | `[:dynamic, :from, :where, :or_where, :having, :or_having, :select, :select_merge, :on, :join, :query, :subquery, :in]` | Calls whose arguments are exempt — defaults to the Ecto query DSL |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments exempt from the check (segment-boundary matched) |

### `NoCastAllKeys`

`cast` must receive an explicit list of permitted fields, never
`Map.keys(params)`. The permitted list exists to whitelist which client-supplied
keys may reach the changeset — `Map.keys(params)` turns it into "whatever the
client sent", a mass-assignment hole that lets a request set fields the endpoint
never meant to expose (`role`, `admin`, `balance`).

```elixir
# BAD — every client-supplied key is cast
cast(user, attrs, Map.keys(attrs))

# GOOD — the permitted fields are enumerated
user
|> cast(attrs, [:name, :email])
|> validate_required([:email])
```

Every spelling of the call is caught: local `cast/3,4`, piped `|> cast(...)`,
qualified `Ecto.Changeset.cast(...)` and `Changeset.cast(...)` under an alias.
Indirection through a variable (`fields = Map.keys(attrs)` then
`cast(user, attrs, fields)`) is invisible to the check — literal lists, module
attributes and variables are all left alone.

### `NoCondElseAtom`

The last `cond` clause must fall through on `true`, not on an arbitrary truthy
atom such as `:else`. Every atom other than `nil`/`false` is truthy in a `cond`
head, so `:else -> ...` works — but it reads as if `cond` supported an `else`
keyword the way `if`/`case` do, which it does not.

```elixir
# BAD
cond do
  a?() -> 1
  :else -> 2
end

# GOOD
cond do
  a?() -> 1
  true -> 2
end
```

Only the last clause's head is inspected — an atom used as an earlier clause
head is a different pattern this check does not cover.

| Param | Default | Meaning |
|---|---|---|
| `disallowed_atoms` | `[:else]` | Atoms that must not be used as the last `cond` clause's head. |

### `NoForWithDiscardedResult`

A `for` comprehension in statement position throws its result away — use
`Enum.each/2` for side-effect-only iteration instead. `for` always builds and
returns a list (or whatever `:into`/`:reduce` accumulates into); written as a
standalone statement, that value is built and immediately discarded, with no
compiler warning to catch it.

```elixir
# BAD — the built list is thrown away
def sync(items) do
  for item <- items do
    Cache.put(item)
  end

  :ok
end

# GOOD — no throwaway list
def sync(items) do
  Enum.each(items, fn item ->
    Cache.put(item)
  end)

  :ok
end
```

A `for` is only flagged when it sits in statement position — an element of a
block that is not the block's last expression. A `for` that IS the last
expression of a block, the right-hand side of `=`, a call argument, or a pipe
stage is consumed elsewhere and is never flagged. `for ... into: ...` and
`for ... reduce: ...` are flagged the same as a plain `for` when they sit in
statement position — the accumulated value is still built and discarded, and
the message names `Enum.into/3` or `Enum.reduce/3` instead of `Enum.each/2`
for those.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments exempt from the check, matched at a path-segment boundary — setup loops dominate the for-in-statement-position shape in tests. |

**Limitations.** A `for` inside a `quote do ... end` body is flagged even
though it is macro-generated AST, not a runtime comprehension.

### `NoDirectErlangRpc`

Remote nodes must be called through the app's RPC wrapper, never directly.
Direct `:rpc`/`:erpc` calls and `Node.spawn*` scatter node selection, error
handling, and telemetry across the codebase. Each umbrella defines a thin
app-level module wrapping [`RpcLoadBalancer`](https://github.com/MikaAK/rpc_load_balancer)
instead, so every remote call gets consistent load-balancing, error handling,
and a `call_directly?` escape hatch for dev/test.

```elixir
# BAD — direct erlang RPC
:rpc.call(node, SharedFeedUtils.FeedServer, :get_state, [adapter, id])

# GOOD — routed through the app's RPC wrapper
MyApp.RPC.call_on_random_node("options_feed", SharedFeedUtils.FeedServer, :get_state, [adapter, id])
```

`Node.spawn/1..3`, `Node.spawn_link/1..3`, and `Node.spawn_monitor/1..3` are
banned the same way — spawning a process directly on a remote node bypasses the
same wrapper.

The erlang primitives underneath are banned with arity awareness:
`:erlang.spawn/2` and `/4` take a remote node as their first argument (the
remote forms) and are banned; `/1` and `/3` spawn locally and are left alone.
`erlang_modules` cannot express this distinction, since it bans every arity of
a module outright — hence the separate `erlang_functions` param.

| Param | Default | Meaning |
|---|---|---|
| `erlang_modules` | `[:rpc, :erpc]` | Erlang modules banned outright — every remote call on one of these is flagged |
| `functions` | `[{Node, :spawn}, {Node, :spawn_link}, {Node, :spawn_monitor}]` | `{module, function}` pairs to ban, alias-aware |
| `erlang_functions` | `[{:erlang, :spawn, [2, 4]}, {:erlang, :spawn_link, [2, 4]}]` | `{module, function, arities}` triples to ban with arity awareness |
| `excluded_paths` | `["rpc_load_balancer/", "elixir_cache/"]` | Path fragments naming files exempt from the check (matched on segment boundaries) — the libraries that implement the wrapper itself |

**Limitations.** Test files are in scope — a test reaching for `:rpc`/`:erpc`
directly is exactly the case this rule exists to catch.
`apply(:rpc, :call, [node, mod, fun, args])` and `mod = :rpc; mod.call(...)`
are both undetected — only a literal `module.function(...)` dot-call is
matched. A locally nested `defmodule Node do ... end` is not treated as
shadowing — `Node.spawn(node, fun)` still fires inside such a module.

### `NoDirectHttpClient`

Direct HTTP client libraries must not be used to make requests — call the
app's HTTP wrapper instead. Scattered `Finch`, `HTTPoison`, `Tesla`, or `Req`
request calls duplicate pooling, header, and error-mapping logic that
`SharedUtils.HTTP` already provides.

```elixir
# BAD — in a context module
Finch.build(:get, url) |> Finch.request(MyFinch)

# GOOD
SharedUtils.HTTP.get(url, headers)
```

Building a client with `use Tesla`, `use HTTPoison.Base`, or
`use Tesla.Builder` is caught the same way as a request call — the documented
client-building idiom of each library, not just a low-level function call.

Only the functions that actually make a request are banned (see the
`functions` param for the full default list per module). A bare reference to
the module elsewhere is left alone, since it is either required to reach the
wrapper or has no wrapper equivalent at all — a supervision child spec that
merely names the client module (`{Finch, name: MyApp.Finch}`), or a Tesla
middleware's own continuation call (`Tesla.run(env, next)`, inside a module
implementing `@behaviour Tesla.Middleware`). `@spec`/`@type`/`@callback`
bodies are pruned entirely too, so a typespec referencing a banned module is
never flagged.

Aliases are still resolved for the calls that remain banned — alias-free
calls (`Finch.build/3` with no prior `alias`) and `alias Req, as: R` followed
by `R.get(url)` are both caught.

Files under `excluded_paths` (default `["shared_utils/"]`) are exempt on a
fragment basis. Files whose app directory ends with one of
`excluded_app_suffixes` (default `["_api"]`) are exempt too — matching a
whole app directory name (`tiingo_api/`), never a fragment in the middle of a
segment (`rest_api_notes/`).

**Why not the stock `Credo.Check.Warning.ForbiddenModule`?** It bans the same
modules by name but is alias-blind (`alias Req, as: R; R.get(url)` evades it)
and has no path-exemption mechanism, so it can't distinguish the wrapper layer
from its callers.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[{Finch, [:build, :request, :request!, :stream]}, ...]` | `{module, functions}` pairs naming the request-making functions banned on each client, alias-aware |
| `use_modules` | `[Tesla, HTTPoison.Base, Tesla.Builder]` | Modules whose `use` idiom builds an HTTP client outright, alias-aware |
| `erlang_modules` | `[:httpc, :hackney]` | Erlang HTTP client modules to ban |
| `excluded_paths` | `["shared_utils/"]` | Path fragments naming files exempt from the check (matched on segment boundaries) |
| `excluded_app_suffixes` | `["_api"]` | App-directory-name suffixes exempt from the check (matched on the segment's own suffix) |

**Limitations.** `alias Finch.{Request, Response}` then
`Request.build(:get, url)` is undetected — the multi-alias clause resolves
inner names against the base module's own alias table, which only ever gains
single-segment entries for `Finch` itself, never for a two-segment submodule
spelling. Same gap for `alias HTTPoison.Base`. A locally nested
`defmodule Req do ... end` is not treated as shadowing, so `Req.get(url)`
inside such a module can still fire.

### `NoContinueFromLiveViewMount`

`mount/3` must not return `{:ok, socket, {:continue, term}}`. `{:continue, term}`
is a `GenServer.init/1` return value — LiveView's `mount/3` does not implement
that protocol, so returning it either does nothing or crashes depending on the
LiveView version.

```elixir
# BAD — {:continue, _} is GenServer-only; mount/3 does not implement it
def mount(_params, _session, socket), do: {:ok, socket, {:continue, :load}}

# GOOD — gate the deferred load on connected?/1 and message yourself
def mount(_params, _session, socket) do
  if connected?(socket), do: send(self(), :load)
  {:ok, socket}
end
```

Only the clause's own last expression is inspected — a continue tuple produced
inside a `case`/`cond` branch that isn't literally the trailing expression of
the `def` body is not flagged. Mirror image of
[`GenServerRequiresHandleContinue`](#genserverrequireshandlecontinue), which
*requires* `{:continue, term}` from a GenServer's `init/1` — same shape,
opposite callback, opposite advice.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `NoEctoSchemaInWebApp`

`use Ecto.Schema` must not appear in a web app — schemas belong in a dedicated
database-layer app (conventionally `_pg` or `schemas`). A schema inside the web
app couples the wire/UI layer to the database layer, forcing every other app
that wants the schema to depend on the whole web app.

```elixir
# BAD — apps/my_web/lib/my_web/user.ex
defmodule MyWeb.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
  end
end

# GOOD — apps/my_pg/lib/my_pg/user.ex
defmodule MyApp.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
  end
end
```

`embedded_schema` is caught too — it's a macro `use Ecto.Schema` itself
provides. In scope: any file with a directory segment ending in a
`banned_path_fragments` entry (default `_web`, matching Phoenix's `<name>_web`
convention), matched at a segment boundary — `lib/cobweb/user.ex` never
matches.

| Param | Default | Meaning |
|---|---|---|
| `modules` | `[Ecto.Schema]` | Modules whose `use` counts as declaring a schema |
| `banned_path_fragments` | `["_web/"]` | Directory-name suffixes that mark a web app |
| `excluded_paths` | `[]` | Path fragments naming files this check skips even inside a banned directory |

Include the leading underscore in `banned_path_fragments` — `"web"` (no
underscore) is a segment-suffix match and over-matches `apps/cobweb/...`.

### `NoClickHandlerOnNonInteractiveElement`

A click binding on a non-interactive element (`<span>`, `<div>`, ...) must use a
native interactive element instead, unless it also carries the ARIA attributes
that make it keyboard- and screen-reader-accessible. A `<span phx-click="...">`
is invisible to keyboard navigation and assistive tech — it never receives
focus, has no default role, and `Tab`/`Enter` do nothing.

```elixir
# BAD
~H"""
<span class="pill" phx-click="show_findings">click</span>
"""

# GOOD
~H"""
<button type="button" aria-label="Show findings" phx-click="show_findings">click</button>
"""
```

An element that legitimately needs the click binding (a full-card click target)
is not flagged once it carries BOTH `role=` and `tabindex=` — the escape hatch
is a conjunction, not a flat ban. An `aria-hidden="true"` element (e.g. a modal
backdrop) is exempted independently of `role`/`tabindex` — pairing
`role`+`tabindex` with `aria-hidden="true"` would itself be a WCAG violation.
An opening tag may span multiple lines; the check scans from `<tag` to its
matching `>` regardless of how many lines that spans.

| Param | Default | Meaning |
|---|---|---|
| `non_interactive_tags` | `["span", "div", "p", "li", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6"]` | Tag names with no native click semantics |
| `bindings` | `["phx-click"]` | Attribute names that count as a click handler. A Hologram repo must set BOTH `sigils: [:sigil_HOLO]` and `bindings: ["$click"]` together — the defaults never combine to scan Hologram templates |
| `escape_attributes` | `["role", "tabindex"]` | Attributes that, when ALL present, exempt the tag |
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies |
| `excluded_paths` | `[]` | Path fragments whose files are skipped entirely |

**Limitations.** Same as `NoRawMarkupInTemplates` — only `~H`/`~F` sigils
colocated inside a `.ex`/`.exs` module are covered; a `.html.heex` file is never
read by Credo. A `>` character inside a quoted attribute value (e.g.
`title="a > b"`) would incorrectly end the tag scan early — accepted as a rare
edge case rather than handled with a full attribute parser. Suppressing an
issue inside a sigil body also works the same as `NoRawMarkupInTemplates` —
see its Limitations section for the two escapes that actually work.

### `NoHeexSigilInHologramModule`

A Hologram module must not use `~H` (HEEx) sigils or `use Phoenix.LiveView`/
`use Phoenix.Component` — Hologram and Phoenix.LiveView are different
frameworks with incompatible compilers. Hologram compiles its own templates
(`~HOLO`) to JavaScript for the client runtime; a `~H` sigil is LiveView's
HEEx template, which Hologram's compiler cannot process.

```elixir
# BAD — mixes LiveView's template engine into a Hologram page
defmodule MyApp.ProductPage do
  use Hologram.Page

  def template, do: ~H"<div/>"
end

# GOOD — Hologram's own template sigil
defmodule MyApp.ProductPage do
  use Hologram.Page

  def template, do: ~HOLO"<div/>"
end
```

Scoped per module, not per file — only a `defmodule` whose own body contains
`use Hologram.Page`/`use Hologram.Component` is inspected, the same
per-defmodule pattern `NoJasonDeriveOnEctoSchema` uses for `use Ecto.Schema`.
A nested `defmodule` without its own Hologram `use` is a separate scope and is
left alone.

| Param | Default | Meaning |
|---|---|---|
| `hologram_modules` | `[Hologram.Page, Hologram.Component]` | Modules whose `use` marks a `defmodule` as a Hologram module |
| `banned_sigils` | `[:sigil_H]` | Sigil node names banned inside a Hologram module |
| `banned_uses` | `[Phoenix.LiveView, Phoenix.Component]` | Modules that must not be `use`d inside a Hologram module |

### `NoIdentityRewrap`

A `case` whose every clause returns its pattern unchanged is a no-op re-wrap —
drop the `case` and return the matched value directly.

```elixir
# BAD — re-emits exactly what it matched
case fetch_user(id) do
  {:ok, user} -> {:ok, user}
  {:error, reason} -> {:error, reason}
end

# GOOD
fetch_user(id)
```

A `case` is only flagged when **every** clause is an identity. A transforming
clause, a guard, or a multi-expression body means the `case` does real work and
it passes. If the `case` exists purely to assert the value's shape, prefer an
explicit pattern match (`{:ok, user} = fetch_user(id)`) — an identity `case`
hides that intent.

### `NoInspectModuleInMigrationSql`

A module alias must not be rendered with `inspect/1` or string interpolation
inside a migration. Oban's `worker` column (and any similar SQL allow-list of
module names) stores names WITHOUT the `Elixir.` prefix, so `inspect(MyApp.Worker)`
and `"\#{MyApp.Worker}"` both render `"Elixir.MyApp.Worker"` — a `WHERE worker IN
(...)` built from either never matches a row.

```elixir
# BAD
worker = inspect(DeveloperAi.Workers.TicketScanner)
execute "UPDATE oban_jobs SET worker = '#{worker}'"

# BAD
execute "UPDATE oban_jobs SET worker = '#{DeveloperAi.Workers.TicketScanner}'"

# GOOD
execute "UPDATE oban_jobs SET worker = 'DeveloperAi.Workers.TicketScanner'"
```

Both spellings are caught anywhere in a migration file. Only the literal-argument
form is detected — `Enum.map([...], &inspect/1) |> Enum.join("','")` is NOT
caught, since `&inspect/1` there is a capture rather than a call with a literal
alias argument. Prefer `~w(DeveloperAi.Workers.TicketScanner)` over that pattern
regardless; this check just can't see through it.

| Param | Default | Meaning |
|---|---|---|
| `migration_paths` | `["migrations/"]` | Path fragments (segment-boundary match) treated as migration directories |
| `also_flag_interpolation` | `true` | Also flag string interpolation of a module alias, not just `inspect/1` |

### `NoJasonDeriveOnEctoSchema`

Ecto schemas must not derive `Jason.Encoder` — serialize in a view or JSON layer
instead. A derived encoder welds the schema's fields to a wire format: adding a
field silently changes every API response, and every caller is forced through
the one shape the schema picked.

```elixir
# BAD — the schema knows about serialization
defmodule MyApp.User do
  use Ecto.Schema

  @derive {Jason.Encoder, only: [:id, :name]}
  schema "users" do
    field :name, :string
  end
end

# GOOD — a JSON layer owns the shape
defmodule MyAppWeb.UserJSON do
  def show(%{user: user}), do: %{id: user.id, name: user.name}
end
```

Scoped per module, not per file — only a `defmodule` whose own body contains
`use Ecto.Schema` (embedded schemas use the same module) is inspected, and a
nested `defmodule` without its own `use Ecto.Schema` is a separate scope. Every
spelling of both modules is caught, including aliases and `@derive` lists.
`defimpl Jason.Encoder` is out of scope — a `defimpl` is its own module and can
live in the JSON layer.

### `NoKernelPrefix`

`Kernel` is auto-imported — never prefix a `Kernel` function with the module
name. Every function in `Kernel` is already callable unqualified, so
`Kernel.inspect(value)` says nothing `inspect(value)` doesn't already say.

```elixir
# BAD
Kernel.inspect(value)
Kernel.length(list)

# GOOD
inspect(value)
length(list)
```

Operator captures are exempt as a readability allowance — `&Kernel.+/2`,
`&Kernel.>=/2`, `&Kernel.!/1` read the intent more plainly than requiring a
reader to know which operators can also be captured bare. A capture of a
named function (`&Kernel.inspect/1`) is not exempt: `&inspect/1` already
works unqualified, so it is flagged like the call form.

An operator used in *call* form is never flagged, in any position —
`Kernel.++(a, b)`, `list |> Kernel.<>(suffix)` are the only valid spellings
for calling those operators outside of infix position; `++(a, b)` and
`and(a, b)` are `SyntaxError`s, so there is no "call it directly" fix to
suggest. `not/1` is an ordinary function, not an operator in this sense, and
keeps being flagged. A file that locally shadows a `Kernel` function via
`import Kernel, except: [to_string: 1]` is honored automatically — that exact
name/arity is not flagged, because the unqualified fix would silently call
the file's own same-named function instead.

The module must resolve to exactly `Kernel` — `Kernel.SpecialForms` and
`Kernel.ParallelCompiler` are never flagged, and aliasing/shadowing is
resolved the same way as every other check in this package.

`LoggerModulePrefixAndInspect` tolerates `Kernel.inspect(value)` inside a
Logger call (it matches qualified spellings on the function name). This check
tightens that outside of Logger messages.

`:"Elixir.Kernel".inspect(value)` and `apply(Kernel, :inspect, [value])` call
the same banned function but evade detection — neither matches the
`__aliases__` shape the check keys on.

| Param | Default | Meaning |
|---|---|---|
| `allowed_functions` | `[]` | Function name atoms allowed to keep the `Kernel.` prefix anyway |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `NoMixEnvAtRuntime`

`Mix.env()` and `Mix.target()` must not be called from compiled code. Mix is a build
tool — it is not part of a release, so a call that compiles fine in dev crashes in
prod with `UndefinedFunctionError`.

```elixir
# BAD — crashes in a release
def start_link(opts) do
  if Mix.env() === :prod, do: connect(opts), else: :ignore
end

# GOOD — decided at compile time via config
@start_mode Application.compile_env(:my_app, :start_mode, :ignore)
```

`.exs` files (mix.exs, config, tests) are exempt. Modules that `use Mix.Task` are
exempt regardless of path; `excluded_paths` fragments match on path-segment
boundaries, so `mix/tasks/` does not exempt `lib/vendor/remix/tasks/`.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:env, :target]` | Mix functions that count as build-env access |
| `excluded_paths` | `["mix/tasks/"]` | Path fragments treated as Mix-only code (segment-boundary matched) |

### `NoMockingLibraries`

Mocking libraries must not be used — define a behaviour and inject the
implementation instead. Mocks couple tests to call sequences instead of contracts,
and their global or process-wide stubbing breaks down under async tests.

```elixir
# BAD
Mox.defmock(MyApp.ClientMock, for: MyApp.Client)

# GOOD — behaviour + injected test implementation
defmodule MyApp.TestClient do
  @behaviour MyApp.Client
  def fetch(id), do: {:ok, %{id: id}}
end
```

Module names are matched on exact segments with full alias resolution — a project
module that merely contains a banned name (`MyApp.MockingBird`, `MyApp.Mock`) is
never flagged, while `alias Mox, as: M` still is. A locally defined module also
shadows a banned bare name, but only the single segment that Elixir's own
implicit nested-module aliasing actually introduces: a nested, single-segment
`defmodule Mock do ... end` shadows `Mock` outright, and a nested, dotted
`defmodule Bar.Baz do ... end` shadows only its first segment (`Bar`), not
`Baz`. A *top-level*, dotted `defmodule MyApp.Mock do ... end` shadows nothing
at all. Only the bare spelling is ever shadowed — the fully-qualified
`Elixir.Mock` spelling still reports.

| Param | Default | Meaning |
|---|---|---|
| `modules` | `[Mox, Hammox, Mock, Mimic, Patch]` | Elixir mocking libraries to ban |
| `erlang_modules` | `[:meck]` | Erlang mocking modules to ban |

### `NoNilComparison`

Comparing against `nil` must use `is_nil/1`, not an equality operator. `is_nil/1`
says exactly what is being asked, works in guards, and is the required spelling in
Ecto queries.

```elixir
# BAD
def missing?(value), do: value == nil
def fallback(value) when value === nil, do: :default

# GOOD
def missing?(value), do: is_nil(value)
def fallback(value) when is_nil(value), do: :default
```

| Param | Default | Meaning |
|---|---|---|
| `operators` | `[:==, :!=, :===, :!==]` | Operators that count as a nil comparison when either operand is the `nil` literal |

### `NoObanInsertBang`

`Oban.insert!/1,2,3` and `Oban.insert_all!/1,2,3` must not be used in application
code. `Oban.insert!` raises on failure — a changeset error, a database blip — taking
down the calling process. `Oban.insert/1` returns `{:ok, job} | {:error, reason}`,
which lets the caller decide how to respond instead of crashing.

```elixir
# BAD — a changeset error crashes the caller
def enqueue(id), do: Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))

# GOOD — the caller decides how to respond
def enqueue(id) do
  with {:ok, _job} <- Oban.insert(MyApp.Workers.Sync.new(%{id: id})), do: :ok
end
```

Every spelling of the module is caught, including `alias Oban, as: MyOban` and the
fully-qualified `Elixir.Oban.insert!(...)`, and Mix tasks are in scope. `Oban.insert_all!/1,2,3`
does not exist on Oban 2.19–2.22 — `Oban.insert_all/1..3` has no bang variant and
raises by design instead (documented for use inside `Repo.transaction/2` rollback),
so it is deliberately not flagged. The entry stays in the default `:functions` list
only so a future Oban release adding a real bang variant is caught without a config
change.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:insert!, :insert_all!]` | `Oban` functions that count as a raising insert |
| `excluded_paths` | `["_test.exs", "test/", "priv/repo/seeds"]` | Path fragments exempt from the check (segment-boundary matched) — a bang insert is legitimate test/seed setup |

### `NoPhxBindingsInHoloTemplate`

A `~HOLO` template must not use Phoenix's `phx-*` bindings or EEx tags —
Hologram has its own template syntax. Hologram templates bind events with
`$click`/`$change`/`$submit` and interpolate with `{@var}`; both `phx-*`
attributes and `<%= %>`/`<% %>` EEx tags are Phoenix.LiveView/HEEx syntax that
Hologram's compiler does not understand — they render as literal text rather
than doing anything.

```elixir
# BAD
defmodule MyApp.ProductPage do
  use Hologram.Page

  def template, do: ~HOLO(<button phx-click="save"><%= @label %></button>)
end

# GOOD
defmodule MyApp.ProductPage do
  use Hologram.Page

  def template, do: ~HOLO(<button $click="save">{@label}</button>)
end
```

Scoped per module, not per file — only a `defmodule` whose own body contains
`use Hologram.Page`/`use Hologram.Component` is inspected, and within it only
`~HOLO` sigil bodies; a `~H` (HEEx) sigil living side-by-side is left alone
(see `NoHeexSigilInHologramModule`, which bans the sigil itself). One issue is
reported per offending match, at the line inside the template where it
occurs — not the line of the `~HOLO` sigil itself.

A valueless binding (`<div phx-no-format>`, with no trailing `=`) is not
detected, and colocated `.holo` template files get zero coverage — Credo
parses only `.ex`/`.exs` files, and Hologram supports `.holo` files as a
first-class alternative to `def template`.

| Param | Default | Meaning |
|---|---|---|
| `hologram_modules` | `[Hologram.Page, Hologram.Component]` | Modules whose `use` marks a `defmodule` as a Hologram module |
| `excluded_paths` | `[]` | Path fragments to exempt from the check (segment-boundary matched) |

### `NoProcessSleepInTests`

Tests must not sleep — sleeping is the number one source of flaky, slow suites. A
sleep guesses how long the system needs; the guess is either too short (flaky under
load) or too long (slow suite). Synchronize on the event itself.

```elixir
# BAD — guesses that 100ms is enough
Orders.update_status(order, :shipped)
Process.sleep(100)
assert_received {:order_updated, _}

# GOOD — waits exactly as long as needed, up to a deadline
Orders.update_status(order, :shipped)
assert_receive {:order_updated, _}, 500
```

Some suites keep a directory of timing fixtures that legitimately sleep (a fake
clock, a poller driving a real external service). Exempt just those directories
with `:excluded_paths` instead of disabling the whole check.

| Param | Default | Meaning |
|---|---|---|
| `test_files` | `["_test.exs"]` | Path suffixes the check runs on — everything else is skipped |
| `functions` | `[{Process, :sleep}, {:timer, :sleep}]` | Sleep functions to flag |
| `excluded_paths` | `[]` | Path fragments exempt from the check (segment-boundary matched) |

### `NoRawEts`

Raw `:ets` must not be used for caching — wrap it in `Cache.ETS` from
[`elixir_cache`](https://github.com/MikaAK/elixir_cache) instead. `:ets.new/2`,
`:ets.insert/2`, and `:ets.lookup/2` reimplement what `elixir_cache` already
provides with TTL, sandboxing, and a consistent API.

```elixir
# BAD
table = :ets.new(:price_cache, [:set, :named_table, read_concurrency: true])
:ets.insert(table, {"AAPL", 150.25})

# GOOD
defmodule MyApp.PriceCache do
  use Cache, adapter: Cache.ETS, name: :price_cache, sandbox?: Mix.env() === :test
end
```

This check scans test files as well as `lib/` — a raw `:ets` table in a test
fixture breaks the same async-safety guarantees a `Cache` sandbox provides.
Diagnostic-only functions (`:ets.info/1,2`, `:ets.whereis/1`, `:ets.all/0`) are
always allowed.

**Limitations.** This check is architectural, not universal — the
`elixir-distributed` feed-server pattern legitimately builds its whole design
on raw `:ets` for lock-free, high-read shared state. Adopters running feed
servers should add those paths to `excluded_paths` before enabling this
check — treat it as opt-in, not default-on, in any repo that owns a feed
server. `apply(:ets, :insert, [table, entry])` and `mod = :ets;
mod.insert(...)` are both undetected — only a literal `:ets.function(...)`
dot-call is matched.

| Param | Default | Meaning |
|---|---|---|
| `erlang_modules` | `[:ets]` | Erlang modules banned as raw in-memory stores — add `:dets` or `:persistent_term` to widen the ban |
| `allowed_functions` | `[:info, :whereis, :all]` | Functions on a banned module that are never flagged |
| `excluded_paths` | `["elixir_cache/"]` | Path fragments naming files exempt from the check (matched on segment boundaries) |

### `NoRawMarkupInTemplates`

Raw HTML primitives inside a `~H`/`~F` template body must go through the project's
design system instead of being hand-rolled. A literal `style="..."` attribute, a
hardcoded hex color, or an inline `<svg>` bypasses the Tailwind theme / design
tokens / icon component the rest of the app relies on.

```elixir
# BAD
~H"""
<div style="width: 30%">
  <svg viewBox="0 0 24 24"><path d="M0 0"/></svg>
  <span class="bg-[#1d4ed8]">badge</span>
</div>
"""

# GOOD
~H"""
<div class="w-1/3">
  <.icon name="check" />
  <.badge tone="info">badge</.badge>
</div>
"""
```

Four independent rules toggle via `:rules`: `:inline_style` (a literal
`style="..."` — a dynamic `style={...}` expression is allowed by default),
`:hex_color` (a 6-digit hex color — 3-digit is deliberately not matched, since
`href="#abc"` anchor fragments are indistinguishable from it; a `#` preceded
by `"` or `=` is also excluded, so `href="#abcdef"` doesn't fire either),
`:inline_svg` (a literal `<svg` tag), and `:raw_tag` (any tag name in
`:banned_tags`, empty by default so it is a no-op until a repo opts specific
tags in).

| Param | Default | Meaning |
|---|---|---|
| `rules` | `[:inline_style, :hex_color, :inline_svg, :raw_tag]` | Which markup rules run |
| `banned_tags` | `[]` | Raw tag names flagged by `:raw_tag` (e.g. `["button"]`) |
| `allow_dynamic_style` | `true` | When `true`, a dynamic `style={...}` expression is allowed |
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies |
| `excluded_paths` | `["icons/"]` | Path fragments whose files are skipped entirely |
| `excluded_app_suffixes` | `["_icons"]` | App directory NAME suffixes, matched per path segment (e.g. `apps/tiingo_icons/`) — the app that legitimately owns raw `<svg>` markup |

**Limitations.** Credo only lints `.ex`/`.exs` files — **a `.html.heex` template
file is never read by Credo** (`Credo.Sources.@default_sources_glob` is
`~w(** *.{ex,exs})`), so this check is blind to every `.html.heex` file. Only
`~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are covered.

Every rule scans the raw template body text — there is no HTML parser, so
matches have no notion of markup structure. Measured false positives: `<svg`
inside an HTML comment still fires (`<!-- <svg>...</svg> -->` reads as
markup, not a comment), and `style="` appearing inside prose text still
fires (`<p>Use the style="..." attribute.</p>`). Measured false negative: an
8-digit CSS4 alpha hex color (`#1d4ed8ff`) does not fire — the trailing `\b`
after the 6 captured digits requires a non-word character next, and the
extra two hex digits are themselves word characters.

A `#` inside a `~H`/`~F` heredoc is template string content, not a comment
token, so neither a HEEx-comment-wrapped pragma inside the sigil nor a plain
`# credo:disable-for-next-line` placed directly above the `~H"""` line ever
suppresses an issue reported from inside the body — the issue's line is
inside the template, past both anchors. This is measured, not theoretical:
both forms below still fire.

```heex
<%!-- # credo:disable-for-next-line MikaCredoRules.NoRawMarkupInTemplates --%>
<svg viewBox="0 0 24 24">...</svg>
```

Suppress an issue reported inside a sigil with one of the two mechanisms that
scope by line count or by file, placed above the enclosing `def`:

```elixir
# credo:disable-for-lines:5 MikaCredoRules.NoRawMarkupInTemplates
def render(assigns) do
  ~H"""
  <svg viewBox="0 0 24 24">...</svg>
  """
end
```

or, for a whole file, `# credo:disable-for-this-file MikaCredoRules.NoRawMarkupInTemplates`.
This applies to every check that scans a `~H`/`~F` body, not just this one —
`MonolithicTemplateComponent`, `NoClickHandlerOnNonInteractiveElement`, and
`PhxValueNoDashes` share the same suppression behavior.

### `NoReimplementedHelper`

Helpers that already exist in a shared library must not be reimplemented locally.
Generic data helpers get re-inlined as private functions over and over, and each
copy drifts from the tested shared implementation. The issue message points at the
canonical helper to call instead.

```elixir
# BAD — local copy of a shared helper
defp atomize_keys(map) do
  Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
end

# GOOD
def process(map), do: SharedUtils.Enum.atomize_keys(map)
```

The shared workspace has **three divergent `SharedUtils` libraries** (one per
umbrella app), not one. The `:functions` default targets their common core — every
pointer is ground-truthed against all three trees, and a pointer only needs to
resolve in at least two of them to make the default. A repo whose `SharedUtils`
carries extra helpers, or lacks one of the defaults, should override `:functions`
with its own pointer map; the suggested override below adds the tree-specific
extras this package verified as real but didn't judge common enough to default on.

```elixir
functions: %{
  # ...defaults, plus:
  apply_defaults: "SharedUtils.Map.apply_defaults/2",
  keys_to_strings: "SharedUtils.Map.keys_to_strings/1",
  deep_reject_nil_values: "SharedUtils.Enum.deep_reject_nil_values/1",
  reject_empty_values: "SharedUtils.Enum.reject_empty_values/1",
  ensure_map: "SharedUtils.Enum.ensure_map/1",
  intersection: "SharedUtils.Enum.intersection/2",
  difference: "SharedUtils.Enum.difference/2",
  map_values: "SharedUtils.Enum.map_values/2",
  to_serializable_map: "SharedUtils.Enum.to_serializable_map/2",
  nilify_keys: "SharedUtils.Enum.nilify_keys/2",
  sort_by_date: "SharedUtils.Collection.sort_by_date/3",
  from_deep_struct: "SharedUtils.Collection.from_deep_struct/1",
  remove_spaces: "SharedUtils.String.remove_spaces/2",
  to_lower_kebab_case: "SharedUtils.String.to_lower_kebab_case/1",
  to_bool: "SharedUtils.String.to_bool/1",
  to_number: "SharedUtils.String.to_number/1",
  slugify: "SharedUtils.String.slugify/1",
  maybe_add_port: "SharedUtils.String.maybe_add_port/2",
  days_between: "SharedUtils.DateTime.days_between/2",
  start_of_day: "SharedUtils.DateTime.start_of_day/1",
  start_of_year: "SharedUtils.DateTime.start_of_year/1",
  same_day?: "SharedUtils.DateTime.same_day?/2",
  equal_till_second?: "SharedUtils.DateTime.equal_till_second?/2",
  humanize: "SharedUtils.DateTime.humanize/1",
  beginning_of_next_month: "SharedUtils.Date.beginning_of_next_month/1",
  end_of_next_month: "SharedUtils.Date.end_of_next_month/1",
  next_month: "SharedUtils.Date.next_month/1",
  add_months: "SharedUtils.Date.add_months/2",
  deep_ls: "SharedUtils.File.deep_ls/1",
  deep_relative_ls: "SharedUtils.File.deep_relative_ls/1",
  url_safe_encode64: "SharedUtils.Base.url_safe_encode64/1",
  url_safe_decode64: "SharedUtils.Base.url_safe_decode64/1",
  humanize_ms: "SharedUtils.TimeConversion.humanize_ms/1",
  payload_keys_to_strings: "SharedUtils.Enum.stringify_keys/1"
}
```

These extras were verified present in `trader_fira_umbrella` and
`notification_platform_umbrella`, absent from `cheddar_flow_ex_umbrella`.
`wrap` was deliberately left out of this list — it measured as a false positive
against a `SharedUtils.Collection.wrap/2` in `trader_fira_umbrella` that is a
domain-specific pivot helper, not a generic "wrap in a list" utility, so banning
a local `wrap/N` would misdirect on unrelated code.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `%{atom_if_exists: "String.to_existing_atom/1", atomize_keys: "SharedUtils.Enum.atomize_keys/1", atomize_params: "SharedUtils.Enum.atomize_keys/1", deep_merge: "SharedUtils.Map.merge_deep_left/2", deep_struct_to_map: "SharedUtils.Map.deep_struct_to_map/1", deep_transform: "SharedUtils.Enum.deep_transform/2", drop_nil_values: "SharedUtils.Enum.reject_nil_values/1", pluck: "SharedUtils.Collection.pluck/2", random_string: "SharedUtils.String.generate_random/1", reject_nil_values: "SharedUtils.Enum.reject_nil_values/1", stringify_keys: "SharedUtils.Enum.stringify_keys/1", title_case: "SharedUtils.String.title_case/1", valid_email?: "SharedUtils.String.valid_email?/1"}` | Banned local function names → the shared helper to use instead. Overriding replaces the whole map. `atom_if_exists` points at `String.to_existing_atom/1` (what `atomize_keys/1` calls internally for one key), not `atomize_keys/1` itself, which takes an enumerable. |
| `excluded_paths` | `["shared_utils/"]` | Path fragments exempt from the check (segment-boundary matched) — the shared library itself defines the canonical implementations. The trailing `/` keeps a lookalike file, such as `apps/my_app/lib/my_app/shared_utils.ex`, covered by the check. |

Only `def`/`defp` are matched — `defmacro`/`defmacrop` are not. `drop_nil_values`
and `reject_nil_values` both point at `SharedUtils.Enum.reject_nil_values/1`, which
is map-only in `cheddar_flow_ex_umbrella` but also accepts a list in the other two
trees — passing a list on the map-only tree raises `FunctionClauseError`.

### `NoRepoWritesInTests`

Tests must not write to the database directly — use `FactoryEx` for test data. A
raw `Repo.insert!/1` in a test hardcodes every required association and default
inline, so it silently drifts from the schema's real constraints. `FactoryEx`
centralizes that shape in one factory module every test shares.

```elixir
# BAD
{:ok, user} = Repo.insert(%User{email: "a@b.c"})
Repo.insert_all(Order, rows)
%User{email: "a@b.c"} |> Repo.insert!()

# GOOD
user = FactoryEx.insert!(MyApp.Support.Factory.User)
```

Reads are left alone — asserting on persisted state is the correct way to pin a
behavioural test (`Repo.get/2`, `Repo.all/1`, `Repo.one/1`, `Repo.preload/2` never
fire). A repo is identified two ways: any `__aliases__` path whose last segment is
`:Repo` (`MyApp.Repo`, `Repo`, `Schemas.Repo`) — no alias tracking needed for a
plain `alias MyApp.Repo`, since that preserves the last segment — plus any module
named in `:repo_modules`, alias-resolved for repos that are not named `Repo` at
all.

This is the complement of blitz `NoRampantRepos`, which excludes every `.exs` file
and so never sees a single one of these — run both.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:insert, :insert!, :insert_all, :update, :update!, :update_all, :delete, :delete!, :delete_all, :insert_or_update, :insert_or_update!]` | Write-side `Ecto.Repo` functions to flag |
| `repo_modules` | `[]` | Additional repo modules to treat as write targets, for repos not named `Repo`. Alias-resolved via `AstHelpers.resolve_aliases/2` |
| `test_files` | `["_test.exs"]` | Path suffixes the check runs on — everything else is skipped |
| `excluded_paths` | `["test/support/"]` | Path fragments exempt from the check (segment-boundary matched) — factories and `DataCase` helpers legitimately write |

**Limitations:** a repo with no `FactoryEx` setup at all will fail every one of
these issues with no path forward — ship this opt-in rather than in a
recommended-default bundle until `FactoryEx` is wired up. `alias MyApp.Repo, as:
DB` renames the last segment, so a bare `DB.insert!/1` call is a false negative
under the default heuristic — name the real module in `:repo_modules`
(`repo_modules: [MyApp.Repo]`) to catch it too, reported as `DB.insert!`. A
cleanup call in `setup`/`on_exit` (`Repo.delete_all(User)`) still fires, but "use
FactoryEx for test data" is not the fix for teardown — deleting test rows
directly there is legitimate. Only a literal alias at the call site is
recognised: `@repo.insert!()`, `repo().insert!()`, `apply(Repo, :insert!, [x])`,
and `Ecto.Adapters.SQL.query!(Repo, "DELETE ...", [])` are all undetected.

### `NoSelfSendZeroDelay`

`Process.send_after(self(), _, 0)` and `send(self(), _)` in `init/1` schedule a
message to yourself with no delay so a later callback can do the real work — that
is exactly what `{:continue, term}` is for. `GenServerRequiresHandleContinue`
allow-lists `Process.send_after` in `init/1` because a *nonzero* delay is a
genuine timer; this check closes the zero-delay gap that allowance leaves open.

```elixir
# BAD — indirection for exactly what a continue does directly
def init(opts) do
  Process.send_after(self(), :load, 0)
  {:ok, opts}
end

# GOOD
def init(opts), do: {:ok, opts, {:continue, :load}}
def handle_continue(:load, state), do: {:noreply, do_load(state)}
```

`Process.send_after(self(), _, 0)` is flagged everywhere it appears, regardless
of whether the file uses GenServer. `send(self(), _)` in `init/1` is scoped to
`use GenServer` modules and gated behind `:also_flag_send_self_in_init`.

| Param | Default | Meaning |
|---|---|---|
| `also_flag_send_self_in_init` | `true` | Also flag `send(self(), _)` inside `init/1` of a `use GenServer` module |
| `excluded_paths` | `[]` | Path fragments naming files to skip entirely (segment-boundary matched) |

### `NoServerCodeInHologramAction`

A Hologram action must not call the server, touch sessions/cookies, or use a
form the client compiler doesn't implement yet — actions run entirely in the
browser. Work that needs any of those belongs in a command, dispatched via
`put_command/2,3` and returned to the client through `put_action/2,3`.

```elixir
# BAD — hits the database from the client
defmodule MyApp.ProductPage do
  use Hologram.Page

  def action(:save, params, component) do
    MyApp.Repo.insert(%Product{name: params.name})
  end
end

# GOOD — defers the write to a command
defmodule MyApp.ProductPage do
  use Hologram.Page

  def action(:save, params, component) do
    put_command(component, :save_product, name: params.name)
  end

  def command(:save_product, params, server) do
    MyApp.Repo.insert(%Product{name: params.name})
    server
  end
end
```

Three independent things are flagged inside a `def action(...)` clause of
arity 3 (one issue per offending node): a call on a banned module (actions run
client-side only), a local call to a session/cookie function (only available
in `init/3` and `command/3`), and a `with`/`try`/`receive` form (not
implemented in Hologram's client compiler as of version 0.8.3). Scoped per
module and per callback — `command/3` and `init/3` run on the server and are
exempt; a plain context function called from an action is not itself flagged.

`:banned_forms` covers the explicit `try do ... end` block only, not the
implicit `def action(...) do ... rescue ... end` form — Hologram's
unsupported-forms list is expected to change across versions, so every entry
is a param.

| Param | Default | Meaning |
|---|---|---|
| `hologram_modules` | `[Hologram.Page, Hologram.Component]` | Modules whose `use` marks a `defmodule` as a Hologram module |
| `action_callbacks` | `[:action]` | Function names treated as client-side action callbacks (arity 3 only) |
| `banned_modules` | `[Repo, Ecto, Ecto.Query, Oban, File, IO, Port, Process, System, Node, SharedUtils.HTTP, Finch, Req, HTTPoison]` | Modules banned from an action. `Repo` matches by its LAST segment (so `MyApp.Repo.insert/1` is caught without listing every app's repo module); `Ecto` matches BY PREFIX (so `Ecto.Changeset`, `Ecto.Multi`, and every other `Ecto.*` submodule are caught); every other entry matches its exact, alias-resolved path |
| `banned_functions` | `[:get_session, :put_session, :delete_session, :get_cookie, :put_cookie, :delete_cookie]` | Local session/cookie function names banned from an action |
| `banned_forms` | `[:with, :try, :receive]` | Special forms not usable inside an action because Hologram's client compiler does not implement them yet |

### `NoSingleLetterVariables`

Variables must not be named with a single letter — the name should say what the
value is. Only binding sites are reported (function heads, `fn` clauses,
`case`/`receive` patterns, `=` matches, comprehension generators); `_` and
`_`-prefixed names are always allowed, and typespec type variables, `cond` heads and
`receive`-`after` heads are correctly ignored.

```elixir
# BAD
def double(x), do: x * 2
Enum.map(users, fn u -> u.name end)

# GOOD
def double(number), do: number * 2
Enum.map(users, fn user -> user.name end)
```

Names longer than a single letter that still carry no meaning — acronyms such as
`cs` or `sf` rather than words — can be banned the same way through
`:banned_names`, reported at the same binding sites and with the same
underscore-prefix exemption.

| Param | Default | Meaning |
|---|---|---|
| `allowed_names` | `[]` | Single-letter names allowed anyway — atoms or strings |
| `banned_names` | `[]` | Additional variable names flagged at binding sites, whatever their length — atoms or strings, e.g. project-specific abbreviations you have banned. A name in both `:banned_names` and `:allowed_names` is still flagged — `:banned_names` wins. A single-letter name in `:banned_names` is reported as a single-letter violation, not a banned name, since that check runs first. |

### `NoVacuousAssert`

Assertions must exercise real behaviour, never a hardcoded literal. `assert true`,
`assert :ok`, `refute false` always pass regardless of what the test does — they
are placeholders that survived past the point a real assertion should have
replaced them. `assert x === x` is the same trap wearing an operator: it
compares a value to itself, so it can never fail.

```elixir
# BAD
assert true
assert :ok
refute false
refute nil
assert Orders.status(order) === Orders.status(order)

# GOOD
assert Orders.status(order) === :shipped
```

A bare variable or a function call is never flagged — `assert some_call()` and
`assert x` are legitimate assertions on a value computed elsewhere.

`assert x == x` with a bare-variable left-hand side is also caught by Credo's
own default-on `Credo.Check.Warning.OperationOnSameValues` — measured: it does
not flag `assert x === x` or a function-call comparison like
`assert Orders.status(order) === Orders.status(order)`, only bare-variable
`==`, so the overlap is narrow. Disable the stock check for the `==` case if
the double report is unwanted:

```elixir
checks: %{
  enabled: [{MikaCredoRules.NoVacuousAssert, []}],
  disabled: [{Credo.Check.Warning.OperationOnSameValues, []}]   # superseded for asserts
}
```

Disabling it also drops its unrelated coverage of `x >= x`, `x != x`, `y / y`,
etc. outside of `assert`/`refute` — only disable it if that coverage isn't
otherwise wanted.

| Param | Default | Meaning |
|---|---|---|
| `test_files` | `["_test.exs"]` | Path suffixes the check runs on — everything else is skipped |

**Limitation:** `assert f() === f()` with an impure `f` (timestamps, random
values, a counter) is a deliberate determinism/memoization test and will be
flagged — the check compares AST shape, not runtime purity.

### `NoWordSigilLists`

Word lists must be written as list literals, never the `~w`/`~W` sigil. `~w(a b)`
and `["a", "b"]` compile to the identical list — the sigil saves a few characters
of quoting and costs more than it saves: it isn't greppable for a specific
element, and `~w(a b)a` vs `~w(a b)` differ by one easily-missed trailing `a`
where `[:a]` vs `["a"]` cannot be misread.

```elixir
# BAD
@enforce_keys ~w(id type changes)a
Map.take(changes, ~w(customer_id customer_name))

# GOOD
@enforce_keys [:id, :type, :changes]
Map.take(changes, ["customer_id", "customer_name"])
```

**Volume warning:** this rule is absolute, not situational — every existing
`~w`/`~W` site in a mature codebase is reported the first time this check is
enabled. Adopt with a baseline (fix the reported sites, or exempt legacy
directories through `:excluded_paths`) rather than expecting a clean run
immediately.

| Param | Default | Meaning |
|---|---|---|
| `sigils` | `[:sigil_w, :sigil_W]` | Sigil node atoms to ban |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `NoTruthyAndOr`

`and`/`or`/`not` must not be used on a provably-nilable operand. `and` and `or`
require a strictly boolean operand and raise `BadBooleanError` the moment either
side is `nil`; `not` requires the same and raises `ArgumentError` instead.
`opts[:key]`, `Map.get/2`, `Keyword.get/2`, and `List.first/1` all evaluate to
`nil` when the value is absent.

```elixir
# BAD — crashes with BadBooleanError when opts[:key] is nil
if opts[:llm_merge] or opts[:ai_review], do: ...

# GOOD — ||/&&/! handle nil/falsy operands
if opts[:llm_merge] || opts[:ai_review], do: ...
```

`Map.get/3`/`Keyword.get/3` are only flagged when the default argument is the
literal `nil` — a non-nil default means the result can never be `nil` and is not
flagged. Plain variables, ordinary function calls, and comparisons are never
flagged. One issue is emitted per `and`/`or`/`not` node, not per nilable
operand — `opts[:a] and opts[:b]` reports once, `a and b and c` reports twice.

`test/support/` is excluded by default — Phoenix/Ecto generator files
(`data_case.ex`, `conn_case.ex`, `feature_case.ex`) commonly write `shared: not
tags[:async]`, and ExUnit guarantees `:async` is always a boolean by the time
this runs, so that specific shape can never raise there.

| Param | Default | Meaning |
|---|---|---|
| `nilable_functions` | `[{Access, :get, 2}, {Map, :get, 2}, {Keyword, :get, 2}, {List, :first, 1}, {Map, :get, 3}, {Keyword, :get, 3}]` | `{module, function, arity}` shapes that count as provably nilable — `{Access, :get, 2}` also covers `x[:k]` bracket syntax |
| `excluded_paths` | `["test/support/"]` | Path fragments exempt from the check (segment-boundary matched) |

### `ObanWorkerRequiresMaxAttempts`

`use Oban.Worker` must set `:max_attempts` explicitly. Oban silently falls back to
its own retry default when `:max_attempts` is omitted, but different job shapes
need different attempt counts — a worker that never states its count is a worker
nobody has actually thought about.

```elixir
# BAD — relies on whatever Oban currently defaults to
defmodule MyApp.Workers.SyncOrder do
  use Oban.Worker, queue: :orders
end

# GOOD — the attempt count is a deliberate part of the worker's contract
defmodule MyApp.Workers.SyncOrder do
  use Oban.Worker, queue: :orders, max_attempts: 3
end
```

Every spelling of the module is caught, including `alias Oban.Worker` and the
fully-qualified `Elixir.Oban.Worker`. `:unique` is deliberately not required by
default — pick it per worker, not by blanket rule. Only a literal keyword list in
the `use` clause is inspected; a non-literal option list (a module attribute or a
call that builds the options) is invisible to a static check and is silently
skipped rather than guessed at. `use Oban.Pro.Worker, ...` is a different module
and is invisible to this check.

| Param | Default | Meaning |
|---|---|---|
| `required_keys` | `[:max_attempts]` | `use Oban.Worker` options that must be present |
| `excluded_paths` | `["test/"]` | Path fragments exempt from the check — throwaway fixture workers under test/ |

### `NoStaticNotLoadedDropList`

A static drop-list must not be used to scrub `%Ecto.Association.NotLoaded{}`
values before serializing a schema. The list has no way to know about an
association added next sprint — the new field silently slips through and crashes
`Jason.encode!/1` at runtime. Reject unloaded associations by type instead.

```elixir
# BAD
@association_keys [:__meta__, :workspace, :sessions]
struct |> Map.from_struct() |> Map.drop(@association_keys)

# GOOD
struct
|> Map.from_struct()
|> Map.reject(fn {_key, value} -> match?(%Ecto.Association.NotLoaded{}, value) end)
|> Map.delete(:__meta__)
```

The `:__meta__` marker is what makes the trigger unambiguous — a list containing
`:__meta__` plus at least one other atom is a drop-list by construction.
`Map.drop(map, [:__meta__])` alone is fine. Both a literal list argument and a
module attribute holding one are caught, standalone and piped, and `Map` is
matched alias-aware.

| Param | Default | Meaning |
|---|---|---|
| `marker_key` | `:__meta__` | The atom that marks a drop-list as an association-scrubbing list |
| `excluded_paths` | `[]` | Path fragments (segment-boundary match) exempt from the check |

### `NoTaskAsyncInGenServer`

`Task.async` and `Task.Supervisor.async` must not be called from inside a
GenServer or GenStage callback. `Task.async/1,3` links the new task to the process
that calls it — inside a callback, that process IS the server, so a crashing task
takes the whole server down with it.

```elixir
# BAD — a crashing task takes the GenServer down with it
def handle_continue(:init_work, state) do
  task = Task.async(fn -> expensive_fetch(state.config) end)
  {:noreply, %{state | task_ref: task.ref}}
end

# GOOD — isolate the crash, handle it explicitly
def handle_continue(:init_work, state) do
  task = Task.Supervisor.async_nolink(MyApp.TaskSupervisor, fn -> expensive_fetch(state.config) end)
  {:noreply, %{state | task_ref: task.ref}}
end

def handle_info({ref, result}, %{task_ref: ref} = state) do
  Process.demonitor(ref, [:flush])
  {:noreply, %{state | task_ref: nil, data: result}}
end
```

There is no bare `Task.async_nolink/1,2` — only the supervised
`Task.Supervisor.async_nolink/2,3,4` exists, which needs a `Task.Supervisor`
already running in the app's supervision tree.

Only the bodies of callbacks are inspected — a public client-side function
defined in the same module runs in the caller's process, not the server's, and
may legitimately want the link `Task.async` provides, so it is never scanned.
`async` is matched by exact function name, never a prefix — `Task.async_stream/2`
is a different, unlinked API and is never flagged here.

| Param | Default | Meaning |
|---|---|---|
| `banned` | `[{Task, :async}, {Task.Supervisor, :async}]` | `{module, function}` pairs banned inside a callback body |
| `callbacks` | `[:init, :handle_call, :handle_cast, :handle_info, :handle_continue, :handle_events, :handle_demand, :terminate]` | Function names whose bodies are inspected |
| `behaviour_modules` | `[GenServer, GenStage]` | Modules whose `use` marks a file as worth scanning at all (alias-aware) |

### `NoUnsupervisedTaskStart`

`Task.start/1,3` must not be used — a crash inside the task is silently
discarded. Nothing supervises it and nothing is linked to it, so the failure
disappears with no log, no restart and no trace.

```elixir
# BAD — a crash here is silently lost
def notify(payload), do: Task.start(fn -> send_webhook(payload) end)

# GOOD — supervised; a crash is visible and can be handled
def notify(payload) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> send_webhook(payload) end)
end
```

`Task.start_link/1,3` links the caller instead of losing the crash silently — a
different, often intentional trade-off — so it is left alone by default.

| Param | Default | Meaning |
|---|---|---|
| `also_flag_start_link` | `false` | Also flag `Task.start_link/1,3` |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files to skip (segment-boundary matched) |

### `NoTelemetrySupervisorModule`

A dedicated `*Telemetry` supervisor module must not exist — add a
`{PrometheusTelemetry, ...}` child spec to `application.ex` instead. `phx.new`
generates a `MyAppWeb.Telemetry` supervisor wrapping `:telemetry_poller`; the
house convention starts `PrometheusTelemetry` directly as a child of the
application, so the separate supervisor module only adds indirection.

```elixir
# BAD — the file phx.new generates
defmodule MyAppWeb.Telemetry do
  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
end

# GOOD — a child spec in application.ex, no separate supervisor module
children = [{PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: [...]}]
```

Flagged when a `defmodule`'s last name segment is a member of
`:module_suffixes` **and** its own body contains `use Supervisor`. Scoped per
module — a nested `defmodule Telemetry do ... end` is its own scope, the same
way `NoJasonDeriveOnEctoSchema` scopes `@derive`, and `use Supervisor` is
alias-aware: a project module shadowing the bare name (`alias MyApp.Supervisor`)
is correctly not treated as Elixir's `Supervisor`.

| Param | Default | Meaning |
|---|---|---|
| `module_suffixes` | `[:Telemetry]` | Last-segment module names inspected |
| `supervisor_modules` | `[Supervisor]` | Modules that count as the `Supervisor` behaviour in a `use` expression (alias-aware) |
| `excluded_paths` | `[]` | Path fragments exempt from the check (segment-boundary matched) |

### `PrometheusExporterMustBeGated`

The Prometheus exporter must not be hardcoded to `enabled?: true` — gate it to
production. An always-on exporter opens an HTTP endpoint in every environment
including dev and test; the idiomatic gate is a compile-time flag derived from
`Application.compile_env/3`.

```elixir
# BAD — exposed in every environment
@is_prod Application.compile_env(:my_app, :env) === :prod
{PrometheusTelemetry, exporter: [enabled?: true], metrics: [...]}

# GOOD
{PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: [...]}
```

Only a literal `enabled?: true` inside a keyword list or map literal is
flagged — a computed value (`enabled?: @is_prod`) always passes. `.exs`
files are always exempt, since `config/prod.exs` may legitimately hardcode
the flag for a single environment. A `case`/`fn` clause pattern and a
`@type`/`@spec` body are never inspected.

**Adopting this check:** the default `excluded_paths` covers `test/`, since
a test double whose entire purpose is a running exporter (a mock supervisor
under `test/support/`) is not production config and the suggested
`@is_prod` gate would break it. Add your own `test/`-adjacent fixture
directories to `excluded_paths` if they live outside that convention.

| Param | Default | Meaning |
|---|---|---|
| `keys` | `[:exporter]` | Outer keyword-list keys inspected for a hardcoded `enabled?: true` |
| `excluded_paths` | `["test/"]` | Path fragments exempt from the check (segment-boundary matched), in addition to the always-exempt `.exs` files |

**Known limitations:** a runtime concatenation (`exporter: [enabled?: true] ++
extra()`), a value built via `Keyword.put([], :enabled?, true)`, or a literal
assigned to a variable before being referenced (`conf = [enabled?: true];
exporter: conf`) all evade the check — the last is the realistic way a
hardcoded flag survives review, since the literal and the flagged key end up
on different lines.

### `PhxValueNoDashes`

A multiword `phx-value-*` attribute key must use underscores, never dashes.
LiveView takes the text after `phx-value-` verbatim as the param key —
`phx-value-group-id` becomes `%{"group-id" => ...}`, the dash is kept, not
converted. This never matches a `%{"group_id" => _}` clause; a handler
written the natural way, with underscored keys, raises a
`FunctionClauseError` when it receives the dashed key instead.

```elixir
# BAD — never matches a %{"group_id" => _} handler clause
~H"""
<button phx-click="delete" phx-value-group-id={@id}>Delete</button>
"""

# GOOD
~H"""
<button phx-click="delete" phx-value-group_id={@id}>Delete</button>
"""
```

Single-word keys (`phx-value-id`, `phx-value-kind`) are unaffected.

| Param | Default | Meaning |
|---|---|---|
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies |
| `excluded_paths` | `[]` | Path fragments whose files are skipped entirely |

**Limitations.** Same as `NoRawMarkupInTemplates` — only `~H`/`~F` sigils
colocated inside a `.ex`/`.exs` module are covered; a `.html.heex` file is
never read by Credo. Suppressing an issue inside a sigil body also works the
same as `NoRawMarkupInTemplates` — see its Limitations section for the two
escapes that actually work.

### `RefuteOverAssertNot`

Negated assertions must use `refute`, not `assert !` or `assert not`. `refute expr`
states "this must be falsy" directly and produces better failure output.

```elixir
# BAD
assert !valid?(user)
assert not valid?(user)

# GOOD
refute valid?(user)
```

`assert value not in collection` is left alone — the membership form is idiomatic.

| Param | Default | Meaning |
|---|---|---|
| `test_files` | `["_test.exs"]` | Path suffixes the check runs on |

### `SingleModulePerFile`

One top-level module per file. A file that defines several top-level modules
recompiles them together — anything depending on one is recompiled whenever any
co-located module changes, and mutual references between co-located modules can
grow into cycles the compiler cannot split apart.

```elixir
# BAD — two sibling modules in one file
defmodule MyApp.Worker do
  def run, do: :ok
end

defmodule MyApp.WorkerSupervisor do
  def start_link, do: :ok
end

# GOOD — a nested module belongs to its parent, never flagged
defmodule MyApp.Worker do
  defmodule State do
    defstruct [:status]
  end

  def run, do: :ok
end
```

Only top-level `defmodule`s count — a module nested inside another is part of
its parent. `defimpl` and `defprotocol` are never flagged, and `defmodule`
inside a `quote` block is skipped — a macro that generates a module defines it
at the call site. Test files are excluded by default.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["test/", "test/support/", "_test.exs"]` | Path fragments and filename suffixes exempt from the check (segment-boundary matched) |

### `SqlSandboxPlugMustBeCompileGated`

`plug Phoenix.Ecto.SQL.Sandbox` must be compile-gated — never shipped unguarded.
The sandbox plug hands any client that knows the header format control over the
request's database connection; it exists purely so feature tests can share a
transaction with the test process.

```elixir
# BAD — ships to prod
plug Phoenix.Ecto.SQL.Sandbox

# GOOD — gated on a flag only config/test.exs ever sets
if Application.compile_env(:my_web, :sql_sandbox, false) do
  plug Phoenix.Ecto.SQL.Sandbox
end
```

Every spelling of the module is caught, including a prefix alias (`alias
Phoenix.Ecto.SQL` then `plug SQL.Sandbox`). The gate's module is resolved the
same alias-aware way, so a shadowing `alias MyApp.Application` correctly stops
`if Application.compile_env(...)` from counting as a gate. A gate expressed
through a module attribute (`if @sandbox?`) is **not** recognised — see the
moduledoc's `## Known limitations` for the `# credo:disable-for-next-line`
escape.

| Param | Default | Meaning |
|---|---|---|
| `gate_functions` | `[{Application, :compile_env}]` | `{module, function}` pairs whose call, found in an enclosing `if`'s condition, counts as gating the plug |
| `excluded_paths` | `[]` | Path fragments naming files this check skips |

### `StrictEquality`

Comparisons must use `===`/`!==` instead of `==`/`!=`. `==` coerces across numeric
types — `1 == 1.0` is true — so a refactor that changes a value from integer to
float keeps every comparison silently passing. `===` fails loudly the moment types
drift.

```elixir
# BAD
if user.age == 18, do: ...

# GOOD
if user.age === 18, do: ...
```

The Ecto query DSL is exempt — `==`/`!=` are the only equality operators the query
compiler accepts. The exemption is scoped to the query call's own arguments, follows
`alias Ecto.Query` (including `as:` renames and multi-alias), and issues carry exact
column numbers, so a loose comparison on the same line as a query call is still
caught. `start_permanent: Mix.env() == :prod` in mix.exs is also exempt.

| Param | Default | Meaning |
|---|---|---|
| `ignored_functions` | `[:dynamic, :from, :where, :or_where, :having, :or_having, :select, :select_merge, :on, :join, :query, :subquery, :in]` | Calls whose arguments are exempt (the Ecto query DSL) |

### `TestOnlyDepsScoped`

A dev/test-only dependency must be scoped so it never ships to a release. A
tool like `:credo` or `:ex_doc` has no business running in production —
omitting `only:` pulls it (and its own transitive deps) into every
environment, and omitting `runtime: false` on a compile-time-only tool lets
it try to start an application that was never meant to run.

```elixir
# BAD — no only:, ships to every environment
defp deps do
  [
    {:credo, "~> 1.7"}
  ]
end

# GOOD — scoped to the environments it's actually needed in
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
  ]
end
```

`:test_only_packages` and `:require_runtime_false` are checked
independently — a package on both lists (e.g. `:wallaby`) missing both
options is reported twice, once per missing option. `only: :dev`, `only:
:test`, and `only: [:dev, :test]` all satisfy the first check, and every dep
shape is recognised: 2-tuple with a version, 3-tuple with a version and opts,
and the opts-only 2-tuple git/path form.

**Limitation:** the `only:` check only rejects values that still include
`:prod` — it does not validate against a fixed list of "real" environments,
so an unconventional atom like `only: :nonsense` satisfies it just as well
as `only: :test`, since both keep the dependency out of a production
release.

This package's own `.credo.exs` drops `:credo` from `:test_only_packages`:
`mika_credo_rules`'s modules `use Credo.Check`, so `:credo` must compile in
every environment this package itself compiles in — `runtime: false` alone
is the correct scoping here, unlike for a normal consumer.

| Param | Default | Meaning |
|---|---|---|
| `mix_files` | `["mix.exs"]` | Filenames (matched by basename) treated as mix.exs files |
| `test_only_packages` | `[:wallaby, :credo, :dialyxir, :mix_test_watch, :excoveralls, :ex_doc, :mika_credo_rules]` | Packages that must carry an `only:` option |
| `require_runtime_false` | `[:wallaby, :credo, :dialyxir, :ex_doc, :mika_credo_rules]` | Packages that must carry `runtime: false` |

### `TaskAsyncStreamRequiresTimeout`

`Task.async_stream/2,3` and `Task.Supervisor.async_stream/3,4` (and its
`async_stream_nolink` sibling) default to a 5-second-per-item timeout when no
`:timeout` option is given. One slow item then crashes the whole stream — pass
`timeout:` explicitly, even when the value is `:infinity`.

```elixir
# BAD — silently uses the 5s default and kills long batches
Task.async_stream(symbols, &process_one/1, max_concurrency: 5)

# BAD — no options argument at all
Task.async_stream(symbols, &process_one/1)

# GOOD
Task.async_stream(symbols, &process_one/1, max_concurrency: 5, timeout: 35_000)
```

Only a literal trailing options keyword list is inspected — options built by a
helper or held in a variable are invisible to this check, an accepted false
negative rather than a guess in either direction.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[{Task, :async_stream}, {Task.Supervisor, :async_stream}, {Task.Supervisor, :async_stream_nolink}]` | `{module, function}` pairs whose trailing options are checked |
| `excluded_paths` | `[]` | Path fragments naming files to skip (segment-boundary matched) |

### `TodosNeedTickets`

Every todo comment must reference a ticket URL on the same or an adjacent line. A
todo without a ticket has no owner, no priority and no deadline — it is a wish, not
a plan.

```elixir
# BAD — nothing tracks this
# TODO: make this faster

# GOOD — ticket adjacent to the todo
# TODO: make this faster
# https://linear.app/company/issue/443
```

Suppression is **per-todo**, not per-file — a URL elsewhere in the file does not
excuse an unticketed TODO. For `@doc`/`@moduledoc` todos, the URL must appear
somewhere in the same doc string.

Each tag matches as a whole word, not a prefix — a trailing letter, digit or
underscore means the comment is prose, not an annotation. `# TODOs remaining`
does not fire; `# TODO: remaining work` does. This is a behaviour change from
earlier versions, which treated a tag as a prefix and fired on ordinary words
like `hackney` or `reviewed`.

Setting `:require_uppercase` to `true` additionally requires the tag itself to be
spelled in uppercase and immediately followed by a colon — this is a formatting
check, independent of ticketing, so `# todo: ...` is reported even with a ticket
URL attached.

```elixir
# BAD (require_uppercase: true) — lowercase tag, reported even though ticketed
# todo: make this faster, see https://linear.app/company/issue/443

# GOOD (require_uppercase: true) — uppercase tag with a colon
# TODO: make this faster, see https://linear.app/company/issue/443
```

| Param | Default | Meaning |
|---|---|---|
| `tags` | `["TODO", "FIXME", "OPTIMIZE", "HACK", "REVIEW"]` | Tag words treated as todos (case-insensitive) |
| `ticket_url` | `"http"` | Substring a line must contain to count as a ticket reference — set to your tracker's URL prefix so only real tickets count |
| `require_uppercase` | `false` | When `true`, a tag must be uppercase and immediately followed by a colon (`TODO:`) — reported even when ticketed |

## Adopting incrementally

A repo that is green on stock Credo can still light up hundreds of issues on
these checks. That is an adoption in progress, not a failure — the deliverable is
"enable what passes, quantify the rest", never a mass rewrite.

1. **Prove the baseline.** `git stash push .credo.exs mix.exs mix.lock && mix credo && git stash pop` —
   old-config green means every new issue is attributable to these checks.
2. **Read the file count.** `running N checks on 0 files` means `included` matches
   nothing (`included` resolves relative to CWD, not the config file). Umbrella
   roots need `["lib/", "test/", "apps/*/lib/", "apps/*/test/"]`. Checks that
   inspect `mix.exs`, `.credo.exs` or `config/*.exs` need those paths listed too.
3. **Tier every check before fixing anything** (`MIX_ENV=test mix credo --strict --only MikaCredoRules.<Check>`):
   - **Free** (0 issues) — enable now; it locks in what the repo already does.
   - **Mechanical** (semantics-preserving rewrite — `NoNilComparison`,
     `RefuteOverAssertNot`, `StrictEquality`, `NoSingleLetterVariables`,
     `LoggerModulePrefixAndInspect`) — fix, then enable.
   - **Architectural** (`NoApplicationEnvOutsideConfig`, `ErrorMessageRequired`,
     `NoBlanketRescue`, `GenServerRequiresHandleContinue`, the accessor-routing
     checks) — defer; these change behaviour and ripple into tests.
4. **Defer honestly.** `{MikaCredoRules.Check, false}, # not yet adopted: N issues / M files — reason`
   in `.credo.exs`. Never mass-tune `excluded_paths` to fake a green — an enabled
   check that skips 70 files is worse than an honest `false`.
5. **Fix all sites or none.** A check with one remaining issue is exactly as
   deferred as one with fifty.
6. **Commit fixes first, the config enable last** — every commit green in isolation.

## Stock Credo checks worth enabling

Several house conventions are already covered by checks that ship with Credo but
are **off by default**. Enable them instead of writing (or asking for) a new check:

| Convention | Enable |
|---|---|
| Never `alias X.Y.Z, as: Name` | `Credo.Check.Readability.AliasAs` |
| Never pipe into `case`/`if`/`with` | `Credo.Check.Readability.BlockPipe` |
| Pipe chains start with a raw value | `Credo.Check.Refactor.PipeChainStart` |
| A single-op pipe is a direct call | `Credo.Check.Readability.SinglePipe` |
| Parentheses on one-arity functions in pipes | `Credo.Check.Readability.OneArityFunctionInPipe` |
| Module layout order | `Credo.Check.Readability.StrictModuleLayout` with `order: [:moduledoc, :behaviour, :use, :import, :require, :alias, :module_attribute, :defstruct, :type, :callback, :macrocallback, :optional_callbacks, :public_macro, :public_guard, :public_fun, :private_fun]` |
| Never `String.to_atom/1` on input | `Credo.Check.Warning.UnsafeToAtom` |
| `not is_nil(x)` reads better as `!is_nil` | `Credo.Check.Refactor.NegatedIsNil` |
| `async:` declared on every test case; `async: false` needs a comment | `Credo.Check.Refactor.PassAsyncInTestCases` with `force_comment_on_explicit_false: true` |
| A skipped test needs a comment | `Credo.Check.Design.SkipTestWithoutComment` |
| `@spec` on public functions | `Credo.Check.Readability.Specs` |
| Ban a module outright (alias-blind) | `Credo.Check.Warning.ForbiddenModule` — `NoDirectHttpClient` / `NoRawEts` exist because they add alias resolution, path exemptions and a fix pointer |

Two conventions are enforced by the compiler under `--warnings-as-errors` and need
no check: rebinding a variable inside an `if`/`case` block (unused-variable
warning) and `@doc` on a `defp`.

If [`blitz_credo_checks`](https://hex.pm/packages/blitz_credo_checks) is already a
dependency, `DocsBeforeSpecs`, `NoRampantRepos` (lib-side `Repo` calls — the
complement of `NoRepoWritesInTests`), `NoAsyncFalse` and `SetWarningsAsErrorsInTest`
cover their conventions; keep them.

## License

MIT
