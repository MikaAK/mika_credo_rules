defmodule MikaCredoRules.NoSyncMailerDeliverInWebTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoSyncMailerDeliverInWeb

  @controller_file "apps/my_app_web/lib/my_app_web/controllers/signup_controller.ex"
  @live_dir_file "apps/my_app_web/lib/my_app_web/live/signup_live.ex"
  @live_suffix_file "apps/my_app_web/lib/my_app_web/signup_live.ex"
  @controller_suffix_file "apps/my_app_web/lib/my_app_web/signup_controller.ex"
  @worker_file "apps/my_app/lib/my_app/workers/send_welcome_email.ex"
  @lookalike_dir_file "apps/my_app/lib/my_app/remote_controllers/handler.ex"
  @controller_test_file "apps/my_app_web/test/my_app_web/controllers/signup_controller_test.exs"
  @web_app_suffix_file "apps/cfx_web/lib/cfx_web/auth.ex"

  @moduledoc_examples NoSyncMailerDeliverInWeb
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoSyncMailerDeliverInWeb"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end
  end

  describe "&run/2 flags sync mail delivery in a web-layer path" do
    test "reports a fully qualified MyApp.Mailer.deliver/1 in a controller" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "MyApp.Mailer.deliver"
        assert issue.message =~ "deliver"
        assert issue.message =~ "Oban"
      end)
    end

    test "reports an aliased Mailer.deliver!/1 in a LiveView" do
      """
      defmodule MyAppWeb.SignupLive do
        alias MyApp.Mailer

        def handle_event("submit", _params, socket) do
          Mailer.deliver!(socket.assigns.email)
          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@live_dir_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.trigger === "Mailer.deliver!" end)
    end

    test "reports an injected mailer held in a module attribute" do
      """
      defmodule MyAppWeb.SignupController do
        @mailer Application.compile_env(:my_app, :mailer)

        def create(conn, params) do
          @mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "@mailer.deliver"
      end)
    end

    test "reports an injected mailer passed as a variable" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params, mailer) do
          mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.trigger === "mailer.deliver" end)
    end

    test "reports an unqualified deliver under import" do
      """
      defmodule MyAppWeb.SignupController do
        import MyApp.Mailer

        def create(conn, params) do
          deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.trigger === "deliver" end)
    end

    test "fires on a file ending in _live.ex outside a live/ directory" do
      """
      defmodule MyAppWeb.SignupLive do
        def handle_event("submit", _params, socket) do
          MyApp.Mailer.deliver(socket.assigns.email)
          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@live_suffix_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end

    test "fires on a file ending in _controller.ex outside a controllers/ directory" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_suffix_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end

    test "fires on a real-shaped *_web app directory via the _web/ default" do
      """
      defmodule CfxWeb.Auth do
        def call(conn, _opts) do
          MyApp.Mailer.deliver(conn.assigns.email)
          conn
        end
      end
      """
      |> to_source_file(@web_app_suffix_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end

    test "reports a piped MyApp.Mailer.deliver/1 call" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params, email) do
          email |> MyApp.Mailer.deliver()
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Mailer.deliver" end)
    end

    test "still reports a lib path that merely contains 'test' as a substring, not a segment" do
      """
      defmodule MyAppWeb.Latest.Helpers do
        def notify(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/latest/helpers.ex")
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue()
    end

    test "reports a delivery written as a module attribute's value" do
      """
      defmodule MyAppWeb.SignupController do
        @preview MyApp.Mailer.deliver(:sample)
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "MyApp.Mailer.deliver"
      end)
    end

    test "reports an unrelated deliver/1 called on an unrecognized receiver name" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params, package) do
          courier.deliver(package)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.trigger === "courier.deliver" end)
    end
  end

  describe "&run/2 stays silent outside the web layer and on non-matching calls" do
    test "does not report the same call in a non-web worker module" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a directory that merely contains 'controllers' as a substring" do
      """
      defmodule MyApp.RemoteControllers.Handler do
        def perform(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@lookalike_dir_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report Oban.insert in a controller" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          %{email: params.email} |> MyApp.Workers.SendWelcomeEmail.new() |> Oban.insert()
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a non-Mailer module in a controller" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Notifier.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a function not in :functions" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver_many(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a deliver definition head" do
      """
      defmodule MyAppWeb.Mailer do
        def deliver(email), do: email
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a bodiless deliver head with a default argument" do
      """
      defmodule MyAppWeb.Mailer do
        def deliver(email \\\\ nil)
        def deliver(email), do: email
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report an @spec type signature for a deliver function" do
      """
      defmodule MyAppWeb.SignupController do
        @spec deliver(map()) :: :ok
        def deliver(email), do: email
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a @callback type signature for a deliver function" do
      """
      defmodule MyAppWeb.MailerBehaviour do
        @callback deliver(map()) :: :ok
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a struct/map field read like assigns.deliver" do
      """
      defmodule MyAppWeb.SettingsLive do
        use Phoenix.Component

        attr :deliver, :boolean, default: false

        def render(assigns) do
          assigns.deliver
        end
      end
      """
      |> to_source_file(@live_dir_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a controller test file even though its path matches controllers/" do
      """
      defmodule MyAppWeb.SignupControllerTest do
        def send_test_email(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@controller_test_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a real test-support .ex file under a *_web app's test/ directory" do
      """
      defmodule MyAppWeb.ConnCase do
        def email_fixture(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file("apps/my_app_web/test/support/conn_case.ex")
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a defdelegate whose name matches a flagged function" do
      """
      defmodule MyAppWeb.SignupController do
        defdelegate deliver(email), to: MyApp.Mailer
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a defguard whose name matches a flagged function" do
      """
      defmodule MyAppWeb.SignupController do
        defguard deliver(value) when is_map(value)
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a module attribute definition whose name matches a flagged function" do
      """
      defmodule MyAppWeb.SignupController do
        @deliver true
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report apply/3 indirection" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params, email) do
          apply(MyApp.Mailer, :deliver, [email])
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not crash and stays silent on a __MODULE__-relative alias path" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          __MODULE__.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not crash and stays silent on an attribute-prefixed alias path" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          @base.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not crash and stays silent on a variable-prefixed alias path" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params, mod) do
          mod.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a call through an :as rename that drops the suffix" do
      """
      defmodule MyAppWeb.SignupController do
        alias MyApp.Mailer, as: Notifier

        def create(conn, params) do
          Notifier.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end

    test "does not report a module spelled as an Elixir-prefixed atom" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          :"Elixir.MyApp.Mailer".deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two deliveries on one line its own column" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, first, second) do
          MyApp.Mailer.deliver(first) && MyApp.Mailer.deliver(second)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 honours param overrides" do
    test "respects a custom :functions list" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver_later(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb, functions: [:deliver_later])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Mailer.deliver_later" end)
    end

    test "respects a custom :module_suffixes" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Notifier.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb, module_suffixes: ["Notifier"])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Notifier.deliver" end)
    end

    test "respects a custom :included_paths narrowing scope below the default" do
      """
      defmodule MyAppWeb.SignupController do
        def create(conn, params) do
          MyApp.Mailer.deliver(params)
          conn
        end
      end
      """
      |> to_source_file(@controller_file)
      |> run_check(NoSyncMailerDeliverInWeb, included_paths: ["live/"])
      |> refute_issues()
    end

    test "respects a custom :included_paths widening scope to a new directory" do
      """
      defmodule MyApp.Workers.SendWelcomeEmail do
        def perform(email) do
          MyApp.Mailer.deliver(email)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoSyncMailerDeliverInWeb, included_paths: ["workers/"])
      |> assert_issue()
    end
  end
end
