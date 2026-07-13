defmodule MikaCredoRules.NoIdentityRewrap do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor

  @moduledoc """
  A `case` whose every clause returns its pattern unchanged is a no-op re-wrap —
  drop the `case` and return the matched value directly.

  Wrapping already-tagged tuples in a `case` that re-emits them adds reading
  effort without changing the value.

      # BAD
      case fetch_user(id) do
        {:ok, user} -> {:ok, user}
        {:error, reason} -> {:error, reason}
      end

      # GOOD — return the call directly
      fetch_user(id)

      # GOOD — the error clause transforms, so the case does real work
      case fetch_user(id) do
        {:ok, user} -> {:ok, user}
        {:error, reason} -> {:error, {:user_fetch_failed, reason}}
      end

  A `case` is only flagged when every clause is an identity re-wrap. Clauses
  with guards make the `case` a deliberate filter or assertion, so a `case`
  containing any guarded clause is never flagged. If the `case` exists purely to
  assert the shape of the value, prefer an explicit pattern match
  (`{:ok, user} = fetch_user(id)`) or a clause that transforms — an identity
  `case` hides that intent.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse/2)
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp traverse({:case, meta, [_subject, [do: clauses]]} = ast, rewrap_lines)
       when is_list(clauses) and clauses !== [] do
    if Enum.all?(clauses, &identity_clause?/1) do
      {ast, [meta[:line] | rewrap_lines]}
    else
      {ast, rewrap_lines}
    end
  end

  defp traverse(ast, rewrap_lines), do: {ast, rewrap_lines}

  # A guarded head makes the case a deliberate filter/assertion — never identity.
  defp identity_clause?({:->, _, [[{:when, _, _}], _body]}), do: false

  # A multi-expression body does work beyond re-emitting the pattern.
  defp identity_clause?({:->, _, [_patterns, {:__block__, _, _}]}), do: false

  defp identity_clause?({:->, _, [[pattern], body]}) do
    strip_meta(pattern) === strip_meta(body)
  end

  defp identity_clause?(_clause), do: false

  defp strip_meta(ast) do
    Macro.prewalk(ast, fn
      {form, meta, args} when is_list(meta) -> {form, [], args}
      other -> other
    end)
  end

  defp issue_for(line_no, issue_meta) do
    format_issue(issue_meta,
      message:
        "identity re-wrap case found — every clause returns its pattern unchanged; return the value directly",
      trigger: "case",
      line_no: line_no
    )
  end
end
