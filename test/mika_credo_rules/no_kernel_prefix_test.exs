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
        assert issue.message =~ "Kernel.inspect found"
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

  describe "&run/2 exempts operator CALLS — call syntax has no valid unqualified spelling" do
    test "does not report a piped Kernel.++ call" do
      """
      defmodule MyApp.Worker do
        def combine(list, extra), do: list |> Kernel.++(extra)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report a piped Kernel.<> call" do
      """
      defmodule MyApp.Worker do
        def join(left, right), do: left |> Kernel.<>(right)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report a piped Kernel.|| call" do
      """
      defmodule MyApp.Worker do
        def first(value, fallback), do: value |> Kernel.||(fallback)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "does not report a standalone Kernel.++ call" do
      """
      defmodule MyApp.Worker do
        def combine(a, b), do: Kernel.++(a, b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "still reports Kernel.inspect(x) as a bare call" do
      """
      defmodule MyApp.Worker do
        def show(value), do: Kernel.inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.inspect" end)
    end

    test "still reports a piped Kernel.inspect call exactly once" do
      """
      defmodule MyApp.Worker do
        def show(value), do: value |> Kernel.inspect()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.inspect" end)
    end

    test "still reports a piped Kernel.not call — not/1 has a valid unqualified call form" do
      """
      defmodule MyApp.Worker do
        def negate(value), do: value |> Kernel.not()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.not" end)
    end
  end

  describe "&run/2 honors import Kernel, except:" do
    test "does not report a call whose name/arity is excepted" do
      """
      defmodule MyApp.Worker do
        import Kernel, except: [to_string: 1]

        def show(worker), do: worker |> Kernel.to_string()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
    end

    test "still reports a different function not covered by the except list" do
      """
      defmodule MyApp.Worker do
        import Kernel, except: [to_string: 1]

        def show(value), do: Kernel.inspect(value)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.inspect" end)
    end

    test "still reports the same name at an arity the except list does not cover" do
      """
      defmodule MyApp.Worker do
        import Kernel, except: [to_string: 2]

        def show(worker), do: worker |> Kernel.to_string()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> assert_issue(fn issue -> assert issue.trigger === "Kernel.to_string" end)
    end
  end

  describe "&run/2 leaves alias statements alone" do
    test "does not report a Kernel.{} multi-alias as a call" do
      """
      defmodule MyApp.Worker do
        alias Kernel.{SpecialForms}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoKernelPrefix)
      |> refute_issues()
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
