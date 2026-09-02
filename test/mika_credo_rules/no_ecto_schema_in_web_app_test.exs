defmodule MikaCredoRules.NoEctoSchemaInWebAppTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoEctoSchemaInWebApp

  describe "&run/2 flags use Ecto.Schema inside a web app" do
    test "reports the moduledoc BAD example (literal _web app directory)" do
      """
      defmodule MyWeb.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file("apps/my_web/lib/my_web/user.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "use"
        assert issue.message =~ "use Ecto.Schema found"
        assert issue.message =~ "_pg"
      end)
    end

    test "reports a schema under the realistic Phoenix app_web naming convention" do
      """
      defmodule MyAppWeb.Money do
        use Ecto.Schema

        embedded_schema do
          field :amount, :integer
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/money.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports use Schema under alias Ecto.Schema" do
      """
      defmodule MyAppWeb.User do
        alias Ecto.Schema

        use Schema

        schema "users" do
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/user.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports the Elixir-prefixed atom spelling" do
      """
      defmodule MyAppWeb.User do
        use :"Elixir.Ecto.Schema"

        schema "users" do
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/user.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports each use Ecto.Schema independently" do
      """
      defmodule MyAppWeb.User do
        use Ecto.Schema

        schema "users" do
        end
      end

      defmodule MyAppWeb.Post do
        use Ecto.Schema

        schema "posts" do
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/schemas.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 9]
      end)
    end
  end

  describe "&run/2 does not flag schemas outside a web app" do
    test "does not report the moduledoc GOOD example (dedicated pg app)" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file("apps/my_pg/lib/my_pg/user.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> refute_issues()
    end

    test "does not report a lookalike path that merely contains the substring web" do
      """
      defmodule Cobweb.User do
        use Ecto.Schema

        schema "users" do
        end
      end
      """
      |> to_source_file("lib/cobweb/user.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> refute_issues()
    end

    test "does not report import Ecto.Schema (not a use)" do
      """
      defmodule MyAppWeb.Token do
        import Ecto.Schema

        defstruct [:value]
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/token.ex")
      |> run_check(NoEctoSchemaInWebApp)
      |> refute_issues()
    end
  end

  describe "&run/2 respects custom params" do
    test "honors a custom modules list" do
      """
      defmodule MyAppWeb.User do
        use MyApp.Schema

        schema "users" do
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/user.ex")
      |> run_check(NoEctoSchemaInWebApp, modules: [MyApp.Schema])
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "honors a custom banned_path_fragments list" do
      """
      defmodule MyApp.Admin.User do
        use Ecto.Schema

        schema "users" do
        end
      end
      """
      |> to_source_file("apps/my_app_admin/lib/my_app_admin/user.ex")
      |> run_check(NoEctoSchemaInWebApp, banned_path_fragments: ["_admin"])
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "honors excluded_paths as a carve-out inside a banned path" do
      """
      defmodule MyAppWeb.FormValidator.User do
        use Ecto.Schema

        embedded_schema do
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/form_validators/user.ex")
      |> run_check(NoEctoSchemaInWebApp, excluded_paths: ["form_validators/"])
      |> refute_issues()
    end
  end
end
