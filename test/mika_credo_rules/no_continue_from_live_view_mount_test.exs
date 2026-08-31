defmodule MikaCredoRules.NoContinueFromLiveViewMountTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoContinueFromLiveViewMount

  @live_file "apps/my_app_web/lib/my_app_web/live/dashboard_live.ex"

  describe "&run/2 flags mount/3 clauses ending in {:continue, _}" do
    test "reports the moduledoc BAD example (single-line do:)" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket), do: {:ok, socket, {:continue, :load}}
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === ":continue"
        assert issue.message =~ ":continue found"
        assert issue.message =~ "connected?"
      end)
    end

    test "reports a multi-line mount/3 whose last expression is the continue tuple" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          socket = assign(socket, :ready, false)
          {:ok, socket, {:continue, :load}}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports each offending mount/3 clause independently" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(%{"id" => _id}, _session, socket) do
          {:ok, socket, {:continue, :load_one}}
        end

        def mount(_params, _session, socket) do
          {:ok, socket, {:continue, :load_two}}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 7]
      end)
    end

    test "issue carries a column pointing at the continue tuple, not nil" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          socket = assign(socket, :ready, false)
          {:ok, socket, {:continue, :load}}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.column === 20
      end)
    end

    test "reports a continue tuple carrying a compound term" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket), do: {:ok, socket, {:continue, {:load, 1}}}
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end
  end

  describe "&run/2 does not flag ordinary mount/3 returns" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          if connected?(socket), do: send(self(), :load)
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> refute_issues()
    end

    test "does not report a plain {:ok, socket} return" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket), do: {:ok, socket}
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> refute_issues()
    end

    test "does not report a continue tuple nested inside a case, not the literal last expression" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          case connected?(socket) do
            true -> {:ok, socket, {:continue, :load}}
            false -> {:ok, socket}
          end
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> refute_issues()
    end

    test "does not report a continue tuple nested inside an if, not the literal last expression" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          if connected?(socket) do
            {:ok, socket, {:continue, :load}}
          else
            {:ok, socket}
          end
        end
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes to mount/3 only" do
    test "does not report mount/2 (not a LiveView callback)" do
      """
      defmodule MyApp.LegacyMount do
        def mount(_params, socket), do: {:ok, socket, {:continue, :load}}
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount)
      |> refute_issues()
    end
  end

  describe "&run/2 respects excluded_paths" do
    test "does not report a file matching an excluded path fragment" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket), do: {:ok, socket, {:continue, :load}}
      end
      """
      |> to_source_file(@live_file)
      |> run_check(NoContinueFromLiveViewMount, excluded_paths: ["dashboard_live.ex"])
      |> refute_issues()
    end
  end
end
