defmodule MikaCredoRules.NoBooleanLiteralComparisonTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoBooleanLiteralComparison

  describe "&run/2 flags comparisons against a boolean literal" do
    test "reports x == true" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin == true
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "== true found"
        assert issue.message =~ "boolean literal"
        refute issue.message =~ "guaranteed boolean"
      end)
    end

    test "reports x === true" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin === true
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "=== true found" end)
    end

    test "reports x != false with advice softened for non-boolean operands" do
      """
      defmodule MyApp.Worker do
        def active?(status), do: status != false
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue ->
        assert issue.message =~ "!= false found"
        assert issue.message =~ "guaranteed boolean"
      end)
    end

    test "reports x !== false with advice softened for non-boolean operands" do
      """
      defmodule MyApp.Worker do
        def active?(status), do: status !== false
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue ->
        assert issue.message =~ "!== false found"
        assert issue.message =~ "guaranteed boolean"
      end)
    end

    test "reports the mirrored true == x form" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: true == user.admin
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "== true found" end)
    end

    test "reports the mirrored false != x form" do
      """
      defmodule MyApp.Worker do
        def active?(status), do: false != status
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue -> assert issue.message =~ "!= false found" end)
    end

    test "reports a comparison inside a guard" do
      """
      defmodule MyApp.Worker do
        def label(x) when x == true, do: :yes
        def label(_x), do: :no
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports two triggers on the same line at their own columns" do
      """
      defmodule MyApp.Worker do
        def check(a, b), do: (a == true) && (b != false)
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.column) |> Enum.sort() === [27, 42]
      end)
    end
  end

  describe "&run/2 allows non-boolean-literal comparisons" do
    test "does not report strict comparison against a non-boolean value" do
      """
      defmodule MyApp.Worker do
        def adult?(age), do: age === 18
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report using the boolean value directly" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin
        def not_admin?(user), do: not user.admin
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores the Ecto query DSL" do
    test "does not report a boolean literal comparison inside bare where via import" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def active(query) do
          where(query, [u], u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report a boolean literal comparison inside from's where: keyword form" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def active do
          from(u in User, where: u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report through alias Ecto.Query" do
      """
      defmodule MyApp.Users do
        alias Ecto.Query

        def active(query) do
          Query.where(query, [u], u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report through alias Ecto.Query, as: Q" do
      """
      defmodule MyApp.Users do
        alias Ecto.Query, as: Q

        def active(query) do
          Q.where(query, [u], u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report through a multi-alias of Ecto.Query" do
      """
      defmodule MyApp.Users do
        alias Ecto.{Changeset, Query}

        def active(query) do
          Query.where(query, [u], u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "still reports alias MyApp.Query — over-correction probe" do
      """
      defmodule MyApp.Users do
        alias MyApp.Query

        def active(query) do
          Query.where(query, [u], u.active == true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue()
    end

    test "still reports a boolean literal comparison beside a query call on the same line" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def filter(query, flag),
          do: if(flag == true, do: query, else: where(query, [u], u.active == true))
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end
  end

  describe "&run/2 honours the :operators param" do
    test "flags only the configured operators" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin == true
        def active?(status), do: status != false
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison, operators: [:==])
      |> assert_issue(fn issue -> assert issue.message =~ "== true found" end)
    end
  end

  describe "&run/2 honours the :ignored_functions param" do
    test "exempts a custom function name" do
      """
      defmodule MyApp.Users do
        def adults(query), do: scope(query, [u], u.active == true)
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison, ignored_functions: [:scope])
      |> refute_issues()
    end

    test "flags where once it is no longer ignored" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def active(query), do: where(query, [u], u.active == true)
      end
      """
      |> to_source_file()
      |> run_check(NoBooleanLiteralComparison, ignored_functions: [])
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report a file under an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        def admin?(user), do: user.admin == true
      end
      """
      |> to_source_file("lib/my_app/legacy/worker.ex")
      |> run_check(NoBooleanLiteralComparison, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "&run/2 excludes test files by default" do
    test "does not report assert x === true in a _test.exs file" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        test "times out" do
          assert state.timeout === false
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "does not report a boolean literal comparison anywhere under test/" do
      """
      defmodule MyApp.Support.Helper do
        def admin?(user), do: user.admin === true
      end
      """
      |> to_source_file("test/support/helper.ex")
      |> run_check(NoBooleanLiteralComparison)
      |> refute_issues()
    end

    test "still reports the same shape under a lookalike lib/latest/ path" do
      """
      defmodule MyApp.Latest.Worker do
        def admin?(user), do: user.admin === true
      end
      """
      |> to_source_file("lib/latest/worker.ex")
      |> run_check(NoBooleanLiteralComparison)
      |> assert_issue()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin === true
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> NoBooleanLiteralComparison.run([])
      |> case do
        [] -> raise "BAD example does not fire — the docs are lying"
        issues -> issues
      end
    end

    test "moduledoc GOOD example does not fire" do
      """
      defmodule MyApp.Worker do
        def admin?(user), do: user.admin
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> NoBooleanLiteralComparison.run([])
      |> case do
        [] -> :ok
        issues -> raise "GOOD example fires — #{inspect(issues)}"
      end
    end
  end
end
