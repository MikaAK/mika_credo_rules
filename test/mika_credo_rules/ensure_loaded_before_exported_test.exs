defmodule MikaCredoRules.EnsureLoadedBeforeExportedTest do
  use Credo.Test.Case

  alias MikaCredoRules.EnsureLoadedBeforeExported

  describe "&run/2 flags unguarded module-capability checks" do
    test "reports function_exported?/3 with no Code.ensure_loaded? in the clause" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          else
            mod.compile()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "function_exported?"
        assert issue.message =~ "function_exported? found without Code.ensure_loaded?"

        assert issue.message =~
                 "Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity)"
      end)
    end

    test "reports macro_exported?/3 with no Code.ensure_loaded? in the clause" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if macro_exported?(mod, :compile, 1) do
            mod.compile(opts)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue ->
        assert issue.trigger === "macro_exported?"
        assert issue.message =~ "macro_exported? found without Code.ensure_loaded?"
      end)
    end

    test "reports the Kernel-qualified spelling" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if Kernel.function_exported?(mod, :compile, 1), do: mod.compile(opts)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.trigger === "function_exported?" end)
    end

    test "reports each unguarded call site with its own line number" do
      """
      defmodule MyApp.Worker do
        def one(mod), do: function_exported?(mod, :one, 0)
        def two(mod), do: function_exported?(mod, :two, 0)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3]
      end)
    end

    test "flags the unguarded clause while a sibling clause is guarded" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) when is_map(opts) do
          Code.ensure_loaded?(mod) and function_exported?(mod, :compile, 1)
        end

        def compile(mod, _opts) do
          function_exported?(mod, :compile, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end

    test "reports two triggers on the same line at their own columns" do
      """
      defmodule MyApp.Worker do
        def compile(mod, other), do: function_exported?(mod, :a, 0) or function_exported?(other, :b, 0)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.column) |> Enum.sort() === [32, 66]
      end)
    end
  end

  describe "&run/2 allows guarded module-capability checks" do
    test "does not report when Code.ensure_loaded?/1 guards the call" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if Code.ensure_loaded?(mod) and function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          else
            mod.compile()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not report when the guard is anywhere else in the same clause body" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          loaded? = Code.ensure_loaded?(mod)

          if function_exported?(mod, :compile, 1) and loaded? do
            mod.compile(opts)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not report when Code.ensure_loaded/1 (non-bang, non-?) guards the call" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          {:module, ^mod} = Code.ensure_loaded(mod)
          if function_exported?(mod, :compile, 1), do: mod.compile(opts)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not report when Code.ensure_compiled/1 guards the call" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          Code.ensure_compiled(mod)
          if function_exported?(mod, :compile, 1), do: mod.compile(opts)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not report when Code.ensure_compiled!/1 guards the call" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          Code.ensure_compiled!(mod)
          if function_exported?(mod, :compile, 1), do: mod.compile(opts)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of Code" do
    test "does not report when Code is aliased with as:" do
      """
      defmodule MyApp.Worker do
        alias Code, as: C

        def compile(mod, opts) do
          if C.ensure_loaded?(mod) and function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured functions" do
      """
      defmodule MyApp.Worker do
        def one(mod), do: function_exported?(mod, :one, 0)
        def two(mod), do: macro_exported?(mod, :two, 0)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported, functions: [:macro_exported?])
      |> assert_issue(fn issue -> assert issue.trigger === "macro_exported?" end)
    end
  end

  describe "&run/2 honours the :guard_functions param" do
    test "accepts a custom guard function as satisfying the guard" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if MyApp.Loader.loaded?(mod) and function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported, guard_functions: [{MyApp.Loader, :loaded?}])
      |> refute_issues()
    end

    test "no longer accepts Code.ensure_loaded? once removed from :guard_functions" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if Code.ensure_loaded?(mod) and function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported, guard_functions: [])
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report a file under an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        def compile(mod), do: function_exported?(mod, :compile, 1)
      end
      """
      |> to_source_file("lib/my_app/legacy/worker.ex")
      |> run_check(EnsureLoadedBeforeExported, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          else
            mod.compile()
          end
        end
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> EnsureLoadedBeforeExported.run([])
      |> case do
        [] -> raise "BAD example does not fire — the docs are lying"
        issues -> issues
      end
    end

    test "moduledoc GOOD example does not fire" do
      """
      defmodule MyApp.Worker do
        def compile(mod, opts) do
          if Code.ensure_loaded?(mod) and function_exported?(mod, :compile, 1) do
            mod.compile(opts)
          else
            mod.compile()
          end
        end
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> EnsureLoadedBeforeExported.run([])
      |> case do
        [] -> :ok
        issues -> raise "GOOD example fires — #{inspect(issues)}"
      end
    end
  end
end
