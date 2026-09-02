defmodule MikaCredoRules.MigrationForeignKeyNeedsIndexTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.MigrationForeignKeyNeedsIndex

  @migration_file "priv/repo/migrations/20260101000000_create_users.exs"
  @umbrella_migration_file "apps/my_app/priv/repo/migrations/20260101000000_create_users.exs"
  @lookalike_file "lib/premigrations_helper.ex"

  describe "&run/2 flags a foreign key with no covering index" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "references"
        assert issue.message =~ ":organizations"
        assert issue.message =~ ":organization_id"
        assert issue.message =~ "create index(:users, [:organization_id])"
      end)
    end

    test "reports a foreign key whose references/2 carries options" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations, on_delete: :delete_all), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue(fn issue ->
        assert issue.trigger === "references"
        assert issue.message =~ ":organizations"
      end)
    end

    test "reports each uncovered foreign key in the same table" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
            add :team_id, references(:teams), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) === [6, 7] end)
    end

    test "reports in create_if_not_exists table" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create_if_not_exists table(:users) do
            add :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue()
    end

    test "reports an existing index that does not cover the foreign key column" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create index(:users, [:email])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue()
    end

    test "reports an index on the same column but a different table" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create index(:teams, [:organization_id])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue()
    end

    test "reports a foreign key added via alter table" do
      """
      defmodule MyApp.Repo.Migrations.AddOrganizationToUsers do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports a foreign key added via add_if_not_exists in alter table" do
      """
      defmodule MyApp.Repo.Migrations.AddOrganizationToUsers do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add_if_not_exists :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports in an umbrella migration path" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@umbrella_migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> assert_issue()
    end
  end

  describe "&run/2 allows a covering index" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create index(:users, [:organization_id])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report when covered by a composite index" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create unique_index(:users, [:email, :organization_id])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report when covered by a single-atom index form" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create index(:users, :organization_id)
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report when covered by a concurrently-built index" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        @disable_ddl_transaction true
        @disable_migration_lock true

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create_if_not_exists index(:users, [:organization_id], concurrently: true)
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report a covered foreign key added via alter table" do
      """
      defmodule MyApp.Repo.Migrations.AddOrganizationToUsers do
        use Ecto.Migration

        def change do
          alter table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create index(:users, [:organization_id])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report modify on a pre-existing foreign key inside alter table" do
      """
      defmodule MyApp.Repo.Migrations.WidenTicketIdReference do
        use Ecto.Migration

        def change do
          alter table(:comments) do
            modify :ticket_id, references(:tickets), from: references(:tickets)
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "does not report a column that is not a foreign key" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :email, :string, null: false
          end
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "does not report on a lookalike lib path" do
      """
      defmodule MyApp.PremigrationsHelper do
        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end
        end
      end
      """
      |> to_source_file(@lookalike_file)
      |> run_check(MigrationForeignKeyNeedsIndex)
      |> refute_issues()
    end

    test "honors a custom :migration_paths param" do
      source_file =
        """
        defmodule MyApp.Migrations.CreateUsers do
          def change do
            create table(:users) do
              add :organization_id, references(:organizations), null: false
            end
          end
        end
        """
        |> to_source_file("lib/db_migrations/create_users.ex")

      refute_issues(run_check(source_file, MigrationForeignKeyNeedsIndex))

      source_file
      |> run_check(MigrationForeignKeyNeedsIndex, migration_paths: ["db_migrations/"])
      |> assert_issue()
    end

    test "honors a custom :index_functions param" do
      """
      defmodule MyApp.Repo.Migrations.CreateUsers do
        use Ecto.Migration

        def change do
          create table(:users) do
            add :organization_id, references(:organizations), null: false
          end

          create custom_index(:users, [:organization_id])
        end
      end
      """
      |> to_source_file(@migration_file)
      |> run_check(MigrationForeignKeyNeedsIndex, index_functions: [:custom_index])
      |> refute_issues()
    end
  end
end
