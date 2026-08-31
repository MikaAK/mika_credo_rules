defmodule MikaCredoRules.TodosNeedTicketsTest do
  use Credo.Test.Case

  alias MikaCredoRules.TodosNeedTickets

  @source_file "apps/my_app/lib/my_app/worker.ex"
  @ticket_url "https://linear.app/company/issue/"

  describe "&run/2 flags todos without an adjacent ticket URL" do
    test "reports a TODO comment" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "# TODO: make this faster"
        assert issue.message =~ "todos must reference a ticket URL"
        assert issue.message =~ @ticket_url
      end)
    end

    test "reports a FIXME comment" do
      """
      defmodule MyApp.Worker do
        # FIXME: handle the error tuple
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.trigger === "# FIXME: handle the error tuple" end)
    end

    test "reports a lowercase todo comment" do
      """
      defmodule MyApp.Worker do
        # todo: tidy this up
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.trigger === "# todo: tidy this up" end)
    end

    test "reports each todo line once with its own line number" do
      """
      defmodule MyApp.Worker do
        # TODO: split this module
        def work, do: :ok

        # FIXME: stop rescuing everything
        def rescue_all, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 5]
      end)
    end

    test "reports a @moduledoc that starts with a tag" do
      """
      defmodule MyApp.Worker do
        @moduledoc "TODO: write documentation"
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "TODO: write documentation"
      end)
    end

    test "reports a @doc that starts with a tag" do
      """
      defmodule MyApp.Worker do
        @doc "FIXME: document the return value"
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.trigger === "FIXME: document the return value" end)
    end

    test "reports a todo that is not adjacent to the ticket URL" do
      """
      defmodule MyApp.Worker do
        # TODO: split this module
        def work, do: :ok

        # see https://linear.app/company/issue/443
        def other, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "# TODO: split this module"
      end)
    end

    test "reports a todo whose neighbouring URL belongs to another todo" do
      """
      defmodule MyApp.Worker do
        # TODO: split this module
        # https://linear.app/company/issue/443
        def work, do: :ok

        # FIXME: stop rescuing everything
        def rescue_all, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "# FIXME: stop rescuing everything"
      end)
    end
  end

  describe "&run/2 allows todos with an adjacent ticket URL" do
    test "does not report a todo with the ticket URL right after the tag" do
      """
      defmodule MyApp.Worker do
        # TODO: https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a todo without a colon before the ticket URL" do
      """
      defmodule MyApp.Worker do
        # TODO https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a todo with the ticket URL after the description" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a todo with the ticket URL on the next comment line" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster
        # https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a todo with the ticket URL on the previous comment line" do
      """
      defmodule MyApp.Worker do
        # https://linear.app/company/issue/443
        # TODO: make this faster
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a doc todo whose doc string contains the ticket URL" do
      """
      defmodule MyApp.Worker do
        @moduledoc \"\"\"
        TODO: rewrite this module.

        Tracked in https://linear.app/company/issue/443.
        \"\"\"
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a file with no todos" do
      """
      defmodule MyApp.Worker do
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores todo text inside strings" do
    test "does not report a string containing TODO" do
      """
      defmodule MyApp.Worker do
        def label, do: "TODO: not a real todo"
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not count a distant URL inside a code string as a ticket reference" do
      """
      defmodule MyApp.Worker do
        # TODO: use the configured URL
        def work, do: :ok

        def url, do: "https://linear.app/company/issue/443"
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end
  end

  describe "&run/2 flags the new default tags" do
    test "reports an OPTIMIZE comment" do
      """
      defmodule MyApp.Worker do
        # OPTIMIZE: this loop is quadratic
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.trigger === "# OPTIMIZE: this loop is quadratic"
      end)
    end

    test "reports a HACK comment" do
      """
      defmodule MyApp.Worker do
        # HACK: patched until the upstream fix lands
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.trigger === "# HACK: patched until the upstream fix lands"
      end)
    end

    test "reports a REVIEW comment" do
      """
      defmodule MyApp.Worker do
        # REVIEW: is this the right retry count?
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.trigger === "# REVIEW: is this the right retry count?"
      end)
    end

    test "still reports a ticketed OPTIMIZE the same as a ticketed TODO" do
      """
      defmodule MyApp.Worker do
        # OPTIMIZE: this loop is quadratic, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end
  end

  describe "&run/2 requires a trailing word boundary on a tag" do
    test "does not report a comment where the tag is a prefix of a longer word" do
      """
      defmodule MyApp.Worker do
        # hackney 2.x async/stream responses are unsupported
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a hacky-workaround comment as a HACK tag" do
      """
      defmodule MyApp.Worker do
        # hacky workaround for the flaky client
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a reviewed-by comment as a REVIEW tag" do
      """
      defmodule MyApp.Worker do
        # reviewed by Bob
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a reviewer-notes comment as a REVIEW tag" do
      """
      defmodule MyApp.Worker do
        # reviewer notes go in the PR
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report an optimized-version comment as an OPTIMIZE tag" do
      """
      defmodule MyApp.Worker do
        # optimized version of the parser
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a @moduledoc that merely starts with a longer word" do
      """
      defmodule MyApp.Worker do
        @moduledoc "Hackney adapter for Tesla."
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "does not report a comment where the tag is followed by more letters" do
      """
      defmodule MyApp.Worker do
        # TODOs remaining before release
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end

    test "still reports a real tag immediately followed by a colon" do
      """
      defmodule MyApp.Worker do
        # TODO: fix the retry logic
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.trigger === "# TODO: fix the retry logic" end)
    end
  end

  describe "&run/2 honours the :require_uppercase param" do
    test "reports a lowercase tag even when it carries a ticket URL" do
      """
      defmodule MyApp.Worker do
        # todo: make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issue(fn issue ->
        assert issue.trigger === "todo"
        assert issue.message =~ "todo found"
        assert issue.message =~ "annotation tags must be uppercase followed by a colon"
      end)
    end

    test "reports a mixed-case tag with a colon even when it carries a ticket URL" do
      """
      defmodule MyApp.Worker do
        # Todo: make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issue(fn issue -> assert issue.trigger === "Todo" end)
    end

    test "reports an uppercase tag with no colon" do
      """
      defmodule MyApp.Worker do
        # TODO make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issue(fn issue -> assert issue.trigger === "TODO" end)
    end

    test "reports both the missing ticket and the bad casing for the same todo" do
      """
      defmodule MyApp.Worker do
        # todo: make this faster
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        messages = Enum.map(issues, & &1.message)
        assert Enum.any?(messages, &(&1 =~ "todos must reference a ticket URL"))
        assert Enum.any?(messages, &(&1 =~ "annotation tags must be uppercase"))
      end)
    end

    test "reports a lowercase @moduledoc tag" do
      """
      defmodule MyApp.Worker do
        @moduledoc "todo: write documentation, see https://linear.app/company/issue/443"
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issue(fn issue -> assert issue.trigger === "todo" end)
    end

    test "does not report a properly cased, ticketed todo" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> refute_issues()
    end

    test "still reports bad casing on an inline comment with no space before the tag" do
      """
      defmodule MyApp.Worker do
        def work, do: :ok# todo: fix this, see https://linear.app/company/issue/443
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url, require_uppercase: true)
      |> assert_issue(fn issue ->
        assert issue.trigger === "todo"
        assert issue.message =~ "annotation tags must be uppercase followed by a colon"
      end)
    end

    test "does not report casing when the param is left at its default" do
      """
      defmodule MyApp.Worker do
        # todo: make this faster, see https://linear.app/company/issue/443
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :tags param" do
    test "flags only the configured tags" do
      """
      defmodule MyApp.Worker do
        # HACK: patched until the upstream fix lands
        # TODO: fix later
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, tags: ["HACK"], ticket_url: @ticket_url)
      |> assert_issue(fn issue ->
        assert issue.trigger === "# HACK: patched until the upstream fix lands"
      end)
    end
  end

  describe "&run/2 honours the :ticket_url param" do
    test "accepts any http or https URL when no :ticket_url is set" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster
        # https://any-tracker.example.com/issues/17
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets)
      |> refute_issues()
    end

    test "flags a todo without any URL when no :ticket_url is set" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets)
      |> assert_issue(fn issue ->
        assert issue.message =~ "todos must reference a ticket URL"
      end)
    end

    test "does not count a URL from another tracker when :ticket_url is set" do
      """
      defmodule MyApp.Worker do
        # TODO: make this faster
        # https://example.com/not-a-ticket
        def work, do: :ok
      end
      """
      |> to_source_file(@source_file)
      |> run_check(TodosNeedTickets, ticket_url: @ticket_url)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end
  end
end
