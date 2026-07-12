defmodule MikaCredoRules.NoBlanketRescueTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoBlanketRescue

  describe "&run/2 flags blanket rescues in try blocks" do
    test "reports rescue _ that swallows the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            _ -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.trigger === "_"
        assert issue.message =~ "rescue _ found"
      end)
    end

    test "reports a bare variable rescue that swallows the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue ->
        assert issue.line_no === 6
        assert issue.message =~ "rescue error found"
      end)
    end

    test "reports an underscore-prefixed variable rescue" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            _error -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue -> assert issue.message =~ "rescue _error found" end)
    end

    test "reports only the blanket clause when mixed with typed clauses" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error in File.Error -> {:error, error}
            error -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue -> assert issue.line_no === 7 end)
    end

    test "reports each nested try block on its own" do
      """
      defmodule MyApp.Worker do
        def load(path) do
          try do
            try do
              File.read!(path)
            rescue
              _ -> :inner
            end
          rescue
            _ -> :outer
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [7, 10]
      end)
    end
  end

  describe "&run/2 flags blanket rescues on the implicit def rescue form" do
    test "reports a bare variable rescue on def" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          File.read!(path)
        rescue
          error -> {:error, error}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.message =~ "rescue error found"
      end)
    end

    test "reports rescue _ on defp" do
      """
      defmodule MyApp.Worker do
        defp read_file(path) do
          File.read!(path)
        rescue
          _ -> :error
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports each def with its own line number" do
      """
      defmodule MyApp.Worker do
        def one(path) do
          File.read!(path)
        rescue
          _ -> :error
        end

        def two(path) do
          File.read!(path)
        rescue
          _ -> :error
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [5, 11]
      end)
    end
  end

  describe "&run/2 allows typed rescue clauses" do
    test "does not report rescuing a specific exception module" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error in File.Error -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report rescuing a list of exception modules" do
      """
      defmodule MyApp.Worker do
        def parse(input) do
          try do
            String.to_integer(input)
          rescue
            error in [File.Error, ArgumentError] -> {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a bare exception module pattern" do
      """
      defmodule MyApp.Worker do
        def parse(input) do
          try do
            String.to_integer(input)
          rescue
            ArgumentError -> :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a typed rescue on the implicit def rescue form" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          File.read!(path)
        rescue
          error in File.Error -> {:error, error}
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report code without any rescue" do
      """
      defmodule MyApp.Worker do
        def read_file(path), do: File.read(path)
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end
  end

  describe "&run/2 allows blanket rescues that handle the exception" do
    test "does not report a clause that logs the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error ->
              Logger.error(inspect(error))
              {:error, error}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a clause that reraises" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error -> reraise error, __STACKTRACE__
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a clause that raises a wrapping exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error -> raise MyApp.WrapperError, original: error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a def rescue clause that logs the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          File.read!(path)
        rescue
          error ->
            Logger.error(inspect(error))
            :error
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end

    test "does not report a recovery call nested deeper in the clause body" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error ->
              if verbose?() do
                Logger.error(inspect(error))
              end

              :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :allowed_recovery_calls param" do
    test "treats a custom module as handling the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error ->
              Sentry.capture_exception(error)
              :error
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue, allowed_recovery_calls: [:reraise, :raise, Logger, Sentry])
      |> refute_issues()
    end

    test "treats a custom local function as handling the exception" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error -> report_error(error)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue,
        allowed_recovery_calls: [:reraise, :raise, Logger, :report_error]
      )
      |> refute_issues()
    end

    test "flags a reraise once reraise is no longer allowed" do
      """
      defmodule MyApp.Worker do
        def read_file(path) do
          try do
            File.read!(path)
          rescue
            error -> reraise error, __STACKTRACE__
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoBlanketRescue, allowed_recovery_calls: [])
      |> assert_issue(fn issue -> assert issue.message =~ "rescue error found" end)
    end
  end
end
