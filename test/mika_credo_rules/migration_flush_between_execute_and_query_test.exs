defmodule MikaCredoRules.MigrationFlushBetweenExecuteAndQueryTest do
  use Credo.Test.Case

  alias MikaCredoRules.MigrationFlushBetweenExecuteAndQuery

  @migration_file "priv/repo/migrations/20260101000000_reassign_oban_workers.exs"
  @umbrella_migration_file "apps/my_app/priv/repo/migrations/20260101000000_reassign_oban_workers.exs"
  @lookalike_file "lib/premigrations_helper.ex"

  describe "&run/2 flags a direct query after execute with no flush" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "repo().query!"
        assert issue.message =~ "flush()"
      end)
    end

    test "reports repo().query (non-bang) after execute" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports repo().query_many! after execute" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def change do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query_many!("SELECT 1; SELECT 2;")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports repo().query_many after execute" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def change do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query_many("SELECT 1; SELECT 2;")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports each unflushed query following the same execute" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query!("SELECT 1")
          repo().query!("SELECT 2")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) === [6, 7] end)
    end

    test "reports a query wrapped in a case subject" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"

          case repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'") do
            {:ok, result} -> result
            {:error, reason} -> raise reason
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue ->
        assert issue.line_no === 7
        assert issue.trigger === "repo().query!"
      end)
    end

    test "reports a query wrapped in a match assignment" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          {:ok, result} = repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
          result
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports in an umbrella migration path" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@umbrella_migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> assert_issue()
    end
  end

  describe "&run/2 allows flush() between execute and a direct query" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          flush()
          repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "does not report a direct query with no preceding execute" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "does not report an execute with no following query" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "does not report a one-liner def with only a query" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up, do: repo().query!("SELECT 1")
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "does not report a case-wrapped query when flush() precedes it" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          flush()

          case repo().query!("SELECT 1") do
            {:ok, result} -> result
            {:error, reason} -> raise reason
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "does not report a query after flush resets a second execute pairing" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          flush()
          execute "UPDATE oban_jobs SET queue = 'other' WHERE worker IN ('C')"
          flush()
          repo().query!("SELECT 1")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "does not report on a lookalike lib path" do
      """
      defmodule MyApp.PremigrationsHelper do
        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          repo().query!("SELECT DISTINCT worker FROM oban_jobs WHERE queue = 'default'")
        end
      end
      """
      |> to_source_file(@lookalike_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery)
      |> refute_issues()
    end

    test "honors a custom :migration_paths param" do
      source_file =
        """
        defmodule MyApp.Migrations.ReassignObanWorkers do
          def up do
            execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
            repo().query!("SELECT 1")
          end
        end
        """
        |> to_source_file("lib/db_migrations/reassign_oban_workers.ex")

      refute_issues(run_check(source_file, MigrationFlushBetweenExecuteAndQuery))

      source_file
      |> run_check(MigrationFlushBetweenExecuteAndQuery, migration_paths: ["db_migrations/"])
      |> assert_issue()
    end

    test "honors a custom :flush_function param" do
      """
      defmodule MyApp.Repo.Migrations.ReassignObanWorkers do
        use Ecto.Migration

        def up do
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('A','B')"
          flush_migration()
          repo().query!("SELECT 1")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationFlushBetweenExecuteAndQuery, flush_function: :flush_migration)
      |> refute_issues()
    end
  end
end
