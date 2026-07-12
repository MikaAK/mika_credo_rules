defmodule MikaCredoRules.NoProcessSleepInTests do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      test_files: ["_test.exs"],
      functions: [{Process, :sleep}, {:timer, :sleep}]
    ],
    explanations: [
      params: [
        test_files: """
        A list of file path suffixes treated as test files. The check only runs on a
        source file whose path ends with one of these.

        Defaults to `["_test.exs"]`, which covers ExUnit test files in both an
        umbrella (`apps/my_app/test/my_app/worker_test.exs`) and a single app
        (`test/my_app/worker_test.exs`).
        """,
        functions: """
        A list of `{module, function}` tuples naming the sleep functions to flag.
        Defaults to `Process.sleep/1` and erlang's `:timer.sleep/1`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Tests must not sleep — sleeping is the number one source of flaky, slow suites.

  A `Process.sleep/1` in a test guesses how long the system under test needs. The
  guess is either too short (flaky under load) or too long (slow suite), and it is
  usually both over the life of the test. Synchronize on the event itself instead:
  `assert_receive`/`refute_receive` with a timeout, `Task.await/2`, or a polling
  helper that re-checks a condition until a deadline.

      # BAD — guesses that 100ms is enough for the broadcast to arrive
      test "broadcasts the update" do
        Orders.update_status(order, :shipped)
        Process.sleep(100)
        assert_received {:order_updated, %{status: :shipped}}
      end

      # GOOD — waits exactly as long as needed, up to a timeout
      test "broadcasts the update" do
        Orders.update_status(order, :shipped)
        assert_receive {:order_updated, %{status: :shipped}}, 500
      end

  Both the Elixir and the erlang spelling are caught:

      Process.sleep(100)   # caught
      :timer.sleep(100)    # caught

  The check only runs on test files, identified by filename via the `:test_files`
  param — a sleep in `lib/` code (backoff, rate limiting) is outside this rule.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if test_file?(source_file.filename, test_files(params)) do
      issue_meta = IssueMeta.for(source_file, params)
      matchers = params |> Params.get(:functions, __MODULE__) |> build_matchers()

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, matchers))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp test_files(params), do: Params.get(params, :test_files, __MODULE__)

  defp test_file?(filename, test_files) do
    SourceFilter.matches_suffix?(filename, test_files)
  end

  # Elixir modules appear in the AST as alias part lists, in both their plain and
  # fully qualified spelling. Erlang modules appear as bare atoms.
  defp build_matchers(functions), do: Enum.flat_map(functions, &expand_matcher/1)

  defp expand_matcher({module, function}) do
    case Atom.to_string(module) do
      "Elixir." <> _rest ->
        # Bounded input: the :functions check param from .credo.exs (a handful of
        # module names supplied by the developer), never scanned source code.
        # skill-ok: string-to-atom
        parts = module |> Module.split() |> Enum.map(&String.to_atom/1)
        [{parts, function}, {[Elixir | parts], function}]

      _erlang_module ->
        [{module, function}]
    end
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         sleep_calls,
         matchers
       )
       when is_list(args) do
    if {module, function} in matchers do
      {ast, [sleep_call(Enum.join(module, "."), function, args, meta) | sleep_calls]}
    else
      {ast, sleep_calls}
    end
  end

  defp traverse({{:., _, [module, function]}, meta, args} = ast, sleep_calls, matchers)
       when is_atom(module) and is_list(args) do
    if {module, function} in matchers do
      {ast, [sleep_call(":#{module}", function, args, meta) | sleep_calls]}
    else
      {ast, sleep_calls}
    end
  end

  defp traverse(ast, sleep_calls, _matchers), do: {ast, sleep_calls}

  defp sleep_call(module, function, args, meta) do
    %{module: module, function: function, arity: length(args), line_no: meta[:line]}
  end

  defp issue_for(sleep_call, issue_meta) do
    trigger = "#{sleep_call.module}.#{sleep_call.function}"

    format_issue(issue_meta,
      message:
        "#{trigger}/#{sleep_call.arity} found — tests must synchronize with assert_receive/refute_receive or a polling helper instead of sleeping",
      trigger: trigger,
      line_no: sleep_call.line_no
    )
  end
end
