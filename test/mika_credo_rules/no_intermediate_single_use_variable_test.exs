defmodule MikaCredoRules.NoIntermediateSingleUseVariableTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoIntermediateSingleUseVariable

  @lib_file "apps/my_app/lib/my_app/config.ex"

  @moduledoc_examples NoIntermediateSingleUseVariable
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoIntermediateSingleUseVariable"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a variable bound once and used once, immediately after" do
    test "reports a `case var do` consumer (the spec's own example)" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)

          case provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "provider"
        assert issue.message =~ "bind-and-pass-once"
        assert issue.message =~ "Keyword.get(opts, :provider, default)"
      end)
    end

    test "reports a `f(var)` sole-argument consumer" do
      """
      defmodule MyApp.Reports do
        def summarize(account_id) do
          transactions = Ledger.list_transactions(account_id)
          render_summary(transactions)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "transactions"
        assert issue.message =~ "Ledger.list_transactions(account_id)"
      end)
    end

    test "reports a `Mod.f(var)` qualified sole-argument consumer" do
      """
      defmodule MyApp.Reports do
        def summarize(account_id) do
          transactions = Ledger.list_transactions(account_id)
          MyApp.Formatter.render(transactions)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "transactions" end)
    end

    test "reports a `var |> f()` pipe consumer" do
      """
      defmodule MyApp.Reports do
        def summarize(account_id) do
          transactions = Ledger.list_transactions(account_id)
          transactions |> render_summary()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "transactions" end)
    end

    test "reports an operator-expression right-hand side (call-shaped, not a literal)" do
      """
      defmodule MyApp.Reports do
        def label(alpha, beta) do
          name = alpha <> beta
          render(name)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "name" end)
    end

    test "reports a comparison right-hand side whose operands are variables, not literals" do
      """
      defmodule MyApp.Reports do
        def flagged?(alpha, beta) do
          flag = alpha == beta
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "flag" end)
    end

    test "reports a `var |> fun.()` anonymous-function-call pipe consumer" do
      """
      defmodule MyApp.Config do
        def go(opts, fun) do
          ids = load_ids(opts)
          ids |> fun.()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "ids" end)
    end

    test "reports a module-attribute right-hand side" do
      """
      defmodule MyApp.Config do
        @timeout 5_000

        def go(_opts) do
          limit = @timeout
          render(limit)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "limit" end)
    end

    test "reports a bare dot-field-access right-hand side" do
      """
      defmodule MyApp.Config do
        def go(assigns) do
          identifiers = assigns.ids
          render(identifiers)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "identifiers" end)
    end

    test "reports an anonymous-function-call right-hand side" do
      """
      defmodule MyApp.Config do
        def go(handler, payload) do
          result = handler.(payload)
          render(result)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "result" end)
    end

    test "reports a multi-stage pipe chain consumer" do
      """
      defmodule MyApp.Reports do
        def summarize(id) do
          rows = Repo.all(id)
          rows |> Enum.reverse() |> Enum.take(3)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "rows" end)
    end

    test "reports a `fun.(var)` anonymous-function-call consumer" do
      """
      defmodule MyApp.Config do
        def go(opts, fun) do
          ids = load_ids(opts)
          fun.(ids)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "ids" end)
    end

    test "reports a bind-and-pass-once pair inside a defmacro body" do
      """
      defmodule MyApp.Config do
        defmacro go(opts) do
          ids = load_ids(opts)
          render(ids)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "ids" end)
    end
  end

  describe "&run/2 stays silent on the closest lookalikes" do
    test "does not report a variable used twice after binding" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)
          log_provider(provider)
          provider
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report when the right-hand side is a case" do
      """
      defmodule MyApp.Config do
        def provider(opts) do
          provider =
            case opts[:mode] do
              :prod -> :ses
              _mode -> :local
            end

          handle_provider(provider)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report when the next statement uses var as a second argument" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)
          log_event(:provider_loaded, provider)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a right-hand side at or over :max_inline_length" do
      """
      defmodule MyApp.Config do
        def provider(opts) do
          provider = Keyword.get(opts, :really_long_provider_configuration_key_name, default_value)
          case provider do
            :ses -> MyApp.Mailer.SES
            _other -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a variable that is rebound later in the clause" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)

          case provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end

          provider = :overridden
          provider
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report an underscore-prefixed variable" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          _provider = Keyword.get(opts, :provider, default)

          case _provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a literal right-hand side" do
      """
      defmodule MyApp.Config do
        def provider(_opts) do
          provider = :ses

          case provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a binary literal right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = <<1, 2>>
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a sigil right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          label = ~s(hello world)
          render(label)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a ~D date-sigil right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          date = ~D[2024-01-01]
          render(date)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a unary-minus numeric literal right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          offset = -1
          render(offset)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a range literal right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          window = 1..10
          render(window)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a stepped-range literal right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          window = 1..10//2
          render(window)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report an arithmetic literal right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = 1 + 2
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a literal string-concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          label = "a" <> "b"
          render(label)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a literal list-concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          combined = [1] ++ [2]
          render(combined)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a nested arithmetic literal chain right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = 1 + 2 + 3
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a nested list-concatenation literal chain right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          combined = [1] ++ [2] ++ [3]
          render(combined)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a nested string-concatenation literal chain right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          label = "a" <> "b" <> "c"
          render(label)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a mixed-operator arithmetic literal chain right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = 1 + 2 * 3
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a unary-minus literal nested in a binary arithmetic expression" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = -1 + 2
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a comparison right-hand side on literal operands" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = 1 == 2
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a greater-than comparison right-hand side on literal operands" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = 1 > 2
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a boolean right-hand side on literal operands" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = true and false
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a unary-boolean right-hand side on a literal operand" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = not true
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a membership right-hand side on literal operands" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = :a in [:a, :b]
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a multi-stage pipe whose first hop takes an argument" do
      """
      defmodule MyApp.Reports do
        def summarize(id) do
          rows = Repo.all(id)
          rows |> Enum.take(3) |> Enum.reverse()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a multi-stage pipe when the variable reappears later in the chain" do
      """
      defmodule MyApp.Reports do
        def summarize(id) do
          rows = Repo.all(id)
          rows |> Enum.reverse() |> Enum.zip(rows)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a `fun.(var, extra)` anonymous-function call with more than one argument" do
      """
      defmodule MyApp.Config do
        def go(opts, fun) do
          ids = load_ids(opts)
          fun.(ids, :extra)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a capture right-hand side" do
      """
      defmodule MyApp.Config do
        def provider(_opts) do
          formatter = &to_string/1
          apply_formatter(formatter)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a binding whose next statement does not consume it at all" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end
  end

  describe "&run/2 stays silent on non-scalar literal operands inside an operator expression" do
    test "does not report a keyword-list concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          merged = [a: 1] ++ [b: 2]
          render(merged)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a map-literal equality right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = %{a: 1} == %{a: 1}
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report an empty-map equality right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = %{} == %{}
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a 2-tuple-literal equality right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          flag = {1, 2} == {1, 2}
          render(flag)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a list-of-2-tuples concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          merged = [{1, 2}] ++ [{3, 4}]
          render(merged)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a list-containing-a-map concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          merged = [%{a: 1}] ++ []
          render(merged)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a binary-literal concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          total = <<1, 2>> <> <<3>>
          render(total)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a date-sigil range right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          window = ~D[2024-01-01]..~D[2024-12-31]
          render(window)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a string-plus-sigil concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          label = "a" <> ~s(b)
          render(label)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "does not report a word-sigil-list concatenation right-hand side" do
      """
      defmodule MyApp.Config do
        def go(_opts) do
          words = ~w(a b) ++ ~w(c)
          render(words)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end
  end

  describe "&run/2 counts occurrences across the whole function clause, not just the body" do
    test "does not report a binding that rebinds a parameter the head still references" do
      """
      defmodule MyApp.Config do
        def build(opts) do
          opts = fetch_defaults()
          render(opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end

    test "still reports a rebound name that is not a parameter" do
      """
      defmodule MyApp.Config do
        def build(_opts) do
          local = fetch_defaults()
          render(local)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "local" end)
    end
  end

  describe "&run/2 respects :max_inline_length" do
    test "reports a normally-silent long right-hand side once the limit is raised" do
      """
      defmodule MyApp.Config do
        def provider(opts) do
          provider = Keyword.get(opts, :really_long_provider_configuration_key_name, default_value)
          case provider do
            :ses -> MyApp.Mailer.SES
            _other -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable, max_inline_length: 100)
      |> assert_issue(fn issue -> assert issue.trigger === "provider" end)
    end

    test "silences a normally-flagged binding once the limit is lowered" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)

          case provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable, max_inline_length: 10)
      |> refute_issues()
    end

    test "reports a right-hand side one character under the default :max_inline_length" do
      """
      defmodule MyApp.Config do
        def provider(opts) do
          provider = Keyword.get(opts, :providerxxxxxxxxxxxxxxxxxxxxxx, default)
          case provider do
            :ses -> MyApp.Mailer.SES
            _other -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.trigger === "provider" end)
    end

    test "does not report a right-hand side exactly at the default :max_inline_length" do
      """
      defmodule MyApp.Config do
        def provider(opts) do
          provider = Keyword.get(opts, :providerxxxxxxxxxxxxxxxxxxxxxxx, default)
          case provider do
            :ses -> MyApp.Mailer.SES
            _other -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the bound variable" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Config do
        def provider(opts, default) do
          provider = Keyword.get(opts, :provider, default)

          case provider do
            :ses -> MyApp.Mailer.SES
            :smtp -> MyApp.Mailer.SMTP
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives two bind-and-pass-once bindings on one line their own columns" do
      """
      defmodule MyApp.Config do
        def provider(opts, other) do
          first = Keyword.get(opts, :first); handle_first(first); second = Keyword.get(other, :second); handle_second(second)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIntermediateSingleUseVariable)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
