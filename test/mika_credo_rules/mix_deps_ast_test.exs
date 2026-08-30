defmodule MikaCredoRules.MixDepsAstTest do
  use ExUnit.Case, async: true

  alias MikaCredoRules.MixDepsAst

  describe "deps/1" do
    test "extracts a 2-tuple dep with only a version requirement" do
      assert [%{pkg: :ex_doc, requirement: "~> 0.34", opts: [], line_no: nil}] =
               deps_from("""
               defmodule Sample.MixProject do
                 defp deps do
                   [
                     {:ex_doc, "~> 0.34"}
                   ]
                 end
               end
               """)
    end

    test "extracts a 3-tuple dep with version and opts, capturing the AST line" do
      assert [%{pkg: :credo, requirement: "~> 1.7", opts: [runtime: false], line_no: 4}] =
               deps_from("""
               defmodule Sample.MixProject do
                 defp deps do
                   [
                     {:credo, "~> 1.7", runtime: false}
                   ]
                 end
               end
               """)
    end

    test "extracts a 2-tuple dep with only opts (path/git dep)" do
      assert [%{pkg: :my_lib, requirement: nil, opts: [path: "../my_lib"], line_no: nil}] =
               deps_from("""
               defmodule Sample.MixProject do
                 defp deps do
                   [
                     {:my_lib, path: "../my_lib"}
                   ]
                 end
               end
               """)
    end

    test "reads from a public def deps as well as defp" do
      assert [%{pkg: :credo}] =
               deps_from("""
               defmodule Sample.MixProject do
                 def deps do
                   [{:credo, "~> 1.7"}]
                 end
               end
               """)
    end

    test "returns an empty list when deps is not a literal list" do
      assert [] =
               deps_from("""
               defmodule Sample.MixProject do
                 defp deps, do: shared_deps() ++ extra_deps()
               end
               """)
    end

    test "returns an empty list when there is no deps function" do
      assert [] =
               deps_from("""
               defmodule Sample.MixProject do
                 def project, do: []
               end
               """)
    end

    test "extracts every entry in a multi-dep list" do
      assert [%{pkg: :credo}, %{pkg: :dialyxir}, %{pkg: :ex_doc}] =
               deps_from("""
               defmodule Sample.MixProject do
                 defp deps do
                   [
                     {:credo, "~> 1.7", runtime: false},
                     {:dialyxir, "~> 1.4", only: :test, runtime: false},
                     {:ex_doc, "~> 0.34"}
                   ]
                 end
               end
               """)
    end
  end

  describe "line_no/2" do
    test "returns the AST line when already known" do
      source =
        Credo.SourceFile.parse("defp deps, do: [{:credo, \"~> 1.7\", runtime: false}]", "mix.exs")

      [dep] = MixDepsAst.deps(source)

      assert MixDepsAst.line_no(dep, source) === dep.line_no
    end

    test "falls back to a raw source scan for a 2-tuple with no AST line" do
      source =
        Credo.SourceFile.parse(
          """
          defmodule Sample.MixProject do
            defp deps do
              [
                {:ex_doc, "~> 0.34"}
              ]
            end
          end
          """,
          "mix.exs"
        )

      [dep] = MixDepsAst.deps(source)

      assert MixDepsAst.line_no(dep, source) === 4
    end
  end

  defp deps_from(code) do
    code
    |> Credo.SourceFile.parse("mix.exs")
    |> MixDepsAst.deps()
  end
end
