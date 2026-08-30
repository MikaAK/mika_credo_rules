defmodule MikaCredoRules.NoObanInsertBang do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:insert!, :insert_all!],
      excluded_paths: ["_test.exs", "test/", "seeds"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the `Oban` functions that count as a raising
        insert. Defaults to `[:insert!, :insert_all!]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment
        matches when the source file's path starts with it, ends with it, or
        contains it after a directory separator.

        Defaults to `["_test.exs", "test/", "seeds"]` — a bang insert that
        crashes its caller is legitimate as a test setup assertion or in a
        one-shot seed script, where crashing loudly on bad data is the point.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Oban.insert!/1,2,3` and `Oban.insert_all!/1,2,3` must not be used in
  application code.

  `Oban.insert!` raises on failure — a changeset error, a database blip —
  taking down the calling process. `Oban.insert/1` returns
  `{:ok, job} | {:error, reason}`, which lets the caller decide how to
  respond instead of crashing.

      # BAD — a changeset error crashes the caller
      defmodule MyApp.Worker do
        def enqueue(id) do
          Oban.insert!(MyApp.Workers.Sync.new(%{id: id}))
        end
      end

      # GOOD — the caller decides how to respond
      defmodule MyApp.Worker do
        def enqueue(id) do
          with {:ok, _job} <- Oban.insert(MyApp.Workers.Sync.new(%{id: id})) do
            :ok
          end
        end
      end

  Every spelling of the module is caught, including `alias Oban, as: MyOban`
  and the fully-qualified `Elixir.Oban.insert!(...)`.

  ## Known limitations

  `Oban.insert_all!/1,2,3` is not part of Oban's public API as of Oban
  2.19–2.22 (verified against local dependency checkouts) — it is kept in the
  default `:functions` list defensively, for a future Oban release or an
  `Oban.Pro` extension that adds it. The entry never matches today's Oban.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    %{
      modules: AstHelpers.resolve_aliases(source_file, [Oban]),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         inserts,
         context
       )
       when is_list(args) do
    if module in context.modules and function in context.functions do
      {ast, [insert_call(Enum.join(module, "."), function, meta) | inserts]}
    else
      {ast, inserts}
    end
  end

  defp traverse(ast, inserts, _context), do: {ast, inserts}

  defp insert_call(module, function, meta) do
    %{module: module, function: function, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(insert_call, issue_meta) do
    trigger = to_string(insert_call.function)
    full_call = "#{insert_call.module}.#{trigger}"
    base_function = String.trim_trailing(trigger, "!")

    format_issue(issue_meta,
      message:
        "#{full_call} found — prefer #{insert_call.module}.#{base_function}/1..3 and handle the {:error, _} case instead of raising",
      trigger: trigger,
      line_no: insert_call.line_no,
      column: insert_call.column
    )
  end
end
