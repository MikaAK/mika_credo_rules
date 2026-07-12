defmodule MikaCredoRules.RefuteOverAssertNotTest do
  use Credo.Test.Case

  alias MikaCredoRules.RefuteOverAssertNot

  @test_file "apps/my_app/test/my_app/worker_test.exs"
  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags negated assertions in test files" do
    test "reports assert !" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert !valid?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "assert !"
        assert issue.message =~ "refute"
      end)
    end

    test "reports assert not" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert not valid?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "assert not"
        assert issue.message =~ "refute"
      end)
    end

    test "reports assert ! with a message argument" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert !valid?(), "input slipped through validation"
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> assert_issue(fn issue -> assert issue.message =~ "assert !" end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert !valid?()
          assert not accepted?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 4]
      end)
    end

    test "reports test files outside an umbrella" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert !valid?()
        end
      end
      """
      |> to_source_file("test/my_app/worker_test.exs")
      |> run_check(RefuteOverAssertNot)
      |> assert_issue()
    end
  end

  describe "&run/2 allows refute and positive assertions" do
    test "does not report refute" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          refute valid?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> refute_issues()
    end

    test "does not report assert on a positive expression" do
      """
      defmodule MyApp.WorkerTest do
        test "accepts valid input" do
          assert valid?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> refute_issues()
    end

    test "does not report negated comparison operators" do
      """
      defmodule MyApp.WorkerTest do
        test "values differ" do
          assert one() !== two()
          assert one() != two()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> refute_issues()
    end

    test "does not report assert not in" do
      """
      defmodule MyApp.WorkerTest do
        test "value is excluded" do
          assert value() not in [1, 2, 3]
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot)
      |> refute_issues()
    end
  end

  describe "&run/2 only runs on test files" do
    test "does not report assert ! in a lib file" do
      """
      defmodule MyApp.Worker do
        def check!(input) do
          assert !valid?(input)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(RefuteOverAssertNot)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :test_files param" do
    test "treats a custom filename suffix as a test file" do
      """
      defmodule MyApp.WorkerCheck do
        test "rejects invalid input" do
          assert !valid?()
        end
      end
      """
      |> to_source_file("apps/my_app/checks/worker_check.exs")
      |> run_check(RefuteOverAssertNot, test_files: ["_check.exs"])
      |> assert_issue()
    end

    test "skips _test.exs files once they are no longer in :test_files" do
      """
      defmodule MyApp.WorkerTest do
        test "rejects invalid input" do
          assert !valid?()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(RefuteOverAssertNot, test_files: ["_check.exs"])
      |> refute_issues()
    end
  end
end
