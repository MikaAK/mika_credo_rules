defmodule MikaCredoRules.EctoMetricsRequiresAppAtomTest do
  use Credo.Test.Case

  alias MikaCredoRules.EctoMetricsRequiresAppAtom

  @application_file "apps/my_app/lib/my_app/application.ex"

  describe "&run/2 flags a zero-arity PrometheusTelemetry.Metrics.Ecto.metrics/0 call" do
    test "reports the unaliased qualified call" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> assert_issue(fn issue ->
        assert issue.message =~ "PrometheusTelemetry.Metrics.Ecto.metrics"
      end)
    end

    test "reports the fully qualified Elixir.PrometheusTelemetry.Metrics.Ecto" do
      """
      defmodule MyApp.Application do
        def metrics, do: [Elixir.PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> assert_issue()
    end
  end

  describe "&run/2 allows the app-atom form and other functions" do
    test "does not report metrics(:my_app)" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics(:my_app)]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> refute_issues()
    end

    test "does not report a different function on the same module" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics_for_repo(MyApp.Repo)]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> refute_issues()
    end

    test "does not report an unrelated module named Ecto with no alias in scope" do
      """
      defmodule MyApp.Application do
        def metrics, do: [Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves the PrometheusTelemetry.Metrics alias" do
    test "reports through alias PrometheusTelemetry.Metrics + Metrics.Ecto.metrics()" do
      """
      defmodule MyApp.Application do
        alias PrometheusTelemetry.Metrics

        def metrics, do: [Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> assert_issue()
    end

    test "known limitation: does not report a bare Ecto.metrics() reached via a full submodule alias" do
      """
      defmodule MyApp.Application do
        alias PrometheusTelemetry.Metrics.Ecto

        def metrics, do: [Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags an additionally configured module/function pair" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Phoenix.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom,
        functions: [{PrometheusTelemetry.Metrics.Phoenix, :metrics}]
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ "PrometheusTelemetry.Metrics.Phoenix.metrics"
      end)
    end

    test "no longer flags Ecto once :functions is overridden away from it" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom,
        functions: [{PrometheusTelemetry.Metrics.Phoenix, :metrics}]
      )
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/scripts/experimental.ex")
      |> run_check(EctoMetricsRequiresAppAtom, excluded_paths: ["scripts/"])
      |> refute_issues()
    end

    test "still reports a lookalike lib path that merely contains the test/ substring" do
      """
      defmodule MyApp.Latest.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file("apps/my_app/lib/latest/application.ex")
      |> run_check(EctoMetricsRequiresAppAtom, excluded_paths: ["test/"])
      |> assert_issue()
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics()]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> assert_issue()
    end

    test "the GOOD example is clean" do
      """
      defmodule MyApp.Application do
        def metrics, do: [PrometheusTelemetry.Metrics.Ecto.metrics(:my_app)]
      end
      """
      |> to_source_file(@application_file)
      |> run_check(EctoMetricsRequiresAppAtom)
      |> refute_issues()
    end
  end
end
