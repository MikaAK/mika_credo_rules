defmodule MikaCredoRules.MonolithicTemplateComponentTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.MonolithicTemplateComponent

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  defp render_with_lines(count) do
    lines = for index <- 1..count, do: "<div>line #{index}</div>"

    """
    defmodule MyAppWeb.Comp do
      def render(assigns) do
        ~H\"\"\"
        #{Enum.join(lines, "\n")}
        \"\"\"
      end
    end
    """
  end

  describe "&run/2 flags sigils over max_lines" do
    test "reports a sigil spanning more than the default max_lines (60)" do
      61
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "~H"
        assert issue.message =~ "61 lines"
        assert issue.message =~ "decompose"
      end)
    end

    test "does not report a sigil at exactly max_lines" do
      60
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent)
      |> refute_issues()
    end

    test "reports a sigil one line over a custom max_lines" do
      11
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, max_lines: 10)
      |> assert_issue(fn issue -> assert issue.message =~ "11 lines" end)
    end

    test "does not report a sigil at a custom max_lines" do
      10
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, max_lines: 10)
      |> refute_issues()
    end
  end

  describe "&run/2 sigils param" do
    test "inspects ~F bodies when configured" do
      source =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~F\"\"\"
            #{Enum.join(for(index <- 1..11, do: "<div>#{index}</div>"), "\n")}
            \"\"\"
          end
        end
        """

      source
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, max_lines: 10)
      |> assert_issue(fn issue -> assert issue.trigger === "~F" end)
    end

    test "ignores every sigil not listed in :sigils" do
      source =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~F\"\"\"
            #{Enum.join(for(index <- 1..11, do: "<div>#{index}</div>"), "\n")}
            \"\"\"
          end
        end
        """

      source
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, max_lines: 10, sigils: [:sigil_H])
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "excludes configured paths" do
      61
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, excluded_paths: ["live/"])
      |> refute_issues()
    end
  end

  describe "&run/2 accepts every sigil form" do
    test "does not report a single-line ~H\"<div/>\" form" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H"<div/>"
      end
      """
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent, max_lines: 0)
      |> assert_issue(fn issue -> assert issue.message =~ "1 line" end)
    end

    test "fires inside a .exs test file" do
      61
      |> render_with_lines()
      |> to_source_file("apps/my_app_web/test/my_app_web/comp_test.exs")
      |> run_check(MonolithicTemplateComponent)
      |> assert_issue(fn issue -> assert issue.trigger === "~H" end)
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      90
      |> render_with_lines()
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent)
      |> assert_issue(fn issue -> assert issue.message =~ "90 lines" end)
    end

    test "the GOOD example is clean" do
      """
      defmodule MyAppWeb.Comp do
        def progress(assigns) do
          ~H\"\"\"
          <.progress_header {assigns} />
          <.lesson_group_card :for={g <- @groups} group={g} />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(MonolithicTemplateComponent)
      |> refute_issues()
    end
  end
end
