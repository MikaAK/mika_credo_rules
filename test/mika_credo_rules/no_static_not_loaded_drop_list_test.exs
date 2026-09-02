defmodule MikaCredoRules.NoStaticNotLoadedDropListTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoStaticNotLoadedDropList

  @schema_file "apps/my_app/lib/my_app/user.ex"
  @support_file "apps/my_app/test/support/user_fixtures.ex"

  describe "&run/2 flags a static drop-list with :__meta__ plus another atom" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.User do
        @association_keys [:__meta__, :workspace, :sessions]

        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop(@association_keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "drop"
        assert issue.message =~ "NotLoaded"
      end)
    end

    test "reports a literal list argument, standalone call" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          Map.drop(Map.from_struct(struct), [:__meta__, :workspace])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a literal list argument, piped call" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop([:__meta__, :workspace])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports in test/support" do
      """
      defmodule MyApp.UserFixtures do
        @association_keys [:__meta__, :workspace]

        def to_map(struct), do: struct |> Map.from_struct() |> Map.drop(@association_keys)
      end
      """
      |> to_source_file(@support_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> assert_issue()
    end

    test "reports Map.drop under alias Elixir.Map" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          struct |> Elixir.Map.from_struct() |> Elixir.Map.drop([:__meta__, :workspace])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> assert_issue()
    end
  end

  describe "&run/2 allows the moduledoc GOOD example and benign drops" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          struct
          |> Map.from_struct()
          |> Map.reject(fn {_key, value} -> match?(%Ecto.Association.NotLoaded{}, value) end)
          |> Map.delete(:__meta__)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report Map.drop with only :__meta__" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop([:__meta__])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report Map.drop without :__meta__ at all" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop([:workspace, :sessions])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report a module attribute list with only :__meta__" do
      """
      defmodule MyApp.User do
        @meta_only [:__meta__]

        def to_serializable_map(struct), do: struct |> Map.from_struct() |> Map.drop(@meta_only)
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report a drop-list containing only :__meta__ and :__struct__" do
      """
      defmodule MyApp.User do
        @sensitive_keys [:__meta__, :__struct__]

        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop(@sensitive_keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "resolves a module attribute from the LAST assignment in the file, not the one before the point of reference" do
      """
      defmodule MyApp.User do
        @keys [:__meta__, :workspace]

        def to_serializable_map(struct), do: struct |> Map.from_struct() |> Map.drop(@keys)

        @keys [:__meta__]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report a variable drop-list" do
      """
      defmodule MyApp.User do
        def to_serializable_map(struct, keys) do
          struct |> Map.from_struct() |> Map.drop(keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report Map.drop when Map is shadowed by a project alias" do
      """
      defmodule MyApp.User do
        alias MyApp.Map

        def to_serializable_map(struct) do
          Map.drop(struct, [:__meta__, :workspace])
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end

    test "does not report Map.drop/1 called directly (missing the map argument)" do
      """
      defmodule MyApp.User do
        @association_keys [:__meta__, :workspace]

        def to_serializable_map do
          Map.drop(@association_keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList)
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "honors a custom :marker_key param" do
      """
      defmodule MyApp.User do
        @association_keys [:custom_marker, :workspace]

        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop(@association_keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList, marker_key: :custom_marker)
      |> assert_issue()
    end

    test "honors a custom :non_association_keys param" do
      """
      defmodule MyApp.User do
        @association_keys [:__meta__, :workspace]

        def to_serializable_map(struct) do
          struct |> Map.from_struct() |> Map.drop(@association_keys)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoStaticNotLoadedDropList, non_association_keys: [:__struct__, :workspace])
      |> refute_issues()
    end

    test "honors a custom :excluded_paths param" do
      source_file =
        """
        defmodule MyApp.Generated.User do
          @association_keys [:__meta__, :workspace]

          def to_serializable_map(struct) do
            struct |> Map.from_struct() |> Map.drop(@association_keys)
          end
        end
        """
        |> to_source_file("apps/my_app/lib/my_app/generated/user.ex")

      assert_issue(run_check(source_file, NoStaticNotLoadedDropList))

      source_file
      |> run_check(NoStaticNotLoadedDropList, excluded_paths: ["generated/"])
      |> refute_issues()
    end
  end
end
