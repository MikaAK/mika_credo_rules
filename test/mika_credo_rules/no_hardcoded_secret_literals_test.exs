# credo:disable-for-this-file MikaCredoRules.NoHardcodedSecretLiterals
defmodule MikaCredoRules.NoHardcodedSecretLiteralsTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoHardcodedSecretLiterals

  @lib_file "apps/my_app/lib/my_app/config.ex"
  @mix_file "apps/my_app/mix.exs"
  @config_file "config/prod.exs"

  @moduledoc_examples NoHardcodedSecretLiterals
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoHardcodedSecretLiterals"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end
  end

  describe "&run/2 flags credential-shaped string literals" do
    test "reports a Stripe live key" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @api_key "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "Stripe"
        refute issue.message =~ secret
      end)
    end

    test "reports a Stripe webhook secret" do
      secret = "whsec_" <> String.duplicate("a", 24)

      """
      defmodule MyApp.Config do
        @webhook_secret "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Stripe" end)
    end

    test "reports an AWS access key" do
      secret = "AKIA" <> String.duplicate("A", 16)

      """
      defmodule MyApp.Config do
        @aws_key "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "AWS" end)
    end

    test "reports a Slack token" do
      secret = "xoxb-" <> String.duplicate("1", 12)

      """
      defmodule MyApp.Config do
        @slack_token "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Slack" end)
    end

    test "reports a GitHub personal access token" do
      secret = "ghp_" <> String.duplicate("a", 22)

      """
      defmodule MyApp.Config do
        @github_token "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "GitHub" end)
    end

    test "reports a GitHub fine-grained token" do
      secret = "github_pat_" <> String.duplicate("a", 22)

      """
      defmodule MyApp.Config do
        @github_token "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "GitHub" end)
    end

    test "reports a PEM private key in a heredoc" do
      """
      defmodule MyApp.Config do
        @private_key \"\"\"
        -----BEGIN RSA PRIVATE KEY-----
        MIIEpAIBAAKCAQEA0Z3VS5JJcds3xfn/ygWyF0/dtE1CqxWFHY0PmDDcnbxvQCyz
        -----END RSA PRIVATE KEY-----
        \"\"\"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "PEM" end)
    end

    test "reports a bearer token" do
      secret = "Bearer " <> String.duplicate("a", 42)

      """
      defmodule MyApp.Config do
        @auth_header "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Bearer" end)
    end

    test "reports a secret inside config/prod.exs at its real line" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      import Config

      config :stripe_api,
        secret_key: "#{secret}"
      """
      |> to_source_file(@config_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports the real line of a secret nested in a multiline map" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @secrets %{
          other: "value",
          other2: "value2",
          key: "#{secret}"
        }
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports the real line of a secret nested in a multiline list" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @keys [
          "other",
          "#{secret}"
        ]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "uses Credo.Issue.no_trigger/0 so the trigger never echoes the secret" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @api_key "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue ->
        assert issue.trigger === Credo.Issue.no_trigger()
        assert issue.column === 13
      end)
    end

    test "reports a secret embedded as a substring of a longer literal" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @stripe_url "https://user:#{secret}@host/path"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Stripe" end)
    end

    test "reports a Bearer token embedded inside a full header string" do
      secret = "Bearer " <> String.duplicate("a", 42)

      """
      defmodule MyApp.Config do
        @header "Authorization: #{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Bearer" end)
    end

    test "reports a secret hidden inside a charlist sigil" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @api_key ~c"#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue(fn issue -> assert issue.message =~ "Stripe" end)
    end

    test "reports a secret inside mix.exs" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [app: :my_app, secret_key: "#{secret}"]
        end
      end
      """
      |> to_source_file(@mix_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue()
    end
  end

  describe "&run/2 allows non-credential-shaped strings" do
    test "does not report an ordinary string literal" do
      """
      defmodule MyApp.Config do
        @greeting "hello world"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "does not report a secret-shaped value in @moduledoc" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @moduledoc \"\"\"
        Example key: #{secret}
        \"\"\"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "does not report a secret-shaped value in @typedoc" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @typedoc \"\"\"
        Example key: #{secret}
        \"\"\"
        @type api_key :: String.t()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "does not report a secret-shaped value in @doc" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @doc \"\"\"
        Example key: #{secret}
        \"\"\"
        def api_key, do: nil
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "does not report a fully interpolated secret" do
      """
      defmodule MyApp.Config do
        def api_key(suffix), do: "sk_live_\#{suffix}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "does not report a variable" do
      """
      defmodule MyApp.Config do
        def api_key(value), do: value
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

    test "respects a custom :excluded_paths" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @api_key "#{secret}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals, excluded_paths: ["config.ex"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      defmodule MyApp.Config do
        @api_key "#{secret}"
      end
      """
      |> to_source_file("apps/my_app/lib/latest/config.ex")
      |> run_check(NoHardcodedSecretLiterals, excluded_paths: ["test/"])
      |> assert_issue()
    end

    test "respects a custom :patterns list" do
      """
      defmodule MyApp.Config do
        @internal_id "internal_secret_12345"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals,
        patterns: [{"internal ID", ~r/^internal_secret_[0-9]+$/}]
      )
      |> assert_issue(fn issue -> assert issue.message =~ "internal ID" end)
    end
  end
end
