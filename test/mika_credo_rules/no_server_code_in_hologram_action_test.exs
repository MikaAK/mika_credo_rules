defmodule MikaCredoRules.NoServerCodeInHologramActionTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoServerCodeInHologramAction

  @page_file "apps/my_app/lib/my_app/product_page.ex"

  describe "&run/2 flags banned module calls inside actions" do
    test "reports a namespaced Repo call matched by its last segment" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          MyApp.Repo.insert(params)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "MyApp.Repo.insert"
        assert issue.message =~ "MyApp.Repo.insert found"
        assert issue.message =~ "command/3"
      end)
    end

    test "the literal moduledoc BAD example fires" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          MyApp.Repo.insert(%Product{name: params.name})
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Repo.insert" end)
    end

    test "reports a bare Repo call" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          Repo.insert(params)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "Repo.insert" end)
    end

    test "reports an Ecto.Changeset call matched by the Ecto.* prefix rule" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          Ecto.Changeset.cast(%{}, params, [:name])
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "Ecto.Changeset.cast" end)
    end

    test "reports an Oban call, alias-aware exact match" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, _params, component) do
          Oban.insert(new_job())
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "Oban.insert" end)
    end

    test "reports a SharedUtils.HTTP call" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:load, _params, component) do
          SharedUtils.HTTP.get("https://example.com")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end
  end

  describe "&run/2 flags local session/cookie calls inside actions" do
    test "reports get_session" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, _params, component) do
          get_session(component, :user_id)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue ->
        assert issue.trigger === "get_session"
        assert issue.message =~ "init/3 and command/3"
      end)
    end

    test "reports put_cookie" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, _params, component) do
          put_cookie(component, "theme", "dark")
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "put_cookie" end)
    end
  end

  describe "&run/2 flags unsupported client forms inside actions" do
    test "reports a with expression" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          with {:ok, name} <- Map.fetch(params, :name) do
            component
          end
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue ->
        assert issue.trigger === "with"
        assert issue.message =~ "0.8.3"
      end)
    end

    test "reports a try expression" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, _params, component) do
          try do
            component
          rescue
            _error -> component
          end
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "try" end)
    end

    test "reports a receive expression" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, _params, component) do
          receive do
            :ping -> component
          end
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issue(fn issue -> assert issue.trigger === "receive" end)
    end
  end

  describe "&run/2 reports one issue per offending node" do
    test "reports both a banned module call and a banned local call in the same action" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          get_session(component, :user_id)
          MyApp.Repo.insert(params)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() ===
                 ["MyApp.Repo.insert", "get_session"]
      end)
    end
  end

  describe "&run/2 leaves commands, init/3, and clean actions alone" do
    test "does not report a Repo call inside command/3" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, params, server) do
          MyApp.Repo.insert(params)
          server
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end

    test "does not report get_session inside command/3" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          get_session(server, :user_id)
          server
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end

    test "does not report a with expression inside command/3" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, params, server) do
          with {:ok, name} <- Map.fetch(params, :name) do
            server
          end
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end

    test "does not report an action calling a plain context function" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:load, _params, component) do
          put_state(component, :users, MyApp.Accounts.list_users())
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end

    test "does not report in a non-Hologram module" do
      """
      defmodule MyApp.Plain do
        def action(:save, params, component) do
          MyApp.Repo.insert(params)
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end

    test "the literal moduledoc GOOD example is clean" do
      """
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def action(:save, params, component) do
          put_command(component, :save_product, name: params.name)
        end

        def command(:save_product, params, server) do
          MyApp.Repo.insert(%{name: params.name})
          server
        end
      end
      """
      |> to_source_file(@page_file)
      |> run_check(NoServerCodeInHologramAction)
      |> refute_issues()
    end
  end
end
