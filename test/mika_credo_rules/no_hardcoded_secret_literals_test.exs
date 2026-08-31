defmodule MikaCredoRules.NoHardcodedSecretLiteralsTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoHardcodedSecretLiterals

  @lib_file "apps/my_app/lib/my_app/config.ex"
  @mix_file "apps/my_app/mix.exs"
  @config_file "config/prod.exs"

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

    test "reports a secret inside config/prod.exs" do
      secret = "sk_live_" <> String.duplicate("0", 24)

      """
      import Config

      config :stripe_api, secret_key: "#{secret}"
      """
      |> to_source_file(@config_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue()
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

    test "reports the moduledoc BAD example" do
      token = "Bearer " <> String.duplicate("x", 40)

      """
      defmodule MyApp.Config do
        @auth_header "#{token}"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> assert_issue()
    end
  end

  describe "&run/2 allows non-credential-shaped strings" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Config do
        def auth_header, do: "Bearer " <> Application.get_env(:my_app, :api_token)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoHardcodedSecretLiterals)
      |> refute_issues()
    end

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
