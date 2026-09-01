defmodule MikaCredoRules.ChatModelRequiresReceiveTimeoutTest do
  use Credo.Test.Case

  alias MikaCredoRules.ChatModelRequiresReceiveTimeout
  alias MikaCredoRules.DocExamples

  @lib_file "apps/my_app/lib/my_app/llm.ex"

  @moduledoc_examples ChatModelRequiresReceiveTimeout
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "ChatModelRequiresReceiveTimeout"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a literal map missing :receive_timeout" do
    test "reports LangChain.ChatModels.ChatOpenAI.new!/1" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o", stream: true})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "LangChain.ChatModels.ChatOpenAI.new!"
        assert issue.message =~ "receive_timeout"
      end)
    end

    test "reports .new/1 (no bang)" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new(%{model: "gpt-4o"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue(fn issue ->
        assert issue.trigger === "LangChain.ChatModels.ChatOpenAI.new"
      end)
    end

    test "reports under alias LangChain.ChatModels.ChatOpenAI" do
      """
      defmodule MyApp.LLM do
        alias LangChain.ChatModels.ChatOpenAI

        def chat_model, do: ChatOpenAI.new!(%{model: "gpt-4o", stream: true})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue(fn issue -> assert issue.trigger === "ChatOpenAI.new!" end)
    end

    test "reports ChatAnthropic.new!/1 by default" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatAnthropic.new!(%{model: "claude"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end

    test "reports ChatGoogleAI.new!/1 by default" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatGoogleAI.new!(%{model: "gemini"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end

    test "reports an empty map literal" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end
  end

  describe "&run/2 allows a map with :receive_timeout and non-literal args" do
    test "does not report a map literal that includes :receive_timeout" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o", receive_timeout: 60_000})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "does not report a variable argument" do
      """
      defmodule MyApp.LLM do
        def chat_model(opts), do: LangChain.ChatModels.ChatOpenAI.new!(opts)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "does not report a Map.merge/2 built config" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(Map.merge(%{model: "gpt-4o"}, extra()))
        defp extra, do: %{receive_timeout: 60_000}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "does not report a module not in :modules" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: OtherProvider.ChatOpenAI.new!(%{model: "gpt-4o"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "does not report when the module is shadowed by a project alias" do
      """
      defmodule MyApp.LLM do
        alias MyApp.ChatOpenAI

        def chat_model, do: ChatOpenAI.new!(%{model: "gpt-4o"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "respects a custom :required_keys" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o", receive_timeout: 1})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout, required_keys: [:model, :api_key])
      |> assert_issue(fn issue -> assert issue.message =~ "api_key" end)
    end

    test "does not report a string-keyed config carrying the required key" do
      """
      defmodule MyApp.LLM do
        def chat_model do
          LangChain.ChatModels.ChatOpenAI.new!(%{"model" => "gpt-4o", "receive_timeout" => 120_000})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> refute_issues()
    end

    test "reports a string-keyed config missing the required key" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{"model" => "gpt-4o"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue()
    end

    test "names the real LangChain default rather than claiming an indefinite hang" do
      """
      defmodule MyApp.LLM do
        def chat_model, do: LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o"})
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ChatModelRequiresReceiveTimeout)
      |> assert_issue(fn issue ->
        assert issue.message =~ "60_000"
        refute issue.message =~ "indefinitely"
      end)
    end
  end
end
