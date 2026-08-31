defmodule MikaCredoRules.FunWithFlagsAtomFlagNamesTest do
  use Credo.Test.Case

  alias MikaCredoRules.FunWithFlagsAtomFlagNames

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags string literal flag names" do
    test "reports FunWithFlags.enabled?/1 with a string flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "FunWithFlags.enabled?"
        assert issue.message =~ "FunWithFlags.enabled?"
        assert issue.message =~ "atom identity"
      end)
    end

    test "reports FunWithFlags.enable/1 with a string flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enable("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.enable" end)
    end

    test "reports FunWithFlags.disable/1 with a string flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.disable("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.disable" end)
    end

    test "reports FunWithFlags.clear/1 with a string flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.clear("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.clear" end)
    end

    test "reports FunWithFlags.lookup/1 with a string flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.lookup("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.lookup" end)
    end

    test "reports a fully qualified Elixir.FunWithFlags.enabled?/1" do
      """
      defmodule MyApp.Worker do
        def run, do: Elixir.FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue()
    end

    test "reports FunWithFlags.enabled? under alias FunWithFlags" do
      """
      defmodule MyApp.Worker do
        alias FunWithFlags

        def run, do: FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue()
    end

    test "reports FunWithFlags.enabled? under alias FunWithFlags, as: Flags" do
      """
      defmodule MyApp.Worker do
        alias FunWithFlags, as: Flags

        def run, do: Flags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue(fn issue -> assert issue.trigger === "Flags.enabled?" end)
    end

    test "reports two calls on one line at their own columns" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?("a") and FunWithFlags.enabled?("b")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issues(fn [first, second] ->
        assert first.column !== second.column
      end)
    end

    test "reports a wrapper module added through :modules" do
      """
      defmodule MyApp.Worker do
        def run, do: MyApp.FeatureFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames, modules: [MyApp.FeatureFlags])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.FeatureFlags.enabled?" end)
    end

    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> assert_issue()
    end
  end

  describe "&run/2 allows atom flag names and non-literal names" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?(:beta_feature)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report an atom flag name" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?(:beta_feature)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report a variable flag name" do
      """
      defmodule MyApp.Worker do
        def run(flag), do: FunWithFlags.enabled?(flag)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report an interpolated flag name" do
      """
      defmodule MyApp.Worker do
        def run(suffix), do: FunWithFlags.enabled?("beta_\#{suffix}")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report when FunWithFlags is shadowed by a project alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.FunWithFlags

        def run, do: FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report a module not in :modules" do
      """
      defmodule MyApp.Worker do
        def run, do: MyApp.FeatureFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "does not report a function not in :functions" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.all_flags("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames)
      |> refute_issues()
    end

    test "respects a custom :excluded_paths" do
      """
      defmodule MyApp.Worker do
        def run, do: FunWithFlags.enabled?("beta_feature")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(FunWithFlagsAtomFlagNames, excluded_paths: ["worker.ex"])
      |> refute_issues()
    end
  end
end
