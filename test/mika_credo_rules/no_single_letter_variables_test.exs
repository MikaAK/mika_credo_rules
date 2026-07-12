defmodule MikaCredoRules.NoSingleLetterVariablesTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoSingleLetterVariables

  describe "&run/2 flags single-letter variables at binding sites" do
    test "reports a single-letter def parameter" do
      """
      defmodule MyApp.Worker do
        def double(x), do: x * 2
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "x"
        assert issue.message =~ ~s("x" found)
      end)
    end

    test "reports every single-letter parameter in a multi-arity defp" do
      """
      defmodule MyApp.Worker do
        defp add(a, b), do: a + b
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === ["a", "b"]
      end)
    end

    test "reports a single-letter fn parameter" do
      """
      defmodule MyApp.Worker do
        def run(values), do: Enum.map(values, fn e -> e end)
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.trigger === "e" end)
    end

    test "reports a single-letter binding in a match" do
      """
      defmodule MyApp.Worker do
        def fetch do
          {:ok, v} = call()
          v
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "v"
      end)
    end

    test "reports a single-letter case clause pattern" do
      """
      defmodule MyApp.Worker do
        def describe(value) do
          case value do
            x -> x
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "x"
      end)
    end

    test "reports a single-letter comprehension generator" do
      """
      defmodule MyApp.Worker do
        def double_all(numbers) do
          for n <- numbers, do: n * 2
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.trigger === "n" end)
    end

    test "reports a single-letter with clause binding" do
      """
      defmodule MyApp.Worker do
        def load do
          with {:ok, r} <- fetch() do
            r
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.trigger === "r" end)
    end

    test "reports a single-letter rescue clause binding" do
      """
      defmodule MyApp.Worker do
        def safe_call do
          run!()
        rescue
          e -> {:error, e}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "e"
      end)
    end

    test "reports single-letter bindings inside nested patterns" do
      """
      defmodule MyApp.Worker do
        def unpack(%{items: [h | t]}) do
          {h, t}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === ["h", "t"]
      end)
    end

    test "reports each binding with its own line number" do
      """
      defmodule MyApp.Worker do
        def one(a), do: a
        def two(b), do: b
        def three(c), do: c
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4]
      end)
    end

    test "reports a binding made inside a cond clause head" do
      """
      defmodule MyApp.Worker do
        def check(value) do
          cond do
            (r = transform(value)) > 1 -> r
            true -> :none
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "r"
      end)
    end

    test "reports a guarded parameter exactly once" do
      """
      defmodule MyApp.Worker do
        def positive?(n) when is_integer(n) and n > 0, do: true
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.trigger === "n" end)
    end
  end

  describe "&run/2 ignores non-binding and allowed forms" do
    test "does not report descriptive or two-letter names" do
      """
      defmodule MyApp.Worker do
        def add(id, ok) do
          total = id + 1
          {total, ok}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> refute_issues()
    end

    test "does not report underscore and underscore-prefixed variables" do
      """
      defmodule MyApp.Worker do
        def ignore(_, _x) do
          _y = compute()
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> refute_issues()
    end

    test "does not report a pinned variable, only its original binding" do
      """
      defmodule MyApp.Worker do
        def matches?(x, values) do
          Enum.any?(values, fn
            ^x -> true
            _other -> false
          end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "does not report type variables in a spec" do
      """
      defmodule MyApp.Worker do
        @spec transform(Enumerable.t(), (a -> b)) :: [b] when a: var, b: var
        def transform(enumerable, fun), do: Enum.map(enumerable, fun)
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> refute_issues()
    end

    test "does not report type variables in type and callback attributes" do
      """
      defmodule MyApp.Worker do
        @type mapper(a, b) :: (a -> b)
        @typep pair(a) :: {a, a}
        @opaque wrapped(t) :: {:ok, t}
        @callback run(a, mapper(a, b)) :: b when a: var, b: var
        @macrocallback build(a) :: Macro.t() when a: var
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> refute_issues()
    end

    test "does not report a variable used in a cond clause head, only its binding" do
      """
      defmodule MyApp.Worker do
        def bucket(number) do
          x = compute(number)

          cond do
            x > 10 -> :many
            true -> :few
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "x"
      end)
    end

    test "does not report the receive after head, only real bindings" do
      """
      defmodule MyApp.Worker do
        def loop(t) do
          receive do
            {:msg, m} -> m
          after
            t -> :timed_out
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(&{&1.line_no, &1.trigger}) |> Enum.sort() ===
                 [{2, "t"}, {4, "m"}]
      end)
    end

    test "does not report single-letter module attributes" do
      """
      defmodule MyApp.Worker do
        @v 5

        def value, do: @v
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :allowed_names param" do
    test "allows names given as strings" do
      """
      defmodule MyApp.Worker do
        def repeat(value, i), do: List.duplicate(value, i)
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables, allowed_names: ["i"])
      |> refute_issues()
    end

    test "allows names given as atoms" do
      """
      defmodule MyApp.Worker do
        def repeat(value, i), do: List.duplicate(value, i)
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables, allowed_names: [:i])
      |> refute_issues()
    end

    test "still reports names missing from the allowed list" do
      """
      defmodule MyApp.Worker do
        def pair(i, j), do: {i, j}
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables, allowed_names: ["i"])
      |> assert_issue(fn issue -> assert issue.trigger === "j" end)
    end
  end

  describe "&run/2 reports each binding site once" do
    test "does not double-report a variable bound in an alias pattern" do
      """
      defmodule MyApp.Worker do
        def track(%{count: c} = params) do
          {c, params}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoSingleLetterVariables)
      |> assert_issue(fn issue -> assert issue.trigger === "c" end)
    end
  end
end
