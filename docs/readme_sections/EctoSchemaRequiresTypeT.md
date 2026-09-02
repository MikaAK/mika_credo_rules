### `EctoSchemaRequiresTypeT`

Every `Ecto.Schema` module must define `@type t :: %__MODULE__{}` for
Dialyzer. Without it, every function returning a struct from this schema is
typed as a bare `map()` (or left unspeced) to Dialyzer — a caller matching
the wrong field name, or passing the wrong struct entirely, gets no static
warning. `@type t :: %__MODULE__{}` gives Dialyzer the struct shape once,
for every `@spec` that returns it.

```elixir
# BAD — no @type t for Dialyzer
defmodule MyApp.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
  end
end

# GOOD — @type t documents the struct shape for Dialyzer
defmodule MyApp.User do
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "users" do
    field :name, :string
  end
end
```

`embedded_schema` modules use the same `use Ecto.Schema` and are checked
identically. The check is scoped per module, not per file — a nested
`defmodule` inside a schema file is judged on its own body: it is only
flagged when it declares its own `use Ecto.Schema` and calls `schema`/
`embedded_schema` itself, and it must define its own `@type t` even when an
enclosing module already has one. A module whose `use Ecto.Schema` never
reaches an actual `schema`/`embedded_schema` call is not flagged — most
commonly a base module that injects `use Ecto.Schema` for its callers from
inside a `quote` block, or a bare `use Ecto.Schema` with no schema block at
all.

**Limitations:** only a type literally named `t`, arity 0, declared via
`@type`, `@opaque`, or `@typep` (`@type t :: ...`, `@opaque t :: ...`,
`@type t() :: ...`, etc.), satisfies the check — a differently named type
alias for the same struct is not recognized. Aliases are resolved from a
flat, file-level table rather than a lexical scope stack, and an alias
injected by a macro (via `__using__`) is invisible to Credo. A schema built
through a project base wrapper (a module that itself calls `use Ecto.Schema`,
e.g. `use MyApp.Schema`) is invisible under the default
`schema_modules: [Ecto.Schema]` — list the wrapper too, e.g.
`schema_modules: [Ecto.Schema, MyApp.Schema]`.

| Param | Default | Meaning |
|---|---|---|
| `schema_modules` | `[Ecto.Schema]` | Modules whose `use` counts as declaring an Ecto schema, alias-aware |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments exempt from the check (segment-boundary matched) — a schema struct built only for a test fixture has no Dialyzer caller relying on `t()` |
