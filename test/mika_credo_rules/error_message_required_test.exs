defmodule MikaCredoRules.ErrorMessageRequiredTest do
  use Credo.Test.Case

  alias MikaCredoRules.ErrorMessageRequired

  @lib_file "lib/my_app/worker.ex"
  @test_file "test/my_app/worker_test.exs"

  describe "&run/2 flags string-literal error tuples" do
    test "reports a string-literal reason" do
      """
      defmodule MyApp.Worker do
        def create, do: {:error, "not found"}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ ~s({:error, "not found"})
        assert issue.trigger === ~s({:error, "not found"})
      end)
    end

    test "reports each construction with its own line number" do
      """
      defmodule MyApp.Worker do
        def one, do: {:error, "one"}
        def two, do: {:error, "two"}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3]
      end)
    end

    test "reports a construction inside a case clause body" do
      """
      defmodule MyApp.Worker do
        def create(params) do
          case validate(params) do
            :ok -> :ok
            :invalid -> {:error, "invalid params"}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end
  end

  describe "&run/2 allows structured and dynamic reasons" do
    test "does not report ErrorMessage constructors and structs" do
      """
      defmodule MyApp.Users do
        def missing(id), do: {:error, ErrorMessage.not_found("no user", %{id: id})}
        def invalid, do: {:error, %ErrorMessage{code: :bad_request, message: "invalid"}}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report a variable reason" do
      """
      defmodule MyApp.Users do
        def update(changeset), do: {:error, changeset}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report an atom reason by default" do
      """
      defmodule MyApp.Users do
        def fetch, do: {:error, :timeout}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report reasons built at runtime" do
      """
      defmodule MyApp.Users do
        def interpolated(reason), do: {:error, "failed: \#{inspect(reason)}"}
        def concatenated(prefix), do: {:error, prefix <> " failed"}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :also_flag_atoms param" do
    test "flags an atom reason when enabled" do
      """
      defmodule MyApp.Users do
        def fetch, do: {:error, :timeout}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired, also_flag_atoms: true)
      |> assert_issue(fn issue -> assert issue.message =~ "{:error, :timeout}" end)
    end

    test "keeps flagging string literals alongside atoms" do
      """
      defmodule MyApp.Users do
        def fetch, do: {:error, :timeout}
        def create, do: {:error, "boom"}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired, also_flag_atoms: true)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end
  end

  describe "&run/2 does not flag matching on error tuples" do
    test "does not report case clause patterns" do
      """
      defmodule MyApp.Worker do
        def handle do
          case ThirdParty.call() do
            {:error, "expired"} -> :retry
            other -> other
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report function head patterns" do
      """
      defmodule MyApp.Worker do
        def unwrap({:error, "not found"}), do: nil
        def unwrap(other), do: other
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report match and with-clause patterns" do
      """
      defmodule MyApp.Worker do
        def check do
          {:error, "boom"} = ThirdParty.call()
          with {:error, "nope"} <- ThirdParty.fetch(), do: :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag keyword and map pairs" do
    test "does not report error: keys in maps and keyword lists" do
      """
      defmodule MyApp.Worker do
        def render, do: %{error: "not found"}
        def opts, do: [error: "not found", retry: true]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 skips excluded files" do
    test "does not report inside a test file" do
      """
      defmodule MyApp.WorkerTest do
        def fixture, do: {:error, "not found"}
      end
      """
      |> to_source_file(@test_file)
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "does not report inside an umbrella test support file" do
      """
      defmodule MyApp.Support.Fixtures do
        def error, do: {:error, "not found"}
      end
      """
      |> to_source_file("apps/my_app/test/support/fixtures.ex")
      |> run_check(ErrorMessageRequired)
      |> refute_issues()
    end

    test "treats a custom path fragment as excluded" do
      """
      defmodule MyApp.Legacy do
        def fetch, do: {:error, "not found"}
      end
      """
      |> to_source_file("lib/my_app/legacy.ex")
      |> run_check(ErrorMessageRequired, excluded_files: ["legacy.ex"])
      |> refute_issues()
    end

    test "flags a test file once :excluded_files is emptied" do
      """
      defmodule MyApp.WorkerTest do
        def fixture, do: {:error, "not found"}
      end
      """
      |> to_source_file(@test_file)
      |> run_check(ErrorMessageRequired, excluded_files: [])
      |> assert_issue()
    end
  end
end
