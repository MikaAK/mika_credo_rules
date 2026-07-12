defmodule MikaCredoRules.NoReimplementedHelper do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: %{
        atomize_keys: "SharedUtils.Enum.atomize_keys/1",
        deep_merge: "SharedUtils.Map.merge_deep_left/2",
        deep_struct_to_map: "SharedUtils.Map.deep_struct_to_map/1",
        pluck: "SharedUtils.Collection.pluck/2",
        random_string: "SharedUtils.String.generate_random/1",
        reject_nil_values: "SharedUtils.Enum.reject_nil_values/1",
        stringify_keys: "SharedUtils.Enum.stringify_keys/1",
        valid_email?: "SharedUtils.String.valid_email?/1"
      },
      excluded_paths: ["shared_utils"]
    ],
    explanations: [
      params: [
        functions: """
        A map of banned function names to the shared helper that already implements
        them (pointed to in the issue message). Overriding this param replaces the
        whole map, it is not merged with the default.
        """,
        excluded_paths: """
        A list of path fragments. A source file is exempt when its path starts or
        ends with a fragment, or contains one after a `/` — matching happens on
        path-segment boundaries, so `test/` does not exempt `lib/latest/`.

        Defaults to `["shared_utils"]`, exempting the shared library that defines
        the canonical implementations.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Helpers that already exist in a shared library must not be reimplemented locally.

  Generic data helpers (`atomize_keys/1`, `deep_merge/2`, `pluck/2`, ...) get
  re-inlined as private functions over and over, and each copy drifts from the
  tested shared implementation. Call the shared helper instead of redefining it.

      # BAD — local copy of a shared helper
      defmodule MyApp.Worker do
        defp atomize_keys(map) do
          Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
        end
      end

      # GOOD — the shared implementation is the only implementation
      defmodule MyApp.Worker do
        def process(map), do: SharedUtils.Enum.atomize_keys(map)
      end

  Any `def` or `defp` whose name is a key of the `:functions` map is flagged,
  whatever its arity or body — a local function named after a shared helper is a
  drift hazard even when its body currently matches. Calls to the shared helpers
  are never flagged, only definitions.

  Files matching an entry of `:excluded_paths` on a path-segment boundary are
  exempt, so the shared library itself can define the canonical implementations.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      functions = Params.get(params, :functions, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, functions))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp traverse({keyword, meta, [definition | _]} = ast, reimplementations, functions)
       when keyword in [:def, :defp] do
    name = definition_name(definition)

    case functions do
      %{^name => replacement} ->
        {ast, [reimplementation(keyword, name, replacement, meta) | reimplementations]}

      _ ->
        {ast, reimplementations}
    end
  end

  defp traverse(ast, reimplementations, _functions), do: {ast, reimplementations}

  # `def name(args) when guard` wraps the head in a `:when` node.
  defp definition_name({:when, _, [head | _]}), do: definition_name(head)
  defp definition_name({name, _, _}) when is_atom(name), do: name
  defp definition_name(_definition), do: nil

  defp reimplementation(keyword, name, replacement, meta) do
    %{keyword: keyword, name: name, replacement: replacement, line_no: meta[:line]}
  end

  defp issue_for(reimplementation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reimplementation.keyword} #{reimplementation.name} found — already exists as " <>
          "#{reimplementation.replacement}, use it",
      trigger: to_string(reimplementation.name),
      line_no: reimplementation.line_no
    )
  end
end
