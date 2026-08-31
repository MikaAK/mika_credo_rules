defmodule MikaCredoRules.CredoConfigNamedDefaultTest do
  use Credo.Test.Case

  alias MikaCredoRules.CredoConfigNamedDefault

  describe "&run/2 flags a .credo.exs with no config named \"default\"" do
    test "reports the moduledoc BAD example" do
      """
      %{
        configs: [
          %{
            name: "mika",
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> assert_issue(fn issue ->
        assert issue.trigger === "configs:"
        assert issue.message =~ "default"
      end)
    end

    test "reports a single config not named default" do
      """
      %{
        configs: [
          %{
            name: "strict",
            files: %{included: ["lib/"], excluded: []},
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> assert_issue()
    end
  end

  describe "&run/2 does not flag a .credo.exs with a config named \"default\"" do
    test "does not report the moduledoc GOOD example" do
      """
      %{
        configs: [
          %{
            name: "default",
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> refute_issues()
    end

    test "does not report when a config's name: is a non-literal expression" do
      """
      config_name = "mika"

      %{
        configs: [
          %{
            name: config_name,
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> refute_issues()
    end

    test "does not report when two configs exist and the second is named default" do
      """
      %{
        configs: [
          %{
            name: "strict",
            checks: []
          },
          %{
            name: "default",
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> refute_issues()
    end
  end

  describe "&run/2 documented limitations" do
    test "an unrelated nested map with a coincidental configs: key still fires" do
      """
      %{
        a: %{
          configs: [
            %{name: "x", checks: []}
          ]
        }
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> assert_issue()
    end

    test "a configs: list built with the cons operator still fires even when default is present" do
      """
      rest = []

      %{
        configs: [%{name: "default", checks: []} | rest]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> assert_issue()
    end
  end

  describe "&run/2 skips a file whose shape it cannot statically parse" do
    test "does not report when the config is built dynamically" do
      """
      {config, _binding} = Code.eval_file("shared_credo_config.exs")
      config
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> refute_issues()
    end
  end

  describe "&run/2 only scopes to Credo config files" do
    test "does not report inside an unrelated file, even with the same shape" do
      """
      %{
        configs: [
          %{
            name: "mika",
            checks: []
          }
        ]
      }
      """
      |> to_source_file("lib/my_app/some_config.ex")
      |> run_check(CredoConfigNamedDefault)
      |> refute_issues()
    end

    test "reports inside a named secondary Credo config file" do
      """
      %{
        configs: [
          %{
            name: "mika",
            checks: []
          }
        ]
      }
      """
      |> to_source_file("strict.credo.exs")
      |> run_check(CredoConfigNamedDefault)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :allowed_names param" do
    test "accepts a custom allowed name" do
      """
      %{
        configs: [
          %{
            name: "strict",
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault, allowed_names: ["strict"])
      |> refute_issues()
    end

    test "still reports \"default\" once it is no longer in :allowed_names" do
      """
      %{
        configs: [
          %{
            name: "default",
            checks: []
          }
        ]
      }
      """
      |> to_source_file(".credo.exs")
      |> run_check(CredoConfigNamedDefault, allowed_names: ["strict"])
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :config_files param" do
    test "treats a custom filename as a Credo config file" do
      """
      %{
        configs: [
          %{
            name: "mika",
            checks: []
          }
        ]
      }
      """
      |> to_source_file("credo_config.exs")
      |> run_check(CredoConfigNamedDefault, config_files: ["credo_config.exs"])
      |> assert_issue()
    end
  end
end
