defmodule MikaCredoRules.NoHeexSigilInHologramModuleTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoHeexSigilInHologramModule

  @page_file "apps/my_app/lib/my_app/product_page.ex"

  describe "&run/2 flags ~H sigils inside Hologram modules" do
    test "reports a bare ~H sigil" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~H"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "~H"
        assert issue.message =~ "~H found"
        assert issue.message =~ "~HOLO"
      end)
    end

    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page
        def template, do: ~H"<div/>"   # BAD — must be ~HOLO
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue -> assert issue.trigger === "~H" end)
    end

    test "reports every ~H sigil in a Hologram Component module" do
      """
      defmodule MyApp.Counter do
        use Hologram.Component

        def template, do: ~H"<span/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end
  end

  describe "&run/2 flags use Phoenix.LiveView / Phoenix.Component inside Hologram modules" do
    test "reports use Phoenix.LiveView" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page
        use Phoenix.LiveView
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Phoenix.LiveView"
        assert issue.message =~ "Phoenix.LiveView found"
        assert issue.message =~ "Hologram.Page"
      end)
    end

    test "reports use Phoenix.Component" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page
        use Phoenix.Component
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue -> assert issue.trigger === "Phoenix.Component" end)
    end

    test "reports both a banned use and a banned sigil in the same module" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page
        use Phoenix.LiveView

        def template, do: ~H"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === ["Phoenix.LiveView", "~H"]
      end)
    end
  end

  describe "&run/2 resolves aliases" do
    test "reports use Page under alias Hologram.Page" do
      """
      defmodule MyApp.ProductPage do
        alias Hologram.Page

        use Page

        def template, do: ~H"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "does not report when a project alias shadows Page" do
      """
      defmodule MyApp.ProductPage do
        alias MyApp.Page

        use Page

        def template, do: ~H"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves non-Hologram modules and correct usage alone" do
    test "does not report ~H in a plain LiveView module" do
      """
      defmodule MyAppWeb.ProductLive do
        use Phoenix.LiveView

        def render(assigns), do: ~H"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> refute_issues()
    end

    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<div/>"
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> refute_issues()
    end

    test "does not report a nested module that is not itself a Hologram module" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        defmodule Helpers do
          def render(assigns), do: ~H"<div/>"
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> refute_issues()
    end

    test "does not report a def head whose function is literally named sigil_H" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def sigil_H(term, _modifiers), do: term
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoHeexSigilInHologramModule)
      |> refute_issues()
    end
  end
end
