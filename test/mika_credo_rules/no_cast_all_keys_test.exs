defmodule MikaCredoRules.NoCastAllKeysTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoCastAllKeys

  @schema_file "apps/my_app/lib/my_app/user.ex"

  describe "&run/2 flags cast whose permitted list is Map.keys" do
    test "reports a local cast/3" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          cast(user, attrs, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "cast"
        assert issue.message =~ "Map.keys"
        assert issue.message =~ "enumerate the permitted fields"
      end)
    end

    test "reports a local cast/4 with options" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          cast(user, attrs, Map.keys(attrs), empty_values: [""])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a piped cast at the cast call's own position" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          user
          |> cast(attrs, Map.keys(attrs))
          |> validate_required([:email])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.column === 8
      end)
    end

    test "reports the single-line piped moduledoc example" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs), do: user |> cast(attrs, Map.keys(attrs)) |> validate_required([:email])
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports a piped cast with options" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          user |> cast(attrs, Map.keys(attrs), empty_values: [""])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a fully qualified Ecto.Changeset.cast" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          Ecto.Changeset.cast(user, attrs, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports Changeset.cast under alias Ecto.Changeset" do
      """
      defmodule MyApp.User do
        alias Ecto.Changeset

        def changeset(user, attrs) do
          Changeset.cast(user, attrs, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports a piped Changeset.cast under alias Ecto.Changeset" do
      """
      defmodule MyApp.User do
        alias Ecto.Changeset

        def changeset(user, attrs) do
          user |> Changeset.cast(attrs, Map.keys(attrs)) |> Changeset.validate_required([:email])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports Map.keys of a different variable than the params argument" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs, other) do
          cast(user, attrs, Map.keys(other))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 allows explicit permitted lists" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          user
          |> cast(attrs, [:name, :email])
          |> validate_required([:email])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report a literal field list" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          cast(user, attrs, [:name, :email])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report a module attribute" do
      """
      defmodule MyApp.User do
        @permitted [:name, :email]

        def changeset(user, attrs) do
          cast(user, attrs, @permitted)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report a variable permitted list" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          fields = Map.keys(attrs)
          cast(user, attrs, fields)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report Keyword.keys" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          cast(user, attrs, Keyword.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report Map.keys when Map is shadowed by a project alias" do
      """
      defmodule MyApp.User do
        alias MyApp.Map

        def changeset(user, attrs) do
          cast(user, attrs, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report Changeset.cast without an alias for Ecto.Changeset" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          Changeset.cast(user, attrs, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end

    test "does not report a two-argument cast" do
      """
      defmodule MyApp.User do
        def changeset(user, attrs) do
          cast(user, Map.keys(attrs))
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoCastAllKeys)
      |> refute_issues()
    end
  end
end
