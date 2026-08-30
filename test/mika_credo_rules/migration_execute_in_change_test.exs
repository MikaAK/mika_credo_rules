defmodule MikaCredoRules.MigrationExecuteInChangeTest do
  use Credo.Test.Case

  alias MikaCredoRules.MigrationExecuteInChange

  @migration_file "priv/repo/migrations/20260101000000_backfill_role.exs"
  @umbrella_migration_file "apps/my_app/priv/repo/migrations/20260101000000_backfill_role.exs"
  @lookalike_file "lib/premigrations_helper.ex"

  describe "&run/2 flags execute/1 inside def change" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def change do
          execute "UPDATE users SET role = 'student' WHERE role IS NULL"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "execute"
        assert issue.message =~ "execute/1"
        assert issue.message =~ "irreversible"
      end)
    end

    test "reports a one-liner def change" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def change, do: execute("UPDATE users SET role = 'student' WHERE role IS NULL")
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports every execute/1 call in a multi-statement change" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def change do
          execute "UPDATE users SET role = 'student' WHERE role IS NULL"
          execute "UPDATE users SET role = 'admin' WHERE email = 'a@b.com'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) === [5, 6]
      end)
    end

    test "reports execute/1 in an umbrella migration path" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def change do
          execute "UPDATE users SET role = 'student' WHERE role IS NULL"
        end
      end
      """
      |> to_source_file(@umbrella_migration_file)
      |> run_check(MigrationExecuteInChange)
      |> assert_issue()
    end
  end

  describe "&run/2 allows execute/2 and up/down" do
    test "does not report the moduledoc up/down GOOD example" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def up, do: execute("UPDATE users SET role = 'student' WHERE role IS NULL")
        def down, do: :ok
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end

    test "does not report the moduledoc reversible two-arg GOOD example" do
      """
      defmodule MyApp.Repo.Migrations.CreateCitext do
        use Ecto.Migration

        def change, do: execute("CREATE EXTENSION citext", "DROP EXTENSION citext")
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end

    test "does not report execute/2 inside a multi-statement change" do
      """
      defmodule MyApp.Repo.Migrations.CreateCitext do
        use Ecto.Migration

        def change do
          execute("CREATE EXTENSION citext", "DROP EXTENSION citext")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end

    test "does not report execute/1 inside a multi-statement up" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def up do
          execute "UPDATE users SET role = 'student' WHERE role IS NULL"
        end

        def down, do: :ok
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end

    test "does not report execute/1 inside down" do
      """
      defmodule MyApp.Repo.Migrations.BackfillRole do
        use Ecto.Migration

        def up, do: :ok
        def down, do: execute("UPDATE users SET role = NULL")
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "does not report execute/1 in a lookalike lib path" do
      """
      defmodule MyApp.PremigrationsHelper do
        def change do
          execute "UPDATE users SET role = 'student' WHERE role IS NULL"
        end
      end
      """
      |> to_source_file(@lookalike_file)
      |> run_check(MigrationExecuteInChange)
      |> refute_issues()
    end

    test "honors a custom :migration_paths param" do
      source_file =
        """
        defmodule MyApp.Migrations.BackfillRole do
          def change do
            execute "UPDATE users SET role = 'student' WHERE role IS NULL"
          end
        end
        """
        |> to_source_file("lib/db_migrations/backfill_role.ex")

      refute_issues(run_check(source_file, MigrationExecuteInChange))

      source_file
      |> run_check(MigrationExecuteInChange, migration_paths: ["db_migrations/"])
      |> assert_issue()
    end
  end
end
