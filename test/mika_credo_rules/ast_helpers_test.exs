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

  describe "remote_call/1" do
    test "destructures a call through an alias path" do
      assert AstHelpers.remote_call(quote(do: Mix.env())) === {[:Mix], :env, []}
    end

    test "destructures a nested alias path with arguments" do
      assert {[:Ecto, :Query], :where, [_query, _bindings, _expr]} =
               AstHelpers.remote_call(quote(do: Ecto.Query.where(query, [u], u.age)))
    end

    test "destructures an erlang call" do
      assert AstHelpers.remote_call(quote(do: :ets.new(:table, []))) ===
               {:ets, :new, [:table, []]}
    end

    test "normalizes a bare-atom Elixir module to its fully-qualified path" do
      bracket_access = quote(do: opts[:url])

      assert {[Elixir, :Access], :get, [_opts, :url]} = AstHelpers.remote_call(bracket_access)
    end

    test "returns nil for local calls, variables, and literals" do
      assert is_nil(AstHelpers.remote_call(quote(do: env())))
      assert is_nil(AstHelpers.remote_call(quote(do: value)))
      assert is_nil(AstHelpers.remote_call(quote(do: 42)))
      assert is_nil(AstHelpers.remote_call(quote(do: %{a: 1})))
    end

    test "returns nil for a dot access without a call" do
      assert is_nil(AstHelpers.remote_call(quote(do: map.field)))
    end
  end

  describe "remote_call?/3" do
    test "true for a matching module and function in either spelling" do
      assert AstHelpers.remote_call?(quote(do: Mix.env()), [Mix], [:env])
      assert AstHelpers.remote_call?(quote(do: Elixir.Mix.env()), [Mix], [:env])
    end

    test "true for a matching erlang call" do
      assert AstHelpers.remote_call?(quote(do: :ets.new(:table, [])), [:ets], [:new])
    end

    test "false when the function does not match" do
      refute AstHelpers.remote_call?(quote(do: Mix.target()), [Mix], [:env])
    end

    test "false when only the function name collides on another module" do
      refute AstHelpers.remote_call?(quote(do: Enum.join(list)), [Ecto.Query], [:join])
    end

    test "false for bracket access when Access is not listed" do
      refute AstHelpers.remote_call?(quote(do: opts[:url]), [Mix], [:get])
    end

    test "true for bracket access when Access is listed" do
      assert AstHelpers.remote_call?(quote(do: opts[:url]), [Access], [:get])
    end

    test "false for non-call AST" do
      refute AstHelpers.remote_call?(quote(do: value), [Mix], [:env])
    end
  end

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end
end
