defmodule MikaCredoRules.NoPhxBindingsInHoloTemplateTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoPhxBindingsInHoloTemplate

  @page_file "apps/my_app/lib/my_app/product_page.ex"

  describe "&run/2 flags phx-* attributes inside ~HOLO templates" do
    test "reports a phx-click binding, on the correct line inside the sigil" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template do
          ~HOLO\"""
          <div>
            <button phx-click="save">Save</button>
          </div>
          \"""
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "phx-click="
        assert issue.message =~ "phx-click="
        assert issue.message =~ "$click"
      end)
    end

    test "reports a phx-value-* attribute" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<button phx-value-id=\\"1\\">Del</button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-id=" end)
    end
  end

  describe "&run/2 flags EEx tags inside ~HOLO templates" do
    test "reports an <%= tag" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<p><%= @label %></p>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> assert_issue(fn issue ->
        assert issue.trigger === "<%="
        assert issue.message =~ "{@var}"
      end)
    end

    test "reports a bare <% scriptlet tag" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<p><% x = 1 %></p>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> assert_issue(fn issue -> assert issue.trigger === "<%" end)
    end
  end

  describe "&run/2 reports one issue per offending match" do
    test "reports both a phx-click and an EEx tag in the same template" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<button phx-click=\\"x\\"><%= @label %></button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === ["<%=", "phx-click="]
      end)
    end
  end

  describe "&run/2 leaves correct usage, other sigils, and non-Hologram modules alone" do
    test "does not report $click bindings" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<button $click=\\"save\\">Save</button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> refute_issues()
    end

    test "does not report {@var} interpolation" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<p>{@label}</p>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> refute_issues()
    end

    test "does not scan a ~H sigil (not ~HOLO)" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~H"<button phx-click=\\"save\\">Save</button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> refute_issues()
    end

    test "does not report in a non-Hologram module" do
      """
      defmodule MyAppWeb.ProductLive do
        use Phoenix.LiveView

        def template, do: ~HOLO"<button phx-click=\\"save\\">Save</button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> refute_issues()
    end

    test "does not report a file matching an excluded path" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<button phx-click=\\"save\\">Save</button>"
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/product_page.ex")
      |> run_check(NoPhxBindingsInHoloTemplate, excluded_paths: ["legacy/"])
      |> refute_issues()
    end

    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<button $click=\\"save\\">{@label}</button>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoPhxBindingsInHoloTemplate)
      |> refute_issues()
    end
  end
end
