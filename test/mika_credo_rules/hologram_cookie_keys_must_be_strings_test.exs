defmodule MikaCredoRules.HologramCookieKeysMustBeStringsTest do
  use Credo.Test.Case

  alias MikaCredoRules.HologramCookieKeysMustBeStrings

  @page_file "apps/my_app/lib/my_app/product_page.ex"

  describe "&run/2 flags an atom key literal" do
    test "reports put_cookie/3" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, :theme, "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "put_cookie"
        assert issue.message =~ "put_cookie found"
        assert issue.message =~ "strings"
      end)
    end

    test "reports get_cookie/3 (with a default value argument)" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def init(_params, _component, server) do
          get_cookie(server, :theme, "light")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue -> assert issue.trigger === "get_cookie" end)
    end

    test "reports delete_cookie/2" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:logout, _params, server) do
          delete_cookie(server, :token)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue -> assert issue.trigger === "delete_cookie" end)
    end

    test "reports put_cookie/4 (with trailing options)" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, :token, "abc", max_age: 86_400)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue -> assert issue.trigger === "put_cookie" end)
    end

    test "the literal moduledoc BAD example fires" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, :theme, "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue -> assert issue.trigger === "put_cookie" end)
    end
  end

  describe "&run/2 handles piped calls (key shifts position when the server is piped in)" do
    test "reports a piped put_cookie whose key is an atom, Hologram's own idiom" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          server
          |> put_action(:done)
          |> put_cookie(:prefs, %{theme: "dark"})
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> assert_issue(fn issue -> assert issue.trigger === "put_cookie" end)
    end

    test "does not report a piped put_cookie whose value happens to be an atom" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          server |> put_cookie("theme", :dark)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves string keys, variable keys, and non-Hologram modules alone" do
    test "does not report a string key" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, "theme", "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> refute_issues()
    end

    test "does not report a variable key" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, params, server) do
          put_cookie(server, params.key, "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> refute_issues()
    end

    test "does not report in a non-Hologram module" do
      """
      defmodule MyApp.Plain do
        def save(server) do
          put_cookie(server, :theme, "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> refute_issues()
    end

    test "the literal moduledoc GOOD example is clean" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, "theme", "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(HologramCookieKeysMustBeStrings)
      |> refute_issues()
    end
  end
end
