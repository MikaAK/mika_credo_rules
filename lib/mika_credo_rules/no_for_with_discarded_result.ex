defmodule MikaCredoRules.NoForWithDiscardedResult do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments exempt from the check, matched at a path-segment
        boundary.

        Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `for` comprehension in statement position throws its result away — use
  `Enum.each/2` for side-effect-only iteration instead.

  `for` always builds and returns a list (or whatever `:into`/`:reduce`
  accumulates into). Written as a standalone statement, that value is built and
  immediately discarded — wasted work with no compiler warning to catch it.

      # BAD — the built list is thrown away
      def sync(items) do
        for item <- items do
          Cache.put(item)
        end

        :ok
      end

      # GOOD — no throwaway list
      def sync(items) do
        Enum.each(items, fn item ->
          Cache.put(item)
        end)

        :ok
      end

  A `for` is only flagged when it sits in statement position — an element of a
  block that is not the block's last expression. A `for` that IS the last
  expression of a block (its result becomes the block's value), the
  right-hand side of `=`, a call argument, or a pipe stage is consumed
  elsewhere and is never flagged:

      # GOOD — the for is the function's return value
      def user_ids(users) do
        for user <- users, do: user.id
      end

  `for ... into: ...` and `for ... reduce: ...` are flagged the same as a plain
  `for` when they sit in statement position — the accumulated value is still
  built and discarded.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_file?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp traverse({:__block__, _meta, exprs} = ast, discarded) when is_list(exprs) do
    {ast, collect_discarded_fors(exprs, discarded)}
  end

  defp traverse(ast, discarded), do: {ast, discarded}

  defp collect_discarded_fors(exprs, discarded) do
    exprs
    |> Enum.drop(-1)
    |> Enum.filter(&for_node?/1)
    |> Enum.map(&for_match/1)
    |> Kernel.++(discarded)
  end

  defp for_node?({:for, _meta, args}), do: is_list(args)
  defp for_node?(_expr), do: false

  defp for_match({:for, meta, _args}) do
    %{line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "for comprehension with discarded result found — use Enum.each/2 for side effects",
      trigger: "for",
      line_no: match.line_no,
      column: match.column
    )
  end
end
