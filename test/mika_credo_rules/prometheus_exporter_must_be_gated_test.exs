defmodule MikaCredoRules.PrometheusExporterMustBeGatedTest do
  use Credo.Test.Case

  alias MikaCredoRules.PrometheusExporterMustBeGated

  @lib_file "apps/my_app/lib/my_app/application.ex"

  describe "&run/2 flags a hardcoded enabled?: true" do
    test "reports exporter: [enabled?: true] in a child spec tuple" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: [enabled?: true], metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "exporter: [enabled?: true]"
        assert issue.message =~ "exporter: [enabled?: true]"
        assert issue.message =~ "gate"
      end)
    end

    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.Application do
        @is_prod Application.compile_env(:my_app, :env) === :prod

        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: [enabled?: true], metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> assert_issue()
    end

    test "reports each occurrence with its own issue" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          web = {PrometheusTelemetry, exporter: [enabled?: true], metrics: []}
          admin = {PrometheusTelemetryAdmin, exporter: [enabled?: true], metrics: []}
          Supervisor.start_link([web, admin], strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "honors a custom :keys param" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [{PrometheusTelemetry, reporter: [enabled?: true]}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated, keys: [:reporter])
      |> assert_issue()
    end
  end

  describe "&run/2 leaves gated and non-literal exporters alone" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.Application do
        @is_prod Application.compile_env(:my_app, :env) === :prod

        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: [enabled?: @is_prod], metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> refute_issues()
    end

    test "does not report a variable exporter option list" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: exporter_opts(), metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> refute_issues()
    end

    test "does not report enabled?: false" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          children = [{PrometheusTelemetry, exporter: [enabled?: false], metrics: []}]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> refute_issues()
    end

    test "does not report an unrelated key with enabled?: true" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          _config = [feature_flags: [enabled?: true]]
          Supervisor.start_link([], strategy: :one_for_one)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PrometheusExporterMustBeGated)
      |> refute_issues()
    end
  end

  describe "&run/2 exempts .exs files" do
    test "does not report exporter: [enabled?: true] in config/prod.exs" do
      """
      import Config

      config :my_app, PrometheusTelemetry, exporter: [enabled?: true]
      """
      |> to_source_file("config/prod.exs")
      |> run_check(PrometheusExporterMustBeGated)
      |> refute_issues()
    end
  end
end
