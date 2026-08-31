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
| [`ErrorMessageRequired`](#errormessagerequired) | `:design` | `{:error, "string literal"}` tuples — use `%ErrorMessage{}` |
| [`ExceptionNamesEndInError`](#exceptionnamesendinerror) | `:readability` | An exception module whose name does not end in `Error` |
| [`GenServerRequiresHandleContinue`](#genserverrequireshandlecontinue) | `:refactor` | Real work in `init/1` instead of `handle_continue/2` |
| [`InUmbrellaDepsNoVersion`](#inumbrelladepsnoversion) | `:readability` | `{:app, "~> x", in_umbrella: true}` — a version requirement on an in_umbrella dep |
| [`LoggerModulePrefixAndInspect`](#loggermoduleprefixandinspect) | `:warning` | Logger messages missing the `#{__MODULE__}: ` prefix or interpolating values without `inspect/1` |
| [`NoAccessOnStructSubject`](#noaccessonstructsubject) | `:warning` | `changeset[:name]` — `Access` on a struct raises `UndefinedFunctionError` |
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
| [`NoIdentityRewrap`](#noidentityrewrap) | `:refactor` | `case` expressions whose every clause returns its pattern unchanged |
| [`NoJasonDeriveOnEctoSchema`](#nojasonderiveonectoschema) | `:design` | `@derive Jason.Encoder` inside Ecto schema modules |
| [`NoKernelPrefix`](#nokernelprefix) | `:readability` | `Kernel.inspect(value)` — `Kernel` is auto-imported, drop the prefix |
| [`NoMixEnvAtRuntime`](#nomixenvatruntime) | `:warning` | `Mix.env()`/`Mix.target()` in compiled code — crashes in releases |
| [`NoMockingLibraries`](#nomockinglibraries) | `:design` | Any reference to Mox, Hammox, Mock, Mimic, Patch or `:meck` |
| [`NoNilComparison`](#nonilcomparison) | `:readability` | `x == nil` / `x != nil` — use `is_nil/1` |
| [`NoObanInsertBang`](#nobaninsertbang) | `:warning` | `Oban.insert!`/`Oban.insert_all!` in application code — prefer the non-bang form and handle `{:error, _}` |
| [`NoProcessSleepInTests`](#noprocesssleepintests) | `:warning` | `Process.sleep/1` and `:timer.sleep/1` in test files |
| [`NoRawEts`](#norawets) | `:design` | Raw `:ets` calls — wrap in `Cache.ETS` from elixir_cache |
| [`NoReimplementedHelper`](#noreimplementedhelper) | `:design` | Local re-implementations of shared library helpers |
| [`NoRepoWritesInTests`](#norepowritesintests) | `:design` | Write-side `Repo` calls (`insert!`, `update!`, `delete!`, ...) in test files — use `FactoryEx` |
| [`NoSingleLetterVariables`](#nosinglelettervariables) | `:readability` | Single-letter variable bindings |
| [`NoVacuousAssert`](#novacuousassert) | `:warning` | `assert true` / `assert <literal>` / `refute false` / `assert x === x` — placeholder assertions that can never fail |
| [`NoWordSigilLists`](#nowordsigillists) | `:readability` | `~w`/`~W` sigils — use a list literal instead |
| [`NoTruthyAndOr`](#notruthyandor) | `:warning` | `and`/`or`/`not` on a provably-nilable operand (`opts[:key]`, `Map.get/2`, ...) — use `&&`/`\|\|`/`!` |
| [`ObanWorkerRequiresMaxAttempts`](#obanworkerrequiresmaxattempts) | `:design` | `use Oban.Worker` whose literal opts omit `:max_attempts` |
| [`RefuteOverAssertNot`](#refuteoverassertnot) | `:readability` | `assert !expr` / `assert not expr` — use `refute` |
| [`SingleModulePerFile`](#singlemoduleperfile) | `:design` | More than one top-level `defmodule` per file (nested modules allowed) |
| [`StrictEquality`](#strictequality) | `:warning` | `==`/`!=` — use `===`/`!==` (Ecto query DSL exempt) |
| [`TestOnlyDepsScoped`](#testonlydepsscoped) | `:warning` | A dev/test-only mix.exs dep missing `only:` or `runtime: false` |
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
