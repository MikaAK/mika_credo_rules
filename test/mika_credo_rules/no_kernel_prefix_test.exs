defmodule MikaCredoRules.NoKernelPrefixTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoKernelPrefix

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags Kernel.-prefixed remote calls" do
    test "reports a bare Kernel.inspect/1 call" do
      """
      defmodule MyApp.Worker do
        def show(value), do: Kernel.inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "Kernel.inspect"
        assert issue.message =~ "Kernel.inspect/1 found"
        assert issue.message =~ "Kernel is auto-imported"
      end)
    end

    test "reports each Kernel.-prefixed call on its own column when repeated on one line" do
      """
      defmodule MyApp.Worker do
        def show(a, b), do: Kernel.inspect(a) && Kernel.inspect(b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.column) |> Enum.sort() === [23, 44]
      end)
    end

    test "does not report a bare unqualified call" do
      """
      defmodule MyApp.Worker do
        def show(value), do: inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end
  end

  describe "&run/2 exempts operator captures" do
    test "does not report &Kernel.+/2" do
      """
      defmodule MyApp.Worker do
        def adder, do: &Kernel.+/2
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report &Kernel.>=/2" do
      """
      defmodule MyApp.Worker do
        def gte, do: &Kernel.>=/2
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report &Kernel.!/1" do
      """
      defmodule MyApp.Worker do
        def negate, do: &Kernel.!/1
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "still reports a non-operator capture like &Kernel.inspect/1" do
      """
      defmodule MyApp.Worker do
        def inspector, do: &Kernel.inspect/1
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.inspect" end)
    end
  end

  describe "&run/2 leaves sibling Kernel.* modules alone" do
    test "does not report Kernel.SpecialForms references" do
      """
      defmodule MyApp.Worker do
        def build, do: Kernel.SpecialForms.unquote(:x)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report Kernel.ParallelCompiler references" do
      """
      defmodule MyApp.Worker do
        def compile, do: Kernel.ParallelCompiler.compile([])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliasing and shadowing" do
    test "reports under alias Kernel, as: K" do
      """
      defmodule MyApp.Worker do
        alias Kernel, as: K

        def show(value), do: K.inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "K.inspect" end)
    end

    test "does not report bare Kernel.foo when shadowed by alias MyApp.Kernel" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Kernel

        def show(value), do: Kernel.foo(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end
  end

  describe "&run/2 honors :allowed_functions" do
    test "does not report an allow-listed function" do
      """
      defmodule MyApp.Worker do
        def show(value), do: Kernel.inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix, allowed_functions: [:inspect])
      |> refute_issues()
    end

    test "still reports a function not on the allow-list" do
      """
      defmodule MyApp.Worker do
        def show(list), do: Kernel.length(list)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix, allowed_functions: [:inspect])
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.length" end)
    end
  end

  describe "&run/2 honors :excluded_paths" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        def show(value), do: Kernel.inspect(value)
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/worker.ex")
      |> run_check(NoKernelPrefix, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "reports the moduledoc BAD example" do
      """
      Kernel.inspect(value)
      Kernel.length(list)
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "does not report the moduledoc GOOD example" do
      """
      inspect(value)
      length(list)
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end
  end
end
