defmodule MikaCredoRules.ExceptionNamesEndInErrorTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.ExceptionNamesEndInError

  @lib_file "apps/my_app/lib/my_app/bad_http_code.ex"

  describe "&run/2 flags exception modules whose name does not end in the suffix" do
    test "reports a defexception module named without the Error suffix" do
      """
      defmodule BadHTTPCode do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> assert_issue(fn issue ->
        assert issue.line_no === 1
        assert issue.column === 11
        assert issue.trigger === "BadHTTPCode"
        assert issue.message =~ "BadHTTPCode found"
        assert issue.message =~ "must end in \"Error\""
      end)
    end

    test "reports the last segment of a namespaced module" do
      """
      defmodule MyApp.Errors.BadHTTPCode do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.Errors.BadHTTPCode" end)
    end
  end

  describe "&run/2 does not flag correctly-named exceptions" do
    test "does not report a module already ending in Error" do
      """
      defmodule BadHTTPCodeError do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end

    test "does not report a plain module without defexception" do
      """
      defmodule BadHTTPCode do
        defstruct [:code]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes per defmodule, not per file" do
    test "reports each exception module independently" do
      """
      defmodule FirstBad do
        defexception [:message]
      end

      defmodule SecondBadError do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> assert_issue(fn issue -> assert issue.trigger === "FirstBad" end)
    end

    test "reports a nested defexception module inside a plain module" do
      """
      defmodule MyApp do
        defmodule BadHTTPCode do
          defexception [:message]
        end

        def helper, do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "does not report a plain module sharing a file with an exception" do
      """
      defmodule MyApp.Helper do
        def run, do: :ok
      end

      defmodule MyApp.BadHTTPCodeError do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end
  end

  describe "&run/2 skips defexception inside quote blocks" do
    test "does not report a defexception generated inside a quote" do
      """
      defmodule MyApp.ExceptionBuilder do
        defmacro __using__(_opts) do
          quote do
            defexception [:message]
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end

    test "does not report a nested defmodule template generated inside a quote" do
      """
      defmodule MyApp.ExceptionBuilder do
        defmacro __using__(_opts) do
          quote do
            defmodule Foo do
              defexception [:message]
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end
  end

  describe "&run/2 honors :suffix" do
    test "reports against a custom suffix" do
      """
      defmodule BadHTTPCode do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError, suffix: "Exception")
      |> assert_issue(fn issue -> assert issue.message =~ "must end in \"Exception\"" end)
    end

    test "does not report a name ending in a custom suffix" do
      """
      defmodule BadHTTPCodeException do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError, suffix: "Exception")
      |> refute_issues()
    end
  end

  describe "&run/2 honors :excluded_paths" do
    test "does not report inside an excluded path" do
      """
      defmodule BadHTTPCode do
        defexception [:message]
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/vendor/bad_http_code.ex")
      |> run_check(ExceptionNamesEndInError, excluded_paths: ["vendor/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "reports the moduledoc BAD example" do
      """
      defmodule BadHTTPCode do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> assert_issue()
    end

    test "does not report the moduledoc GOOD example" do
      """
      defmodule BadHTTPCodeError do
        defexception [:message]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ExceptionNamesEndInError)
      |> refute_issues()
    end
  end
end
