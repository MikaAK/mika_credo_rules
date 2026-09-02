### `ImportComponentsNotAlias`

`<.func>` component call syntax needs the component module `import`ed, not
aliased. `alias MyAppWeb.CourseShowComponents` only shortens the qualified
name to `CourseShowComponents.card(assigns)` — Elixir never treats an
aliased module as imported, so an unqualified `<.card>` cannot resolve and
every call site needs the module qualifier instead, breaking the idiom the
`<.func>` syntax exists for.

```elixir
# BAD — alias leaves calls qualified, <.card> cannot resolve
defmodule MyAppWeb.CourseShowLive do
  alias MyAppWeb.CourseShowComponents

  def card_slot(assigns), do: CourseShowComponents.card(assigns)
end

# GOOD — import keeps card/1 (and <.card>) callable unqualified
defmodule MyAppWeb.CourseShowLive do
  import MyAppWeb.CourseShowComponents

  def card_slot(assigns), do: card(assigns)
end
```

A components module is identified by its own last alias segment, however
deeply nested — `MyAppWeb.Admin.CourseShowComponents` still ends in
`"Components"`. A name that merely contains the suffix without ending in it
(`MyApp.ComponentsRegistry`), whose *last* segment does not match
(`MyAppWeb.Components.Card`, last segment `Card`), or whose last segment *is*
the suffix with nothing before it (`MyAppWeb.Components`, a pure namespace
with no functions of its own to import), is left alone. An `as:` rename is
followed, not defeated — `alias MyAppWeb.CourseShowComponents, as: CSC`
still fires. A multi-alias group —
`alias MyAppWeb.{CourseShowComponents, Layouts}` — reports only the segment
that matches, not the whole statement. The
`:"Elixir.MyAppWeb.CourseShowComponents"` atom spelling of a target is
recognized the same as the dotted form. Test files are exempt by default.

**Limitations:** this is a naming heuristic on the alias statement itself,
not usage analysis — an alias that is never actually called still fires, and
a components module re-exported under an unrelated name is invisible. The
alias may also be needed as a bare module value rather than for qualified
calls (`module={CardComponents}`, `apply(CardComponents, ...)`) — there,
`import` is additive, not a replacement, and following the advice literally
(removing the alias) breaks the reference. A last segment that exactly equals a suffix
(`alias MyAppWeb.Components`) is treated as a namespace and never flagged,
even when it holds real
`*Components` submodules — a namespace segment like this is usually not a
defined module at all, so `import`ing it is a `CompileError` (`module
MyAppWeb.Components is not loaded and could not be found`); on the rare
occasion it is defined, it exports nothing of its own, so the import is just
a silent no-op either way. Relative or macro-built alias targets
(`alias __MODULE__.CardComponents`, `alias __MODULE__.{A, B}`,
`alias unquote(mod).CardComponents`) are not resolved and are never
flagged.

| Param | Default | Meaning |
|---|---|---|
| `suffixes` | `["Components"]` | Suffixes identifying a components module by its own last alias segment. |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
