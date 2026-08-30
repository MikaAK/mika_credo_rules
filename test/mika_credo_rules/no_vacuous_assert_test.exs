defmodule MikaCredoRules.NoVacuousAssertTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoVacuousAssert

  @test_file "apps/my_app/test/my_app/orders_test.exs"
  @lib_file "apps/my_app/lib/my_app/orders.ex"

  describe "&run/2 flags assert on a truthy literal" do
    test "reports assert true" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "assert true"
        assert issue.message =~ "assert a behaviour, not a literal"
      end)
    end

    test "reports assert with an atom literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert :ok
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert :ok" end)
    end

    test "reports assert with a number literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert 1
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert 1" end)
    end

    test "reports assert with zero, since zero is truthy in Elixir" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert 0
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert 0" end)
    end

    test "reports assert with a string literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert "ok"
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ ~s(assert "ok") end)
    end

    test "reports assert with a list literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert [1, 2, 3]
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert [1, 2, 3]" end)
    end

    test "reports assert with a tuple literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert {1, 2}
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert {1, 2}" end)
    end

    test "reports assert with a map literal" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert %{a: 1}
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert %{a: 1}" end)
    end
  end

  describe "&run/2 flags refute on a falsy literal" do
    test "reports refute false" do
      """
      defmodule MyApp.OrdersTest do
        test "never fails" do
          refute false
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "refute false" end)
    end

    test "reports refute nil" do
      """
      defmodule MyApp.OrdersTest do
        test "never fails" do
          refute nil
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "refute nil" end)
    end
  end

  describe "&run/2 flags assert x === x / assert x == x" do
    test "reports assert x === x with a variable" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert x === x
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert x === x" end)
    end

    test "reports assert x == x with a variable" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert x == x
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue(fn issue -> assert issue.message =~ "assert x == x" end)
    end

    test "reports identical call expressions on both sides" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert Orders.status(order) === Orders.status(order)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issue()
    end
  end

  describe "&run/2 ignores real assertions" do
    test "does not report assert on a function call" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          assert Orders.create(attrs)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end

    test "does not report assert on a bare variable" do
      """
      defmodule MyApp.OrdersTest do
        test "checks a computed value" do
          assert result
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end

    test "does not report assert x === y with different variables" do
      """
      defmodule MyApp.OrdersTest do
        test "compares two values" do
          assert x === y
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end

    test "does not report assert with a real comparison to a value" do
      """
      defmodule MyApp.OrdersTest do
        test "checks status" do
          assert Orders.status(order) === :shipped
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end

    test "does not report refute on a function call" do
      """
      defmodule MyApp.OrdersTest do
        test "rejects invalid orders" do
          refute Orders.valid?(order)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end

    test "does not report assert nil (always-failing, not vacuous-true)" do
      """
      defmodule MyApp.OrdersTest do
        test "checks something" do
          assert nil
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores non-test files" do
    test "does not report assert true in a lib file" do
      """
      defmodule MyApp.Orders do
        def always_valid?(_order), do: assert(true)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :test_files param" do
    test "treats a custom suffix as a test file" do
      """
      defmodule MyApp.OrdersSpec do
        test "always passes" do
          assert true
        end
      end
      """
      |> to_source_file("apps/my_app/spec/my_app/orders_spec.exs")
      |> run_check(NoVacuousAssert, test_files: ["_spec.exs"])
      |> assert_issue()
    end

    test "no longer flags _test.exs files once :test_files is overridden" do
      """
      defmodule MyApp.OrdersTest do
        test "always passes" do
          assert true
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert, test_files: ["_spec.exs"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires on every line" do
      """
      defmodule MyApp.OrdersTest do
        test "vacuous" do
          assert true
          assert :ok
          refute false
          refute nil
          assert Orders.status(order) === Orders.status(order)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> assert_issues(fn issues -> assert length(issues) === 5 end)
    end

    test "moduledoc GOOD example is clean" do
      """
      defmodule MyApp.OrdersTest do
        test "checks status" do
          assert Orders.status(order) === :shipped
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoVacuousAssert)
      |> refute_issues()
    end
  end
end
