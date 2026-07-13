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
built-in `TagTODO` (default-on, flags every TODO even ticketed ones — you'd get two
issues per TODO):

```elixir
checks: %{
  enabled: [{MikaCredoRules.TodosNeedTickets, []}],
  disabled: [{Credo.Check.Design.TagTODO, []}]   # superseded by TodosNeedTickets
}
```

## Checks

| Check | Category | What it catches |
|---|---|---|
| [`ErrorMessageRequired`](#errormessagerequired) | `:design` | `{:error, "string literal"}` tuples — use `%ErrorMessage{}` |
| [`GenServerRequiresHandleContinue`](#genserverrequireshandlecontinue) | `:refactor` | Real work in `init/1` instead of `handle_continue/2` |
| [`LoggerModulePrefixAndInspect`](#loggermoduleprefixandinspect) | `:warning` | Logger messages missing the `#{__MODULE__}: ` prefix or interpolating values without `inspect/1` |
| [`NoApplicationEnvOutsideConfig`](#noapplicationenvoutsideconfig) | `:design` | Any read or write of application env outside a config module |
| [`NoAtomStringKeyFallback`](#noatomstringkeyfallback) | `:warning` | `m["key"] \|\| m[:key]` mixed-key fallback reads — normalize keys at the boundary |
| [`NoBlanketRescue`](#noblanketrescue) | `:warning` | Catch-all rescue clauses that swallow exceptions |
| [`NoCastAllKeys`](#nocastallkeys) | `:warning` | `cast(data, params, Map.keys(params))` — a mass-assignment hole |
| [`NoIdentityRewrap`](#noidentityrewrap) | `:refactor` | `case` expressions whose every clause returns its pattern unchanged |
| [`NoJasonDeriveOnEctoSchema`](#nojasonderiveonectoschema) | `:design` | `@derive Jason.Encoder` inside Ecto schema modules |
| [`NoMixEnvAtRuntime`](#nomixenvatruntime) | `:warning` | `Mix.env()`/`Mix.target()` in compiled code — crashes in releases |
| [`NoMockingLibraries`](#nomockinglibraries) | `:design` | Any reference to Mox, Hammox, Mock, Mimic, Patch or `:meck` |
| [`NoNilComparison`](#nonilcomparison) | `:readability` | `x == nil` / `x != nil` — use `is_nil/1` |
| [`NoProcessSleepInTests`](#noprocesssleepintests) | `:warning` | `Process.sleep/1` and `:timer.sleep/1` in test files |
| [`NoReimplementedHelper`](#noreimplementedhelper) | `:design` | Local re-implementations of shared library helpers |
| [`NoSingleLetterVariables`](#nosinglelettervariables) | `:readability` | Single-letter variable bindings |
| [`RefuteOverAssertNot`](#refuteoverassertnot) | `:readability` | `assert !expr` / `assert not expr` — use `refute` |
| [`SingleModulePerFile`](#singlemoduleperfile) | `:design` | More than one `defmodule` per file |
| [`StrictEquality`](#strictequality) | `:warning` | `==`/`!=` — use `===`/`!==` (Ecto query DSL exempt) |
| [`TodosNeedTickets`](#todosneedtickets) | `:design` | TODO/FIXME comments without an adjacent ticket URL |

---

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
(`apps/my_app/lib/my_app/config.ex`) and a single app (`lib/my_app/config.ex`).
There are no other exemptions by default — test files and `application.ex` are
checked too; a test reaching for `Application.put_env/3` is exactly the case this
rule exists to catch. Env access is caught through every spelling, including
`alias Application, as: App` and `:application.get_env/2`.

| Param | Default | Meaning |
|---|---|---|
| `config_files` | `["config.ex"]` | Path suffixes treated as config modules |
| `functions` | every `Application` env function | Which `Application` functions count as env access |
| `erlang_functions` | `[:get_env, :get_all_env, :set_env, :unset_env]` | Which `:application` functions count as env access |

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
never flagged, while `alias Mox, as: M` still is.

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

| Param | Default | Meaning |
|---|---|---|
| `test_files` | `["_test.exs"]` | Path suffixes the check runs on — everything else is skipped |
| `functions` | `[{Process, :sleep}, {:timer, :sleep}]` | Sleep functions to flag |

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

| Param | Default | Meaning |
|---|---|---|
| `functions` | `%{atomize_keys: "SharedUtils.Enum.atomize_keys/1", deep_merge: "SharedUtils.Map.merge_deep_left/2", deep_struct_to_map: "SharedUtils.Map.deep_struct_to_map/1", pluck: "SharedUtils.Collection.pluck/2", random_string: "SharedUtils.String.generate_random/1", reject_nil_values: "SharedUtils.Enum.reject_nil_values/1", stringify_keys: "SharedUtils.Enum.stringify_keys/1", valid_email?: "SharedUtils.String.valid_email?/1"}` | Banned local function names → the shared helper to use instead. Overriding replaces the whole map. |
| `excluded_paths` | `["shared_utils"]` | Path fragments exempt from the check (segment-boundary matched) — the shared library itself defines the canonical implementations |

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

| Param | Default | Meaning |
|---|---|---|
| `allowed_names` | `[]` | Single-letter names allowed anyway — atoms or strings |

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

Each module gets its own file. A file that defines several modules recompiles
them together — anything depending on one is recompiled whenever any co-located
module changes, and mutual references between co-located modules can grow into
cycles the compiler cannot split apart.

```elixir
# BAD — two sibling modules in one file
defmodule MyApp.Worker do
  def run, do: :ok
end

defmodule MyApp.WorkerSupervisor do
  def start_link, do: :ok
end

# GOOD — exactly one module per file
defmodule MyApp.Worker do
  def run, do: :ok
end
```

Every `defmodule` after the first is flagged, nested or sibling. `defimpl` and
`defprotocol` are never flagged, and `defmodule` inside a `quote` block is
skipped — a macro that generates a module defines it at the call site. Test
files are excluded by default — nested test-helper modules are idiomatic there.

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

| Param | Default | Meaning |
|---|---|---|
| `tags` | `["Todo", "TODO", "Fixme", "FIXME"]` | Tag words treated as todos (case-insensitive) |
| `ticket_url` | `"http"` | Substring a line must contain to count as a ticket reference — set to your tracker's URL prefix so only real tickets count |

## License

MIT
