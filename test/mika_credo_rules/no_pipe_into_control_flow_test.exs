defmodule MikaCredoRules.NoPipeIntoControlFlowTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoPipeIntoControlFlow

  @lib_file "apps/my_app/lib/my_app/orders/pricing.ex"

  @moduledoc_examples NoPipeIntoControlFlow
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoPipeIntoControlFlow"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a pipe into case" do
    test "reports the pipe operator's line, a `|>` trigger, and a `|> case` message" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |> case do
            total when total > 100 -> total * 0.9
            total -> total
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "|>"
        assert issue.message =~ "|> case"
        assert issue.message =~ "bind"
      end)
    end

    test "reports a `|>` trigger for a paren-wrapped case (non-canonical spacing)" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |> (case do
            total -> total
          end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> case"
      end)
    end

    test "reports a `|>` trigger when the operator sits at end of line" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |>
            case do
              total -> total
            end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> case"
      end)
    end
  end

  describe "&run/2 flags a pipe into if/unless/cond/with" do
    test "reports a piped if" do
      """
      defmodule MyApp.Orders.Pricing do
        def eligible?(order) do
          order
          |> discount_amount()
          |> if do
            true
          else
            false
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "|>"
        assert issue.message =~ "|> if"
      end)
    end

    test "reports a piped unless" do
      """
      defmodule MyApp.Orders.Pricing do
        def skip_shipping?(order) do
          order
          |> shipping_cost()
          |> unless do
            true
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> unless"
      end)
    end

    test "reports a piped cond (parses but does not compile; pinned for constructs-list parity)" do
      """
      defmodule MyApp.Orders.Pricing do
        def tier(order) do
          order
          |> total_spent()
          |> cond do
            spent when spent > 1000 -> :gold
            true -> :standard
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> cond"
      end)
    end

    test "reports a piped with" do
      """
      defmodule MyApp.Orders.Pricing do
        def checkout(order) do
          order
          |> with {:ok, total} <- calculate_total(order) do
            total
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> with"
      end)
    end
  end

  describe "&run/2 allows the closest lookalikes" do
    test "does not report a bare case on an already-bound value" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          total = calculate_total(order)

          case total do
            total when total > 100 -> total * 0.9
            total -> total
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end

    test "does not report a pipe into then/2" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |> then(fn total -> if total > 100, do: total * 0.9, else: total end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end

    test "does not report a case nested inside a piped anonymous function" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discounts(orders) do
          orders
          |> Enum.map(fn order ->
            case order do
              %{total: total} when total > 100 -> total * 0.9
              %{total: total} -> total
            end
          end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end

    test "does not report a pipe chain without a control-flow tail" do
      """
      defmodule MyApp.Orders.Pricing do
        def normalize(order) do
          order
          |> calculate_total()
          |> Float.round(2)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> refute_issues()
    end
  end

  describe "&run/2 respects a :constructs override" do
    test "only flags the constructs listed in the param" do
      """
      defmodule MyApp.Orders.Pricing do
        def eligible?(order) do
          order
          |> discount_amount()
          |> if do
            true
          else
            false
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow, constructs: [:case])
      |> refute_issues()
    end

    test "still flags a construct that remains in the narrowed list" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          order
          |> calculate_total()
          |> case do
            total -> total
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow, constructs: [:case])
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> case"
      end)
    end
  end

  describe "&run/2 threads a real column so two triggers on one line differ" do
    test "gives each of two piped cases on one line its own column" do
      """
      defmodule MyApp.Orders.Pricing do
        def combine(first, second) do
          (first |> normalize() |> case(do: (x -> x))) <> (second |> normalize() |> case(do: (y -> y)))
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 finds a nested pipe-into-control-flow inside a branch body" do
    test "reports the inner pipe even though the outer case is bound first" do
      """
      defmodule MyApp.Orders.Pricing do
        def apply_discount(order) do
          total = calculate_total(order)

          case total do
            total when total > 100 ->
              total
              |> discounted()
              |> if do
                :discounted
              else
                :full_price
              end

            total ->
              total
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoPipeIntoControlFlow)
      |> assert_issue(fn issue ->
        assert issue.trigger === "|>"
        assert issue.message =~ "|> if"
      end)
    end
  end
end
