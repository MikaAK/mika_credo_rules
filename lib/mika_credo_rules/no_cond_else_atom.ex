defmodule MikaCredoRules.NoCondElseAtom do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [disallowed_atoms: [:else]],
    explanations: [
      params: [
        disallowed_atoms: """
        A list of atoms that must not be used as the last `cond` clause's head.

        Defaults to `[:else]`.
        """
      ]
    ]

  @moduledoc """
  The last `cond` clause must fall through on `true`, not on an arbitrary
  truthy atom such as `:else`.

  Every atom other than `nil` and `false` is truthy in a `cond` head, so
  `:else -> ...` works — but it reads as if `cond` supported an `else` keyword
  the way `if`/`case` do, which it does not. `true` says "always match" without
  implying a keyword that doesn't exist.

      # BAD
      cond do
        a?() -> 1
        :else -> 2
      end

      # GOOD
      cond do
        a?() -> 1
        true -> 2
      end

  Only the LAST clause's head is inspected — an atom used as an earlier clause
  head is a different (and separately dubious) pattern this check does not
  cover.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    disallowed_atoms = Params.get(params, :disallowed_atoms, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, disallowed_atoms))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp traverse({:cond, _meta, [[do: clauses]]} = ast, matches, disallowed_atoms)
       when is_list(clauses) and clauses !== [] do
    case last_clause_match(List.last(clauses), disallowed_atoms) do
      nil -> {ast, matches}
      match -> {ast, [match | matches]}
    end
  end

  defp traverse(ast, matches, _disallowed_atoms), do: {ast, matches}

  defp last_clause_match({:->, meta, [[atom], _body]}, disallowed_atoms) when is_atom(atom) do
    if atom in disallowed_atoms, do: %{atom: atom, line_no: meta[:line]}
  end

  defp last_clause_match(_clause, _disallowed_atoms), do: nil

  defp issue_for(match, issue_meta) do
    trigger = ":#{match.atom}"

    format_issue(issue_meta,
      message: "cond clause head #{trigger} found — use `true` as the last cond branch",
      trigger: trigger,
      line_no: match.line_no
    )
  end
end
