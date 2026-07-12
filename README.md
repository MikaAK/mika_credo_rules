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

#### Params

| Param | Default | Meaning |
|---|---|---|
| `config_files` | `["config.ex"]` | Path suffixes treated as config modules |
| `functions` | every `Application` env function (see below) | Which `Application` functions count as env access |

`functions` defaults to the full env surface, reads and writes:

```elixir
[
  :get_env, :fetch_env, :fetch_env!, :get_all_env,
  :compile_env, :compile_env!,
  :put_env, :put_all_env,
  :delete_env
]
```

`Application.app_dir/2`, `get_application/1`, and `spec/2` are not env access and are
never flagged.

To widen the exemption or narrow the functions:

```elixir
{MikaCredoRules.NoApplicationEnvOutsideConfig,
 config_files: ["config.ex", "settings.ex"],
 functions: [:get_env, :compile_env]}
```

#### Known limitation

Calls made through an alias (`alias Application, as: App` then `App.get_env/2`) are
not detected. Resolving aliases requires scope tracking the walker does not do.

## License

MIT
