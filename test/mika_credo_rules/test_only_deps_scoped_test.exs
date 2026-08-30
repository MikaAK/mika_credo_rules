defmodule MikaCredoRules.TestOnlyDepsScopedTest do
  use Credo.Test.Case

  alias MikaCredoRules.TestOnlyDepsScoped

  describe "&run/2 flags a test-only package missing :only" do
    test "reports a 2-tuple dep with a version but no only:" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:excoveralls, "~> 0.18"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === ":excoveralls"
        assert issue.message =~ ":excoveralls"
        assert issue.message =~ "only:"
      end)
    end

    test "reports a 3-tuple dep that isn't runtime-relevant but is missing only:" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:excoveralls, "~> 0.18", runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue -> assert issue.message =~ "only:" end)
    end

    test "does not report when only: is a bare atom" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:dialyxir, "~> 1.4", only: :test, runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end

    test "does not report when only: is a list" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a package missing runtime: false" do
    test "reports a dep with only: present but no runtime: false" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", only: :test}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue -> assert issue.message =~ "runtime: false" end)
    end

    test "does not report when runtime: false and only: are both present" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", only: :test, runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end

    test "reports when runtime is present but not false" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", runtime: true, only: :test}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue -> assert issue.message =~ "runtime: false" end)
    end
  end

  describe "&run/2 reports both violations independently" do
    test "the moduledoc BAD example fires with both missing options" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issues(fn issues ->
        messages = Enum.map(issues, & &1.message)
        assert length(issues) === 2
        assert Enum.any?(messages, &(&1 =~ "only:"))
        assert Enum.any?(messages, &(&1 =~ "runtime: false"))
      end)
    end

    test "a package in both lists missing both opts gets two issues" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:wallaby, "~> 0.30"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issues(fn issues ->
        messages = Enum.map(issues, & &1.message)
        assert length(issues) === 2
        assert Enum.any?(messages, &(&1 =~ "only:"))
        assert Enum.any?(messages, &(&1 =~ "runtime: false"))
      end)
    end

    test "the moduledoc GOOD example raises no issues" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
            {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end
  end

  describe "&run/2 handles every dep tuple shape" do
    test "handles a git/path dep with no version (2-tuple opts form)" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:mix_test_watch, path: "../mix_test_watch"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue -> assert issue.message =~ "only:" end)
    end

    test "resolves the line of a bare 2-tuple via a raw source scan" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
            {:mix_test_watch, "~> 1.0"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> assert_issue(fn issue ->
        assert issue.trigger === ":mix_test_watch"
        assert issue.line_no === 5
      end)
    end
  end

  describe "&run/2 leaves unrelated packages alone" do
    test "does not report a package outside both lists" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:phoenix, "~> 1.7"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end

    test "does not report an in_umbrella dep" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:shared_utils, in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end
  end

  describe "&run/2 only scopes to mix.exs files" do
    test "does not report inside a non mix.exs file" do
      """
      defp deps do
        [{:credo, "~> 1.7"}]
      end
      """
      |> to_source_file("lib/my_app/deps_helper.ex")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end

    test "does not report a mix.exs lookalike filename" do
      """
      defp deps do
        [{:credo, "~> 1.7"}]
      end
      """
      |> to_source_file("lib/remix.exs")
      |> run_check(TestOnlyDepsScoped)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :test_only_packages and :require_runtime_false params" do
    test "removing a package from :test_only_packages silences the only: check" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped, test_only_packages: [:wallaby])
      |> refute_issues()
    end

    test "adding a package to :test_only_packages reports it" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:my_custom_dev_tool, "~> 1.0", runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(TestOnlyDepsScoped, test_only_packages: [:my_custom_dev_tool])
      |> assert_issue(fn issue -> assert issue.message =~ "only:" end)
    end
  end
end
