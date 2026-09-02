defmodule MikaCredoRules.NoDoPrefixedHelperTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoDoPrefixedHelper

  @lib_file "apps/my_app/lib/my_app/importer.ex"

  @moduledoc_examples NoDoPrefixedHelper
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoDoPrefixedHelper"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a def name + defp do_name pair" do
    test "reports the defp do_process head line, trigger, and message" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "do_process"
        assert issue.message =~ "do_process"
        assert issue.message =~ "process"
      end)
    end

    test "reports a column pointing at the do_process identifier" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.column === 8 end)
    end

    test "fires regardless of a mismatched arity between name and do_name" do
      """
      defmodule MyApp.Importer do
        def process(row), do: do_process(row, [], :strict)

        defp do_process(row, acc, mode) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_process" end)
    end

    test "fires when do_process is defined above process in source order" do
      """
      defmodule MyApp.Importer do
        defp do_process(row, acc) do
          [row | acc]
        end

        def process(row) do
          do_process(row, [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "unwraps a guard clause head to find the do_process identifier" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row)
        end

        defp do_process(row) when is_list(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue ->
        assert issue.trigger === "do_process"
        assert issue.line_no === 6
      end)
    end
  end

  describe "&run/2 flags a defp name + defp do_name pair" do
    test "reports the defp do_name head" do
      """
      defmodule MyApp.Importer do
        defp process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_process" end)
    end
  end

  describe "&run/2 does not crash on a metaprogrammed def head" do
    test "a `for` comprehension generating def unquote(name)(args) heads does not raise" do
      """
      defmodule MyApp.Gen do
        for name <- [:alpha, :beta] do
          def unquote(name)(row), do: row
        end

        defp do_alpha(row), do: row
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "a defp unquote(:do_process)(row) head does not raise" do
      """
      defmodule MyApp.Gen do
        defp unquote(:do_process)(row), do: row
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a multi-clause do_name helper once, not once per clause" do
    test "reports exactly one issue at the earliest clause's line" do
      """
      defmodule MyApp.Importer do
        def process(row), do: do_process(row)

        defp do_process([]), do: []
        defp do_process([head | rest]), do: [head | do_process(rest)]
        defp do_process(nil), do: []
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end
  end

  describe "&run/2 leaves a do_-prefixed helper with no sibling alone" do
    test "does not report a recursion accumulator with no public twin" do
      """
      defmodule MyApp.Importer do
        def normalize(rows) do
          do_process(rows, [])
        end

        defp do_process([], acc), do: acc
        defp do_process([head | rest], acc), do: do_process(rest, [head | acc])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "does not report def do_something when no something exists" do
      """
      defmodule MyApp.Importer do
        def do_something(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "does not report a public def do_something even when something exists" do
      """
      defmodule MyApp.Importer do
        def something(row), do: row

        def do_something(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes per module" do
    test "does not report a pair split across an outer module and a nested one" do
      """
      defmodule MyApp.Outer do
        def process(row), do: row

        defmodule Inner do
          defp do_process(row), do: row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "does not report a pair split across two sibling modules in one file" do
      """
      defmodule MyApp.A do
        def process(row), do: row
      end

      defmodule MyApp.B do
        defp do_process(row), do: row
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "still reports a real pair inside a nested module" do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          def process(row) do
            do_process(row)
          end

          defp do_process(row), do: row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end

    test "does not pair a defimpl's do_ helper with an unrelated def in the enclosing module" do
      """
      defmodule MyApp.Row do
        defstruct [:value]
        def process(row), do: row.value

        defimpl Jason.Encoder do
          def encode(row, opts), do: do_process(row, opts)
          defp do_process(row, opts), do: Jason.Encode.map(%{value: row.value}, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "still reports a real pair living entirely inside a defimpl" do
      """
      defmodule MyApp.Row do
        defstruct [:value]

        defimpl Jason.Encoder do
          def encode(row, opts), do: do_encode(row, opts)
          defp do_encode(row, opts), do: Jason.Encode.map(%{value: row.value}, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_encode" end)
    end

    test "still reports a real pair living entirely inside a defprotocol" do
      """
      defmodule MyApp.Proto do
        defprotocol Formattable do
          def format(row)
          defp do_format(row), do: format(row)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_format" end)
    end

    test "still reports a real pair living entirely inside a keyword-do defimpl" do
      """
      defmodule MyApp.Row do
        defstruct [:value]

        defimpl Jason.Encoder, for: MyApp.Row, do: (
          def encode(row, opts), do: do_encode(row, opts)
          defp do_encode(row, opts), do: Jason.Encode.map(%{value: row.value}, opts)
        )
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_encode" end)
    end
  end

  describe "&run/2 scopes a quote block independently" do
    test "does not pair a def injected by a __using__ macro's quote with an unrelated do_ recursion accumulator" do
      """
      defmodule MyApp.Injector do
        defmacro __using__(_opts) do
          quote do
            def process(row), do: row
          end
        end

        defp do_process([], acc), do: acc
        defp do_process([head | rest], acc), do: do_process(rest, [head | acc])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "still reports a real pair both injected by the same __using__ macro's quote" do
      """
      defmodule MyApp.Injector do
        defmacro __using__(_opts) do
          quote do
            def aggregate(distribution, trade), do: do_aggregate(distribution, trade)

            defp do_aggregate(distribution, trade) do
              distribution
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_aggregate" end)
    end
  end

  describe "&run/2 never collects a defmacro/defmacrop or defdelegate as a sibling" do
    test "does not pair a defmacro with a defp do_name of the same base name" do
      """
      defmodule MyApp.Importer do
        defmacro process(row) do
          quote do: unquote(row)
        end

        defp do_process(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "does not pair a defmacrop with a defp do_name of the same base name" do
      """
      defmodule MyApp.Importer do
        defmacrop process(row) do
          quote do: unquote(row)
        end

        defp do_process(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end

    test "does not pair a defdelegate with a defp do_name of the same base name" do
      """
      defmodule MyApp.Importer do
        defdelegate process(row), to: MyApp.Other

        defp do_process(row) do
          row
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> refute_issues()
    end
  end

  describe "&run/2 gives two triggers on one line distinct columns" do
    test "reports do_a and do_b at different columns when split by a semicolon" do
      """
      defmodule MyApp.Importer do
        def a(row), do: row
        def b(row), do: row

        defp do_a(row), do: row; defp do_b(row), do: row
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
        assert Enum.sort([first.trigger, second.trigger]) === ["do_a", "do_b"]
      end)
    end
  end

  describe "&run/2 does not crash on quote/defimpl used as a bare variable" do
    test "a `quote` parameter alongside a real do_-pair still reports exactly one issue" do
      """
      defmodule MyApp.Quotes do
        def price(quote) do
          quote.last
        end

        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_process" end)
    end

    test "a `defimpl` parameter alongside a real do_-pair still reports exactly one issue" do
      """
      defmodule MyApp.Handlers do
        def which(defimpl) do
          defimpl
        end

        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue(fn issue -> assert issue.trigger === "do_process" end)
    end
  end

  describe "&run/2 respects :excluded_paths" do
    test "does not report a file matching an excluded path" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file("apps/my_app/lib/vendor/importer.ex")
      |> run_check(NoDoPrefixedHelper, excluded_paths: ["vendor/"])
      |> refute_issues()
    end

    test "still reports a boundary-lookalike path (lib/vendored/ does not end with vendor/)" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file("apps/my_app/lib/vendored/importer.ex")
      |> run_check(NoDoPrefixedHelper, excluded_paths: ["vendor/"])
      |> assert_issue()
    end

    test "defaults to checking every file (:excluded_paths defaults to [])" do
      """
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end
      """
      |> to_source_file("apps/my_app/lib/vendor/importer.ex")
      |> run_check(NoDoPrefixedHelper)
      |> assert_issue()
    end
  end
end
