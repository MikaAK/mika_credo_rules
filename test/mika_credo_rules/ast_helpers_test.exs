defmodule MikaCredoRules.AstHelpersTest do
  use ExUnit.Case, async: true

  alias MikaCredoRules.AstHelpers

  doctest MikaCredoRules.AstHelpers

  describe "module_paths/1" do
    test "returns bare and fully-qualified spellings of a top-level module" do
      assert AstHelpers.module_paths(Mix) === [[:Mix], [Elixir, :Mix]]
    end

    test "returns both spellings of a nested module" do
      assert AstHelpers.module_paths(Ecto.Query) === [
               [:Ecto, :Query],
               [Elixir, :Ecto, :Query]
             ]
    end

    test "returns both spellings of a deeply nested module" do
      assert AstHelpers.module_paths(Mix.Tasks.Deploy) === [
               [:Mix, :Tasks, :Deploy],
               [Elixir, :Mix, :Tasks, :Deploy]
             ]
    end
  end

  describe "resolve_aliases/2" do
    test "returns both base spellings when the file declares no aliases" do
      paths = resolve("defmodule Sample, do: :ok", [Ecto.Query])

      assert [:Ecto, :Query] in paths
      assert [Elixir, :Ecto, :Query] in paths
    end

    test "ADD: a plain alias joins the match set" do
      paths = resolve("defmodule Sample do\n  alias Ecto.Query\nend", [Ecto.Query])

      assert [:Query] in paths
    end

    test "ADD: an as: rename joins the match set under the renamed name" do
      paths = resolve("defmodule Sample do\n  alias Ecto.Query, as: Q\nend", [Ecto.Query])

      assert [:Q] in paths
      refute [:Query] in paths
    end

    test "ADD: a multi-alias joins the match set" do
      paths = resolve("defmodule Sample do\n  alias Ecto.{Query, Changeset}\nend", [Ecto.Query])

      assert [:Query] in paths
      refute [:Changeset] in paths
    end

    test "REMOVE: a project alias shadows a single-segment base name" do
      paths = resolve("defmodule Sample do\n  alias MyApp.Application\nend", [Application])

      refute [:Application] in paths
      assert [Elixir, :Application] in paths
    end

    test "a project alias over a multi-segment base is a no-op" do
      paths = resolve("defmodule Sample do\n  alias MyApp.Query\nend", [Ecto.Query])

      refute [:Query] in paths
      assert [:Ecto, :Query] in paths
    end

    test "an unrelated alias changes nothing" do
      paths = resolve("defmodule Sample do\n  alias MyApp.Worker\nend", [Application])

      assert paths === AstHelpers.module_paths(Application)
    end

    test "ORDER: a later alias overrides an earlier one (shadow wins)" do
      code = "defmodule Sample do\n  alias Task.Supervisor\n  alias MyApp.Supervisor\nend"
      paths = resolve(code, [Task.Supervisor])

      refute [:Supervisor] in paths
    end

    test "ORDER: a later alias overrides an earlier one (add wins)" do
      code = "defmodule Sample do\n  alias MyApp.Supervisor\n  alias Task.Supervisor\nend"
      paths = resolve(code, [Task.Supervisor])

      assert [:Supervisor] in paths
    end

    test "ORDER: a later re-alias restores a shadowed single-segment name" do
      code = "defmodule Sample do\n  alias MyApp.Application\n  alias Application\nend"
      paths = resolve(code, [Application])

      assert [:Application] in paths
    end
  end

  describe "defined_module_names/1" do
    test "returns the name of a top-level defmodule" do
      assert [:Sample] in defined_names("defmodule Sample, do: :ok")
    end

    test "returns the name of a defmodule nested inside another module" do
      names =
        defined_names("""
        defmodule Sample do
          defmodule Mock do
            def build, do: :ok
          end
        end
        """)

      assert [:Sample] in names
      assert [:Mock] in names
    end

    test "returns the literal AST segments, not the fully qualified name" do
      names =
        defined_names("""
        defmodule Sample do
          defmodule Sample.Nested do
            def build, do: :ok
          end
        end
        """)

      assert [:Sample] in names
      assert [:Sample, :Nested] in names
      refute [:Nested] in names
    end

    test "returns each name once even when defined only once" do
      names = defined_names("defmodule Sample, do: :ok")

      assert names === [[:Sample]]
    end
  end

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end

  defp defined_names(code) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.defined_module_names()
  end
end
