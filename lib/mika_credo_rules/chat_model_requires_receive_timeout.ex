defmodule MikaCredoRules.ChatModelRequiresReceiveTimeout do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      modules: [
        LangChain.ChatModels.ChatOpenAI,
        LangChain.ChatModels.ChatAnthropic,
        LangChain.ChatModels.ChatGoogleAI
      ],
      functions: [:new, :new!],
      required_keys: [:receive_timeout],
      excluded_paths: []
    ],
    explanations: [
      params: [
        modules: """
        A list of chat model modules whose config map is checked. Alias-aware,
        like every module-identity param in this package.
        """,
        functions: """
        A list of atoms naming the constructor functions to check. Defaults to
        `[:new, :new!]`.
        """,
        required_keys: """
        A list of keys that must ALL appear in the literal config map; any
        missing key is reported. Defaults to `[:receive_timeout]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Chat model constructors must set `:receive_timeout` — the LangChain default
  leaves long prompts to hang indefinitely.

      # BAD — no receive_timeout, long prompts hang indefinitely
      LangChain.ChatModels.ChatOpenAI.new!(%{model: "gpt-4o", stream: true})

      # GOOD
      LangChain.ChatModels.ChatOpenAI.new!(%{
        model: "gpt-4o",
        stream: true,
        receive_timeout: 120_000
      })

  Only a literal map argument is inspected — a config built in a variable or
  through `Map.merge/2` is invisible to this check (an accepted false
  negative; static analysis cannot know its runtime shape). This also means
  there are no false positives: nothing is reported unless the check can see
  the literal keys itself.

  `ChatAnthropic` and `ChatGoogleAI` are checked by default alongside
  `ChatOpenAI`; add a project's own wrapper through the `:modules` param.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack. Aliases injected by a macro (via `__using__`) are invisible to
  Credo and cannot be resolved.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    %{
      modules: AstHelpers.resolve_aliases(source_file, Params.get(params, :modules, __MODULE__)),
      functions: Params.get(params, :functions, __MODULE__),
      required_keys: Params.get(params, :required_keys, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, [config]} = ast,
         issues,
         context
       ) do
    if module in context.modules and function in context.functions do
      case missing_keys(config, context.required_keys) do
        [] -> {ast, issues}
        missing -> {ast, [chat_model_call(module, function, alias_meta, missing) | issues]}
      end
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  defp missing_keys({:%{}, _, [{:|, _, _} | _rest]}, _required_keys), do: []

  defp missing_keys({:%{}, _, pairs}, required_keys) when is_list(pairs) do
    present_keys = for {key, _value} <- pairs, do: key
    Enum.reject(required_keys, &(&1 in present_keys))
  end

  defp missing_keys(_config, _required_keys), do: []

  defp chat_model_call(module, function, meta, missing_keys) do
    %{
      trigger: "#{Enum.join(module, ".")}.#{function}",
      line_no: meta[:line],
      column: meta[:column],
      missing_keys: missing_keys
    }
  end

  defp issue_for(call, issue_meta) do
    missing_keys = Enum.map_join(call.missing_keys, ", ", &inspect/1)

    format_issue(issue_meta,
      message:
        "#{call.trigger} found — missing #{missing_keys}; long prompts hang indefinitely without an explicit timeout",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
