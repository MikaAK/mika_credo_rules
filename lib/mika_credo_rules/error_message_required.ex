defmodule MikaCredoRules.ErrorMessageRequired do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      excluded_files: ["_test.exs", "test/"],
      also_flag_atoms: false
    ],
    explanations: [
      params: [
        excluded_files: """
        A list of path fragments naming files this check skips. A fragment matches
        when the source file's path starts with it, ends with it, or contains it
        after a directory separator.

        Defaults to `["_test.exs", "test/"]`, which skips test files and anything
        under a `test/` directory — `{:error, "..."}` literals are legitimate
        fixture data there.
        """,
        also_flag_atoms: """
        When `true`, atom reasons such as `{:error, :timeout}` are flagged too.
        Defaults to `false` — atom reasons are idiomatic in many libraries.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Error tuples must carry a structured `%ErrorMessage{}`, not a bare string literal.

  `{:error, "something went wrong"}` gives callers nothing to match on — a string
  reason can only be compared byte-for-byte and carries no code or details. The
  house convention returns `{:error, %ErrorMessage{}}` built through the
  `elixir_error_message` constructors.

      # BAD — unmatchable, unstructured reason
      defmodule MyApp.Users do
        def find(nil), do: {:error, "user id is required"}
      end

      # GOOD — structured error with code, message and details
      defmodule MyApp.Users do
        def find(nil), do: {:error, ErrorMessage.bad_request("user id is required")}
      end

  Only literal reasons are flagged. Variables, atoms and structs pass:

      {:error, changeset}                       # passes — reason unknowable statically
      {:error, :timeout}                        # passes by default (:also_flag_atoms)
      {:error, %ErrorMessage{}}                 # passes — already structured
      {:error, ErrorMessage.not_found("...")}   # passes

  Matching on an error tuple someone else constructed is fine — only construction
  is flagged:

      case ThirdParty.call() do
        {:error, "expired"} -> :retry           # passes — a match, not a construction
      end

  Test files are skipped by default (see `:excluded_files`) — `{:error, "..."}`
  literals are legitimate fixture data in tests. `:excluded_files` is the single
  scoping mechanism on purpose: Credo's builtin `:files` param is deliberately not
  defaulted, because it prunes files before `run/2` is ever called and would
  silently override `excluded_files: []` for consumers re-enabling test-file
  flagging.

  ## Known limitations

  Two-element tuples of literals carry no position metadata in the Elixir AST, so
  the reported line is the nearest enclosing expression that has one — exact for
  one-liners and clause bodies, the `def` line for a construction inside a
  multi-line body.

  Keyword pairs are indistinguishable from tuple literals in the AST —
  `[error: "boom"]` and `[{:error, "boom"}]` parse identically — so pairs inside
  list and map literals are never flagged.

  Reasons built at runtime (`"failed: \#{inspect(reason)}"` interpolation or
  `"prefix" <> rest` concatenation) are not literals and are not flagged.
  """
  @explanation [check: @moduledoc]

  @definitions [:def, :defp, :defmacro, :defmacrop]
  @match_operators [:->, :<-, :=]
  @neutralized :__mika_credo_rules_neutralized__

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, excluded_files(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      flag_atoms = Params.get(params, :also_flag_atoms, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, flag_atoms), %{line: nil, issues: []})
      |> Map.fetch!(:issues)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_files(params), do: Params.get(params, :excluded_files, __MODULE__)

  defp excluded_file?(filename, excluded_files) do
    SourceFilter.matches_fragment?(filename, excluded_files)
  end

  defp traverse(ast, acc, flag_atoms) do
    acc = remember_line(acc, ast)
    pruned_ast = ast |> skip_match_positions() |> skip_literal_pairs()

    {pruned_ast, record_construction(ast, acc, flag_atoms)}
  end

  # Two-element tuples of literals carry no metadata, so issues are reported at the
  # line of the nearest enclosing expression that has one.
  defp remember_line(acc, {_form, meta, _args}) when is_list(meta) do
    case meta[:line] do
      nil -> acc
      line -> %{acc | line: line}
    end
  end

  defp remember_line(acc, _ast), do: acc

  # The left side of `->`, `<-` and `=` and a function head are match positions —
  # matching an error tuple someone else constructed is fine, so drop the pattern
  # from the walk and keep only the expression side.
  defp skip_match_positions({operator, meta, [_pattern, expression]})
       when operator in @match_operators do
    {operator, meta, [@neutralized, expression]}
  end

  defp skip_match_positions({definition, meta, [_head | body]})
       when definition in @definitions do
    {definition, meta, [@neutralized | body]}
  end

  defp skip_match_positions(ast), do: ast

  # `%{error: "boom"}` and `[error: "boom"]` contain the pair `{:error, "boom"}`,
  # which is AST-identical to the error tuple. Drop the key and keep walking the
  # value, trading the false positive for a false negative on `[{:error, "boom"}]`.
  defp skip_literal_pairs({:%{}, meta, pairs}) when is_list(pairs) do
    {:%{}, meta, Enum.map(pairs, &neutralize_error_pair/1)}
  end

  defp skip_literal_pairs(list) when is_list(list) do
    Enum.map(list, &neutralize_error_pair/1)
  end

  defp skip_literal_pairs(ast), do: ast

  defp neutralize_error_pair({:error, value}), do: {@neutralized, value}
  defp neutralize_error_pair(element), do: element

  defp record_construction({:error, reason}, acc, _flag_atoms) when is_binary(reason) do
    add_issue(acc, reason)
  end

  defp record_construction({:error, reason}, acc, true) when is_atom(reason) do
    add_issue(acc, reason)
  end

  defp record_construction(_ast, acc, _flag_atoms), do: acc

  defp add_issue(acc, reason) do
    %{acc | issues: [%{reason: inspect(reason), line_no: acc.line} | acc.issues]}
  end

  defp issue_for(construction, issue_meta) do
    trigger = "{:error, #{construction.reason}}"

    format_issue(issue_meta,
      message:
        "#{trigger} found — error tuples must carry a structured %ErrorMessage{}, not a bare literal (e.g. ErrorMessage.not_found(\"message\"))",
      trigger: trigger,
      line_no: construction.line_no
    )
  end
end
