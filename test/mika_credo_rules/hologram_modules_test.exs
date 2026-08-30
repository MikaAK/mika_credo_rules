defmodule MikaCredoRules.HologramModulesTest do
  use ExUnit.Case, async: true

  alias MikaCredoRules.HologramModules

  describe "hologram_module_bodies/2" do
    test "returns the body of a module using Hologram.Page" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          def template, do: :ok
        end
        """)

      assert length(bodies) === 1
    end

    test "returns the body of a module using Hologram.Component" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.Counter do
          use Hologram.Component
        end
        """)

      assert length(bodies) === 1
    end

    test "does not return a module with no Hologram use" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.PlainModule do
          def hello, do: :ok
        end
        """)

      assert bodies === []
    end

    test "does not give a nested non-Hologram module its own entry" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          defmodule Helpers do
            def hello, do: :ok
          end
        end
        """)

      assert length(bodies) === 1
    end

    test "gives a nested Hologram module its own independent entry" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          defmodule Counter do
            use Hologram.Component
          end
        end
        """)

      assert length(bodies) === 2
    end

    test "resolves an alias of Hologram.Page" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          alias Hologram.Page

          use Page
        end
        """)

      assert length(bodies) === 1
    end

    test "does not fire when a project alias shadows Page" do
      bodies =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          alias MyApp.Page

          use Page
        end
        """)

      assert bodies === []
    end
  end

  describe "own_body_callback_clauses/2" do
    test "returns def action/3 clauses from a Hologram module's own body" do
      [{_module_ast, body}] =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          def action(:save, _params, component), do: component
          def command(:save, _params, server), do: server
        end
        """)

      clauses = HologramModules.own_body_callback_clauses(body, [:action])

      assert length(clauses) === 1
    end

    test "does not match a differently-named callback" do
      [{_module_ast, body}] =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          def command(:save, _params, server), do: server
        end
        """)

      assert HologramModules.own_body_callback_clauses(body, [:action]) === []
    end

    test "requires arity 3" do
      [{_module_ast, body}] =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          def action(:save, _params), do: :ok
        end
        """)

      assert HologramModules.own_body_callback_clauses(body, [:action]) === []
    end

    test "excludes clauses inside a nested defmodule" do
      [{_module_ast, body}] =
        hologram_bodies("""
        defmodule MyApp.ProductPage do
          use Hologram.Page

          def action(:save, _params, component), do: component

          defmodule Nested do
            def action(:other, _params, component), do: component
          end
        end
        """)

      clauses = HologramModules.own_body_callback_clauses(body, [:action])

      assert length(clauses) === 1
    end
  end

  defp hologram_bodies(code) do
    code
    |> Credo.SourceFile.parse("lib/my_app/product_page.ex")
    |> HologramModules.hologram_module_bodies([Hologram.Page, Hologram.Component])
  end
end
