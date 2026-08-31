defmodule MikaCredoRules.LiveViewSubscribeRequiresConnectedTest do
  use Credo.Test.Case

  alias MikaCredoRules.LiveViewSubscribeRequiresConnected

  @live_file "apps/my_app_web/lib/my_app_web/live/dashboard_live.ex"

  describe "&run/2 flags subscribe calls unguarded by connected?/1" do
    test "reports the moduledoc BAD example (unguarded remote subscribe)" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "subscribe"
        assert issue.message =~ "subscribe found"
        assert issue.message =~ "connected?"
      end)
    end

    test "reports a local (unqualified) subscribe call" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a subscribe guarded by an unrelated if condition" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          if socket.assigns.ready?, do: :noop
          MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports only the unguarded subscribe when a guarded one sits alongside it" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          if connected?(socket) do
            MyApp.PubSub.subscribe("a")
          end

          MyApp.PubSub.subscribe("b")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end

    test "reports each unguarded mount/3 clause independently" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(%{"id" => _id}, _s, socket) do
          MyApp.PubSub.subscribe("a")
          {:ok, socket}
        end

        def mount(_p, _s, socket) do
          MyApp.PubSub.subscribe("b")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 8]
      end)
    end

    test "reports a subscribe guarded by a custom helper not in default guard_functions" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          if live?(socket), do: MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 does not flag subscribe guarded by connected?/1" do
    test "does not report the moduledoc GOOD example (if-guarded)" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          if connected?(socket), do: MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe guarded by unless/else" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          unless connected?(socket) do
            :ok
          else
            MyApp.PubSub.subscribe("topic")
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe guarded by case connected?(socket)" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          case connected?(socket) do
            true -> MyApp.PubSub.subscribe("topic")
            false -> :ok
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe guarded by cond" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          cond do
            connected?(socket) -> MyApp.PubSub.subscribe("topic")
            true -> :ok
          end

          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe guarded by &&" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          connected?(socket) && MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe guarded by and" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          connected?(socket) and MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end
  end

  describe "&run/2 respects custom params" do
    test "honors a custom subscribe_functions list" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          MyApp.PubSub.listen("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, subscribe_functions: [:listen])
      |> assert_issue(fn issue -> assert issue.trigger === "listen" end)
    end

    test "honors a custom guard_functions list" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          if live?(socket), do: MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, guard_functions: [:live?])
      |> refute_issues()
    end

    test "honors subscribe_modules and does not flag a same-named call on a different module" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          EventBus.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, subscribe_modules: [Phoenix.PubSub])
      |> refute_issues()
    end

    test "honors subscribe_modules and still flags a call on a matching module" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, subscribe_modules: [Phoenix.PubSub])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "subscribe_modules does not filter a local subscribe call (ambiguous, documented limitation)" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, subscribe_modules: [Phoenix.PubSub])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "honors excluded_paths" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected, excluded_paths: ["dashboard_live.ex"])
      |> refute_issues()
    end
  end

  describe "&run/2 known limitations (documented, not fixed)" do
    test "does not report an unguarded apply/3 subscribe call" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_p, _s, socket) do
          apply(Phoenix.PubSub, :subscribe, [MyApp.PubSub, "topic"])
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "reports a subscribe-named call inside mount/3 even when the module is not a LiveView" do
      """
      defmodule MyApp.PlainModule do
        def mount(_p, _s, socket) do
          MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 scopes to mount/3 only" do
    test "does not report an unguarded subscribe inside mount/2 (not LiveView)" do
      """
      defmodule MyApp.LegacyMount do
        def mount(_p, socket) do
          MyApp.PubSub.subscribe("topic")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end

    test "does not report a subscribe call outside any mount/3 clause" do
      """
      defmodule MyAppWeb.DashboardLive do
        def handle_info(:refresh, socket) do
          MyApp.PubSub.subscribe("topic")
          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(LiveViewSubscribeRequiresConnected)
      |> refute_issues()
    end
  end
end
