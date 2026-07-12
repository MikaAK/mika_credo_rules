defmodule MikaCredoRules.StrictEqualityTest do
  use Credo.Test.Case

  alias MikaCredoRules.StrictEquality

  describe "&run/2 flags loose comparisons" do
    test "reports ==/2" do
      """
      defmodule MyApp.Worker do
        def adult?(age), do: age == 18
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "=="
        assert issue.message =~ "==/2 found"
        assert issue.message =~ "===/2"
      end)
    end

    test "reports !=/2" do
      """
      defmodule MyApp.Worker do
        def active?(status), do: status != :inactive
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue ->
        assert issue.trigger === "!="
        assert issue.message =~ "!=/2 found"
        assert issue.message =~ "!==/2"
      end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.Worker do
        def one(value), do: value == 1
        def two(value), do: value == 2
        def three(value), do: value != 3
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4]
      end)
    end

    test "reports a loose comparison in a guard" do
      """
      defmodule MyApp.Worker do
        def unit?(value) when value == 1, do: true
        def unit?(_value), do: false
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports the loose comparison at its own column, not the first == on the line" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def bad?(query, flag) do
          where(query, [u], u.age == 18) && flag == true
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.column === 44
      end)
    end

    test "reports the &==/2 capture" do
      """
      defmodule MyApp.Worker do
        def loose_comparator, do: &==/2
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue -> assert issue.trigger === "==" end)
    end
  end

  describe "&run/2 allows strict comparisons" do
    test "does not report ===/2 and !==/2" do
      """
      defmodule MyApp.Worker do
        def adult?(age), do: age === 18
        def active?(status), do: status !== :inactive
        def unit?(value) when value === 1, do: true
        def unit?(_value), do: false
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores the Ecto query DSL" do
    test "does not report loose comparisons inside from" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def adults do
          from(u in User, where: u.age == 18, or_where: u.status != :banned, select: u.name)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons inside piped where and or_where" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def active(query) do
          query
          |> where([u], u.deleted == false)
          |> or_where([u], u.status != :banned)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons inside piped having, or_having, select and select_merge" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def report(query) do
          query
          |> having([u], count(u.id) == 1)
          |> or_having([u], count(u.id) != 0)
          |> select([u], u.age == 18)
          |> select_merge([u], %{adult: u.age != 17})
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons inside dynamic" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def by_age(age), do: dynamic([u], u.age == ^age)
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons inside a join on clause" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def with_posts(query) do
          join(query, :inner, [u], p in Post, on: p.user_id == u.id)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons inside a qualified Ecto.Query.where" do
      """
      defmodule MyApp.Users do
        def adults(query), do: Ecto.Query.where(query, [u], u.age == 18)
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "reports a loose comparison inside Enum.join arguments" do
      """
      defmodule MyApp.Worker do
        def label(names, left, right) do
          Enum.join(names, if(left == right, do: ",", else: ";"))
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "=="
      end)
    end

    test "does not report loose comparisons through alias Ecto.Query" do
      """
      defmodule MyApp.Users do
        alias Ecto.Query

        def scope(query, age) do
          Query.where(query, [u], u.age == ^age)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons through alias Ecto.Query, as: Q" do
      """
      defmodule MyApp.Users do
        alias Ecto.Query, as: Q

        def scope(query, age) do
          Q.where(query, [u], u.age == ^age)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report loose comparisons through a multi-alias of Ecto.Query" do
      """
      defmodule MyApp.Users do
        alias Ecto.{Changeset, Query}

        def scope(query, age) do
          Query.where(query, [u], u.age == ^age)
        end
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "still reports a loose comparison beside a query call on the same line" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def filter(query, mode),
          do: if(mode == :all, do: query, else: where(query, [u], u.deleted == false))
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "=="
      end)
    end
  end

  describe "&run/2 ignores Mix.env comparisons" do
    test "does not report start_permanent: Mix.env() == :prod" do
      """
      defmodule MyApp.MixProject do
        def project do
          [app: :my_app, start_permanent: Mix.env() == :prod]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report !=/2 against Mix.env()" do
      """
      defmodule MyApp.Worker do
        def verbose?, do: Mix.env() != :test
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end

    test "does not report Mix.env() on the right side" do
      """
      defmodule MyApp.Worker do
        def prod?, do: :prod == Mix.env()
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :ignored_functions param" do
    test "exempts loose comparisons inside a custom function" do
      """
      defmodule MyApp.Users do
        def adults(query), do: scope(query, [u], u.age == 18)
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality, ignored_functions: [:scope])
      |> refute_issues()
    end

    test "flags where once it is no longer ignored" do
      """
      defmodule MyApp.Users do
        import Ecto.Query

        def adults(query), do: where(query, [u], u.age == 18)
      end
      """
      |> to_source_file()
      |> run_check(StrictEquality, ignored_functions: [])
      |> assert_issue(fn issue -> assert issue.trigger === "==" end)
    end
  end
end
