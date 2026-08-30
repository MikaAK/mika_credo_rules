defmodule MikaCredoRules.NoTruthyAndOrTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoTruthyAndOr

  describe "&run/2 flags and/or/not on a provably-nilable operand" do
    test "reports or with an Access bracket read" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: opts[:llm_merge] or opts[:ai_review]
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "or"
        assert issue.message =~ "or found"
        assert issue.message =~ "||"
      end)
    end

    test "reports or with a string-key Access bracket read" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: opts["llm_merge"] or false
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "or" end)
    end

    test "reports and with Map.get/2" do
      """
      defmodule MyApp.Worker do
        def ready?(config), do: Map.get(config, :enabled) and ready?()
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue ->
        assert issue.trigger === "and"
        assert issue.message =~ "&&"
      end)
    end

    test "reports not with Keyword.get/2" do
      """
      defmodule MyApp.Worker do
        def skip?(opts), do: not Keyword.get(opts, :skip)
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue ->
        assert issue.trigger === "not"
        assert issue.message =~ "!"
      end)
    end

    test "reports and with List.first/1" do
      """
      defmodule MyApp.Worker do
        def first_ok?(list), do: List.first(list) and true
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "and" end)
    end

    test "reports or with Map.get/3 whose default is a literal nil" do
      """
      defmodule MyApp.Worker do
        def enabled?(config), do: Map.get(config, :enabled, nil) or false
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "or" end)
    end

    test "reports or with Keyword.get/3 whose default is a literal nil" do
      """
      defmodule MyApp.Worker do
        def enabled?(opts), do: Keyword.get(opts, :enabled, nil) or false
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "or" end)
    end

    test "reports the mirrored operand order" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: true and opts[:llm_merge]
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "and" end)
    end

    test "reports an explicit qualified Access.get call" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: Access.get(opts, :llm_merge) or false
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "or" end)
    end

    test "resolves an alias of Map" do
      """
      defmodule MyApp.Worker do
        alias Map, as: M

        def ready?(config), do: M.get(config, :enabled) and true
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issue(fn issue -> assert issue.trigger === "and" end)
    end

    test "flags the inner and of a nested and chain, not the outer or" do
      """
      defmodule MyApp.Worker do
        def two(opts), do: opts[:a] and true or opts[:b] and true
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === ["and", "and"]
        assert issues |> Enum.map(& &1.column) |> Enum.sort() === [31, 52]
      end)
    end
  end

  describe "&run/2 allows non-nilable operands" do
    test "does not report plain variables" do
      """
      defmodule MyApp.Worker do
        def both?(a, b), do: a and b
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> refute_issues()
    end

    test "does not report function calls" do
      """
      defmodule MyApp.Worker do
        def both?(opts), do: enabled?(opts) or disabled?(opts)
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> refute_issues()
    end

    test "does not report comparisons" do
      """
      defmodule MyApp.Worker do
        def match?(a, b, c, d), do: a == b and c == d
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> refute_issues()
    end

    test "does not report Map.get/3 with a non-nil default" do
      """
      defmodule MyApp.Worker do
        def enabled?(config), do: Map.get(config, :enabled, false) or fallback?()
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> refute_issues()
    end

    test "does not report Keyword.get/3 with a non-nil default" do
      """
      defmodule MyApp.Worker do
        def enabled?(opts), do: Keyword.get(opts, :enabled, false) or fallback?()
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :nilable_functions param" do
    test "accepts a custom nilable function shape" do
      """
      defmodule MyApp.Worker do
        def ready?(mod), do: MyApp.Loader.fetch(mod) and true
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr, nilable_functions: [{MyApp.Loader, :fetch, 1}])
      |> assert_issue(fn issue -> assert issue.trigger === "and" end)
    end

    test "no longer flags Map.get/2 once removed from :nilable_functions" do
      """
      defmodule MyApp.Worker do
        def ready?(config), do: Map.get(config, :enabled) and true
      end
      """
      |> to_source_file()
      |> run_check(NoTruthyAndOr, nilable_functions: [])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report a file under an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        def merge?(opts), do: opts[:llm_merge] or false
      end
      """
      |> to_source_file("lib/my_app/legacy/worker.ex")
      |> run_check(NoTruthyAndOr, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: opts[:llm_merge] or opts[:ai_review]
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> NoTruthyAndOr.run([])
      |> case do
        [] -> raise "BAD example does not fire — the docs are lying"
        issues -> issues
      end
    end

    test "moduledoc GOOD example does not fire" do
      """
      defmodule MyApp.Worker do
        def merge?(opts), do: opts[:llm_merge] || opts[:ai_review]
      end
      """
      |> Credo.SourceFile.parse("lib/my_app/worker.ex")
      |> NoTruthyAndOr.run([])
      |> case do
        [] -> :ok
        issues -> raise "GOOD example fires — #{inspect(issues)}"
      end
    end
  end
end
