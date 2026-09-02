defmodule MikaCredoRules.NoDirectRepoCallTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoDirectRepoCall

  @lib_file "apps/my_app/lib/my_app/accounts.ex"
  @test_file "apps/my_app/test/my_app/accounts_test.exs"
  @migration_file "apps/my_app/priv/repo/migrations/20260830000000_backfill.exs"

  @moduledoc_examples NoDirectRepoCall
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoDirectRepoCall"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a direct repo call" do
    test "reports a fully qualified MyApp.Repo.insert/1" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "MyApp.Repo.insert"
        assert issue.message =~ "MyApp.Repo.insert"
        assert issue.message =~ "EctoShorts.Actions"
      end)
    end

    test "reports an aliased Repo.all/1" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def list_users(query) do
          Repo.all(query)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.all" end)
    end

    test "reports a piped Repo.one/0" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def find_user(query) do
          query |> Repo.one()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.one" end)
    end

    test "reports a differently-named repo matched by suffix" do
      """
      defmodule MyApp.Jobs do
        def clear(query) do
          Schemas.JobsRepo.delete_all(query)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Schemas.JobsRepo.delete_all" end)
    end
  end

  describe "&run/2 allows the default allowed function and non-repo modules" do
    test "does not report Repo.transaction/1" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def transfer(multi) do
          Repo.transaction(multi)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report a module whose last segment merely contains Repo" do
      """
      defmodule MyApp.Accounts do
        def summarize(pattern) do
          MyApp.Reporting.build(pattern)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "respects a custom :allowed_functions override" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def create_user(attrs) do
          Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall, allowed_functions: [:insert])
      |> refute_issues()
    end

    test "an :allowed_functions override no longer exempts the default :transaction" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def transfer(multi) do
          Repo.transaction(multi)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall, allowed_functions: [:insert])
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.transaction" end)
    end
  end

  describe "&run/2 respects :excluded_paths" do
    test "does not report a test file by default" do
      """
      defmodule MyApp.AccountsTest do
        def seed_user(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.AccountsTest do
        def seed_user(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectRepoCall, excluded_paths: [])
      |> assert_issue()
    end

    test "does not report a migration file by default" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        def change do
          MyApp.Repo.query!("UPDATE users SET active = true")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/accounts.ex")
      |> run_check(NoDirectRepoCall)
      |> assert_issue()
    end
  end

  describe "&run/2 respects :repo_suffixes" do
    test "does not report a module whose suffix is not in :repo_suffixes" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          MyApp.Notifier.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "respects a custom :repo_suffixes override" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          MyApp.Notifier.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall, repo_suffixes: ["Notifier"])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Notifier.insert" end)
    end
  end

  describe "&run/2 exempts a module that defines a repo" do
    test "does not report a call inside its own use Ecto.Repo body" do
      """
      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres

        def custom_insert(changeset) do
          MyApp.Repo.insert(changeset)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "still reports the same call shape outside a repo-defining module" do
      """
      defmodule MyApp.Accounts do
        def custom_insert(changeset) do
          MyApp.Repo.insert(changeset)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue()
    end

    test "does not exempt a sibling call when a NESTED module defines the repo" do
      """
      defmodule MyApp.Accounts do
        defmodule Repo do
          use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
        end

        def create(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Repo.insert" end)
    end
  end

  describe "&run/2 prunes typespec bodies" do
    test "does not report @spec referencing Ecto.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @spec find_user(Ecto.Repo.t(), integer()) :: User.t() | nil
        def find_user(repo, id), do: nil
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report @type referencing MyApp.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @type repo :: MyApp.Repo.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report @typep referencing Ecto.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @typep repo :: Ecto.Repo.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report @opaque referencing Ecto.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @opaque repo :: Ecto.Repo.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report @callback referencing Ecto.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @callback repo() :: Ecto.Repo.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report @macrocallback referencing Ecto.Repo.t/0" do
      """
      defmodule MyApp.Accounts do
        @macrocallback repo() :: Ecto.Repo.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag multi-alias sugar" do
    test "alias MyApp.Repo.{A, B} is not a repo call" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo.{Migrations, Seeds}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 does not crash on a non-literal alias segment" do
    test "a __MODULE__-prefixed repo call does not raise and stays silent" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          __MODULE__.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves documented undetected call shapes silent even where the file IS scanned" do
    test "does not report a defdelegate to a repo module" do
      """
      defmodule MyApp.Accounts do
        defdelegate insert(changeset), to: MyApp.Repo
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report an unqualified call (no import-based Repo idiom exists)" do
      """
      defmodule MyApp.Accounts do
        import MyApp.Repo

        def create_user(attrs) do
          insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report an injected repo() call" do
      """
      defmodule MyApp.Repo.Migrations.Backfill do
        def change do
          repo().query!("UPDATE users SET active = true", [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 allows Repo.transact/2, the Ecto.Multi-batch idiom the moduledoc names" do
    test "does not report Repo.transact/2 by default" do
      """
      defmodule MyApp.ApiKeys do
        alias MyApp.Repo

        def create(params) do
          Repo.transact(fn ->
            Actions.create(ApiKey, params)
          end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "an :allowed_functions override no longer exempts the default :transact" do
      """
      defmodule MyApp.ApiKeys do
        alias MyApp.Repo

        def create(params) do
          Repo.transact(fn -> Actions.create(ApiKey, params) end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall, allowed_functions: [:insert])
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.transact" end)
    end
  end

  describe "&run/2 allows repo functions EctoShorts.Actions has no equivalent for" do
    test "does not report Repo.query!/2 by default (raw SQL escape hatch)" do
      """
      defmodule Schemas.ContinuousAgg do
        alias Schemas.Repo

        def create_view(name, query) do
          Repo.query!("CREATE MATERIALIZED VIEW " <> name <> " AS " <> query, [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "does not report Repo.disconnect_all/1 by default (pool management)" do
      """
      defmodule Schemas.DbConnectionRecycler do
        alias Schemas.Repo

        def handle_info(:recycle, state) do
          Repo.disconnect_all(5_000)
          {:noreply, state}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end

    test "an :allowed_functions override no longer exempts the default :query!" do
      """
      defmodule Schemas.ContinuousAgg do
        alias Schemas.Repo

        def create_view(name, query) do
          Repo.query!("CREATE MATERIALIZED VIEW " <> name <> " AS " <> query, [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall, allowed_functions: [:insert])
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.query!" end)
    end

    test "a CRUD verb with an Actions equivalent still fires (allowed list is not blanket)" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def create_user(attrs) do
          Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.insert" end)
    end
  end

  describe "&run/2 does not exempt a __using__ macro's own quote body" do
    test "a wrapper module's own calls still fire even though its __using__ macro quotes use Ecto.Repo" do
      """
      defmodule MyApp.RepoBase do
        defmacro __using__(opts) do
          quote do
            use Ecto.Repo, unquote(opts)
          end
        end

        def audit(changeset) do
          MyApp.Repo.insert(changeset)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Repo.insert" end)
    end
  end

  describe "&run/2 fires on bulk DML despite no EctoShorts.Actions equivalent (allowlist is not blanket)" do
    test "fires on Repo.insert_all/2 by default" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def bulk_create(entries) do
          Repo.insert_all(User, entries)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.insert_all" end)
    end

    test "fires on Repo.delete_all/1 by default" do
      """
      defmodule MyApp.Accounts do
        alias MyApp.Repo

        def purge(query) do
          Repo.delete_all(query)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.delete_all" end)
    end
  end

  describe "&run/2 exempts a repo module declared with a non-__aliases__ name" do
    test "does not report a self-call inside a repo module whose name is an atom literal" do
      ~S"""
      defmodule :"Elixir.MyApp.Repo" do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres

        def custom_insert(changeset) do
          MyApp.Repo.insert(changeset)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Accounts do
        def create_user(attrs) do
          MyApp.Repo.insert(attrs)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two repo calls on one line its own column" do
      """
      defmodule MyApp.Accounts do
        def create_users(first, second) do
          MyApp.Repo.insert(first) && MyApp.Repo.insert(second)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectRepoCall)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
