defmodule MikaCredoRules.NoRawMarkupInTemplatesTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoRawMarkupInTemplates

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  describe "&run/2 flags :inline_style" do
    test "reports a literal style=\"...\" attribute" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div style="width: 30%">hi</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "style="
        assert issue.message =~ "style= found"
        assert issue.message =~ "Tailwind"
      end)
    end

    test "does not report style={...} by default (allow_dynamic_style: true)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div style={"width: \#{@percent}%"}>hi</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end

    test "reports style={...} when allow_dynamic_style: false" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div style={"width: \#{@percent}%"}>hi</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, allow_dynamic_style: false)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end
  end

  describe "&run/2 flags :hex_color" do
    test "reports a 6-digit hex color" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span class="bg-[#1d4ed8]">badge</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "#1d4ed8"
        assert issue.message =~ "design token"
      end)
    end

    test "does not report a 3-digit hex anchor fragment" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <a href="#abc">jump</a>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end

    test "does not report a 6-digit hex anchor fragment (href=\"#abcdef\")" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <a href="#abcdef">jump</a>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end
  end

  describe "&run/2 flags :inline_svg" do
    test "reports an inline <svg> tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"><path d="M0 0"/></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "<svg"
        assert issue.message =~ "<.icon>"
      end)
    end
  end

  describe "&run/2 flags :raw_tag" do
    test "does not report <button> with default banned_tags ([])" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button class="btn">Save</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end

    test "reports <button> when banned_tags: [\"button\"]" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button class="btn">Save</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, banned_tags: ["button"])
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "<button"
        assert issue.message =~ "primitive"
      end)
    end

    test "does not match a banned tag as a substring of a longer tag name" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <buttonish class="btn">Save</buttonish>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, banned_tags: ["button"])
      |> refute_issues()
    end

    test "does not match a closing tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div><button>Save</button></div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, banned_tags: ["div"])
      |> assert_issue(fn issue -> assert issue.trigger === "<div" end)
    end
  end

  describe "&run/2 rules param" do
    test "only scans the enabled rules" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div style="color: red" class="bg-[#1d4ed8]">hi</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, rules: [:hex_color])
      |> assert_issue(fn issue -> assert issue.trigger === "#1d4ed8" end)
    end
  end

  describe "&run/2 sigils param" do
    test "inspects ~F bodies when configured" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.trigger === "<svg" end)
    end

    test "ignores every sigil not listed in :sigils" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates, sigils: [:sigil_H])
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "excludes files under icons/" do
      """
      defmodule MyAppWeb.Icons do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/icons/svg.ex")
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end

    test "does not exclude a lookalike path (lib/iconsmith/x.ex)" do
      """
      defmodule MyApp.Iconsmith.X do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/iconsmith/x.ex")
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.trigger === "<svg" end)
    end

    test "excludes a real <project>_icons app by default (segment-suffix, not literal fragment)" do
      """
      defmodule TiingoIcons.SvgDefs do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/tiingo_icons/lib/tiingo_icons/svg_defs.ex")
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end

    test "does not exclude a lookalike app name (tiingo_iconsmith)" do
      """
      defmodule TiingoIconsmith.X do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/tiingo_iconsmith/lib/tiingo_iconsmith/x.ex")
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.trigger === "<svg" end)
    end

    test "excluded_app_suffixes is configurable" do
      """
      defmodule MyApp.Assets.X do
        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_assets/lib/my_app_assets/x.ex")
      |> run_check(NoRawMarkupInTemplates, excluded_app_suffixes: ["_assets"])
      |> refute_issues()
    end
  end

  describe "&run/2 line and column accuracy" do
    test "reports the physical source line for a match inside a multi-line body" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div class="a">
            <span class="bg-[#1d4ed8]">badge</span>
          </div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports distinct columns for two triggers on the same line" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div class="bg-[#1d4ed8]"><span class="bg-[#f97316]">hi</span></div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issues(fn issues ->
        columns = issues |> Enum.map(& &1.column) |> Enum.sort()
        assert length(columns) === 2
        assert Enum.at(columns, 0) < Enum.at(columns, 1)
      end)
    end
  end

  describe "&run/2 accepts every sigil form" do
    test "single-line ~H\"<div/>\" form" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H(<svg viewBox="0 0 24 24"></svg>)
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.trigger === "<svg" end)
    end

    test "fires inside a .exs test file" do
      """
      defmodule MyAppWeb.CompTest do
        use ExUnit.Case

        def render(assigns) do
          ~H\"\"\"
          <svg viewBox="0 0 24 24"></svg>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/test/my_app_web/comp_test.exs")
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issue(fn issue -> assert issue.trigger === "<svg" end)
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div style="width: 30%">
            <svg viewBox="0 0 24 24"><path d="M0 0"/></svg>
            <span class="bg-[#1d4ed8]">badge</span>
          </div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> assert_issues(fn issues -> assert length(issues) === 3 end)
    end

    test "the GOOD example is clean" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div class="w-1/3">
            <.icon name="check" />
            <.badge tone="info">badge</.badge>
          </div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoRawMarkupInTemplates)
      |> refute_issues()
    end
  end
end
