defmodule MikaCredoRules.InUmbrellaDepsNoVersionTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.InUmbrellaDepsNoVersion

  describe "&run/2 flags an in_umbrella dep that pins a version requirement" do
    test "reports the moduledoc BAD example" do
      """
      defp deps do
        [
          {:shared_utils, "~> 0.1", in_umbrella: true}
        ]
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === ":shared_utils"
        assert issue.message =~ ":shared_utils"
        assert issue.message =~ "in_umbrella: true"
      end)
    end

    test "reports every offending dep in a multi-dep list, each with its own line" do
      """
      defmodule MyUmbrella.MixProject do
        defp deps do
          [
            {:app_one, "~> 0.1", in_umbrella: true},
            {:app_two, "~> 0.2", in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [4, 5]
      end)
    end
  end

  describe "&run/2 leaves correctly-formed deps alone" do
    test "does not report the moduledoc GOOD example" do
      """
      defp deps do
        [
          {:shared_utils, in_umbrella: true}
        ]
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end

    test "does not report an in_umbrella dep already without a version" do
      """
      defmodule MyUmbrella.MixProject do
        defp deps do
          [
            {:my_app, in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end

    test "does not report a versioned dep that is not in_umbrella" do
      """
      defmodule MyUmbrella.MixProject do
        defp deps do
          [
            {:credo, "~> 1.7", runtime: false}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end

    test "does not report a plain 2-tuple versioned dep" do
      """
      defmodule MyUmbrella.MixProject do
        defp deps do
          [
            {:ex_doc, "~> 0.34"}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end
  end

  describe "&run/2 only scopes to mix.exs files" do
    test "does not report inside a non mix.exs file" do
      """
      defp deps do
        [
          {:my_app, "~> 0.1", in_umbrella: true}
        ]
      end
      """
      |> to_source_file("lib/my_app/deps_helper.ex")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end

    test "does not report a mix.exs lookalike filename" do
      """
      defp deps do
        [
          {:my_app, "~> 0.1", in_umbrella: true}
        ]
      end
      """
      |> to_source_file("lib/remix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> refute_issues()
    end

    test "reports inside an umbrella app's own mix.exs" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:shared_utils, "~> 0.1", in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("apps/my_app/mix.exs")
      |> run_check(InUmbrellaDepsNoVersion)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :mix_files param" do
    test "treats a custom filename as a mix.exs file" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:my_app, "~> 0.1", in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("project.exs")
      |> run_check(InUmbrellaDepsNoVersion, mix_files: ["project.exs"])
      |> assert_issue()
    end

    test "no longer reports mix.exs once it is removed from :mix_files" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [
            {:my_app, "~> 0.1", in_umbrella: true}
          ]
        end
      end
      """
      |> to_source_file("mix.exs")
      |> run_check(InUmbrellaDepsNoVersion, mix_files: ["project.exs"])
      |> refute_issues()
    end
  end
end
