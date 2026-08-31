# credo:disable-for-this-file MikaCredoRules.NoDirectHttpClient
defmodule MikaCredoRules.NoDirectHttpClient do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: [
        {Finch, [:build, :request, :request!, :stream]},
        {HTTPoison,
         [
           :get,
           :get!,
           :post,
           :post!,
           :put,
           :put!,
           :patch,
           :patch!,
           :delete,
           :delete!,
           :head,
           :head!,
           :options,
           :options!,
           :request,
           :request!
         ]},
        {Tesla,
         [
           :get,
           :get!,
           :post,
           :post!,
           :put,
           :put!,
           :patch,
           :patch!,
           :delete,
           :delete!,
           :head,
           :head!,
           :options,
           :options!,
           :request
         ]},
        {Req,
         [
           :get,
           :get!,
           :post,
           :post!,
           :put,
           :put!,
           :patch,
           :patch!,
           :delete,
           :delete!,
           :head,
           :head!,
           :request,
           :request!,
           :new
         ]}
      ],
      use_modules: [Tesla, HTTPoison.Base, Tesla.Builder],
      erlang_modules: [:httpc, :hackney],
      excluded_paths: ["shared_utils/"],
      excluded_app_suffixes: ["_api"]
    ],
    explanations: [
      params: [
        functions: """
        A list of `{module, functions}` pairs naming the request-making
        functions banned on each Elixir HTTP client, alias-aware. Only these
        functions are flagged — a bare reference to the module elsewhere
        (a supervision child spec, a typespec, a middleware continuation
        call) is left alone.
        """,
        use_modules: """
        A list of modules whose `use` idiom builds an HTTP client outright,
        alias-aware. Defaults to `[Tesla, HTTPoison.Base, Tesla.Builder]`.
        """,
        erlang_modules: """
        A list of erlang HTTP client module atoms to ban. Any remote call on
        one of these (`:httpc.request/1`, `:hackney.get/1`, ...) is reported.
        """,
        excluded_paths: """
        A list of path fragments. A source file is exempt when its path starts
        or ends with a fragment, or contains one after a `/` — matching
        happens on path-segment boundaries.

        Defaults to `["shared_utils/"]`, exempting the shared HTTP wrapper.
        """,
        excluded_app_suffixes: """
        A list of app-directory-name suffixes. A source file is exempt when
        any path segment ends with one of these suffixes — matching a whole
        app directory name (`tiingo_api/`), never a fragment in the middle of
        a segment (`rest_api_notes/`).

        Defaults to `["_api"]`, exempting the conventional dedicated `*_api`
        wrapper-app layer.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Direct HTTP client libraries must not be used to make requests — call the
  app's HTTP wrapper instead.

  Scattered `Finch`, `HTTPoison`, `Tesla`, or `Req` request calls duplicate
  pooling, header, and error-mapping logic that `SharedUtils.HTTP` already
  provides. Route every external HTTP call through the wrapper so retries,
  sandboxing in tests, and error mapping happen in one place.

      # BAD — in a context module
      Finch.build(:get, url) |> Finch.request(MyFinch)

      # GOOD
      SharedUtils.HTTP.get(url, headers)

  Building a client with `use Tesla`, `use HTTPoison.Base`, or
  `use Tesla.Builder` is caught the same way as a request call — these are the
  documented client-building idioms of each library, not just a low-level
  function call:

      # BAD — builds a raw client
      defmodule MyApp.Client do
        use Tesla
      end

  Only the functions that actually make a request are banned (see the
  `:functions` param for the full default list per module). A bare reference
  to the module elsewhere is left alone, because it is either required to
  reach the wrapper or has no wrapper equivalent at all:

      # not flagged — starting the pool the wrapper depends on
      children = [{Finch, name: MyApp.Finch}]

      # not flagged — the mandated Tesla middleware continuation, no wrapper
      # equivalent exists for it
      defmodule MyApp.Middleware.Logger do
        @behaviour Tesla.Middleware

        @impl Tesla.Middleware
        def call(env, next, _opts), do: Tesla.run(env, next)
      end

  `@spec`/`@type`/`@typep`/`@opaque`/`@callback`/`@macrocallback` bodies are
  pruned entirely and never inspected, so a typespec referencing a banned
  module is never flagged either.

  Files under `:excluded_paths` (default `["shared_utils/"]`) are exempt on a
  fragment basis — the shared HTTP wrapper itself. Files whose app directory
  ends with one of `:excluded_app_suffixes` (default `["_api"]`) are exempt
  too — a dedicated `*_api` wrapper app (`tiingo_api/`) is exactly the layer
  meant to hold direct client calls. A lookalike directory that merely
  *contains* `_api` in the middle of a segment (`rest_api_notes/`) is not
  exempt — matching happens on the segment's own suffix.

  ## Limitations

  `Credo.Check.Warning.ForbiddenModule` (a stock Credo check) can ban the same
  modules by name, but it is alias-blind — `alias Req, as: R; R.get(url)`
  evades it — and has no path-exemption mechanism, so it can't distinguish the
  wrapper layer from its callers. This check exists for alias resolution, path
  exemptions, and a message that points at the fix.

  `alias Finch.{Request, Response}` then `Request.build(:get, url)` is
  undetected — the multi-alias clause resolves inner names against the base
  module's own alias table, which only ever gains single-segment entries for
  `Finch` itself, never for a two-segment submodule spelling. Same gap for
  `alias HTTPoison.Base`. A locally nested `defmodule Req do ... end` is not
  treated as shadowing, so `Req.get(url)` inside such a module can still fire.
  """
  @explanation [check: @moduledoc]

  @pruned_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_path?(filename, params) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)
    excluded_app_suffixes = Params.get(params, :excluded_app_suffixes, __MODULE__)

    SourceFilter.matches_fragment?(filename, excluded_paths) or
      SourceFilter.matches_segment_suffix?(filename, excluded_app_suffixes)
  end

  defp build_context(source_file, params) do
    banned_functions = Params.get(params, :functions, __MODULE__)
    use_modules = Params.get(params, :use_modules, __MODULE__)
    client_modules = Enum.map(banned_functions, fn {module, _functions} -> module end)

    %{
      function_bans: resolve_function_bans(source_file, banned_functions),
      use_module_paths: AstHelpers.resolve_aliases(source_file, use_modules),
      alias_target_paths: AstHelpers.resolve_aliases(source_file, client_modules),
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__)
    }
  end

  defp resolve_function_bans(source_file, banned_functions) do
    for {module, functions} <- banned_functions,
        module_path <- AstHelpers.resolve_aliases(source_file, [module]),
        function <- functions,
        into: MapSet.new(),
        do: {module_path, function}
  end

  # `@spec`/`@type`/`@callback` bodies are pruned entirely — a typespec
  # referencing a banned module (e.g. `Finch.request_ref()` as a return type)
  # is never inspected.
  defp traverse({:@, _, [{attribute, _, _}]}, references, _context)
       when attribute in @pruned_attributes do
    {nil, references}
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

  # `use Tesla` / `use HTTPoison.Base` / `use Tesla.Builder` — the
  # client-building idiom, reported the same as a banned function call.
  defp traverse(
         {:use, _, [{:__aliases__, meta, module_segments} | _rest]} = ast,
         references,
         context
       ) do
    if strip_elixir_prefix(module_segments) in context.use_module_paths do
      {nil, [reference(Enum.join(module_segments, "."), meta) | references]}
    else
      {ast, references}
    end
  end

  # A remote call whose module/function/arity is on the banned list — report
  # the full call and prune the subtree so no other clause re-examines it.
  defp traverse(
         {{:., _, [{:__aliases__, meta, module_segments}, function]}, _call_meta, args} = ast,
         references,
         context
       )
       when is_list(args) do
    if {strip_elixir_prefix(module_segments), function} in context.function_bans do
      trigger = "#{Enum.join(module_segments, ".")}.#{function}/#{length(args)}"
      {nil, [reference(trigger, meta) | references]}
    else
      {ast, references}
    end
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
    if strip_elixir_prefix(module_segments) in context.alias_target_paths do
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
