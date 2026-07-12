defmodule MikaCredoRules.LoggerModulePrefixAndInspectTest do
  use Credo.Test.Case

  alias MikaCredoRules.LoggerModulePrefixAndInspect

  @worker_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags Logger messages without the __MODULE__ prefix" do
    test "reports a message whose first interpolation is not __MODULE__" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(reason), do: Logger.error("failed: #{inspect(reason)}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.message =~ "Logger.error/1 without a __MODULE__ prefix"
      end)
    end

    test "reports a plain string literal message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call, do: Logger.info("starting up")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.info/1 without a __MODULE__ prefix"
      end)
    end

    test "reports every Logger function in the default list" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def all do
          Logger.debug("one")
          Logger.info("two")
          Logger.warning("three")
          Logger.warn("four")
          Logger.error("five")
          Logger.critical("six")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issues(fn issues -> assert length(issues) === 6 end)
    end

    test "reports each call site with its own line number" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def one, do: Logger.info("one")
        def two, do: Logger.info("two")
        def three, do: Logger.info("three")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [4, 5, 6]
      end)
    end

    test "reports a message that does not start with the __MODULE__ interpolation" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("processing #{__MODULE__} value #{inspect(value)}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.info/1 without a __MODULE__ prefix"
      end)
    end

    test "reports a literal before the __MODULE__ prefix" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call, do: Logger.info("[worker] #{__MODULE__}: started")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.info/1 without a __MODULE__ prefix"
      end)
    end

    test "reports fully qualified Elixir.Logger" do
      ~S"""
      defmodule MyApp.Worker do
        def call, do: Elixir.Logger.error("boom")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Elixir.Logger.error/1 without a __MODULE__ prefix"
      end)
    end
  end

  describe "&run/2 flags interpolated values not wrapped in inspect/1" do
    test "reports a bare interpolated value" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value), do: Logger.info("#{__MODULE__}: got #{value}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.message =~ "Logger.info/1 interpolating a bare value"
        assert issue.message =~ "inspect/1"
      end)
    end

    test "reports one issue per call regardless of how many values are bare" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(first, second) do
          Logger.info("#{__MODULE__}: first: #{first}, second: #{second}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.info/1 interpolating a bare value"
      end)
    end

    test "reports both violations on a single call" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value), do: Logger.info("got #{value}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issues(fn issues ->
        messages = Enum.map(issues, & &1.message)

        assert length(issues) === 2
        assert Enum.any?(messages, &(&1 =~ "without a __MODULE__ prefix"))
        assert Enum.any?(messages, &(&1 =~ "interpolating a bare value"))
      end)
    end
  end

  describe "&run/2 allows the canonical format" do
    test "does not report a prefixed message with inspected values" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value), do: Logger.info("#{__MODULE__}: got #{inspect(value)}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not report a prefix-only message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call, do: Logger.debug("#{__MODULE__}: starting")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not report inspect/2 with options" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("#{__MODULE__}: got #{inspect(value, pretty: true)}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not report a qualified Kernel.inspect" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("#{__MODULE__}: got #{Kernel.inspect(value)}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not report __MODULE__ interpolated after the prefix" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call, do: Logger.info("#{__MODULE__}: running inside #{__MODULE__}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end
  end

  describe "&run/2 checks the lazy fn form" do
    test "reports violations inside a zero-arity fn message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(reason) do
          Logger.error(fn -> "failed: #{reason}" end)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issues(fn issues ->
        messages = Enum.map(issues, & &1.message)

        assert length(issues) === 2
        assert Enum.any?(messages, &(&1 =~ "without a __MODULE__ prefix"))
        assert Enum.any?(messages, &(&1 =~ "interpolating a bare value"))
      end)
    end

    test "does not report a canonical lazy message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(result) do
          Logger.debug(fn -> "#{__MODULE__}: done, result: #{inspect(result)}" end)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end
  end

  describe "&run/2 skips messages it cannot verify statically" do
    test "skips a variable message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(message), do: Logger.info(message)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "skips a message built by a function call" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(reason), do: Logger.error(build_message(reason))

        defp build_message(reason), do: "failed: " <> to_string(reason)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "skips a module attribute message" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        @message "starting up"

        def call, do: Logger.info(@message)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "skips a fn whose body is not a string literal" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call, do: Logger.info(fn -> build_message() end)

        defp build_message, do: "built"
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not report Logger functions on other modules" do
      ~S"""
      defmodule MyApp.Worker do
        def call, do: MyApp.Logger.info("boom")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end

    test "does not inspect the metadata argument" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(user_id) do
          Logger.info("#{__MODULE__}: user seen", user_id: user_id)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :logger_functions param" do
    test "flags only the configured functions" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("info: #{value}")
          Logger.error("error: #{value}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect,
        logger_functions: [:error],
        enforce_prefix: false
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.error/1 interpolating a bare value"
      end)
    end
  end

  describe "&run/2 honours the :enforce_prefix param" do
    test "does not require the prefix when disabled" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(reason), do: Logger.error("failed: #{inspect(reason)}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect, enforce_prefix: false)
      |> refute_issues()
    end

    test "still flags bare interpolations when the prefix is not enforced" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(reason), do: Logger.error("failed: #{reason}")
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect, enforce_prefix: false)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.error/1 interpolating a bare value"
      end)
    end
  end

  describe "&run/2 honours the :allowed_interpolations param" do
    test "allows extra interpolation functions" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("#{__MODULE__}: got #{format_value(value)}")
        end

        defp format_value(value), do: inspect(value)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect,
        allowed_interpolations: [:__MODULE__, :inspect, :format_value]
      )
      |> refute_issues()
    end

    test "allows a qualified spelling of an allowed function" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("#{__MODULE__}: got #{MyApp.Format.format_value(value)}")
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect,
        allowed_interpolations: [:__MODULE__, :inspect, :format_value]
      )
      |> refute_issues()
    end

    test "flags functions outside the default allow list" do
      ~S"""
      defmodule MyApp.Worker do
        require Logger

        def call(value) do
          Logger.info("#{__MODULE__}: got #{format_value(value)}")
        end

        defp format_value(value), do: inspect(value)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(LoggerModulePrefixAndInspect)
      |> assert_issue(fn issue ->
        assert issue.message =~ "Logger.info/1 interpolating a bare value"
      end)
    end
  end
end
