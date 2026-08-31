defmodule MikaCredoRules.SqlSandboxPlugMustBeCompileGatedTest do
  use Credo.Test.Case

  alias MikaCredoRules.SqlSandboxPlugMustBeCompileGated

  @endpoint_file "apps/my_web/lib/my_web/endpoint.ex"

  describe "&run/2 flags an unguarded Phoenix.Ecto.SQL.Sandbox plug" do
    test "reports the moduledoc BAD example (bare fully-qualified plug)" do
      """
      defmodule MyWeb.Endpoint do
        use Phoenix.Endpoint, otp_app: :my_web

        plug Phoenix.Ecto.SQL.Sandbox
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "plug"
        assert issue.message =~ "plug Phoenix.Ecto.SQL.Sandbox found"
        assert issue.message =~ "compile_env"
      end)
    end

    test "reports an unguarded plug carrying options" do
      """
      defmodule MyWeb.Endpoint do
        plug Phoenix.Ecto.SQL.Sandbox, at: "/sandbox"
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports a plug spelled SQL.Sandbox under alias Phoenix.Ecto.SQL" do
      """
      defmodule MyWeb.Endpoint do
        alias Phoenix.Ecto.SQL

        plug SQL.Sandbox
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a plug spelled SQL.Sandbox under a multi-alias Phoenix.Ecto.{SQL, Repo}" do
      """
      defmodule MyWeb.Endpoint do
        alias Phoenix.Ecto.{SQL, Repo}

        plug SQL.Sandbox
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a plug spelled Sandbox under alias Phoenix.Ecto.SQL.Sandbox" do
      """
      defmodule MyWeb.Endpoint do
        alias Phoenix.Ecto.SQL.Sandbox

        plug Sandbox
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports the Elixir-prefixed atom spelling" do
      """
      defmodule MyWeb.Endpoint do
        plug :"Elixir.Phoenix.Ecto.SQL.Sandbox"
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports the plug when its gate is a module attribute (documented limitation)" do
      """
      defmodule MyWeb.Endpoint do
        @sandbox? Application.compile_env(:my_web, :sql_sandbox, false)

        if @sandbox? do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports a plug inside an unless whose condition does not call the gate function" do
      """
      defmodule MyWeb.Endpoint do
        unless MyApp.Config.some_other_flag?() do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the plug when the gate's Application is shadowed by a project alias" do
      """
      defmodule MyWeb.Endpoint do
        alias MyApp.Application

        if Application.compile_env(:my_web, :sql_sandbox, false) do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end
  end

  describe "&run/2 does not flag a compile-gated plug" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyWeb.Endpoint do
        if Application.compile_env(:my_web, :sql_sandbox, false) do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> refute_issues()
    end

    test "does not report a plug gated behind unless Application.compile_env" do
      """
      defmodule MyWeb.Endpoint do
        unless Application.compile_env(:my_web, :prod?, true) do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> refute_issues()
    end

    test "does not report a gated plug spelled SQL.Sandbox under a prefix alias" do
      """
      defmodule MyWeb.Endpoint do
        alias Phoenix.Ecto.SQL

        if Application.compile_env(:my_web, :sql_sandbox, false) do
          plug SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> refute_issues()
    end

    test "does not report a plug that is not Phoenix.Ecto.SQL.Sandbox" do
      """
      defmodule MyWeb.Endpoint do
        plug Plug.Static, at: "/", from: :my_web
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> refute_issues()
    end

    test "does not report a lookalike SQL.Other under the same prefix alias" do
      """
      defmodule MyWeb.Endpoint do
        alias Phoenix.Ecto.SQL

        plug SQL.Other
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated)
      |> refute_issues()
    end
  end

  describe "&run/2 respects custom params" do
    test "honors a custom gate_functions list" do
      """
      defmodule MyWeb.Endpoint do
        if MyApp.Config.sql_sandbox?() do
          plug Phoenix.Ecto.SQL.Sandbox
        end
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated,
        gate_functions: [{MyApp.Config, :sql_sandbox?}]
      )
      |> refute_issues()
    end

    test "honors excluded_paths" do
      """
      defmodule MyWeb.Endpoint do
        plug Phoenix.Ecto.SQL.Sandbox
      end
      """
      |> to_source_file(@endpoint_file)
      |> run_check(SqlSandboxPlugMustBeCompileGated, excluded_paths: ["endpoint.ex"])
      |> refute_issues()
    end
  end
end
