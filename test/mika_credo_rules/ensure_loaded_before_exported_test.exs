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

  describe "&run/2 flags Code.loaded?/1" do
    test "reports Code.loaded?/1 with no Code.ensure_loaded? in the clause" do
      """
      defmodule MyApp.Worker do
        def compile(mod), do: Code.loaded?(mod)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue ->
        assert issue.trigger === "loaded?"
        assert issue.message =~ "loaded? found without Code.ensure_loaded?"
      end)
    end

    test "does not report when Code.ensure_loaded?/1 guards Code.loaded?/1" do
      """
      defmodule MyApp.Worker do
        def compile(mod) do
          Code.ensure_loaded?(mod)
          Code.loaded?(mod)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "resolves an alias of Code for the Code.loaded?/1 spelling" do
      """
      defmodule MyApp.Worker do
        alias Code, as: C

        def compile(mod), do: C.loaded?(mod)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.trigger === "loaded?" end)
    end
  end

  describe "&run/2 restricts matches to the real arity" do
    test "does not report function_exported? called with the wrong arity" do
      """
      defmodule MyApp.Worker do
        def loaded?(mod), do: function_exported?(mod)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not report macro_exported? called with the wrong arity" do
      """
      defmodule MyApp.Worker do
        def loaded?(mod, fun), do: macro_exported?(mod, fun)
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
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

  describe "&run/2 flags ExUnit test/setup blocks" do
    test "reports an unguarded call inside a test block" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        test "compiles" do
          function_exported?(MyApp.Worker, :compile, 1)
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report a guarded call inside the same test block" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        test "compiles" do
          Code.ensure_loaded?(MyApp.Worker)
          function_exported?(MyApp.Worker, :compile, 1)
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "reports an unguarded call inside a test block with a context pattern" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        test "compiles", ctx do
          function_exported?(ctx.mod, :compile, 1)
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue()
    end

    test "reports an unguarded call inside a setup block" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        setup do
          function_exported?(MyApp.Worker, :compile, 1)
          :ok
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report a guarded call inside the same setup block" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        setup do
          Code.ensure_loaded?(MyApp.Worker)
          function_exported?(MyApp.Worker, :compile, 1)
          :ok
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "reports an unguarded call inside a setup_all block" do
      """
      defmodule MyApp.WorkerTest do
        use ExUnit.Case

        setup_all do
          function_exported?(MyApp.Worker, :compile, 1)
          :ok
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports an unguarded call inside a defmacro body" do
      """
      defmodule MyApp.Macros do
        defmacro require_compile(mod) do
          function_exported?(mod, :compile, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "does not report a guarded call inside the same defmacro body" do
      """
      defmodule MyApp.Macros do
        defmacro require_compile(mod) do
          Code.ensure_loaded?(mod)
          function_exported?(mod, :compile, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end
  end

  describe "&run/2 does not descend into quoted code inside a def/defmacro" do
    test "does not report a function_exported? call quoted inside a defp" do
      """
      defmodule MyApp.Macros do
        defp build(mod) do
          quote do: function_exported?(unquote(mod), :f, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> refute_issues()
    end

    test "does not treat a guard call quoted inside a def as satisfying the guard" do
      """
      defmodule MyApp.Macros do
        def build(mod) do
          quote do
            Code.ensure_loaded?(unquote(mod))
          end

          function_exported?(mod, :f, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(EnsureLoadedBeforeExported)
      |> assert_issue()
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
