defmodule MikaCredoRules.NoQueryImportInContextTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoQueryImportInContext

  @lib_file "apps/my_app/lib/my_app/courses.ex"
  @pg_file "apps/my_pg/lib/my_pg/course.ex"
  @test_file "apps/my_app/test/my_app/courses_test.exs"

  @moduledoc_examples NoQueryImportInContext
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoQueryImportInContext"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end
  end

  describe "&run/2 flags import/require of Ecto.Query in a context" do
    test "reports import Ecto.Query" do
      """
      defmodule MyApp.Courses do
        import Ecto.Query

        def list_open do
          from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "import Ecto.Query"
        assert issue.message =~ "import Ecto.Query found"
        assert issue.message =~ "schema module"
      end)
    end

    test "reports import Ecto.Query, only: [from: 2]" do
      """
      defmodule MyApp.Courses do
        import Ecto.Query, only: [from: 2]

        def list_open do
          from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue -> assert issue.trigger === "import Ecto.Query" end)
    end

    test "reports require Ecto.Query" do
      """
      defmodule MyApp.Courses do
        require Ecto.Query

        def list_open do
          Ecto.Query.from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issues(fn issues -> assert Enum.count(issues) === 2 end)
    end
  end

  describe "&run/2 flags a qualified Ecto.Query.from/dynamic call" do
    test "reports a fully qualified Ecto.Query.from/2" do
      """
      defmodule MyApp.Courses do
        def list_open do
          Ecto.Query.from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Ecto.Query.from"
      end)
    end

    test "reports a fully qualified Ecto.Query.dynamic" do
      """
      defmodule MyApp.Courses do
        def open_filter do
          Ecto.Query.dynamic([course], course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue -> assert issue.trigger === "Ecto.Query.dynamic" end)
    end

    test "reports a call through an alias, alias-aware" do
      """
      defmodule MyApp.Courses do
        alias Ecto.Query

        def list_open do
          Query.from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue -> assert issue.trigger === "Query.from" end)
    end

    test "reports a call through an as: alias" do
      """
      defmodule MyApp.Courses do
        alias Ecto.Query, as: Q

        def list_open do
          Q.from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue -> assert issue.trigger === "Q.from" end)
    end

    test "reports the fully Elixir-prefixed spelling" do
      """
      defmodule MyApp.Courses do
        def list_open do
          Elixir.Ecto.Query.from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Ecto.Query.from" end)
    end

    test "does not report a qualified call to a function outside from/dynamic" do
      """
      defmodule MyApp.Courses do
        def scoped(query) do
          Ecto.Query.where(query, status: :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end

    test "does not report an alias to a different module sharing the last segment" do
      """
      defmodule MyApp.Courses do
        alias MyApp.Query

        def list_open do
          Query.from(:open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag a bare alias with no usage" do
    test "does not report alias Ecto.Query alone" do
      """
      defmodule MyApp.Courses do
        alias Ecto.Query
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end
  end

  describe "&run/2 exempts allowed paths by default" do
    test "stays silent inside the schema app (_pg convention)" do
      """
      defmodule MyApp.Course do
        import Ecto.Query

        def by_status(query \\\\ __MODULE__, status), do: where(query, status: ^status)
      end
      """
      |> to_source_file(@pg_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end

    test "stays silent inside a schemas/ directory" do
      """
      defmodule MyApp.Course do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/schemas/course.ex")
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end

    test "stays silent in priv/repo/migrations" do
      """
      defmodule MyApp.Repo.Migrations.Seed do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/priv/repo/migrations/20260101_seed.exs")
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end

    test "stays silent in a test/ directory" do
      """
      defmodule MyApp.CoursesTest do
        import Ecto.Query
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end

    test "stays silent for a bare _test.exs suffix outside a test/ directory" do
      """
      defmodule MyApp.Support.CoursesTest do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/support/courses_test.exs")
      |> run_check(NoQueryImportInContext)
      |> refute_issues()
    end
  end

  describe "&run/2 still checks boundary-lookalike paths" do
    test "still checks apps/my_pgadmin/ (does not merely end in _pg)" do
      """
      defmodule MyPgadmin.Courses do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_pgadmin/lib/my_pgadmin/courses.ex")
      |> run_check(NoQueryImportInContext)
      |> assert_issue()
    end

    test "still checks lib/latest/ (merely contains the substring test)" do
      """
      defmodule MyApp.Courses do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/latest/courses.ex")
      |> run_check(NoQueryImportInContext)
      |> assert_issue()
    end

    test "still checks apps/my_app/lib/my_app/private/ with a leading-slash priv entry (does not merely start with priv)" do
      """
      defmodule MyApp.Private.Course do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/private/course.ex")
      |> run_check(NoQueryImportInContext, allowed_paths: ["/priv"])
      |> assert_issue()
    end

    test "still checks the same lookalike path with a bare priv entry (no leading slash either)" do
      """
      defmodule MyApp.Private.Course do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/private/course.ex")
      |> run_check(NoQueryImportInContext, allowed_paths: ["priv"])
      |> assert_issue()
    end

    test "an :allowed_paths entry of a bare / does not exempt every file" do
      """
      defmodule MyApp.Courses do
        import Ecto.Query
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext, allowed_paths: ["/"])
      |> assert_issue()
    end

    test "still checks a lookalike filename with a leading-slash dot entry (does not merely end with the suffix)" do
      """
      defmodule MyApp.MyTestHelper do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/my_test_helper.exs")
      |> run_check(NoQueryImportInContext, allowed_paths: ["/test_helper.exs"])
      |> assert_issue()
    end
  end

  describe "&run/2 respects custom params" do
    test "an emptied :allowed_paths checks the schema app too" do
      """
      defmodule MyApp.Course do
        import Ecto.Query
      end
      """
      |> to_source_file(@pg_file)
      |> run_check(NoQueryImportInContext, allowed_paths: [])
      |> assert_issue()
    end

    test "a custom :modules list flags the configured module instead" do
      """
      defmodule MyApp.Courses do
        import MyApp.QueryBuilder
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext, modules: [MyApp.QueryBuilder])
      |> assert_issue(fn issue -> assert issue.trigger === "import MyApp.QueryBuilder" end)
    end

    test "a custom :modules list no longer flags the default Ecto.Query" do
      """
      defmodule MyApp.Courses do
        import Ecto.Query
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext, modules: [MyApp.QueryBuilder])
      |> refute_issues()
    end

    test "a leading-slash allowed_paths entry with no trailing slash still exempts a path-segment match" do
      """
      defmodule MyApp.Repo.Migrations.Seed do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/priv/repo/migrations/20260101_seed.exs")
      |> run_check(NoQueryImportInContext, allowed_paths: ["/priv"])
      |> refute_issues()
    end

    test "the same allowed_paths entry without a leading slash exempts the identical path" do
      """
      defmodule MyApp.Repo.Migrations.Seed do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/priv/repo/migrations/20260101_seed.exs")
      |> run_check(NoQueryImportInContext, allowed_paths: ["priv/"])
      |> refute_issues()
    end

    test "a leading-slash dot entry exempts the real file it names" do
      """
      defmodule MyApp.TestHelper do
        import Ecto.Query
      end
      """
      |> to_source_file("apps/my_app/test_helper.exs")
      |> run_check(NoQueryImportInContext, allowed_paths: ["/test_helper.exs"])
      |> refute_issues()
    end
  end

  describe "&run/2 handles the Elixir-prefixed atom module spelling" do
    test "reports import of an atom-spelled module with no source trigger token" do
      """
      defmodule MyApp.Courses do
        import :"Elixir.Ecto.Query"

        def list_open do
          from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 3
        assert issue.trigger === Credo.Issue.no_trigger()
        assert issue.message =~ "import Elixir.Ecto.Query found"
      end)
    end

    test "reports a qualified call through an atom-spelled module" do
      """
      defmodule MyApp.Courses do
        def list_open do
          :"Elixir.Ecto.Query".from(course in MyApp.Course, where: course.status == :open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === Credo.Issue.no_trigger()
        assert issue.message =~ "Elixir.Ecto.Query.from found"
      end)
    end
  end

  describe "&run/2 locates the issue at a usable column" do
    test "gives each of two calls on one line its own column" do
      """
      defmodule MyApp.Courses do
        def combined do
          Ecto.Query.from(c in MyApp.Course) && Ecto.Query.dynamic([c], c.open)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoQueryImportInContext)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
