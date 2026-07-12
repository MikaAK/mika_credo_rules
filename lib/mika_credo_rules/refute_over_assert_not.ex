defmodule MikaCredoRules.RefuteOverAssertNot do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [test_files: ["_test.exs"]],
    explanations: [
      params: [
        test_files: """
        A list of file path suffixes treated as test files. The check only runs on
        source files whose path ends with one of these.

        Defaults to `["_test.exs"]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Negated assertions must use `refute`, not `assert !` or `assert not`.

  `refute expr` states "this must be falsy" directly. `assert !expr` and
  `assert not expr` say the same thing through a negation the reader has to unwind,
  and they produce worse failure output than `refute`.

      # BAD
      assert !valid?(user)
      assert not valid?(user)

      # GOOD
      refute valid?(user)

  `assert value not in collection` is left alone. It compiles to the same AST as
  `assert not (value in collection)`, and the membership spelling is idiomatic, so
  neither form is flagged.

  Negated comparison operators are not negated expressions — `assert one() !== two()`
  is fine.

  The check only runs on test files, identified by filename via the `:test_files`
  param.
  """
  @explanation [check: @moduledoc]

  @negations [:!, :not]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if test_file?(source_file.filename, test_files(params)) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp test_files(params), do: Params.get(params, :test_files, __MODULE__)

  defp test_file?(filename, test_files) do
    SourceFilter.matches_suffix?(filename, test_files)
  end

  # `assert value not in collection` compiles to `assert not (value in collection)`,
  # so the two spellings cannot be told apart — leave both alone.
  defp traverse({:assert, _, [{:not, _, [{:in, _, _}]} | _]} = ast, negated_asserts) do
    {ast, negated_asserts}
  end

  defp traverse({:assert, meta, [{negation, _, _} | _]} = ast, negated_asserts)
       when negation in @negations do
    {ast, [%{negation: negation, line_no: meta[:line]} | negated_asserts]}
  end

  defp traverse(ast, negated_asserts), do: {ast, negated_asserts}

  defp issue_for(negated_assert, issue_meta) do
    trigger = "assert #{negated_assert.negation}"

    format_issue(issue_meta,
      message: "#{trigger} found — use refute instead of asserting a negated expression",
      trigger: trigger,
      line_no: negated_assert.line_no
    )
  end
end
