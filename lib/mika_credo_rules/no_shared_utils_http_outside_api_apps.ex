defmodule MikaCredoRules.NoSharedUtilsHTTPOutsideApiApps do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      modules: [SharedUtils.HTTP],
      functions: [:get, :post, :patch, :delete, :request],
      allowed_paths: ["_api/", "shared_utils/", "_test.exs", "test/"]
    ],
    explanations: [
      params: [
        modules: """
        A list of modules banned as the shared HTTP transport, alias-aware
        (see `AstHelpers.resolve_aliases/2` — a plain alias, an `as:` rename,
        and shadowing by a project's own same-named module are all
        resolved). Only a call whose function name is also in `:functions`
        is flagged — see that param. A defmodule whose own body declares
        `@behaviour` naming one of these modules is the wrapper itself and is
        exempt entirely, regardless of path (see the moduledoc). A
        non-Elixir-module entry (a string, or an erlang-style atom such as
        `:maps`) is silently ignored rather than raising. Defaults to
        `[SharedUtils.HTTP]`.
        """,
        functions: """
        A list of function names that count as making a request. A bare
        reference to a matched module elsewhere — a supervision child spec,
        the Tesla-client-builder call the wrapper itself is built from, a
        typespec — is left alone, because it either has no wrapper
        equivalent or the wrapper must reach it to exist in the first place.

        Defaults to `[:get, :post, :patch, :delete, :request]` — the request
        verbs `SharedUtils.HTTP` actually delegates to Tesla.
        """,
        allowed_paths: """
        A list of path fragments naming files this check skips. An entry is
        matched two ways:

          * as a path fragment at a segment boundary (see
            `SourceFilter.matches_fragment?/2`) — the file's path starts
            with it, ends with it, or contains it right after a `/`.
          * additionally, when the entry starts with `_`, as an app-directory
            NAME SUFFIX (see `SourceFilter.matches_segment_suffix?/2`) — any
            path segment ending in that suffix counts, not only a segment
            literally equal to it. This is what lets the default `"_api/"`
            exempt a conventionally named wrapper app such as `tiingo_api/`
            or `git_hub_api/`, not only a directory literally named `_api`.

        Defaults to `["_api/", "shared_utils/", "_test.exs", "test/"]` — the
        `*_api` wrapper-app layer, `shared_utils` itself, and tests.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `SharedUtils.HTTP` is the shared HTTP transport — domain code must call its
  app's dedicated `*_api` wrapper module instead of reaching for the
  transport directly.

  Calling the transport from ordinary domain code bypasses whatever auth
  headers, base URL, and error mapping the wrapper app centralizes, and
  couples every caller to the transport's raw request/response shape
  instead of a stable per-service contract.

      # BAD — domain code calls the transport directly
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get("https://example.com/courses/\#{id}", [])
        end
      end

      # GOOD — domain code calls its app's dedicated wrapper
      defmodule MyApp.Courses do
        def fetch(id) do
          MyApp.CoursesApi.fetch(id)
        end
      end

  Aliasing the transport doesn't help — the alias is resolved back to the
  banned module before matching, the same as a fully qualified call:

      # BAD — aliased, still the transport
      defmodule MyApp.Courses do
        alias SharedUtils.HTTP

        def enroll(id) do
          HTTP.post("https://example.com/courses/\#{id}/enroll", %{})
        end
      end

  Only files under one of `:allowed_paths` are exempt — a dedicated `*_api`
  wrapper app (`git_hub_api/`) is exactly the layer meant to call the
  transport, and `shared_utils` itself obviously has to. See the
  `:allowed_paths` param for the matching rules, including the app-suffix
  convention that lets `"_api/"` exempt `git_hub_api/` and not merely a
  directory literally named `_api`.

  Only the functions that actually make a request are banned (see the
  `:functions` param for the full default list). A bare reference to the
  module elsewhere is left alone, because it is either required to reach
  the wrapper or has no wrapper equivalent at all:

      # not flagged — building the Finch pool child spec and the Tesla
      # client the wrapper itself is built from
      defmodule MyApp.Http do
        def child_spec(opts), do: SharedUtils.HTTP.child_spec(opts)
        def new(opts), do: SharedUtils.HTTP.client([], nil, opts)
      end

  A defmodule whose own body declares `@behaviour SharedUtils.HTTP` — the
  sanctioned shape for building a wrapper, documented in `SharedUtils.HTTP`'s
  own moduledoc — IS the wrapper, so its request-verb calls are exempt
  entirely, even outside an `*_api` path:

      # not flagged — this module is the wrapper being built
      defmodule MyApp.VendorClient do
        @behaviour SharedUtils.HTTP

        @impl SharedUtils.HTTP
        def new(opts), do: SharedUtils.HTTP.client([], nil, opts)

        def fetch(url), do: SharedUtils.HTTP.get(new(), url, [])
      end

  A module with the identical shape but no `@behaviour` declaration is not
  recognized as a wrapper and is still flagged — only the literal attribute
  is honoured, never the file's naming or intent.

  `@spec`/`@type`/`@typep`/`@opaque`/`@callback`/`@macrocallback` bodies are
  pruned entirely and never inspected, so a typespec referencing the
  transport module is never flagged either:

      # not flagged — a typespec, not a call
      @spec fetch(String.t()) :: SharedUtils.HTTP.http_response(map())

  ## Limitations

    * Only the `__aliases__` call shape is matched. The Elixir-prefixed atom
      spelling (`:"Elixir.SharedUtils.HTTP".get(url)`) and `apply/3` dynamic
      dispatch are both invisible.
    * A transport reference injected as a dependency (`@http.get(url)`, or a
      variable holding the module) carries no module segments to resolve
      and is invisible — only a literal alias or fully qualified call is
      matched.
    * A locally nested `defmodule HTTP do ... end` is not treated as
      shadowing a single-segment `:modules` override — see
      `AstHelpers.resolve_aliases/2`.
    * The `@behaviour` wrapper exemption is a literal-attribute match: a
      module that merely has the same shape as a wrapper (calls the
      transport from a `new/1`-style function) but never writes
      `@behaviour <one of :modules>` is still flagged.
    * Only calls inside a `defmodule` body are collected. A call at the top
      level of a `.exs` script, or inside a `defimpl` block, is outside any
      `defmodule` scope and is invisible.
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

      modules =
        params
        |> Params.get(:modules, __MODULE__)
        |> List.wrap()
        |> Enum.filter(&elixir_module?/1)

      module_paths = AstHelpers.resolve_aliases(source_file, modules)
      functions = List.wrap(Params.get(params, :functions, __MODULE__))

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, module_paths, functions))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_path?(filename, params) do
    allowed_paths = List.wrap(Params.get(params, :allowed_paths, __MODULE__))

    SourceFilter.matches_fragment?(filename, allowed_paths) or
      SourceFilter.matches_segment_suffix?(filename, app_suffix_patterns(allowed_paths))
  end

  defp app_suffix_patterns(allowed_paths) do
    Enum.filter(allowed_paths, &String.starts_with?(&1, "_"))
  end

  defp elixir_module?(module) when is_atom(module) do
    String.starts_with?(Atom.to_string(module), "Elixir.")
  end

  defp elixir_module?(_other), do: false

  # The check is scoped per defmodule, not per file: a wrapper module — one
  # whose own body declares `@behaviour <one of module_paths>` — IS the
  # transport wrapper, so its own calls are never collected. A nested
  # defmodule (wrapper or not) is a separate scope, visited independently
  # when the outer prewalk reaches it on its own.
  defp traverse(
         {:defmodule, _, [_name, [{:do, body} | _]]} = ast,
         calls,
         module_paths,
         functions
       ) do
    if wrapper_module?(body, module_paths) do
      {ast, calls}
    else
      {ast, collect_calls(body, module_paths, functions) ++ calls}
    end
  end

  defp traverse(ast, calls, _module_paths, _functions), do: {ast, calls}

  defp wrapper_module?(body, module_paths) do
    body
    |> Macro.prewalk(false, fn
      {:defmodule, _, _}, found ->
        {nil, found}

      {:quote, _, _}, found ->
        {nil, found}

      {:@, _, [{:behaviour, _, [{:__aliases__, _, segments}]}]} = node, found ->
        {node, found or segments in module_paths}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  # `@spec`/`@type`/`@callback` bodies are pruned entirely — a typespec
  # referencing a banned module (e.g. `SharedUtils.HTTP.t()` as a return
  # type) is never inspected. Nested defmodule bodies are pruned too — each
  # module owns exactly one scope, evaluated when the outer prewalk visits it.
  defp collect_calls(body, module_paths, functions) do
    body
    |> Macro.prewalk([], fn
      {:defmodule, _, _}, calls ->
        {nil, calls}

      {:@, _, [{attribute, _, _}]}, calls when attribute in @pruned_attributes ->
        {nil, calls}

      {{:., _, [{:__aliases__, meta, module_segments}, function]}, _call_meta, args} = node, calls
      when is_list(args) ->
        if module_segments in module_paths and function in functions do
          {node, [call("#{Enum.join(module_segments, ".")}.#{function}", meta) | calls]}
        else
          {node, calls}
        end

      node, calls ->
        {node, calls}
    end)
    |> elem(1)
  end

  defp call(trigger, meta), do: %{trigger: trigger, line_no: meta[:line], column: meta[:column]}

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — call your app's dedicated *_api wrapper module instead of the shared HTTP transport directly",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
