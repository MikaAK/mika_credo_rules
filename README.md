# MikaCredoRules

Custom [Credo](https://github.com/rrrene/credo) checks used across Mika's Elixir
projects.

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
      name: "default",
      checks: [
        {MikaCredoRules.NoApplicationEnvOutsideConfig, []}
      ]
    }
  ]
}
```

## Checks

| Check | Category | What it catches |
|---|---|---|
| `MikaCredoRules.NoApplicationEnvOutsideConfig` | `:design` | Any read or write of application env outside a config module |

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

defmodule MyApp.Worker do
  def provider, do: MyApp.Config.provider()
end
```

Config modules are identified **by filename**, so this works the same in an umbrella
(`apps/my_app/lib/my_app/config.ex`) and a single app (`lib/my_app/config.ex`).

There are no other exemptions by default. Test files and `application.ex` are checked
too — a test reaching for `Application.put_env/3` is exactly the case this rule exists
to catch.

#### Every spelling of the module is caught

```elixir
Application.get_env(:my_app, :provider)          # caught
Elixir.Application.get_env(:my_app, :provider)   # caught
:application.get_env(:my_app, :provider)         # caught

alias Application, as: App
App.get_env(:my_app, :provider)                  # caught
```

Aliasing something *else* to `Application` correctly suppresses the check, since bare
`Application` no longer refers to Elixir's:

```elixir
alias MyApp.Application

Application.get_env(:my_app, :children)          # not flagged — this is MyApp.Application
```

#### Params

| Param | Default | Meaning |
|---|---|---|
| `config_files` | `["config.ex"]` | Path suffixes treated as config modules |
| `functions` | every `Application` env function (see below) | Which `Application` functions count as env access |
| `erlang_functions` | `[:get_env, :get_all_env, :set_env, :unset_env]` | Which `:application` functions count as env access |

`functions` defaults to the full env surface, reads and writes:

```elixir
[
  :get_env, :fetch_env, :fetch_env!, :get_all_env,
  :compile_env, :compile_env!,
  :put_env, :put_all_env,
  :delete_env
]
```

Erlang gets its own list because it names its writes differently — `set_env`/`unset_env`
rather than `put_env`/`delete_env`.

`Application.app_dir/2`, `get_application/1`, and `spec/2` are not env access and are
never flagged. Neither are `:application.ensure_all_started/1` and friends.

To widen the exemption or narrow the functions:

```elixir
{MikaCredoRules.NoApplicationEnvOutsideConfig,
 config_files: ["config.ex", "settings.ex"],
 functions: [:get_env, :compile_env]}
```

#### Known limitations

Aliases are resolved from a **flat, file-level table** rather than a lexical scope
stack. An alias declared inside one function is treated as applying to the whole file.
To be wrong, the same alias name would have to mean two different modules in two
functions of one file.

Aliases injected by a macro (`use SomeMacro` that aliases from inside `__using__`) are
invisible to Credo, which does not macro-expand. No amount of scope tracking fixes
this.

`import Application` followed by a bare `get_env/2` is not detected.

## License

MIT
