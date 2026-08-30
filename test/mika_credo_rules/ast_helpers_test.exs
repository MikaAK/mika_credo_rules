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

  describe "uses_module?/2" do
    test "true when the file has a literal use of one of the modules" do
      assert uses_module?("defmodule Sample do\n  use GenServer\nend", [GenServer, GenStage])
    end

    test "false when the file uses none of the modules" do
      refute uses_module?("defmodule Sample do\n  def run, do: :ok\nend", [GenServer, GenStage])
    end

    test "is alias-aware: an aliased use resolves through the alias" do
      code =
        "defmodule Sample do\n  alias MyApp.Behaviours.Server, as: GenServer\n  use GenServer\nend"

      refute uses_module?(code, [Elixir.GenServer])
    end
  end

  describe "callback_clauses/2" do
    test "collects a clause whose name matches, any arity" do
      code = """
      defmodule Sample do
        def init(opts), do: {:ok, opts}
        def handle_call(_msg, _from, state), do: {:reply, :ok, state}
        def helper(x), do: x
      end
      """

      names = code |> callback_clauses([:init, :handle_call]) |> Enum.map(&clause_name/1)

      assert Enum.sort(names) === [:handle_call, :init]
    end

    test "matches through a when guard" do
      code = """
      defmodule Sample do
        def handle_info({:DOWN, _ref, :process, _pid, _reason} = msg, state) when is_map(state) do
          {:noreply, state}
        end
      end
      """

      assert [clause] = callback_clauses(code, [:handle_info])
      assert clause_name(clause) === :handle_info
    end

    test "returns an empty list when nothing matches" do
      assert callback_clauses("defmodule Sample do\n  def helper(x), do: x\nend", [:init]) === []
    end
  end

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end

  defp uses_module?(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.uses_module?(modules)
  end

  defp callback_clauses(code, names) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.callback_clauses(names)
  end

  defp clause_name({:def, _, [{:when, _, [head | _guards]}, _body]}),
    do: clause_name_from_head(head)

  defp clause_name({:def, _, [head, _body]}), do: clause_name_from_head(head)

  defp clause_name_from_head({name, _, _args}), do: name
end
