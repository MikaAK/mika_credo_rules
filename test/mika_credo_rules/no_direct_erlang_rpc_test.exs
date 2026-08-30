defmodule MikaCredoRules.NoDirectErlangRpcTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoDirectErlangRpc

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags erlang RPC modules" do
    test "reports :rpc.call/4" do
      """
      defmodule MyApp.Worker do
        def fetch(node, id) do
          :rpc.call(node, SharedFeedUtils.FeedServer, :get_state, [id])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ ":rpc.call/4 found"
      end)
    end

    test "reports :erpc.call/4" do
      """
      defmodule MyApp.Worker do
        def fetch(node, id), do: :erpc.call(node, MyModule, :fun, [id])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue -> assert issue.message =~ ":erpc.call/4 found" end)
    end

    test "does not report other erlang remote calls" do
      """
      defmodule MyApp.Worker do
        def wait, do: :timer.sleep(10)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end
  end

  describe "&run/2 flags banned Node functions" do
    test "reports Node.spawn/2" do
      """
      defmodule MyApp.Worker do
        def start(node), do: Node.spawn(node, fn -> :ok end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue -> assert issue.message =~ "Node.spawn/2 found" end)
    end

    test "reports Node.spawn_link/2" do
      """
      defmodule MyApp.Worker do
        def start(node), do: Node.spawn_link(node, fn -> :ok end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue -> assert issue.message =~ "Node.spawn_link/2 found" end)
    end

    test "reports Node.spawn_monitor/2" do
      """
      defmodule MyApp.Worker do
        def start(node), do: Node.spawn_monitor(node, fn -> :ok end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue -> assert issue.message =~ "Node.spawn_monitor/2 found" end)
    end

    test "does not report other Node functions" do
      """
      defmodule MyApp.Worker do
        def alive?(node), do: Node.ping(node)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end

    test "does not report bare uses of Node shadowed by a project alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Node

        def start, do: Node.spawn(:ok)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report a file under rpc_load_balancer/" do
      """
      defmodule RpcLoadBalancer.Internal do
        def call(node, mod, fun, args), do: :erpc.call(node, mod, fun, args)
      end
      """
      |> to_source_file("apps/rpc_load_balancer/lib/rpc_load_balancer/internal.ex")
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end

    test "does not report a file under elixir_cache/" do
      """
      defmodule Cache.HashRing do
        def call(node, mod, fun, args), do: :erpc.call(node, mod, fun, args)
      end
      """
      |> to_source_file("apps/elixir_cache/lib/cache/hash_ring.ex")
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end

    test "does not exempt a lookalike path" do
      """
      defmodule MyApp.FakeRpcLoadBalancerHelper do
        def call(node, mod, fun, args), do: :erpc.call(node, mod, fun, args)
      end
      """
      |> to_source_file("apps/my_app/lib/fake_rpc_load_balancer_helper.ex")
      |> run_check(NoDirectErlangRpc)
      |> assert_issue(fn issue -> assert issue.message =~ ":erpc.call/4 found" end)
    end
  end

  describe "&run/2 honours the :erlang_modules param" do
    test "flags only the listed erlang modules" do
      """
      defmodule MyApp.Worker do
        def old, do: :rpc.call(node(), Mod, :fun, [])
        def new, do: :my_rpc.call(node(), Mod, :fun, [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc, erlang_modules: [:my_rpc])
      |> assert_issue(fn issue -> assert issue.message =~ ":my_rpc.call/4 found" end)
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the listed module/function pairs" do
      """
      defmodule MyApp.Worker do
        def start(node), do: Node.spawn(node, fn -> :ok end)
        def custom(node), do: MyApp.Remote.spawn_task(node, fn -> :ok end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc, functions: [{MyApp.Remote, :spawn_task}])
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Remote.spawn_task/2 found" end)
    end
  end

  describe "moduledoc examples" do
    test "BAD example 1 (:rpc.call) fires" do
      """
      defmodule MyApp.Worker do
        def fetch(node, id) do
          :rpc.call(node, SharedFeedUtils.FeedServer, :get_state, [:adapter, id])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue()
    end

    test "GOOD example 1 (RPC wrapper) is clean" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          MyApp.RPC.call_on_random_node("options_feed", SharedFeedUtils.FeedServer, :get_state, [:adapter, id])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end

    test "BAD example 2 (Node.spawn) fires" do
      """
      defmodule MyApp.Worker do
        def start(node), do: Node.spawn(node, fn -> :ok end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> assert_issue()
    end

    test "GOOD example 2 (wrapper async call) is clean" do
      """
      defmodule MyApp.Worker do
        def start(args) do
          MyApp.RPC.call_on_random_node("options_feed", MyWorker, :start_async, [args])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectErlangRpc)
      |> refute_issues()
    end
  end
end
