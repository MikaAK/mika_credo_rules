defmodule MikaCredoRules.NoStaticNotLoadedDropList do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      marker_key: :__meta__,
      non_association_keys: [:__struct__],
      excluded_paths: []
    ],
    explanations: [
      params: [
        marker_key: """
        The atom that marks a drop-list as an Ecto association-scrubbing list.

        Defaults to `:__meta__` — every schema struct carries it, and no ordinary
        (non-Ecto) map ever legitimately drops it.
        """,
        non_association_keys: """
        A list of atoms that never count toward making a drop-list dangerous,
        alongside `marker_key`. A list containing only `marker_key` plus atoms
        from this list is not an association scrub.

        Defaults to `[:__struct__]` — every struct carries it, dropping it
        alongside `:__meta__` is universal struct-to-map hygiene, and it can
        never be the name of an association that rots the list.
        """,
        excluded_paths: """
        A list of path fragments, matched at a path-segment boundary via
        `MikaCredoRules.SourceFilter.matches_fragment?/2`. A source file matching
        any of these is exempt from the check.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A static drop-list must not be used to scrub `%Ecto.Association.NotLoaded{}`
  values before serializing a schema.

  `Map.drop(struct_map, [:__meta__, :workspace, :sessions])` rots the moment a
  new association is added to the schema — the list has no way to know about a
  `has_one :parent_ticket` added next sprint, so the new field silently slips
  through and crashes `Jason.encode!/1` at runtime with
  `%Ecto.Association.NotLoaded{}`. Reject unloaded associations by type instead.

      # BAD
      @association_keys [:__meta__, :workspace, :sessions]
      struct |> Map.from_struct() |> Map.drop(@association_keys)

      # GOOD
      struct
      |> Map.from_struct()
      |> Map.reject(fn {_key, value} -> match?(%Ecto.Association.NotLoaded{}, value) end)
      |> Map.delete(:__meta__)

  The `:__meta__` marker is what makes the trigger unambiguous — every Ecto
  schema struct carries it, and no ordinary map drops it. `Map.drop(map,
  [:__meta__])` alone (no other atom in the list) is fine; every schema owns at
  least its own `__meta__`, and dropping only that is not an association scrub.
  `Map.drop(map, [:__meta__, :__struct__])` is fine too — `:__struct__` is
  universal struct metadata, not an association name, and dropping it alongside
  `:__meta__` is ordinary struct-to-map hygiene. A list containing `:__meta__`
  plus at least one atom outside the `:non_association_keys` param is a
  drop-list by construction.

  Both a literal list argument and a module attribute holding one are caught,
  standalone (`Map.drop(map, list)`) and piped (`map |> Map.drop(list)`). `Map`
  is matched alias-aware, so `alias MyApp.Map` shadowing Elixir's `Map` exempts
  the call.

  ## Limitations

    * A module attribute's value is resolved from a flat, file-level table built
      by folding every `@name [...]` assignment in the file — the LAST
      assignment anywhere in the file wins for every reference to that name,
      regardless of position. A later, narrower reassignment of the same
      attribute silently clears an earlier dangerous usage.
    * A drop-list built with `[:__meta__ | @assocs]` (cons) or `[:__meta__] ++
      @assocs` (concatenation) is not a literal list or a bare attribute
      reference, so it is undetected.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp build_context(source_file, params) do
    %{
      map_modules: AstHelpers.resolve_aliases(source_file, [Map]),
      marker_key: Params.get(params, :marker_key, __MODULE__),
      non_association_keys: Params.get(params, :non_association_keys, __MODULE__),
      attribute_lists: collect_attribute_lists(source_file)
    }
  end

  defp collect_attribute_lists(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_attribute/2, %{})
  end

  defp collect_attribute({:@, _, [{name, _, [value]}]} = ast, attrs) when is_list(value) do
    {ast, Map.put(attrs, name, value)}
  end

  defp collect_attribute(ast, attrs), do: {ast, attrs}

  # A piped drop is consumed here, and the call's head is rewritten to a block
  # (arguments stay traversable) so the standalone clause below never
  # re-examines the same call in the wrong argument position.
  defp traverse({:|>, pipe_meta, [lhs, piped_call]} = ast, drops, context) do
    case drop_call(piped_call, context) do
      {meta, args} ->
        {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
         collect_drop(drops, args, :piped, meta, context)}

      nil ->
        {ast, drops}
    end
  end

  defp traverse(ast, drops, context) do
    case drop_call(ast, context) do
      {meta, args} -> {ast, collect_drop(drops, args, :standalone, meta, context)}
      nil -> {ast, drops}
    end
  end

  defp drop_call({{:., _, [{:__aliases__, _, module}, :drop]}, meta, args}, context)
       when is_list(args) do
    if module in context.map_modules, do: {meta, args}
  end

  defp drop_call(_ast, _context), do: nil

  defp collect_drop(drops, args, position, meta, context) do
    if args |> drop_list_arg(position) |> dangerous_list?(context) do
      [%{line_no: meta[:line], column: meta[:column]} | drops]
    else
      drops
    end
  end

  # In `Map.drop(map, list)` the list is the 2nd argument; in
  # `map |> Map.drop(list)` it is the call node's 1st (and only) argument.
  defp drop_list_arg(args, :standalone) when length(args) === 2, do: Enum.at(args, 1)
  defp drop_list_arg(args, :piped) when length(args) === 1, do: Enum.at(args, 0)
  defp drop_list_arg(_args, _position), do: nil

  defp dangerous_list?(list, context) when is_list(list) do
    static_dangerous_list?(list, context.marker_key, context.non_association_keys)
  end

  defp dangerous_list?({:@, _, [{name, _, nil}]}, context) do
    case Map.fetch(context.attribute_lists, name) do
      {:ok, list} ->
        static_dangerous_list?(list, context.marker_key, context.non_association_keys)

      :error ->
        false
    end
  end

  defp dangerous_list?(_arg, _context), do: false

  defp static_dangerous_list?(list, marker_key, non_association_keys) do
    ignored_keys = [marker_key | non_association_keys]

    marker_key in list and Enum.any?(list, &(&1 not in ignored_keys and is_atom(&1)))
  end

  defp issue_for(drop, issue_meta) do
    format_issue(issue_meta,
      message:
        "Map.drop with a static drop-list found — reject %Ecto.Association.NotLoaded{} values by type (Map.reject/2 + match?/2) instead of by field name",
      trigger: "drop",
      line_no: drop.line_no,
      column: drop.column
    )
  end
end
