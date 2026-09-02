# This file's own `use Credo.Test.Case` below has no explicit :async — a
# real instance of what this check flags, not a false positive: Credo.Test.Case
# happens to default to async: true internally (see the AsyncTrueRequired
# moduledoc's Limitations), but this check cannot see through that macro to
# know it, and asks for the choice to be stated regardless.
# credo:disable-for-this-file MikaCredoRules.AsyncTrueRequired
defmodule MikaCredoRules.AsyncTrueRequiredTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.AsyncTrueRequired
  alias MikaCredoRules.DocExamples

  @test_file "apps/my_app/test/my_app/orders_test.exs"
  @lib_file "apps/my_app/lib/my_app/orders.ex"

  @moduledoc_examples AsyncTrueRequired
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "AsyncTrueRequired"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a test case module with no async: key" do
    test "reports use ExUnit.Case with no opts at all" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "use"
        assert issue.message =~ "ExUnit.Case"
        assert issue.message =~ "async"
      end)
    end

    test "reports use MyApp.DataCase with no opts at all" do
      """
      defmodule MyApp.OrdersTest do
        use MyApp.DataCase

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "MyApp.DataCase"
      end)
    end

    test "reports opts present but missing the :async key" do
      """
      defmodule MyApp.OrdersTest do
        use MyApp.ConnCase, register: false

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "MyApp.ConnCase"
      end)
    end
  end

  describe "&run/2 allows an explicit async choice" do
    test "does not report async: true" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case, async: true

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end

    test "does not report an explicit async: false opt-out" do
      """
      defmodule MyApp.OrdersTest do
        use MyApp.DataCase, async: false

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not treat CaseTemplate as a case suffix" do
    test "does not report use ExUnit.CaseTemplate" do
      """
      defmodule MyApp.SharedCase do
        use ExUnit.CaseTemplate
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not target Wallaby.Feature by default" do
    test "does not report a bare use Wallaby.Feature below a case module that already declares async" do
      """
      defmodule MyApp.CheckoutFeatureTest do
        use MyApp.FeatureCase, async: true
        use Wallaby.Feature

        test "checks out" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 renders a non-atom __aliases__ segment without crashing" do
    test "reports use __MODULE__.Case without raising" do
      """
      defmodule MyApp.OrdersTest do
        use __MODULE__.Case

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue(fn issue ->
        assert issue.message =~ "__MODULE__.Case"
      end)
    end
  end

  describe "&run/2 matches the quoted Elixir-atom module spelling" do
    test "reports use :\"Elixir.ExUnit.Case\" without opts" do
      """
      defmodule MyApp.OrdersTest do
        use :"Elixir.ExUnit.Case"
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issue(fn issue ->
        assert issue.message =~ "ExUnit.Case"
      end)
    end

    test "does not report use :\"Elixir.ExUnit.Case\", async: true" do
      """
      defmodule MyApp.OrdersTest do
        use :"Elixir.ExUnit.Case", async: true
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end

    test "does not report a plain erlang atom used as a module" do
      """
      defmodule MyApp.OrdersTest do
        use :some_erlang_module
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag a use nested inside a quote do block" do
    test "does not report a use inside a defmacro's quoted body" do
      """
      defmodule MyApp.OrdersTest do
        defmacro __using__(_opts) do
          quote do
            use ExUnit.Case
          end
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves a non-literal option list alone" do
    test "does not report a module attribute splat" do
      """
      defmodule MyApp.OrdersTest do
        use MyApp.DataCase, @data_case_opts

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 is scoped to test files via :test_files" do
    test "does not scan a non-test file" do
      """
      defmodule MyApp.Orders do
        use ExUnit.Case
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(AsyncTrueRequired)
      |> refute_issues()
    end

    test "still checks a lookalike lib path that merely contains the _test.exs suffix" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file("apps/my_app/lib/generated/orders_test.exs")
      |> run_check(AsyncTrueRequired)
      |> assert_issue()
    end
  end

  describe "&run/2 honours a custom :test_files" do
    test "reports a feature file with a custom suffix" do
      """
      defmodule MyApp.CheckoutCase do
        use MyApp.DataCase
      end
      """
      |> to_source_file("apps/my_app/test/features/checkout_feature.exs")
      |> run_check(AsyncTrueRequired, test_files: ["_feature.exs"])
      |> assert_issue()
    end

    test "does not report the default suffix when :test_files is overridden" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, test_files: ["_feature.exs"])
      |> refute_issues()
    end

    test "tolerates a bare string instead of a list without raising" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, test_files: "_test.exs")
      |> assert_issue()
    end
  end

  describe "&run/2 honours a custom :case_suffixes" do
    test "reports a module ending in a custom suffix" do
      """
      defmodule MyApp.OrdersSpec do
        use MyApp.Spec
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, case_suffixes: ["Spec"])
      |> assert_issue()
    end

    test "does not report the default Case suffix when :case_suffixes is overridden" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, case_suffixes: ["Spec"])
      |> refute_issues()
    end

    test "tolerates a bare string instead of a list without raising" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, case_suffixes: "Case")
      |> assert_issue()
    end

    test "tolerates a bare atom in place of a string without raising" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, case_suffixes: :Case)
      |> assert_issue()
    end

    test "tolerates a non-string element mixed into the suffix list without raising" do
      """
      defmodule MyApp.OrdersSpec do
        use MyApp.Spec
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired, case_suffixes: [:Case, "Spec"])
      |> assert_issue()
    end
  end

  describe "&run/2 locates each issue at the use keyword's own column" do
    test "gives two uses on one line distinct columns" do
      """
      defmodule MyApp.OrdersTest do
        use ExUnit.Case; use MyApp.ConnCase, register: false

        test "creates an order" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(AsyncTrueRequired)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
