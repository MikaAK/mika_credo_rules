defmodule MikaCredoRules.NoBangMailerDeliverTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoBangMailerDeliver

  @lib_file "apps/my_app/lib/my_app/workers/send_welcome_email.ex"
  @test_file "apps/my_app/test/my_app/workers/send_welcome_email_test.exs"

  describe "&run/2 flags deliver! on a Mailer module" do
    test "reports a fully qualified MyApp.Mailer.deliver!/1" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "MyApp.Mailer.deliver!"
        assert issue.message =~ "deliver!"
        assert issue.message =~ "SES"
      end)
    end

    test "reports a piped deliver! under a short alias" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        alias MyApp.Mailer

        def perform(email) do
          email |> Mailer.deliver!()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue -> assert issue.trigger === "Mailer.deliver!" end)
    end

    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        alias MyApp.Mailer

        def perform(email), do: email |> Mailer.deliver!()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue()
    end
  end

  describe "&run/2 allows deliver/1 and non-Mailer modules" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        alias MyApp.Mailer

        def perform(email) do
          case Mailer.deliver(email) do
            {:ok, _metadata} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "does not report deliver! on a non-Mailer module" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Notifier.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "does not report deliver/1 on a Mailer module" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "does not report a function not in :functions" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver_many!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "does not report a test file by default" do
      """
      defmodule MyApp.Workers.SendWelcomeEmailTest do
        def send_test_email(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.Workers.SendWelcomeEmailTest do
        def send_test_email(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBangMailerDeliver, excluded_paths: [])
      |> assert_issue()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/send_welcome_email.ex")
      |> run_check(NoBangMailerDeliver)
      |> assert_issue()
    end

    test "respects a custom :module_suffixes" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Notifier.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver, module_suffixes: ["Notifier"])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Notifier.deliver!" end)
    end
  end
end
