defmodule MikaCredoRules.ImportComponentsNotAlias do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      suffixes: ["Components"],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        suffixes: """
        A list of suffixes identifying a components module by its own last
        alias segment — `MyAppWeb.CourseShowComponents` and
        `MyAppWeb.Admin.CourseShowComponents` both end in `"Components"`.
        Defaults to `["Components"]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `["_test.exs", "test/"]` — a
        components alias written inside a test module is exempt out of the
        box.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `<.func>` component call syntax needs the component module `import`ed, not
  aliased.

  `alias MyAppWeb.CourseShowComponents` only shortens the qualified name to
  `CourseShowComponents.card(assigns)` — Elixir never treats an aliased
  module as imported, so an unqualified `<.card>` cannot resolve and every
  call site needs the module qualifier instead, breaking the idiom the
  `<.func>` syntax exists for.

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

  A components module is identified by its own last alias segment, however
  deeply nested — `MyAppWeb.Admin.CourseShowComponents` still ends in
  `"Components"`. A name that merely contains the suffix without ending in
  it (`MyApp.ComponentsRegistry`), whose *last* segment does not match
  (`MyAppWeb.Components.Card`, last segment `Card`), or whose last segment
  *is* the suffix with nothing before it (`MyAppWeb.Components`, a pure
  namespace with no functions of its own to import) is left alone. A
  multi-alias group — `alias MyAppWeb.{CourseShowComponents, Layouts}` —
  reports only the segment that matches, not the whole statement. The
  `:"Elixir.MyAppWeb.CourseShowComponents"` atom spelling of a target is
  recognized the same as the dotted form.

  ## Limitations

    * This is a naming heuristic on the alias statement itself, not usage
      analysis — an alias that is never actually called still fires, and a
      components module re-exported under an unrelated name is invisible.
      The alias may also be needed as a bare module value rather than for
      qualified calls (`module={CardComponents}`, `apply(CardComponents,
      ...)`) — there, `import` is additive, not a replacement, and
      following the advice literally (removing the alias) breaks the
      reference.
    * Test files are excluded by default via `excluded_paths`; a components
      alias written inside a test module is not flagged unless that default
      is overridden.
    * A last segment that exactly equals a suffix (`alias MyAppWeb.Components`)
      is treated as a namespace, not a components module, and is never
      flagged — even when the namespace holds real `*Components` submodules
      accessed as `Components.Icons.icon/1`. A namespace segment like this is
      usually not a defined module at all, so `import`ing it is a
      `CompileError` (`module MyAppWeb.Components is not loaded and could
      not be found`); on the rare occasion it is defined, it exports nothing
      of its own, so the import is just a silent no-op — flagging it would
      never be advice worth giving.
    * Relative or macro-built alias targets — `alias __MODULE__.CardComponents`,
      `alias __MODULE__.{CardComponents, Layouts}`, `alias unquote(mod).CardComponents` —
      are not resolved to a literal module name and are never flagged.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      suffixes = suffixes(params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, suffixes))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)
  defp suffixes(params), do: Params.get(params, :suffixes, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # `alias MyAppWeb.{CourseShowComponents, Layouts}` — inner aliases are
  # relative to the base, so expand each one against it for the suffix check
  # and the message's fully qualified name, but keep the trigger to just the
  # inner segment — that (not the base-prefixed name) is the literal text
  # sitting at inner_meta's column, and Credo's test harness verifies the
  # trigger against exactly that source span.
  defp traverse(
         {:alias, _meta, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, group} | _rest]},
         aliases,
         suffixes
       ) do
    aliases =
      Enum.reduce(group, aliases, fn
        {:__aliases__, inner_meta, inner}, acc ->
          maybe_alias(base ++ inner, inner, inner_meta, acc, suffixes)

        _other, acc ->
          acc
      end)

    {nil, aliases}
  end

  # Plain alias, with or without an `as:` rename — the rename does not change
  # what module is being pulled in unqualified, so the target's own segments
  # are what matter, and they are also the literal text at alias_meta's
  # column.
  defp traverse(
         {:alias, _meta, [{:__aliases__, alias_meta, segments} | _rest]},
         aliases,
         suffixes
       ) do
    {nil, maybe_alias(segments, segments, alias_meta, aliases, suffixes)}
  end

  # `alias :"Elixir.MyAppWeb.CourseShowComponents"` — the Elixir-prefixed
  # atom spelling of a module reference parses as a bare atom argument, not
  # the `__aliases__` (dotted) node the two clauses above match, so it would
  # otherwise be a working, silent way to defeat this check (one of the
  # three module spellings this repo's checks must normalize — see
  # writing-credo-checks). The source has no dotted trigger token to point
  # at, so report with a real column (the alias node's own) and no trigger.
  defp traverse({:alias, meta, [target | _rest]}, aliases, suffixes) when is_atom(target) do
    {nil, maybe_atom_alias(target, meta, aliases, suffixes)}
  end

  defp traverse(ast, aliases, _suffixes), do: {ast, aliases}

  # `__MODULE__`/`unquote(...)` segments (relative aliases, macro-built
  # aliases) are not atoms, so `Enum.join/2` in `alias_reference/3` would
  # raise `Protocol.UndefinedError` on them — reject rather than resolve;
  # see ## Limitations.
  defp maybe_alias(full_segments, trigger_segments, meta, aliases, suffixes) do
    if literal_alias?(full_segments) and components_module?(full_segments, suffixes) do
      [alias_reference(full_segments, trigger_segments, meta) | aliases]
    else
      aliases
    end
  end

  defp literal_alias?(segments), do: Enum.all?(segments, &is_atom/1)

  defp maybe_atom_alias(target, meta, aliases, suffixes) do
    case atom_alias_segments(target) do
      segments when is_list(segments) ->
        if components_module?(segments, suffixes) do
          [atom_alias_reference(segments, meta) | aliases]
        else
          aliases
        end

      nil ->
        aliases
    end
  end

  # Only the `Elixir.`-prefixed spelling names a module this way — a bare
  # erlang atom (`alias :application`) or something like `nil` parses into
  # this same clause and must be rejected, not resolved.
  defp atom_alias_segments(target) do
    case Atom.to_string(target) do
      "Elixir." <> rest -> String.split(rest, ".")
      _not_elixir_module_atom -> nil
    end
  end

  defp atom_alias_reference(segments, meta) do
    %{
      full_name: Enum.join(segments, "."),
      trigger: Issue.no_trigger(),
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  # A last segment that IS the suffix (`MyAppWeb.Components`) names a
  # namespace, not a components module — require something before the
  # suffix; see ## Limitations.
  defp components_module?(segments, suffixes) do
    last_segment = segments |> List.last() |> to_string()
    Enum.any?(suffixes, &(String.ends_with?(last_segment, &1) and last_segment !== &1))
  end

  # `alias Elixir.MyAppWeb.CourseShowComponents` carries a leading `:Elixir`
  # segment (the implicit, spelled-out root) that reads back into the
  # message as noise absent from the plain `alias MyAppWeb...` spelling —
  # drop it from the reported name so both spellings read the same. The
  # trigger stays untouched: it must match the literal source span.
  defp alias_reference(full_segments, trigger_segments, meta) do
    %{
      full_name: full_segments |> drop_leading_elixir() |> Enum.join("."),
      trigger: Enum.join(trigger_segments, "."),
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp drop_leading_elixir([:"Elixir" | rest]), do: rest
  defp drop_leading_elixir(segments), do: segments

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reference.full_name} found — import #{reference.full_name} instead of aliasing it, so <.func> component syntax stays unqualified",
      trigger: reference.trigger,
      line_no: reference.line_no,
      column: reference.column
    )
  end
end
