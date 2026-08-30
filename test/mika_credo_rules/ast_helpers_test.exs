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

  defp resolve(code, modules) do
    code
    |> Credo.SourceFile.parse("lib/sample.ex")
    |> AstHelpers.resolve_aliases(modules)
  end
end
