defmodule MikaCredoRules.VerifiedRoutesRequiredTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.VerifiedRoutesRequired

  @lib_file "apps/my_app_web/lib/my_app_web/live/course_live.ex"
  @test_file "apps/my_app_web/test/my_app_web/live/course_live_test.exs"

  @moduledoc_examples VerifiedRoutesRequired
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  # DocExamples.readme_section/1 reads README.md, which does not carry this
  # check's section until the integrator merges it — until then it returns ""
  # and the four `for` comprehensions below would silently expand to zero
  # tests. Read our own docs/readme_sections copy instead (the integrator
  # merges it into README.md verbatim), and assert it actually produced
  # examples so a broken fence or a renamed file fails loudly instead of
  # quietly generating nothing.
  @readme_examples "docs/readme_sections/VerifiedRoutesRequired.md"
                   |> File.read!()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  if @readme_examples === [] do
    raise "docs/readme_sections/VerifiedRoutesRequired.md doc-gate found zero BAD/GOOD examples"
  end

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a plain string literal on to:" do
    test "reports redirect/2 with a plain literal" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          conn
          |> clear_session()
          |> redirect(to: "/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "redirect"
        assert issue.message =~ "redirect"
        assert issue.message =~ "~p"
      end)
    end

    test "reports push_patch/2 with a plain literal" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("edit", %{"id" => id}, socket) do
          {:noreply, push_patch(socket, to: "/courses/edit")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "push_patch" end)
    end
  end

  describe "&run/2 flags an interpolated string on to:" do
    test "reports push_navigate/2 with an interpolated string" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: "/courses/\#{id}")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "push_navigate"
        assert issue.message =~ "push_navigate"
      end)
    end

    test "reports live_redirect/2 with an interpolated string" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("archive", %{"id" => id}, socket) do
          {:noreply, live_redirect(socket, to: "/courses/\#{id}/archived")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "live_redirect" end)
    end
  end

  describe "&run/2 flags both bare-call and piped forms" do
    test "reports a bare call" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, push_navigate(socket, to: "/courses")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end

    test "reports a piped call" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, socket |> push_navigate(to: "/courses")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "push_navigate" end)
    end
  end

  describe "&run/2 flags qualified and piped-qualified forms" do
    test "reports a fully qualified bare call" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/courses/\#{id}")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "push_navigate" end)
    end

    test "reports an aliased, piped, qualified call" do
      """
      defmodule MyAppWeb.UserAuth do
        alias Phoenix.LiveView

        def redirect_to_login(conn) do
          conn
          |> LiveView.redirect(to: "/auth/auth0")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "redirect" end)
    end

    test "does not report a qualified call whose to: is a ~p sigil" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/courses/\#{id}")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves ~p sigils, variables, and non-:to keys alone" do
    test "does not report a ~p sigil on to:" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: ~p"/courses/\#{id}")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a module attribute on to:" do
      """
      defmodule MyAppWeb.CourseLive do
        @return_path "/courses"

        def handle_event("cancel", _params, socket) do
          {:noreply, push_patch(socket, to: @return_path)}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a plain variable on to:" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("cancel", %{"path" => path}, socket) do
          {:noreply, push_patch(socket, to: path)}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a literal string under external:" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, external: "https://example.com/logout")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a variable under external:" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, %{"return_url" => url}) do
          redirect(conn, external: url)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 respects :functions and path scoping" do
    test "does not report a function not in :functions" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, live_patch(socket, to: "/courses")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "respects a custom :functions list" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, live_patch(socket, to: "/courses")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired, functions: [:live_patch])
      |> assert_issue(fn issue -> assert issue.trigger === "live_patch" end)
    end

    test "does not report a test file by default" do
      """
      defmodule MyAppWeb.CourseLiveTest do
        def visit_course(socket, id) do
          push_navigate(socket, to: "/courses/\#{id}")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyAppWeb.CourseLiveTest do
        def visit_course(socket, id) do
          push_navigate(socket, to: "/courses/\#{id}")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(VerifiedRoutesRequired, excluded_paths: [])
      |> assert_issue()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, push_navigate(socket, to: "/courses")}
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/latest/course_live.ex")
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end
  end

  describe "&run/2 locates each issue with a column" do
    test "reports a column pointing at the flagged function name" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          {:noreply, push_navigate(socket, to: "/courses")}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.column === 16 end)
    end

    test "gives two triggers on one line distinct columns" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view", _params, socket) do
          push_navigate(socket, to: "/a") && push_navigate(socket, to: "/b")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 finds the options list regardless of argument position" do
    test "reports a call with a leading empty list before the options" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, [], to: "/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end

    test "reports a call with a leading non-empty keyword list before the options" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, [class: "x"], to: "/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end
  end

  describe "&run/2 does not mistake a def/defp head for a call" do
    test "does not report a defp head that pattern-matches a literal to:" do
      """
      defmodule MyAppWeb.SessionController do
        defp redirect(conn, to: "/login"), do: conn
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a def head that pattern-matches a literal to:" do
      """
      defmodule MyAppWeb.SessionController do
        def redirect(conn, to: "/login"), do: conn
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "still reports a real call inside a def's body" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params), do: redirect(conn, to: "/login")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "redirect" end)
    end

    test "does not report a defmacro head that pattern-matches a literal to:" do
      """
      defmodule MyAppWeb.SessionController do
        defmacro redirect(conn, to: "/login"), do: conn
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a defmacrop head that pattern-matches a literal to:" do
      """
      defmodule MyAppWeb.SessionController do
        defmacrop redirect(conn, to: "/login"), do: conn
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 treats a ~s sigil like a plain literal" do
    test "reports a ~s sigil on to:" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, to: ~s"/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end

    test "reports a ~S sigil on to:" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, to: ~S"/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue()
    end

    test "does not report a ~c sigil on to: (a charlist is not a path)" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, to: ~c"/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 still traverses a def head's default-argument expressions" do
    test "reports a real navigation call inside a \\ default expression" do
      """
      defmodule MyAppWeb.SessionController do
        def out(conn, target \\\\ redirect(conn, to: "/login")), do: {conn, target}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "redirect" end)
    end

    test "does not report a plain, non-call default expression" do
      """
      defmodule MyAppWeb.SessionController do
        def out(conn, limit \\\\ 10), do: {conn, limit}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a guarded def head that pattern-matches a literal to:" do
      """
      defmodule MyAppWeb.SessionController do
        def redirect(conn, to: "/login") when is_map(conn), do: conn
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not mistake a module attribute assignment for a call" do
    test "does not report a keyword-list attribute named after a navigation function" do
      """
      defmodule MyAppWeb.SessionController do
        @redirect [to: "/login"]
        def opts, do: @redirect
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end

    test "does not report a keyword-list attribute for a configured :functions entry" do
      """
      defmodule MyAppWeb.CourseLive do
        @link [to: "/dashboard", class: "nav"]
        def opts, do: @link
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired, functions: [:link])
      |> refute_issues()
    end

    test "still reports a real navigation call nested inside an attribute value" do
      """
      defmodule MyAppWeb.CourseLive do
        @paths [push_navigate(nil, to: "/courses")]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "push_navigate" end)
    end
  end

  describe "&run/2 flags a route built by concatenation on a binary literal" do
    test "reports to: built with a literal prefix concatenated onto a variable" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: "/courses/" <> id)}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue -> assert issue.trigger === "push_navigate" end)
    end

    test "does not report to: built from two variables concatenated" do
      """
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: prefix <> id)}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 message wording" do
    test "describes an unmatched ~p route as a compiler warning, not a compile error" do
      """
      defmodule MyAppWeb.SessionController do
        def logout(conn, _params) do
          redirect(conn, to: "/login")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(VerifiedRoutesRequired)
      |> assert_issue(fn issue ->
        refute issue.message =~ "compile error"
        assert issue.message =~ "compiler warning"
        assert issue.message =~ "--warnings-as-errors"
      end)
    end
  end
end
