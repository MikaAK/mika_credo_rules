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

  describe "keyword_literal_has_key?/2" do
    test "returns true when the literal keyword list has the key" do
      assert AstHelpers.keyword_literal_has_key?(
               [max_attempts: 3, queue: :default],
               :max_attempts
             ) ===
               true
    end

    test "returns false when the literal keyword list lacks the key" do
      assert AstHelpers.keyword_literal_has_key?([queue: :default], :max_attempts) === false
    end

    test "returns false for an empty literal list" do
      assert AstHelpers.keyword_literal_has_key?([], :max_attempts) === false
    end

    test "returns :not_literal for a variable" do
      opts_var = {:opts, [line: 1], nil}

      assert AstHelpers.keyword_literal_has_key?(opts_var, :max_attempts) === :not_literal
    end

    test "returns :not_literal for a non-keyword list" do
      assert AstHelpers.keyword_literal_has_key?([1, 2, 3], :max_attempts) === :not_literal
    end

    test "returns :not_literal for a list with a non-atom key" do
      assert AstHelpers.keyword_literal_has_key?([{"queue", :default}], :max_attempts) ===
               :not_literal
    end
  end

  describe "block_statements/1" do
    test "splits a __block__ node into its statements" do
      assert AstHelpers.block_statements({:__block__, [], [1, 2, 3]}) === [1, 2, 3]
    end

    test "wraps a single non-block statement in a list" do
      statement = {:foo, [], []}

      assert AstHelpers.block_statements(statement) === [statement]
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

    test "an arity-pinned entry matches only that arity" do
      code = """
      defmodule Sample do
        def init(opts), do: {:ok, opts}
        def init(conn, opts), do: {:ok, conn, opts}
      end
      """

      assert [clause] = callback_clauses(code, init: 1)
      assert clause_name(clause) === :init
      assert {:def, _, [{:init, _, [_single_arg]}, _body]} = clause
    end

    test "name-only matching still catches every arity" do
      code = """
      defmodule Sample do
        def init(opts), do: {:ok, opts}
        def init(conn, opts), do: {:ok, conn, opts}
      end
      """

      assert callback_clauses(code, [:init]) |> Enum.map(&clause_name/1) === [:init, :init]
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
