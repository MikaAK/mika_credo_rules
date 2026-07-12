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
