defmodule MikaCredoRules.DistributionRequiresBucketsTest do
  use Credo.Test.Case

  alias MikaCredoRules.DistributionRequiresBuckets

  @metrics_file "apps/my_app/lib/my_app/metrics.ex"

  describe "&run/2 flags distribution/2 missing :reporter_options" do
    test "reports the local/imported call" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics do
          [distribution("my_app.job.duration.microseconds", event_name: [:job, :stop], measurement: :duration)]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue(fn issue -> assert issue.message =~ "reporter_options" end)
    end

    test "reports reporter_options present but missing :buckets" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics do
          [distribution("my_app.job.duration.microseconds", event_name: [:job, :stop], reporter_options: [])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue(fn issue -> assert issue.message =~ "buckets" end)
    end

    test "reports the qualified call" do
      """
      defmodule MyApp.Metrics do
        def metrics do
          [Telemetry.Metrics.distribution("my_app.job.duration.microseconds", event_name: [:job, :stop])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue()
    end
  end

  describe "&run/2 allows distribution/2 with :reporter_options set" do
    test "does not report when reporter_options is present" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics do
          [distribution("my_app.job.duration.microseconds",
            event_name: [:job, :stop],
            reporter_options: [buckets: [10, 100, 1000]]
          )]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end

    test "does not report a bare local distribution/2 without import Telemetry.Metrics" do
      """
      defmodule MyApp.Metrics do
        def distribution(name, opts), do: {name, opts}

        def metrics do
          [distribution("my_app.job.duration.microseconds", event_name: [:job, :stop])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end

    test "does not report a distribution/2 function definition head" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics

        defp distribution(name, [foo: 1]), do: name
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end

    test "does not report a distribution/2 function definition head with a do block" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics

        def distribution(name, opts) do
          {name, opts}
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end

    test "does not report a non-literal opts argument" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics(opts) do
          [distribution("my_app.job.duration.microseconds", opts)]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of Telemetry.Metrics" do
    test "reports through an alias" do
      """
      defmodule MyApp.Metrics do
        alias Telemetry.Metrics

        def metrics do
          [Metrics.distribution("my_app.job.duration.microseconds", event_name: [:job, :stop])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue()
    end

    test "reports the fully qualified Elixir.Telemetry.Metrics.distribution" do
      """
      defmodule MyApp.Metrics do
        def metrics do
          [Elixir.Telemetry.Metrics.distribution("my_app.job.duration.microseconds", event_name: [:job, :stop])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :required_keys param" do
    test "flags a custom required key that is missing" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics do
          [distribution("my_app.job.duration.microseconds", reporter_options: [buckets: [1]])]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets, required_keys: [:unit])
      |> assert_issue(fn issue -> assert issue.message =~ "unit" end)
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured function names" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2, summary: 2]

        def metrics do
          [
            distribution("a", event_name: [:a]),
            summary("b", event_name: [:b])
          ]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets, functions: [:summary])
      |> assert_issue(fn issue -> assert issue.message =~ "summary" end)
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics, do: [distribution("a", event_name: [:a])]
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/scripts/experimental_metrics.ex")
      |> run_check(DistributionRequiresBuckets, excluded_paths: ["scripts/"])
      |> refute_issues()
    end

    test "still reports a lookalike lib path that merely contains the test/ substring" do
      """
      defmodule MyApp.Latest.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]

        def metrics, do: [distribution("a", event_name: [:a])]
      end
      """
      |> to_source_file("apps/my_app/lib/latest/metrics.ex")
      |> run_check(DistributionRequiresBuckets, excluded_paths: ["test/"])
      |> assert_issue()
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]
        @stop [:my_app, :job, :stop]

        def metrics do
          [distribution("my_app.job.duration.microseconds", event_name: @stop, measurement: :duration)]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> assert_issue()
    end

    test "the GOOD example is clean" do
      """
      defmodule MyApp.Metrics do
        import Telemetry.Metrics, only: [distribution: 2]
        @stop [:my_app, :job, :stop]
        @buckets [10, 100, 1000]

        def metrics do
          [distribution("my_app.job.duration.microseconds",
            event_name: @stop,
            measurement: :duration,
            reporter_options: [buckets: @buckets]
          )]
        end
      end
      """
      |> to_source_file(@metrics_file)
      |> run_check(DistributionRequiresBuckets)
      |> refute_issues()
    end
  end
end
