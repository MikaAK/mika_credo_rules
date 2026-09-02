defmodule MikaCredoRules.AsyncTrueRequired do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      case_suffixes: ["Case"],
      test_files: ["_test.exs"]
    ],
    explanations: [
      params: [
        case_suffixes: """
        A list of suffixes identifying a test case module by the last segment
        of the module named in `use`, exactly as written at the call site —
        not its resolved identity. Defaults to `["Case"]`, which catches
        `ExUnit.Case`, `MyApp.DataCase`, and `MyApp.ConnCase` without listing
        every project's case module by name. `Wallaby.Feature` is
        deliberately not a default target — see `## Limitations` — but can be
        added here (e.g. `["Case", "Feature"]`) for a project that wants it
        checked anyway. A non-list value is wrapped as a single-element
        list; a non-string element is coerced with `to_string/1`.
        """,
        test_files: """
        A list of filename suffixes this check runs on. Defaults to
        `["_test.exs"]` — only ExUnit test files are scanned; a `use` in
        library code is out of scope.
        """
      ]
    ]

  alias Credo.Code.Name
  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `use`d test case module must declare `:async` explicitly.

  Leaving `async:` unstated hides sandbox misuse a concurrent run would
  surface — a test that only passes because it never races another test —
  and, for a project's own case module, means the *effective* default
  (serial or async) lives wherever that macro's body decides it, not at the
  call site. Every test case should state its concurrency choice on
  purpose, not depend on an implicit default.

      # BAD — async left to ExUnit's serial default
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end

      # GOOD — the choice is explicit
      defmodule MyApp.OrdersTest do
        use ExUnit.Case, async: true
      end

  `:case_suffixes` matches the last segment of the `use`d module as written,
  so `use MyApp.DataCase` and `use MyApp.ConnCase` are caught by the default
  `"Case"` suffix, without this check needing to name every project's case
  module. Only a literal keyword list is inspected — `use MyApp.DataCase,
  @data_case_opts` cannot be reasoned about statically and is left alone.

  This overlaps with Credo's own `Credo.Check.Refactor.PassAsyncInTestCases`,
  which recognises the same `"Case"` suffix and scopes itself via `files:`
  globs (inert under `Credo.Test.Case`, see `writing-credo-checks`). This
  check scopes itself with a `run/2` guard on `:test_files` instead.

  ## Limitations

  An explicit `async: false` opt-out is never flagged here — deliberately
  turning concurrency off for a test case that cannot run in parallel is a
  different, narrower problem than never having stated a choice at all;
  `BlitzCredoChecks.NoAsyncFalse` is the check for that. `use
  ExUnit.CaseTemplate` is not itself a test case, it defines one — its last
  segment, `"CaseTemplate"`, does not end in the default `"Case"` suffix
  (`String.ends_with?("CaseTemplate", "Case")` is `false`), so it is
  correctly never flagged.

  `Wallaby.Feature` is deliberately not a default `:case_suffixes` target.
  `Wallaby.Feature.__using__/1` ignores every option it is given and never
  itself calls `use ExUnit.Case` — it requires a separate case `use` above it
  that already carries `:async`. Flagging the `Wallaby.Feature` line would
  recommend `use Wallaby.Feature, async: true`, an option Wallaby silently
  discards; the real fix belongs to the case module above it, which the
  default `"Case"` suffix already covers.

  This check cannot see through a `use`d macro's own body, so it cannot tell
  whether an omitted `:async` actually falls back to a serial run (plain
  `ExUnit.Case`) or an async one (some house case modules default the other
  way). The message asks for an explicit choice either way, rather than
  asserting what the implicit one is.

  A `use` written as the quoted atom `:"Elixir.ExUnit.Case"` is matched the
  same as the alias-path spelling. A `use` nested inside a `quote do ... end`
  block is never flagged — its `:async` option belongs to whatever calls the
  surrounding macro, not to the quoted line itself, so flagging it would
  recommend hardcoding a choice for every caller.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if checked_file?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      case_suffixes = Params.get(params, :case_suffixes, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, case_suffixes))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp checked_file?(filename, params) do
    SourceFilter.matches_suffix?(filename, List.wrap(Params.get(params, :test_files, __MODULE__)))
  end

  # Hand-rolled rather than AstHelpers.use_options/2: that helper matches a
  # `use`d module against a resolved *identity* (module_paths), but this
  # check matches by the last segment's *suffix* as written — a different
  # question use_options/2 has no arity for.
  defp traverse({:use, meta, [{:__aliases__, _, segments}]} = ast, missing_async, case_suffixes) do
    collect_missing_async(ast, meta, segments, [], missing_async, case_suffixes)
  end

  defp traverse(
         {:use, meta, [{:__aliases__, _, segments}, opts]} = ast,
         missing_async,
         case_suffixes
       ) do
    collect_missing_async(ast, meta, segments, opts, missing_async, case_suffixes)
  end

  # The quoted-atom module spelling, e.g. `use :"Elixir.ExUnit.Case"` — the
  # AST module slot is a bare atom rather than an `__aliases__` path. See
  # AstHelpers.use_module?/2 for the same three-spellings distinction.
  # `Module.split/1` yields strings, not atoms — `case_module?/2` and
  # `Credo.Code.Name.full/1` both already accept either, so segments stay
  # strings here instead of round-tripping through `String.to_atom/1`.
  defp traverse({:use, meta, [module]} = ast, missing_async, case_suffixes)
       when is_atom(module) do
    collect_missing_async_for_atom(ast, meta, module, [], missing_async, case_suffixes)
  end

  defp traverse({:use, meta, [module, opts]} = ast, missing_async, case_suffixes)
       when is_atom(module) do
    collect_missing_async_for_atom(ast, meta, module, opts, missing_async, case_suffixes)
  end

  # A `use` inside a `quote do ... end` block belongs to the macro's caller,
  # not the quoted line — prune the subtree so it is never visited.
  defp traverse({:quote, _meta, _args}, missing_async, _case_suffixes), do: {nil, missing_async}

  defp traverse(ast, missing_async, _case_suffixes), do: {ast, missing_async}

  defp collect_missing_async_for_atom(ast, meta, module, opts, missing_async, case_suffixes) do
    if elixir_prefixed_atom?(module) do
      collect_missing_async(ast, meta, Module.split(module), opts, missing_async, case_suffixes)
    else
      {ast, missing_async}
    end
  end

  defp elixir_prefixed_atom?(module), do: String.starts_with?(Atom.to_string(module), "Elixir.")

  defp collect_missing_async(ast, meta, segments, opts, missing_async, case_suffixes) do
    if case_module?(segments, case_suffixes) and missing_async_key?(opts) do
      {ast, [use_call(segments, meta) | missing_async]}
    else
      {ast, missing_async}
    end
  end

  defp case_module?(segments, case_suffixes) do
    last_segment = segments |> List.last() |> to_string()

    Enum.any?(List.wrap(case_suffixes), &String.ends_with?(last_segment, to_string(&1)))
  end

  # keyword_literal_has_key?/2 is tri-state — :not_literal means "options
  # built at runtime", which must not count as missing.
  defp missing_async_key?(opts),
    do: match?(false, AstHelpers.keyword_literal_has_key?(opts, :async))

  defp use_call(segments, meta) do
    %{module: Name.full(segments), line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(use_call, issue_meta) do
    format_issue(issue_meta,
      message:
        "use #{use_call.module} without :async found — state the concurrency choice explicitly (async: true or async: false) instead of leaving it implicit",
      trigger: "use",
      line_no: use_call.line_no,
      column: use_call.column
    )
  end
end
