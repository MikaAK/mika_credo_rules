# credo:disable-for-this-file MikaCredoRules.NoDirectHttpClient
defmodule MikaCredoRules.NoDirectHttpClient do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      modules: [Finch, HTTPoison, Tesla, Req],
      erlang_modules: [:httpc, :hackney],
      excluded_paths: ["shared_utils/", "_api/"]
    ],
    explanations: [
      params: [
        modules: """
        A list of Elixir HTTP client modules to ban. Any reference to one of
        these — `import`, `alias`, `use`, or a remote call — is reported.

        Module names are matched on their exact segments with full alias
        resolution, so a project module that merely contains a banned name
        (`MyApp.ReqIssueTracker`) is never flagged.
        """,
        erlang_modules: """
        A list of erlang HTTP client module atoms to ban. Any remote call on
        one of these (`:httpc.request/1`, `:hackney.get/1`, ...) is reported.
        """,
        excluded_paths: """
        A list of path fragments. A source file is exempt when its path starts
        or ends with a fragment, or contains one after a `/` — matching
        happens on path-segment boundaries, so `_api/` does not exempt
        `lib/vendor/rest_api_notes/`.

        Defaults to `["shared_utils/", "_api/"]`, exempting the shared HTTP
        wrapper and the conventional dedicated `*_api` wrapper-app layer.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Direct HTTP client libraries must not be used — call the app's HTTP wrapper
  instead.

  Scattered `Finch`, `HTTPoison`, `Tesla`, or `Req` calls duplicate pooling,
  header, and error-mapping logic that `SharedUtils.HTTP` already provides.
  Route every external HTTP call through the wrapper so retries, sandboxing in
  tests, and error mapping happen in one place.

      # BAD — in a context module
      Finch.build(:get, url) |> Finch.request(MyFinch)

      # GOOD
      SharedUtils.HTTP.get(url, headers)

  `use Tesla` and alias-free calls (`Finch.build/3` with no prior `alias`) are
  caught the same way as an explicit alias — every AST spelling of a banned
  module is checked, not just qualified remote calls.

  Files under `:excluded_paths` (default `["shared_utils/", "_api/"]`) are
  exempt — those are the layers meant to hold direct client calls: the shared
  wrapper itself, and a dedicated `*_api` app matching that exact path
  segment. A whole app directory that merely *ends* in `_api` (`tiingo_api/`)
  is matched only when the fragment appears at a path-segment boundary — add
  such an app's own name to `:excluded_paths` to exempt it specifically.

  ## Limitations

  `Credo.Check.Warning.ForbiddenModule` (a stock Credo check) can ban the same
  modules by name, but it is alias-blind — `alias Req, as: R; R.get(url)`
  evades it — and has no path-exemption mechanism, so it can't distinguish the
  wrapper layer from its callers. This check exists for alias resolution, path
  exemptions, and a message that points at the fix.
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
    banned = Params.get(params, :modules, __MODULE__)

    %{
      module_segments: AstHelpers.resolve_aliases(source_file, banned),
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__)
    }
  end

  # `alias MyApp.{Req, Foo}` — the inner aliases are relative to the base, so
  # check the expanded names and prune the node to keep the bare `[:Req]`
  # fragment from being matched on its own.
  defp traverse(
         {{:., _, [{:__aliases__, _, base}, :{}]}, _meta, inner_nodes},
         references,
         context
       ) do
    references =
      Enum.reduce(inner_nodes, references, fn
        {:__aliases__, inner_meta, inner}, acc ->
          maybe_reference(base ++ inner, inner_meta, acc, context)

        _other, acc ->
          acc
      end)

    {nil, references}
  end

  # `alias Req, as: R` — only the target is a library reference; prune the
  # node so the `as:` name is not reported a second time on the same line.
  defp traverse({:alias, _, [{:__aliases__, meta, target}, opts]}, references, context)
       when is_list(opts) do
    {nil, maybe_reference(target, meta, references, context)}
  end

  # A remote call whose module resolves to a banned client — report the full
  # call (with function and arity) and prune the subtree so the generic
  # `__aliases__` clause below doesn't also flag the bare module name.
  defp traverse(
         {{:., _, [{:__aliases__, meta, module_segments}, function]}, _call_meta, args} = ast,
         references,
         context
       )
       when is_list(args) do
    if strip_elixir_prefix(module_segments) in context.module_segments do
      trigger = "#{Enum.join(module_segments, ".")}.#{function}/#{length(args)}"
      {nil, [reference(trigger, meta) | references]}
    else
      {ast, references}
    end
  end

  defp traverse({:__aliases__, meta, module_segments} = ast, references, context) do
    {ast, maybe_reference(module_segments, meta, references, context)}
  end

  defp traverse({{:., _, [erlang_module, function]}, meta, args} = ast, references, context)
       when is_atom(erlang_module) and is_list(args) do
    if erlang_module in context.erlang_modules do
      trigger = "#{inspect(erlang_module)}.#{function}/#{length(args)}"
      {ast, [reference(trigger, meta) | references]}
    else
      {ast, references}
    end
  end

  defp traverse(ast, references, _context), do: {ast, references}

  defp maybe_reference(module_segments, meta, references, context) do
    if strip_elixir_prefix(module_segments) in context.module_segments do
      [reference(Enum.join(module_segments, "."), meta) | references]
    else
      references
    end
  end

  defp strip_elixir_prefix([Elixir | module_segments]), do: module_segments
  defp strip_elixir_prefix(module_segments), do: module_segments

  defp reference(trigger, meta), do: %{trigger: trigger, line_no: meta[:line]}

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reference.trigger} found — call your app's HTTP wrapper instead " <>
          "(e.g. SharedUtils.HTTP.get/post/put/delete)",
      trigger: reference.trigger,
      line_no: reference.line_no
    )
  end
end
