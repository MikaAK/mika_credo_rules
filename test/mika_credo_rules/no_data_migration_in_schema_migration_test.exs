defmodule MikaCredoRules.NoDataMigrationInSchemaMigrationTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoDataMigrationInSchemaMigration

  @migration_file "priv/repo/migrations/20260101000000_backfill_user_status.exs"
  @umbrella_migration_file "apps/my_app/priv/repo/migrations/20260101000000_backfill_user_status.exs"
  @lookalike_file "lib/db_migrations/backfill_user_status.ex"
  @lib_file "lib/my_app/backfill_user_status.ex"

  @moduledoc_examples NoDataMigrationInSchemaMigration
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoDataMigrationInSchemaMigration"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end
  end

  describe "&run/2 flags execute/1,2 DML alongside DDL" do
    test "reports execute(\"UPDATE ...\") in a change that also alters the schema" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :status, :string
          end

          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue ->
        assert issue.line_no === 9
        assert issue.trigger === "execute"
        assert issue.message =~ "execute"
        assert issue.message =~ "DDL"
        assert issue.message =~ "own migration"
      end)
    end

    test "matches an UPDATE case-insensitively" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          create table(:statuses) do
            add :name, :string
          end

          execute "update users set status = 'active' where status is null"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end

    test "matches an INSERT statement in a heredoc" do
      """
      defmodule MyApp.Repo.Migrations.SeedRoles do
        use Ecto.Migration

        def change do
          create table(:roles) do
            add :name, :string
          end

          execute \"\"\"
          INSERT INTO roles (name) VALUES ('admin')
          \"\"\"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end

    test "matches a DELETE statement" do
      """
      defmodule MyApp.Repo.Migrations.PurgeStaleRoles do
        use Ecto.Migration

        def change do
          drop table(:legacy_roles)

          execute "DELETE FROM roles WHERE name = 'legacy'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end

    test "matches a MERGE statement" do
      """
      defmodule MyApp.Repo.Migrations.SyncRoles do
        use Ecto.Migration

        def change do
          create_if_not_exists table(:roles) do
            add :name, :string
          end

          execute "MERGE INTO roles USING staging_roles ON roles.id = staging_roles.id"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end

    test "reports execute(\"UPDATE ...\") alongside create unique_index(...)" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserEmail do
        use Ecto.Migration

        def change do
          create unique_index(:users, [:email])

          execute "UPDATE users SET email = lower(email)"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end

    test "reports execute(\"DELETE ...\") alongside drop_if_exists table(...)" do
      """
      defmodule MyApp.Repo.Migrations.PurgeLegacyAudit do
        use Ecto.Migration

        def up do
          drop_if_exists table(:legacy_audit)

          execute "DELETE FROM audit_log WHERE table_name = 'legacy_audit'"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end

    test "reports execute(\"UPDATE ...\") alongside rename table(...), to: table(...)" do
      """
      defmodule MyApp.Repo.Migrations.RenamePostsToArticles do
        use Ecto.Migration

        def change do
          rename table(:posts), to: table(:articles)

          execute "UPDATE articles SET slug = lower(slug)"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end

    test "reports every DML site in a multi-statement change" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :status, :string
          end

          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
          execute "UPDATE users SET status = 'inactive' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) === [9, 10]
      end)
    end
  end

  describe "&run/2 scans the do body regardless of a rescue/after/else/catch clause" do
    test "reports execute(\"UPDATE ...\") in a def up with a rescue clause" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          create index(:users, [:status])

          execute "UPDATE users SET status = 'active'"
        rescue
          _ -> :ok
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end
  end

  describe "&run/2 recognises the DML keyword in an interpolated execute heredoc" do
    test "reports an INSERT heredoc whose leading segment holds the keyword ahead of an interpolation" do
      """
      defmodule MyApp.Repo.Migrations.CreateApiPlans do
        use Ecto.Migration

        def change do
          create table(:api_plans) do
            add :name, :string
          end

          now = "2026-01-01"

          execute(\"\"\"
          INSERT INTO api_plans (name, inserted_at) VALUES ('x', '\#{now}')
          \"\"\")
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "execute" end)
    end
  end

  describe "&run/2 flags repo().update_all/insert_all/delete_all alongside DDL" do
    test "reports repo().update_all in an up that also creates an index" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          create index(:users, [:status])

          repo().update_all(MyApp.User, set: [status: "active"])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue ->
        assert issue.line_no === 7
        assert issue.trigger === "repo().update_all"
      end)
    end

    test "reports repo().insert_all" do
      """
      defmodule MyApp.Repo.Migrations.SeedRoles do
        use Ecto.Migration

        def up do
          create table(:roles) do
            add :name, :string
          end

          repo().insert_all(MyApp.Role, [%{name: "admin"}])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "repo().insert_all" end)
    end

    test "reports repo().delete_all" do
      """
      defmodule MyApp.Repo.Migrations.PurgeRoles do
        use Ecto.Migration

        def up do
          drop table(:legacy_roles)

          repo().delete_all(MyApp.LegacyRole)
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "repo().delete_all" end)
    end

    test "reports repo().update_all piped from a from(...) query" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          alter table(:users) do
            add :status, :string
          end

          from(user in MyApp.User, where: is_nil(user.status))
          |> repo().update_all(set: [status: "active"])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue(fn issue -> assert issue.trigger === "repo().update_all" end)
    end
  end

  describe "&run/2 allows a DDL-only or DML-only migration" do
    test "does not report a DDL-only change" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :status, :string
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report a DML-only change (a pure data migration is legitimate)" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report repo().update_all with no DDL in the same clause" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          repo().update_all(MyApp.User, set: [status: "active"])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report execute(\"CREATE INDEX CONCURRENTLY ...\") — a DDL string" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :status, :string
          end

          execute "CREATE INDEX CONCURRENTLY users_status_index ON users (status)"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report DDL and DML mixed across change and down (down is exempt)" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          alter table(:users) do
            add :status, :string
          end
        end

        def down do
          alter table(:users) do
            remove :status
          end

          execute "UPDATE users SET legacy_status = NULL"
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report execute/1 called with a variable argument" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :status, :string
          end

          sql = build_update_statement()
          execute sql
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report execute/1 piped into (unlike repo(), only the directly-called form is recognised)" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :status, :string
          end

          "UPDATE users SET status = 'active'" |> execute()
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report repo().insert on its own (not insert_all)" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          create table(:roles) do
            add :name, :string
          end

          repo().insert(%MyApp.Role{name: "admin"})
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end
  end

  describe "&run/2 path scoping" do
    test "checks a migration in an umbrella app" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :status, :string
          end

          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@umbrella_migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issue()
    end

    test "does not report a non-migration lib path" do
      """
      defmodule MyApp.BackfillUserStatus do
        def change do
          alter table(:users) do
            add :status, :string
          end

          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "does not report a boundary lookalike path (db_migrations/ has no /migrations/ boundary)" do
      """
      defmodule MyApp.BackfillUserStatus do
        def change do
          alter table(:users) do
            add :status, :string
          end

          execute "UPDATE users SET status = 'active' WHERE status IS NULL"
        end
      end
      """
      |> to_source_file(@lookalike_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> refute_issues()
    end

    test "honors a custom :included_paths param" do
      source_file =
        """
        defmodule MyApp.Migrations.BackfillUserStatus do
          def change do
            alter table(:users) do
              add :status, :string
            end

            execute "UPDATE users SET status = 'active' WHERE status IS NULL"
          end
        end
        """
        |> to_source_file("lib/db_migrations/backfill_user_status.ex")

      refute_issues(run_check(source_file, NoDataMigrationInSchemaMigration))

      source_file
      |> run_check(NoDataMigrationInSchemaMigration, included_paths: ["db_migrations/"])
      |> assert_issue()
    end
  end

  describe "&run/2 column tracking" do
    test "gives two DML sites on one line distinct columns" do
      """
      defmodule MyApp.Repo.Migrations.BackfillUserStatus do
        use Ecto.Migration

        def up do
          alter table(:users) do
            add :status, :string
          end

          repo().update_all(MyApp.User, set: [status: "a"]) && repo().update_all(MyApp.User, set: [status: "b"])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(NoDataMigrationInSchemaMigration)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
