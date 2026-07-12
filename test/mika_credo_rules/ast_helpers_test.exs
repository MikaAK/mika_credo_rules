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
end
