defmodule MikaCredoRules.NoClickHandlerOnNonInteractiveElementTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoClickHandlerOnNonInteractiveElement

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  describe "&run/2 flags a non-interactive element with a click binding" do
    test "reports <span phx-click=...> with no role/tabindex" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span class="pill" phx-click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "<span"
        assert issue.message =~ "<button type=\"button\">"
        assert issue.message =~ "role"
        assert issue.message =~ "tabindex"
      end)
    end

    test "reports <div phx-click=...> as a full-card click target" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div class="card" phx-click="open">card</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<div" end)
    end

    test "reports the $click binding (default second entry in :bindings)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span $click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end

    test "detects a multi-line opening tag and reports the tag's own start line" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span
            class="pill"
            phx-click="show_findings"
          >click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end
  end

  describe "&run/2 leaves an accessible non-interactive element alone" do
    test "does not report when both role and tabindex are present" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span role="button" tabindex="0" phx-click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end

    test "still reports when only role is present" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span role="button" phx-click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end

    test "still reports when only tabindex is present" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span tabindex="0" phx-click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end
  end

  describe "&run/2 leaves native interactive elements alone" do
    test "does not report <button phx-click=...>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button type="button" phx-click="show_findings">click</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end

    test "does not report a tag name that is only a prefix of a banned tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <divider phx-click="show_findings">click</divider>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end

    test "does not report a closing tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-click="open">
            <span>close x</span>
          </button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end

    test "does not report a non-interactive element with no click binding" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span class="pill">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end
  end

  describe "&run/2 params" do
    test "non_interactive_tags is configurable" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <p phx-click="open">open</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement, non_interactive_tags: ["span"])
      |> refute_issues()
    end

    test "bindings is configurable" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement, bindings: ["$click"])
      |> refute_issues()
    end

    test "escape_attributes is configurable" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span data-a11y="ok" phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement, escape_attributes: ["data-a11y"])
      |> refute_issues()
    end
  end

  describe "&run/2 sigils param" do
    test "inspects ~F bodies when configured" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <span phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end

    test "ignores every sigil not listed in :sigils" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <span phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement, sigils: [:sigil_H])
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "excludes configured paths" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement, excluded_paths: ["live/"])
      |> refute_issues()
    end
  end

  describe "&run/2 accepts every sigil form" do
    test "single-line ~H form" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H(<span phx-click="open">open</span>)
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end

    test "fires inside a .exs test file" do
      """
      defmodule MyAppWeb.CompTest do
        use ExUnit.Case

        def render(assigns) do
          ~H\"\"\"
          <span phx-click="open">open</span>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/test/my_app_web/comp_test.exs")
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <span class="pill" phx-click="show_findings">click</span>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> assert_issue(fn issue -> assert issue.trigger === "<span" end)
    end

    test "the GOOD example is clean" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button type="button" aria-label="Show findings" phx-click="show_findings">click</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoClickHandlerOnNonInteractiveElement)
      |> refute_issues()
    end
  end
end
