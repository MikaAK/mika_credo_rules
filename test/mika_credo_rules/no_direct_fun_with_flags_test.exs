defmodule MikaCredoRules.NoDirectFunWithFlagsTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoDirectFunWithFlags

  @lib_file "apps/my_app/lib/my_app/courses.ex"
  @test_file "apps/my_app/test/my_app/courses_test.exs"
  @wrapper_file "apps/my_app/lib/my_app/feature_flags.ex"
  @wrapper_dir_file "apps/my_app/lib/my_app/feature_flags/manager.ex"
  @wrapper_suffix_file "apps/my_app/lib/my_app_feature_flag/manager.ex"

  @moduledoc_examples NoDirectFunWithFlags
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoDirectFunWithFlags"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end
  end

  describe "&run/2 flags FunWithFlags calls outside a wrapper module" do
    test "reports a fully qualified FunWithFlags.enabled?/1" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "FunWithFlags.enabled?"
        assert issue.message =~ "FunWithFlags.enabled?"
        assert issue.message =~ "wrapper"
      end)
    end

    test "reports get_flag/1" do
      """
      defmodule MyApp.Courses do
        def raw_flag do
          FunWithFlags.get_flag(:new_checkout)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.get_flag" end)
    end

    test "reports all_flags/0" do
      """
      defmodule MyApp.Courses do
        def every_flag do
          FunWithFlags.all_flags()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.all_flags" end)
    end

    test "reports all_flag_names/0" do
      """
      defmodule MyApp.Courses do
        def every_flag_name do
          FunWithFlags.all_flag_names()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.all_flag_names" end)
    end

    test "reports an aliased FunWithFlags.enabled?/1 under alias FunWithFlags" do
      """
      defmodule MyApp.Courses do
        alias FunWithFlags

        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.enabled?" end)
    end

    test "reports the bare-atom Elixir.FunWithFlags spelling" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          :"Elixir.FunWithFlags".enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "enabled?" end)
    end
  end

  describe "&run/2 leaves app wrapper modules and non-FunWithFlags identity silent" do
    test "does not report a project module of a different identity, MyApp.FeatureFlags" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          MyApp.FeatureFlags.enabled?(:new_checkout, course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "a locally nested defmodule FunWithFlags shadows the bare name" do
      """
      defmodule MyApp.Courses do
        defmodule FunWithFlags do
          def enabled?(_flag, _opts), do: true
        end

        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "the shadow holds even after an explicit alias FunWithFlags earlier in the file" do
      """
      defmodule MyApp.Courses do
        alias FunWithFlags

        defmodule FunWithFlags do
          def enabled?(_flag, _opts), do: true
        end

        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "does not report a FunWithFlags function outside :functions" do
      """
      defmodule MyApp.Courses do
        def turn_on do
          FunWithFlags.enable(:new_checkout)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end
  end

  describe "&run/2 still fires the Elixir.-qualified spelling under a defmodule shadow" do
    test "the __aliases__ Elixir.FunWithFlags spelling still fires under a local defmodule shadow" do
      """
      defmodule MyApp.CourseFlagStub do
        defmodule FunWithFlags do
          def enabled?(_flag, _opts), do: true
        end

        def visible?(user) do
          Elixir.FunWithFlags.enabled?(:new_checkout, for: user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.FunWithFlags.enabled?" end)
    end

    test "the bare-atom :\"Elixir.FunWithFlags\" spelling also still fires under the same shadow" do
      """
      defmodule MyApp.CourseFlagStub do
        defmodule FunWithFlags do
          def enabled?(_flag, _opts), do: true
        end

        def visible?(user) do
          :"Elixir.FunWithFlags".enabled?(:new_checkout, for: user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.trigger === "enabled?" end)
    end
  end

  describe "&run/2 respects :allowed_paths for the wrapper module's own file" do
    test "does not report inside a file-basename-matched feature_flags.ex file" do
      """
      defmodule MyApp.FeatureFlags do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@wrapper_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "does not report inside a directory-matched feature_flags/ directory" do
      """
      defmodule MyApp.FeatureFlags.Manager do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@wrapper_dir_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "does not report inside a segment-suffix-matched *_feature_flag directory" do
      """
      defmodule MyApp.FeatureFlag.Manager do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@wrapper_suffix_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike file (feature_flags_extra.ex is not feature_flags)" do
      """
      defmodule MyApp.FeatureFlagsExtra do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/feature_flags_extra.ex")
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue()
    end

    test "still checks a boundary-lookalike directory (feature_flags_migrations is not feature_flags)" do
      """
      defmodule MyApp.FeatureFlagsMigrations.X do
        def run(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/feature_flags_migrations/x.ex")
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue()
    end

    test "reports the default-exempt feature_flags.ex path when :allowed_paths is overridden" do
      """
      defmodule MyApp.FeatureFlags do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@wrapper_file)
      |> run_check(NoDirectFunWithFlags, allowed_paths: ["notifications"])
      |> assert_issue()
    end

    test "does not report the default-exempt file via a plain suffix lookalike (legacy_feature_flags.ex)" do
      """
      defmodule MyApp.LegacyFeatureFlags do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy_feature_flags.ex")
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end
  end

  describe "&run/2 respects :excluded_paths for test files" do
    test "does not report a test file by default" do
      """
      defmodule MyApp.CoursesTest do
        test "flag" do
          FunWithFlags.enabled?(:new_checkout)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectFunWithFlags)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/courses.ex")
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.CoursesTest do
        test "flag" do
          FunWithFlags.enabled?(:new_checkout)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectFunWithFlags, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 respects a :functions override" do
    test "bans only the overridden function list" do
      """
      defmodule MyApp.Courses do
        def raw_flag do
          FunWithFlags.get_flag(:new_checkout)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags, functions: [:get_flag])
      |> assert_issue(fn issue -> assert issue.trigger === "FunWithFlags.get_flag" end)
    end

    test "no longer reports a function dropped from the override" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags, functions: [:get_flag])
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Courses do
        def visible?(course) do
          FunWithFlags.enabled?(:new_checkout, for: course)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two FunWithFlags calls on one line its own column" do
      """
      defmodule MyApp.Courses do
        def visible?(a, b) do
          FunWithFlags.enabled?(a) && FunWithFlags.enabled?(b)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectFunWithFlags)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
