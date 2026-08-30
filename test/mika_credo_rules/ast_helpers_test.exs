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
  end

  describe "ecto_query_functions/0" do
    test "returns the default Ecto query DSL function names" do
      assert AstHelpers.ecto_query_functions() === [
               :dynamic,
               :from,
               :where,
               :or_where,
               :having,
               :or_having,
               :select,
               :select_merge,
               :on,
               :join,
               :query,
               :subquery,
               :in
             ]
    end
  end

  describe "ecto_query_call?/3" do
    test "true for a bare call whose name is ignored" do
      ast = quote do: where(query, [u], u.age == 18)

      assert AstHelpers.ecto_query_call?(ast, [], AstHelpers.ecto_query_functions())
    end

    test "false for a bare call whose name is not ignored" do
      ast = quote do: some_helper(query, [u], u.age === 18)

      refute AstHelpers.ecto_query_call?(ast, [], AstHelpers.ecto_query_functions())
    end

    test "true for a qualified call on an ecto_query_module whose name is ignored" do
      ast = quote do: Ecto.Query.where(query, [u], u.age == 18)

      assert AstHelpers.ecto_query_call?(
               ast,
               [[:Ecto, :Query]],
               AstHelpers.ecto_query_functions()
             )
    end

    test "false for a qualified call whose module is not an ecto_query_module" do
      ast = quote do: Enum.join(names, ",")

      refute AstHelpers.ecto_query_call?(ast, [[:Ecto, :Query]], [:join])
    end

    test "false for a non-call node" do
      refute AstHelpers.ecto_query_call?(quote(do: :ok), [], AstHelpers.ecto_query_functions())
    end
  end

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end
end
