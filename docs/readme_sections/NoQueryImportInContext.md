### `NoQueryImportInContext`

Query composition belongs in the schema module, not the context. `by_*`/
`join_*` query fragments live on the schema — conventionally in the dedicated
database-layer app (`_pg`/`schemas`) — and the context orchestrates by
calling them. `import Ecto.Query` (or `require Ecto.Query`, or a qualified
`Ecto.Query.from`/`dynamic` call) outside that app means the context is
building queries itself instead of delegating.

```elixir
# BAD — apps/my_app/lib/my_app/courses.ex builds the query itself
defmodule MyApp.Courses do
  import Ecto.Query

  def list_open do
    from(course in MyApp.Course, where: course.status == :open)
  end
end

# GOOD — apps/my_app/lib/my_app/courses.ex delegates to the schema
defmodule MyApp.Courses do
  alias MyApp.Course

  def list_open, do: Course.by_status(:open)
end
```

`require Ecto.Query` is caught the same way `import` is. A qualified call to
`Ecto.Query.from` or `Ecto.Query.dynamic` is caught too, alias-aware —
`alias Ecto.Query, as: Q` then `Q.from(...)` is the same smell as importing
it outright. Merely aliasing `Ecto.Query` without ever calling `from` or
`dynamic` through it is not itself flagged.

**Limitations:** only `from` and `dynamic`, at any arity, are caught on a
qualified call — the two functions that actually start composing a query; a
qualified `Ecto.Query.where/3` continuing a query built elsewhere is not
caught. `apply(Ecto.Query, :from, [...])` evades the qualified-call matcher.
An `import`/`require` brought in by a macro (through `__using__`) is
invisible to Credo. Aliases are resolved from a flat, file-level table — an
alias declared inside one function is treated as applying to the whole
file. `require Ecto.Query, as: Q` does not register `Q` as an alias, so a
later `Q.from(...)` evades the qualified-call matcher (the `require` itself
still fires). A single-segment `:modules` entry is not deshadowed by a
local `defmodule` of the same name.

| Param | Default | Meaning |
|---|---|---|
| `allowed_paths` | `["_pg/", "/schemas/", "priv/", "_test.exs", "test/"]` | Path fragments/suffixes where query composition is allowed — the schema app, migrations, tests (segment-boundary matched; a `.`-containing entry like `_test.exs` is a filename suffix, anchored only if written with a leading `/`) |
| `modules` | `[Ecto.Query]` | Modules whose `import`, `require`, or qualified `from`/`dynamic` call counts as query composition |
