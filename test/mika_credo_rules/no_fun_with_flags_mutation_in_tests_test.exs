defmodule MikaCredoRules.NoFunWithFlagsMutationInTestsTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoFunWithFlagsMutationInTests

  @test_file "apps/my_app/test/my_app/banner_test.exs"
  @lib_file "apps/my_app/lib/my_app/banner.ex"

  @moduledoc_examples NoFunWithFlagsMutationInTests
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoFunWithFlagsMutationInTests"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a FunWithFlags mutation in a test file" do
    test "reports FunWithFlags.enable/1" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "FunWithFlags.enable"
        assert issue.message =~ "FunWithFlags.enable"
        assert issue.message =~ "async"
      end)
    end

    test "reports FunWithFlags.disable/1" do
      """
      defmodule MyApp.BannerTest do
        test "hides the beta banner" do
          FunWithFlags.disable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.disable" end)
    end

    test "reports FunWithFlags.clear/1" do
      """
      defmodule MyApp.BannerTest do
        test "clears the flag" do
          FunWithFlags.clear(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.clear" end)
    end

    test "reports a mutation inside a setup block" do
      """
      defmodule MyApp.BannerTest do
        setup do
          FunWithFlags.enable(:beta_banner)
          :ok
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a piped mutation" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          :beta_banner |> FunWithFlags.enable()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.enable" end)
    end
  end

  describe "&run/2 flags a wrapper module via :wrapper_suffixes" do
    test "reports a fully qualified MyApp.FeatureFlags.enable/1" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          MyApp.FeatureFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.FeatureFlags.enable" end)
    end

    test "reports an aliased wrapper" do
      """
      defmodule MyApp.BannerTest do
        alias MyApp.FeatureFlags

        test "shows the beta banner" do
          FeatureFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.trigger === "FeatureFlags.enable" end)
    end
  end

  describe "&run/2 leaves reads and unrelated calls alone" do
    test "does not report FunWithFlags.enabled?/1" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          assert FunWithFlags.enabled?(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "does not report a same-named function on an unmatched module" do
      """
      defmodule MyApp.BannerTest do
        test "polls" do
          Flags.enable_polling()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "does not crash on a __MODULE__-rooted wrapper call" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          __MODULE__.FeatureFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "does not crash on an unquote-rooted wrapper call inside a quote block" do
      """
      defmodule MyApp.BannerTest do
        for mod <- [MyApp, OtherApp] do
          test "shows the beta banner for \#{mod}" do
            unquote(mod).FeatureFlags.enable(:beta_banner)
          end
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "does not report the Elixir-prefixed atom module spelling" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          :"Elixir.FunWithFlags".enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 only checks files matching :included_paths" do
    test "does not report a mutation in a lib file" do
      """
      defmodule MyApp.Banner do
        def seed_flags do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "does not report a boundary-lookalike lib path (lib/latest/ contains 'test')" do
      """
      defmodule MyApp.Banner do
        def seed_flags do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/banner.ex")
      |> run_check(NoFunWithFlagsMutationInTests)
      |> refute_issues()
    end

    test "reports a mutation under test/support/ even without a _test.exs suffix" do
      """
      defmodule MyApp.Support.FlagHelpers do
        def with_beta_banner do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file("apps/my_app/test/support/flag_helpers.ex")
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured function" do
      """
      defmodule MyApp.BannerTest do
        test "toggles the banner" do
          FunWithFlags.enable(:beta_banner)
          FunWithFlags.disable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, functions: [:disable])
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.disable" end)
    end
  end

  describe "&run/2 honours the :wrapper_suffixes param" do
    test "no longer flags the default 'FeatureFlags' suffix once overridden" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          MyApp.FeatureFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, wrapper_suffixes: ["Toggle"])
      |> refute_issues()
    end

    test "flags a custom wrapper suffix" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          MyApp.Toggle.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, wrapper_suffixes: ["Toggle"])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Toggle.enable" end)
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "silences a file that matches :included_paths but also matches :excluded_paths" do
      """
      defmodule CFXFeatureFlagsTest do
        setup :sandbox_feature_flags

        test "puts a new flag" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file("apps/cfx_feature_flags/test/cfx_feature_flags_test.exs")
      |> run_check(NoFunWithFlagsMutationInTests, excluded_paths: ["cfx_feature_flags/test/"])
      |> refute_issues()
    end

    test "still fires on an unrelated test file once :excluded_paths is set" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, excluded_paths: ["cfx_feature_flags/test/"])
      |> assert_issue()
    end
  end

  describe "&run/2 tolerates bare (non-list) param values without raising" do
    test "tolerates a bare atom for :functions" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, functions: :enable)
      |> assert_issue()
    end

    test "tolerates a bare string for :included_paths" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, included_paths: "test/")
      |> assert_issue()
    end

    test "tolerates a bare string for :wrapper_suffixes" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          MyApp.FeatureFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, wrapper_suffixes: "FeatureFlags")
      |> assert_issue()
    end

    test "tolerates a bare string for :excluded_paths" do
      """
      defmodule CFXFeatureFlagsTest do
        test "puts a new flag" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file("apps/cfx_feature_flags/test/cfx_feature_flags_test.exs")
      |> run_check(NoFunWithFlagsMutationInTests, excluded_paths: "cfx_feature_flags/test/")
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :included_paths param" do
    test "treats a custom suffix as an included test file" do
      """
      defmodule MyApp.BannerSpec do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file("apps/my_app/spec/my_app/banner_spec.exs")
      |> run_check(NoFunWithFlagsMutationInTests, included_paths: ["_spec.exs"])
      |> assert_issue()
    end

    test "no longer flags the default _test.exs suffix once overridden" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests, included_paths: ["_spec.exs"])
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two mutations on one line its own column" do
      """
      defmodule MyApp.BannerTest do
        test "toggles twice" do
          FunWithFlags.enable(:first) && FunWithFlags.enable(:second)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoFunWithFlagsMutationInTests)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
