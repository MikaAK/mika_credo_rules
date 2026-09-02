defmodule MikaCredoRules.EmailRequiresTextBodyTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.EmailRequiresTextBody

  @lib_file "apps/my_app/lib/my_app/emails/welcome.ex"
  @test_file "apps/my_app/test/my_app/emails/welcome_test.exs"
  @lookalike_lib_file "apps/my_app/lib/latest/emails/welcome.ex"

  @moduledoc_examples EmailRequiresTextBody
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "EmailRequiresTextBody"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 flags html_body with no matching text_body" do
    test "reports a piped html_body call with no text_body anywhere in the module" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> from("hello@example.com")
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue ->
        assert issue.line_no === 9
        assert issue.trigger === "html_body"
        assert issue.message =~ "html_body"
        assert issue.message =~ "text_body"
      end)
    end

    test "reports a direct (non-piped) html_body call, locating the exact column" do
      """
      defmodule MyApp.Emails.Welcome do
        def welcome(email) do
          html_body(email, "<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "scopes independently across two top-level modules in one file" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end

      defmodule MyApp.Emails.Receipt do
        import Swoosh.Email

        def receipt(order) do
          new() |> subject("Receipt") |> html_body("<h1>Receipt</h1>") |> text_body("Receipt")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "html_body"
      end)
    end
  end

  describe "&run/2 allows a module with both bodies, neither body, or text only" do
    test "does not report a module that also calls text_body" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
          |> text_body("Welcome!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a module with neither html_body nor text_body" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> subject("Welcome!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a text-only module" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> subject("Welcome!")
          |> text_body("Welcome!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 scans flat per top-level module (documented nested-module imprecision)" do
    test "does not report an outer module whose only html_body call lives inside a nested defmodule that also calls text_body" do
      """
      defmodule MyApp.Emails.Bundle do
        defmodule Welcome do
          import Swoosh.Email

          def welcome(user) do
            new()
            |> to(user.email)
            |> subject("Welcome!")
            |> html_body("<h1>Welcome!</h1>")
            |> text_body("Welcome!")
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report an outer module that calls text_body/2 itself when only a nested defmodule calls html_body/2" do
      """
      defmodule MyApp.Emails.Bundle do
        import Swoosh.Email

        def confirmation(user) do
          new() |> subject("Confirmed") |> text_body("Confirmed, \#{user.name}!")
        end

        defmodule Welcome do
          import Swoosh.Email

          def welcome(user) do
            new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 scope boundaries (documented limitations)" do
    test "does not open a scope for a top-level defprotocol" do
      """
      defprotocol MyApp.Emailable do
        @spec html_body(t, String.t()) :: t
        def html_body(email, body)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not scan code outside any top-level defmodule or defimpl" do
      """
      import Swoosh.Email

      new() |> subject("hi") |> html_body("<h1>hi</h1>")
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 opens a scope for a top-level defimpl block" do
    test "reports a top-level defimpl whose only html_body call has no matching text_body" do
      """
      defimpl MyApp.Renderable, for: MyApp.Email do
        def render(email) do
          email
          |> html_body("<h1>Welcome</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "does not report a top-level defimpl that also calls text_body" do
      """
      defimpl MyApp.Renderable, for: MyApp.Email do
        def render(email) do
          email
          |> html_body("<h1>Welcome</h1>")
          |> text_body("Welcome")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "reports a top-level defimpl with implicit for: (2-arg block shape)" do
      """
      defimpl MyApp.Renderable do
        def render(email) do
          email
          |> html_body("<h1>Welcome</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "reports an inline defimpl (`do:` as a keyword entry, not a do...end block)" do
      """
      defimpl MyApp.Renderable, for: MyApp.Email, do: (def render(email), do: html_body(email, "<h1>Welcome</h1>"))
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end
  end

  describe "&run/2 does not crash on a defimpl whose last argument is not a keyword list" do
    test "returns [] instead of raising for a bare defimpl with no do-block at all" do
      """
      defimpl MyApp.Renderable
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 orders issues by source position" do
    test "returns issues in source order across multiple firing top-level modules" do
      issues =
        """
        defmodule MyApp.Emails.Welcome do
          import Swoosh.Email

          def welcome(user) do
            new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
          end
        end

        defmodule MyApp.Emails.Receipt do
          import Swoosh.Email

          def receipt(order) do
            new() |> subject("Receipt") |> html_body("<h1>Receipt</h1>")
          end
        end
        """
        |> to_source_file(@lib_file)
        |> run_check(EmailRequiresTextBody)

      assert Enum.map(issues, & &1.line_no) === [5, 13]
    end

    test "reports only the first html_body call site when a module has two" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end

        def reminder(user) do
          new()
          |> subject("Reminder!")
          |> html_body("<h1>Reminder!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end
  end

  describe "&run/2 does not read Swoosh.Email.new/1 keyword options" do
    test "still reports a later html_body call when text_body was only set via new/1 options" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new(text_body: "Welcome!")
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "does not report a module that sets only the HTML body via new/1 options" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new(html_body: "<h1>Welcome!</h1>")
          |> subject("Welcome!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 arity bounds on the bare html_body/text_body match" do
    test "reports a bare one-argument html_body call, indistinguishable from a piped call" do
      """
      defmodule MyApp.Emails.Bare do
        def render(data) do
          html_body(data)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "does not report an html_body call with three or more arguments" do
      """
      defmodule MyApp.Emails.Extra do
        def render(email) do
          html_body(email, "<h1>Welcome</h1>", :extra)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not let a three-argument text_body call satisfy the scope" do
      """
      defmodule MyApp.Emails.ExtraTextBody do
        import Swoosh.Email

        def welcome(user) do
          text_body(user, "Welcome!", :extra)
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end
  end

  describe "&run/2 the name-only match can suppress a genuine violation (documented limitation)" do
    test "an unrelated local text_body helper silences a genuine html_body call" do
      """
      defmodule MyApp.Emails.HelperSuppresses do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> subject(text_body(user))
          |> html_body("<h1>hi</h1>")
        end

        defp text_body(user), do: user.name
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores lookalikes that are not calls" do
    test "does not report a bare variable or parameter named html_body" do
      """
      defmodule MyApp.Emails.Debug do
        def inspect_content(html_body) do
          html_body
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a local function DEFINITION named html_body/2" do
      """
      defmodule MyApp.Emails.Helpers do
        def html_body(user, greeting) do
          "<h1>\#{greeting}, \#{user.name}!</h1>"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a module-attribute DEFINITION named @html_body" do
      """
      defmodule MyApp.Emails.Constants do
        @html_body "<h1>Welcome</h1>"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report an html_body call satisfied by a text_body call held inside a differently-named attribute" do
      """
      defmodule MyApp.Emails.AttrTextBody do
        import Swoosh.Email

        @base new() |> from({"App", "no-reply@example.com"}) |> text_body("Welcome!")

        def welcome(_user) do
          @base
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "reports an html_body call held inside a differently-named attribute when no text_body exists anywhere" do
      """
      defmodule MyApp.Emails.AttrHtmlOnly do
        import Swoosh.Email

        @base new() |> from({"App", "no-reply@example.com"}) |> html_body("<h1>hi</h1>")

        def welcome(_user), do: @base
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "does not let a @text_body attribute DEFINITION silence a genuine html_body call" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        @text_body "Welcome"

        def welcome(user) do
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "reports the real html_body call site, not an @html_body attribute on an earlier line" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        @html_body "<h1>placeholder</h1>"

        def welcome(user) do
          new()
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue -> assert issue.line_no === 9 end)
    end

    test "does not report a bodiless multi-clause head with a default argument, defining html_body/2" do
      """
      defmodule MyApp.Emails.Helpers do
        def html_body(user, greeting \\\\ "Hi")

        def html_body(user, greeting) do
          "<h1>\#{greeting}, \#{user.name}!</h1>"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a defdelegate to html_body" do
      """
      defmodule MyApp.Emails.Delegated do
        defdelegate html_body(email, body), to: Swoosh.Email
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a local zero-arity html_body() call" do
      """
      defmodule MyApp.Emails.Local do
        defp html_body, do: "<h1>hi</h1>"

        def render do
          html_body()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end
  end

  describe "&run/2 prunes typespec attributes (@spec/@type/@callback/etc. are not calls)" do
    test "does not report a @spec'd local html_body/2 helper with a real body" do
      """
      defmodule MyApp.Emails.Helpers do
        @spec html_body(map(), String.t()) :: map()
        def html_body(email, body), do: email
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a bare @type declaration named html_body" do
      """
      defmodule MyApp.Emails.TypeOnly do
        @type html_body(inner) :: {:html, inner}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not report a bare @callback declaration named html_body with no function bodies at all" do
      """
      defmodule MyApp.Emails.Behaviour do
        @callback html_body(map(), String.t()) :: map()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "does not let a @callback text_body typespec silence a genuine unmatched html_body call" do
      """
      defmodule MyApp.Emails.FnSilenced do
        @callback text_body(map(), String.t()) :: map()

        def welcome(email) do
          html_body(email, "<h1>hi</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end

    test "reports the real html_body call site, not an earlier @spec line" do
      """
      defmodule MyApp.Emails.WrongLoc do
        @spec html_body(map(), String.t()) :: map()

        def welcome(email) do
          html_body(email, "<h1>hi</h1>")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end
  end

  describe "&run/2 path scoping" do
    test "does not report a test file by default" do
      """
      defmodule MyApp.Emails.WelcomeTest do
        import Swoosh.Email

        def build_broken_email(user) do
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(EmailRequiresTextBody)
      |> refute_issues()
    end

    test "reports a test file when :excluded_paths is overridden to []" do
      """
      defmodule MyApp.Emails.WelcomeTest do
        import Swoosh.Email

        def build_broken_email(user) do
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(EmailRequiresTextBody, excluded_paths: [])
      |> assert_issue()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
        end
      end
      """
      |> to_source_file(@lookalike_lib_file)
      |> run_check(EmailRequiresTextBody)
      |> assert_issue()
    end
  end
end
