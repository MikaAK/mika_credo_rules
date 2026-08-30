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

  describe "use_options/2" do
    test "returns the literal keyword list when the module matches" do
      assert use_opts("use Cache, name: :c, sandbox?: true", [Cache]) ===
               [name: :c, sandbox?: true]
    end

    test "returns nil when the module does not match" do
      assert is_nil(use_opts("use GenServer, restart: :temporary", [Cache]))
    end

    test "returns nil when opts is not a literal list (module attribute)" do
      assert is_nil(use_opts("use Cache, @cache_opts", [Cache]))
    end

    test "returns nil when use has no options" do
      assert is_nil(use_opts("use Cache", [Cache]))
    end

    test "matches the Elixir-prefixed atom spelling of the module" do
      assert use_opts(~S(use :"Elixir.Cache", name: :c), [Cache]) === [name: :c]
    end

    test "does not match an erlang atom module" do
      assert is_nil(use_opts("use :ets, name: :c", [Cache]))
    end
  end

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end

  defp use_opts(code, modules) do
    module_paths = Enum.flat_map(modules, &AstHelpers.module_paths/1)

    code
    |> Code.string_to_quoted!()
    |> find_use()
    |> AstHelpers.use_options(module_paths)
  end

  defp find_use(ast) do
    {_ast, use_node} =
      Macro.prewalk(ast, nil, fn
        {:use, _, _} = node, nil -> {node, node}
        node, acc -> {node, acc}
      end)

    use_node
  end
end
