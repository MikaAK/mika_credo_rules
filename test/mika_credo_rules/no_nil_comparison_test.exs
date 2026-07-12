defmodule MikaCredoRules.NoNilComparisonTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoNilComparison

  @worker_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags equality comparisons with nil" do
    test "reports x == nil" do
      """
      defmodule MyApp.Worker do
        def missing?(value), do: value == nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message === "== nil found — use is_nil(value) instead"
      end)
    end

    test "reports x === nil" do
      """
      defmodule MyApp.Worker do
        def missing?(value), do: value === nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "=== nil found — use is_nil(value) instead"
      end)
    end

    test "reports nil on the left (nil == x)" do
      """
      defmodule MyApp.Worker do
        def missing?(value), do: nil == value
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "== nil found — use is_nil(value) instead"
      end)
    end

    test "names the full expression in the replacement" do
      """
      defmodule MyApp.Worker do
        def missing?(map), do: Map.get(map, :key) == nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "== nil found — use is_nil(Map.get(map, :key)) instead"
      end)
    end
  end

  describe "&run/2 flags inequality comparisons with nil" do
    test "reports x != nil" do
      """
      defmodule MyApp.Worker do
        def present?(value), do: value != nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message === "!= nil found — use not is_nil(value) instead"
      end)
    end

    test "reports x !== nil" do
      """
      defmodule MyApp.Worker do
        def present?(value), do: value !== nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "!== nil found — use not is_nil(value) instead"
      end)
    end

    test "reports nil on the left (nil != x)" do
      """
      defmodule MyApp.Worker do
        def present?(value), do: nil != value
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "!= nil found — use not is_nil(value) instead"
      end)
    end
  end

  describe "&run/2 flags nil comparisons in guards" do
    test "reports a nil comparison in a def guard" do
      """
      defmodule MyApp.Worker do
        def fallback(value) when value == nil, do: :default
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message === "== nil found — use is_nil(value) instead"
      end)
    end

    test "reports a nil comparison in a case clause guard" do
      """
      defmodule MyApp.Worker do
        def unwrap(value) do
          case value do
            other when other !== nil -> other
            _ -> :default
          end
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issue(fn issue ->
        assert issue.message === "!== nil found — use not is_nil(other) instead"
      end)
    end
  end

  describe "&run/2 reports each call site with its own line number" do
    test "reports three comparisons on three lines" do
      """
      defmodule MyApp.Worker do
        def one(value), do: value == nil
        def two(value), do: value !== nil
        def three(value), do: nil === value
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> assert_issues(fn issues ->
        assert length(issues) === 3
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4]
      end)
    end
  end

  describe "&run/2 does not flag correct nil checks" do
    test "does not report is_nil/1 and not is_nil/1" do
      """
      defmodule MyApp.Worker do
        def missing?(value), do: is_nil(value)
        def present?(value), do: not is_nil(value)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> refute_issues()
    end

    test "does not report comparisons without a nil operand" do
      """
      defmodule MyApp.Worker do
        def same?(left, right), do: left === right
        def five?(value), do: value == 5
        def named_nil?(name), do: name == "nil"
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> refute_issues()
    end

    test "does not report matching nil in a case pattern" do
      """
      defmodule MyApp.Worker do
        def unwrap(value) do
          case value do
            nil -> :default
            other -> other
          end
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> refute_issues()
    end

    test "does not report nil passed as an argument" do
      """
      defmodule MyApp.Worker do
        def fetch(map), do: Map.get(map, :key, nil)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :operators param" do
    test "flags only the configured operators" do
      """
      defmodule MyApp.Worker do
        def strict?(value), do: value === nil
        def loose?(value), do: value == nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison, operators: [:===])
      |> assert_issue(fn issue ->
        assert issue.message === "=== nil found — use is_nil(value) instead"
      end)
    end

    test "reports nothing when the operator list excludes the comparison" do
      """
      defmodule MyApp.Worker do
        def present?(value), do: value != nil
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoNilComparison, operators: [:==, :===])
      |> refute_issues()
    end
  end
end
