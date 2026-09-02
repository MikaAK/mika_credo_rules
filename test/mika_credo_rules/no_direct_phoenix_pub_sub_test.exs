defmodule MikaCredoRules.NoDirectPhoenixPubSubTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoDirectPhoenixPubSub

  @lib_file "apps/my_app_web/lib/my_app_web/live/dashboard_live.ex"
  @test_file "apps/my_app_web/test/my_app_web/live/dashboard_live_test.exs"
  @wrapper_fragment_file "apps/my_app/lib/my_app/pubsub/courses.ex"
  @wrapper_segment_suffix_file "apps/my_app/lib/my_app_pub_sub/courses.ex"

  @moduledoc_examples NoDirectPhoenixPubSub
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoDirectPhoenixPubSub"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end
  end

  describe "&run/2 flags Phoenix.PubSub calls outside a wrapper module" do
    test "reports a fully qualified Phoenix.PubSub.subscribe/2" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Phoenix.PubSub.subscribe"
        assert issue.message =~ "Phoenix.PubSub.subscribe"
        assert issue.message =~ "wrapper"
      end)
    end

    test "reports an aliased PubSub.broadcast/3 under alias Phoenix.PubSub" do
      """
      defmodule MyAppWeb.DashboardLive do
        alias Phoenix.PubSub

        def refresh(id) do
          PubSub.broadcast(MyApp.PubSub, "courses:\#{id}", :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue -> assert issue.trigger === "PubSub.broadcast" end)
    end

    test "reports the bare-atom Elixir.Phoenix.PubSub spelling" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          :"Elixir.Phoenix.PubSub".subscribe(MyApp.PubSub, "courses:1")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue -> assert issue.trigger === "subscribe" end)
    end
  end

  describe "&run/2 leaves app wrapper modules and non-PubSub identity silent" do
    test "does not report a project module that merely ends in .PubSub.*" do
      """
      defmodule MyApp.Workers.CourseWorker do
        def perform(id) do
          MyApp.PubSub.Courses.subscribe_course(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "a project alias shadowing the bare name wins over Phoenix.PubSub" do
      """
      defmodule MyAppWeb.DashboardLive do
        alias Phoenix.PubSub
        alias MyApp.PubSub

        def refresh(id) do
          PubSub.broadcast(id, :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "the earlier alias order still resolves the bare name to Phoenix.PubSub" do
      """
      defmodule MyAppWeb.DashboardLive do
        alias MyApp.PubSub
        alias Phoenix.PubSub

        def refresh(id) do
          PubSub.broadcast(id, :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue -> assert issue.trigger === "PubSub.broadcast" end)
    end

    test "does not report a nested defmodule PubSub with no alias in force" do
      """
      defmodule MyAppWeb.DashboardLive do
        defmodule PubSub do
          def broadcast(_id, _event), do: :ok
        end

        def refresh(id) do
          PubSub.broadcast(id, :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "still reports through alias Phoenix.PubSub even inside a file with a nested defmodule PubSub" do
      """
      defmodule MyAppWeb.DashboardLive do
        alias Phoenix.PubSub

        defmodule PubSub do
          def broadcast(_id, _event), do: :ok
        end

        def refresh(id) do
          PubSub.broadcast(MyApp.PubSub, "dashboard:\#{id}", :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue -> assert issue.trigger === "PubSub.broadcast" end)
    end

    test "does not report a Phoenix.PubSub function outside :functions" do
      """
      defmodule MyAppWeb.DashboardLive do
        def node(pubsub_name) do
          Phoenix.PubSub.node_name(pubsub_name)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end
  end

  describe "&run/2 respects :allowed_paths for the wrapper module's own file" do
    test "does not report inside a fragment-matched pubsub/ directory" do
      """
      defmodule MyApp.PubSub.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file(@wrapper_fragment_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "does not report inside a segment-suffix-matched *_pub_sub directory" do
      """
      defmodule MyApp.PubSub.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file(@wrapper_segment_suffix_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "all four leading/trailing slash spellings of a single-segment entry agree on one result" do
      code = """
      defmodule MyApp.PubSub.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """

      for spelling <- ["pub_sub", "pub_sub/", "/pub_sub", "/pub_sub/"] do
        code
        |> to_source_file(@wrapper_segment_suffix_file)
        |> run_check(NoDirectPhoenixPubSub, allowed_paths: [spelling])
        |> refute_issues()
      end
    end

    test "still checks a boundary-lookalike path (*_pub_subscriber is not *_pub_sub)" do
      """
      defmodule MyApp.PubSubscriber.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app_pub_subscriber/courses.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end

    test "still checks a segment-prefix-lookalike path (pubsub_migrations is not pubsub)" do
      """
      defmodule MyApp.PubsubMigrations.X do
        def run(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/pubsub_migrations/x.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end

    test "reports the default-exempt pubsub/ path when :allowed_paths is overridden" do
      """
      defmodule MyApp.PubSub.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file(@wrapper_fragment_file)
      |> run_check(NoDirectPhoenixPubSub, allowed_paths: ["notifications"])
      |> assert_issue()
    end

    test "does not report the default-exempt pubsub/ path via a plain suffix lookalike" do
      """
      defmodule MyApp.LegacyPubSub.Courses do
        def subscribe_course(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{id}")
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy_pubsub/courses.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "a multi-segment :allowed_paths entry matches a consecutive run of whole segments" do
      """
      defmodule MyApp.Notifications.Courses do
        def notify_course(id) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "courses:\#{id}", :notify)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/notifications/courses.ex")
      |> run_check(NoDirectPhoenixPubSub, allowed_paths: ["my_app/notifications"])
      |> refute_issues()
    end

    test "a multi-segment :allowed_paths entry does not match a non-consecutive lookalike" do
      """
      defmodule MyApp.Notifications.Courses do
        def notify_course(id) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "courses:\#{id}", :notify)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app_notifications/x/courses.ex")
      |> run_check(NoDirectPhoenixPubSub, allowed_paths: ["my_app/notifications"])
      |> assert_issue()
    end

    test "does not report the default-exempt topics/ path" do
      """
      defmodule MyAppWeb.Topics.SubscriptionEvents do
        def broadcast(id) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "sub:\#{id}", :refresh)
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/my_app_web/topics/subscription_events.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "reports a directory merely ending in the dropped singular 'topic'" do
      """
      defmodule MyAppWeb.HotTopic.X do
        def broadcast(id) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "t", id)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/hot_topic/x.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end
  end

  describe "&run/2 respects :excluded_paths for test files" do
    test "does not report a test file by default" do
      """
      defmodule MyAppWeb.DashboardLiveTest do
        test "renders" do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
          {:ok, socket}
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/latest/dashboard_live.ex")
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyAppWeb.DashboardLiveTest do
        test "renders" do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoDirectPhoenixPubSub, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 respects a :functions override" do
    test "bans only the overridden function list" do
      """
      defmodule MyAppWeb.DashboardLive do
        def refresh(id) do
          Phoenix.PubSub.broadcast(MyApp.PubSub, "courses:\#{id}", :refresh)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub, functions: [:broadcast])
      |> assert_issue(fn issue -> assert issue.trigger === "Phoenix.PubSub.broadcast" end)
    end

    test "no longer reports a function dropped from the override" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub, functions: [:broadcast])
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:1")
          {:ok, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two PubSub calls on one line its own column" do
      """
      defmodule MyAppWeb.DashboardLive do
        def refresh(id) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "a") && Phoenix.PubSub.subscribe(MyApp.PubSub, "b")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectPhoenixPubSub)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
