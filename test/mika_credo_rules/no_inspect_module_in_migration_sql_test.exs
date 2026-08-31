defmodule MikaCredoRules.NoInspectModuleInMigrationSqlTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoInspectModuleInMigrationSql

  @migration_file "priv/repo/migrations/20260101000000_rescan_queue.exs"
  @umbrella_migration_file "apps/my_app/priv/repo/migrations/20260101000000_rescan_queue.exs"
  @lookalike_file "lib/premigrations_helper.ex"

  describe "&run/2 flags inspect/1 on a module alias" do
    test "reports a direct inspect(Module) call" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker = inspect(DeveloperAi.Workers.TicketScanner)
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker = '\#{worker}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "inspect"
        assert issue.message =~ "Elixir."
      end)
    end

    test "reports in an umbrella migration path" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        def change do
          inspect(DeveloperAi.Workers.TicketScanner)
        end
      end
      """
      |> to_source_file(@umbrella_migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue()
    end
  end

  describe "&run/2 flags string interpolation of a module alias" do
    test "reports the moduledoc first BAD example (inspect assigned then interpolated)" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker = inspect(DeveloperAi.Workers.TicketScanner)
          execute "UPDATE oban_jobs SET worker = '\#{worker}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue(fn issue ->
        assert issue.trigger === "inspect"
        assert issue.line_no === 5
      end)
    end

    test "reports the moduledoc second BAD example (direct interpolation)" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          execute "UPDATE oban_jobs SET worker = '\#{DeveloperAi.Workers.TicketScanner}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "DeveloperAi.Workers.TicketScanner"
        assert issue.message =~ "interpolation"
      end)
    end

    test "does not report when :also_flag_interpolation is false" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          execute "UPDATE oban_jobs SET worker = '\#{DeveloperAi.Workers.TicketScanner}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql, also_flag_interpolation: false)
      |> refute_issues()
    end
  end

  describe "&run/2 flags to_string/1 and Atom.to_string/1 on a module alias" do
    test "reports a bare to_string(Module) call" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker = to_string(DeveloperAi.Workers.TicketScanner)
          execute "UPDATE oban_jobs SET worker = '\#{worker}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "to_string"
      end)
    end

    test "reports an Atom.to_string(Module) call" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker = Atom.to_string(DeveloperAi.Workers.TicketScanner)
          execute "UPDATE oban_jobs SET worker = '\#{worker}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "Atom.to_string"
      end)
    end

    test "does not report to_string/1 on a variable" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          reason = :timeout
          execute "-- \#{to_string(reason)}"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end
  end

  describe "&run/2 allows the moduledoc GOOD example and unrelated calls" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          execute "UPDATE oban_jobs SET worker = 'DeveloperAi.Workers.TicketScanner'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end

    test "does not report the documented Enum.map(&inspect/1) capture limitation" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker_list =
            [DeveloperAi.Workers.TicketScanner]
            |> Enum.map(&inspect/1)
            |> Enum.join("','")

          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('\#{worker_list}')"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end

    test "does not report the ~w workaround suggested for the capture limitation" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          workers = ~w(DeveloperAi.Workers.TicketScanner) |> Enum.join("','")
          execute "UPDATE oban_jobs SET queue = 'scanner' WHERE worker IN ('\#{workers}')"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end

    test "does not report inspect/1 on a variable" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          reason = :timeout
          execute "-- \#{inspect(reason)}"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end

    test "does not report interpolation of a variable" do
      """
      defmodule MyApp.Repo.Migrations.RescanQueue do
        use Ecto.Migration

        def change do
          worker = "MyApp.Worker"
          execute "UPDATE oban_jobs SET worker = '\#{worker}'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "does not report on a lookalike lib path" do
      """
      defmodule MyApp.PremigrationsHelper do
        def change do
          inspect(DeveloperAi.Workers.TicketScanner)
        end
      end
      """
      |> to_source_file(@lookalike_file)
      |> run_check(NoInspectModuleInMigrationSql)
      |> refute_issues()
    end

    test "honors a custom :migration_paths param" do
      source_file =
        """
        defmodule MyApp.Migrations.RescanQueue do
          def change do
            inspect(DeveloperAi.Workers.TicketScanner)
          end
        end
        """
        |> to_source_file("lib/db_migrations/rescan_queue.ex")

      refute_issues(run_check(source_file, NoInspectModuleInMigrationSql))

      source_file
      |> run_check(NoInspectModuleInMigrationSql, migration_paths: ["db_migrations/"])
      |> assert_issue()
    end
  end
end
