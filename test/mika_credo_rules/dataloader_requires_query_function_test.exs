defmodule MikaCredoRules.DataloaderRequiresQueryFunctionTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DataloaderRequiresQueryFunction
  alias MikaCredoRules.DocExamples

  @lib_file "apps/my_app/lib/my_app/resolvers/loader.ex"
  @test_file "apps/my_app/test/my_app/resolvers/loader_test.exs"

  @moduledoc_examples DataloaderRequiresQueryFunction
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "DataloaderRequiresQueryFunction"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end
  end

  describe "&run/2 flags Dataloader.Ecto.new/1 with no opts" do
    test "reports a fully qualified new/1 call with no opts" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Dataloader.Ecto.new"
        assert issue.message =~ "Dataloader.Ecto.new/1"
        assert issue.message =~ "query:"
        assert issue.message =~ "silently dropped"
      end)
    end

    test "reports a piped alias new/1 call under a short alias" do
      """
      defmodule MyApp.Resolvers.Loader do
        alias Dataloader.Ecto

        def source(repo) do
          repo |> Ecto.new()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Ecto.new"
        assert issue.message =~ "Ecto.new/1"
      end)
    end
  end

  describe "&run/2 flags Dataloader.Ecto.new/2 with a literal opts missing query:" do
    test "reports literal timeout opts with no query key" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo, timeout: 5_000)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Dataloader.Ecto.new"
        assert issue.message =~ "Dataloader.Ecto.new/2"
      end)
    end

    test "reports an empty literal opts list" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo, [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue()
    end
  end

  describe "&run/2 allows query: and other source types" do
    test "does not report a literal opts with query: present" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo, query: &EctoShorts.CommonFilters.convert_params_to_filter/2)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report opts held in a variable (accepted limitation)" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo, opts) do
          Dataloader.Ecto.new(repo, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report Dataloader.KV.new/1,2 — a different source type" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(fetcher) do
          Dataloader.KV.new(fetcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end
  end

  describe "&run/2 re-derives the true arity of a piped Dataloader.Ecto.new call" do
    test "does not report a piped call with query: present" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          repo |> Dataloader.Ecto.new(query: &EctoShorts.CommonFilters.convert_params_to_filter/2)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report a piped call with query: plus other literal opts" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          repo
          |> Dataloader.Ecto.new(
            query: &EctoShorts.CommonFilters.convert_params_to_filter/2,
            timeout: 5_000
          )
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report a piped call with query: under a short alias" do
      """
      defmodule MyApp.Resolvers.Loader do
        alias Dataloader.Ecto

        def source(repo) do
          repo |> Ecto.new(query: &EctoShorts.CommonFilters.convert_params_to_filter/2)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report a multi-stage pipe chain ending in a query:-carrying call" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          repo
          |> maybe_scope()
          |> Dataloader.Ecto.new(query: &EctoShorts.CommonFilters.convert_params_to_filter/2)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "reports a piped call missing query: with only literal opts, at true arity 2" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          repo |> Dataloader.Ecto.new(timeout: 5_000)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Dataloader.Ecto.new"
        assert issue.message =~ "Dataloader.Ecto.new/2"
      end)
    end

    test "does not report a piped call with opts held in a variable (accepted limitation)" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo, opts) do
          repo |> Dataloader.Ecto.new(opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end
  end

  describe "&run/2 is alias-aware on Dataloader.Ecto" do
    test "reports a bare alias Dataloader.Ecto reference" do
      """
      defmodule MyApp.Resolvers.Loader do
        alias Dataloader.Ecto

        def source(repo) do
          Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue -> assert issue.trigger === "Ecto.new" end)
    end

    test "reports the fully qualified Elixir.Dataloader.Ecto spelling" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Elixir.Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue()
    end

    test "does not report a bare Ecto reference aliased to a different module (shadow)" do
      """
      defmodule MyApp.Resolvers.Loader do
        alias MyApp.Dataloader.Ecto

        def source(repo) do
          Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end
  end

  describe "&run/2 excludes test paths by default" do
    test "does not report a test file matching the _test.exs suffix" do
      """
      defmodule MyApp.Resolvers.LoaderTest do
        def build(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "does not report a file under a test/ directory that does not itself end in _test.exs" do
      """
      defmodule MyApp.Support.LoaderFixtures do
        def build(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file("apps/my_app/test/support/loader_fixtures.ex")
      |> run_check(DataloaderRequiresQueryFunction)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test')" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/loader.ex")
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.Resolvers.LoaderTest do
        def build(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(DataloaderRequiresQueryFunction, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column so Credo can validate the trigger" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(repo) do
          Dataloader.Ecto.new(repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two calls on one line its own column" do
      """
      defmodule MyApp.Resolvers.Loader do
        def source(first_repo, second_repo) do
          Dataloader.Ecto.new(first_repo) && Dataloader.Ecto.new(second_repo)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(DataloaderRequiresQueryFunction)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
