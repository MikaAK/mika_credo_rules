defmodule MikaCredoRules.NoBangMailerDeliverTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoBangMailerDeliver

  @lib_file "apps/my_app/lib/my_app/workers/send_welcome_email.ex"
  @test_file "apps/my_app/test/my_app/workers/send_welcome_email_test.exs"

  @moduledoc_examples NoBangMailerDeliver
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoBangMailerDeliver"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end
  end

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
  end

  describe "&run/2 allows deliver/1 and non-Mailer modules" do
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

    test "does not report a test file when :excluded_paths opts into skipping them" do
      """
      defmodule MyApp.Workers.SendWelcomeEmailTest do
        def send_test_email(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBangMailerDeliver, excluded_paths: ["_test.exs"])
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

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two deliveries on one line its own column" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(first, second) do
          MyApp.Mailer.deliver!(first) && MyApp.Mailer.deliver!(second)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 flags an unqualified deliver!" do
    test "reports a local deliver! call" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        import MyApp.Mailer

        def perform(email) do
          deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue -> assert issue.trigger === "deliver!" end)
    end

    test "reports an injected mailer held in a module attribute" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        @mailer Application.compile_env(:my_app, :mailer)

        def perform(email) do
          @mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "@mailer.deliver!"
      end)
    end

    test "reports an injected mailer passed as a variable" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email, mailer) do
          mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue -> assert issue.trigger === "mailer.deliver!" end)
    end

    test "does not report a non-bang deliver on an injected mailer" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email, mailer) do
          mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "does not report a local deliver call" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        import MyApp.Mailer

        def perform(email) do
          deliver(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end

    test "reports __MODULE__.Mailer.deliver! without crashing the run" do
      """
      defmodule MyApp.Signup do
        defmodule Mailer do
          def deliver!(email), do: email
        end

        def perform(email) do
          __MODULE__.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue(fn issue -> assert issue.trigger === Credo.Issue.no_trigger() end)
    end

    test "does not report a deliver! definition head" do
      """
      defmodule MyApp.Mailer do
        def deliver!(email), do: email
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBangMailerDeliver)
      |> refute_issues()
    end
  end

  describe "&run/2 checks test files by default" do
    test "reports deliver! in a test file" do
      """
      defmodule MyApp.Workers.SendWelcomeEmailTest do
        def setup_mail(email) do
          MyApp.Mailer.deliver!(email)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBangMailerDeliver)
      |> assert_issue()
    end
  end
end
