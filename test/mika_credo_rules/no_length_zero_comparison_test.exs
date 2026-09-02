defmodule MikaCredoRules.NoLengthZeroComparisonTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoLengthZeroComparison

  @worker_file "apps/my_app/lib/my_app/worker.ex"

  @moduledoc_examples NoLengthZeroComparison
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoLengthZeroComparison"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end
  end

  describe "&run/2 flags length-zero comparisons via equality operators" do
    test "reports length(x) === 0" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "==="
        assert issue.message =~ "=== 0 found"
        assert issue.message =~ "Enum.empty?(list)"
      end)
    end

    test "reports 0 === length(x) with the literal on the left" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: 0 === length(list)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.trigger === "==="
        assert issue.message =~ "Enum.empty?(list)"
      end)
    end

    test "reports length(x) == 0" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) == 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "== 0 found" end)
    end

    test "reports length(x) !== 0 with not-empty advice" do
      """
      defmodule MyApp.Worker do
        def some?(list), do: length(list) !== 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.trigger === "!=="
        assert issue.message =~ "not Enum.empty?(list)"
        assert issue.message =~ "!== []"
      end)
    end

    test "reports length(x) != 0" do
      """
      defmodule MyApp.Worker do
        def some?(list), do: length(list) != 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "!= 0 found" end)
    end
  end

  describe "&run/2 flags length-zero comparisons via relational operators" do
    test "reports length(x) > 0" do
      """
      defmodule MyApp.Worker do
        def some?(list), do: length(list) > 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.trigger === ">"
        assert issue.message =~ "not Enum.empty?(list)"
      end)
    end

    test "reports length(x) >= 1" do
      """
      defmodule MyApp.Worker do
        def some?(list), do: length(list) >= 1
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.trigger === ">="
        assert issue.message =~ "not Enum.empty?(list)"
      end)
    end

    test "reports a guard clause with guard-safe advice" do
      """
      defmodule MyApp.Worker do
        def process(list) when length(list) > 0, do: list
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Enum.empty?(list)"
        assert issue.message =~ "!== []"
        assert issue.message =~ "guard"
      end)
    end
  end

  describe "&run/2 flags Enum.count/1 but not the 2-arity predicate form" do
    test "reports Enum.count(x) === 0" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "Enum.empty?(collection)" end)
    end

    test "does not report Enum.count(x, predicate) === 0" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: Enum.count(collection, & &1.active) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not offer the guard-safe alternative for an Enum.count/1 match" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Enum.empty?(collection)"
        refute issue.message =~ "guard"
      end)
    end
  end

  describe "&run/2 stays silent on the closest lookalikes" do
    test "does not report length(x) === 3" do
      """
      defmodule MyApp.Worker do
        def three?(list), do: length(list) === 3
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not report length(x) === len (variable, not a literal)" do
      """
      defmodule MyApp.Worker do
        def same?(list, len), do: length(list) === len
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not report String.length(s) === 0 (a different function)" do
      """
      defmodule MyApp.Worker do
        def none?(string), do: String.length(string) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not report length(x) < 1 — <  is not a handled operator (documented false negative)" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) < 1
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not report length(x) <= 0 — <= is not a handled operator (documented false negative)" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) <= 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves Enum.count through aliasing" do
    test "reports the fully-qualified Elixir.Enum.count/1" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: Elixir.Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue()
    end

    test "reports the Elixir-prefixed atom spelling :\"Elixir.Enum\".count/1" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: :"Elixir.Enum".count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "Enum.empty?(collection)" end)
    end

    test "reports an aliased E.count/1 under alias Enum, as: E" do
      """
      defmodule MyApp.Worker do
        alias Enum, as: E

        def none?(collection), do: E.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue()
    end

    test "does not report bare Enum.count/1 once Enum is shadowed" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Vendor.Enum

        def none?(collection), do: Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "does not report bare Enum.count/1 once Enum is shadowed by a nested defmodule" do
      """
      defmodule MyApp.Worker do
        defmodule Enum do
          def count(_collection), do: 0
        end

        def none?(collection), do: Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> refute_issues()
    end

    test "still reports the fully-qualified Elixir.Enum.count/1 once Enum is shadowed by a nested defmodule" do
      """
      defmodule MyApp.Worker do
        defmodule Enum do
          def count(_collection), do: 0
        end

        def none?(collection), do: Elixir.Enum.count(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue()
    end
  end

  describe "&run/2 supports param overrides" do
    test "honours a custom :local_functions entry" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: size(list) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison, local_functions: [:size])
      |> assert_issue(fn issue -> assert issue.message =~ "Enum.empty?(list)" end)
    end

    test "no longer reports length/1 once :local_functions is overridden away" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison, local_functions: [:size])
      |> refute_issues()
    end

    test "honours a custom :remote_functions entry" do
      """
      defmodule MyApp.Worker do
        def none?(collection), do: MyApp.Collection.size(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison, remote_functions: [{MyApp.Collection, :size}])
      |> assert_issue(fn issue -> assert issue.message =~ "Enum.empty?(collection)" end)
    end

    test "still reports a multi-segment :remote_functions module even when the file defines it" do
      """
      defmodule MyApp.Collection do
        def size(_collection), do: 0
        def none?(collection), do: MyApp.Collection.size(collection) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison, remote_functions: [{MyApp.Collection, :size}])
      |> assert_issue(fn issue -> assert issue.message =~ "Enum.empty?(collection)" end)
    end
  end

  describe "&run/2 locates the issue at the operator column" do
    test "reports a column matching the operator" do
      """
      defmodule MyApp.Worker do
        def none?(list), do: length(list) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issue(fn issue -> assert issue.column === 37 end)
    end

    test "gives two comparisons on one line their own columns" do
      """
      defmodule MyApp.Worker do
        def none?(first, second), do: length(first) === 0 && length(second) === 0
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoLengthZeroComparison)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
