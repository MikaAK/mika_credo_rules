defmodule MikaCredoRules.HttpWrapperRequiresPoolName do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      attribute: :adapter,
      adapter_modules: [Tesla.Adapter.Finch],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        attribute: """
        The module attribute name that holds the Tesla adapter tuple, e.g.
        `@adapter {Tesla.Adapter.Finch, name: __MODULE__}`. Defaults to
        `:adapter` — the name every Finch-backed HTTP wrapper in this
        codebase uses.
        """,
        adapter_modules: """
        A list of adapter modules whose opts are checked for a dedicated pool
        `name:`, alias-aware (see `AstHelpers.resolve_aliases/2`). A
        non-Elixir-module entry (a string, or an erlang-style atom such as
        `:maps`) is silently ignored rather than raising. Defaults to
        `[Tesla.Adapter.Finch]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries, see `SourceFilter.matches_fragment?/2`). Defaults
        to `["_test.exs", "test/"]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A Finch-backed adapter attribute must carry a dedicated pool `name:`.

  `Tesla.Adapter.Finch.call/2` requires `:name` — it calls
  `Keyword.fetch!(opts, :name)`, so an adapter tuple with no `name:` (or no
  opts at all) compiles cleanly but raises `KeyError` the instant a request
  actually goes out. Setting `name: __MODULE__` on the `@adapter` attribute
  — matching a Finch pool started under that same name, typically via
  `SharedUtils.HTTP.child_spec(name: __MODULE__)` in the wrapper's own
  `child_spec/1` — is what keeps the attribute usable at runtime.

      # BAD — no opts at all, so nothing can carry name:
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end

      # BAD — literal opts present, but name: is missing
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, []}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end

      # GOOD — a dedicated pool
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, name: __MODULE__}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end

  Only the attribute's own opts position is ever inspected. When it is a
  literal keyword list, it is checked for `:name` directly. When the whole
  attribute is just the bare adapter module — no tuple, no opts position on
  the attribute itself — the check assumes the house idiom holds (the full
  adapter tuple, `name:` included, lives on the attribute) and fires the
  same as an empty opts list. A call site that instead splices `name:`
  around the bare attribute (`{@adapter, name: __MODULE__}`) diverges from
  that idiom and is invisible to this check — see Limitations.

  This check targets the `@adapter` attribute itself and never a
  `SharedUtils.HTTP.get/post/delete/patch/request` call site. An earlier
  version of this spec proposed flagging those calls directly for a missing
  `name:` opt; that direction was dropped because `SharedUtils.HTTP`'s verb
  functions `defdelegate ..., to: Tesla`, and Tesla builds the request
  `Env` via `struct(Env, options ++ [...])` — `struct/2` silently drops any
  key it does not already define, so a bare `name:` at the top level of a
  call's opts list would be discarded rather than doing anything. The
  adapter tuple (or a per-request `opts: [adapter: [...]]`, see
  Limitations) is where a pool name actually has to live, which is why this
  check inspects `@adapter` instead. Call sites that route through
  `SharedUtils.HTTP` outside an API-wrapper app are covered by the sibling
  `NoSharedUtilsHTTPOutsideApiApps` check.

  A nested attribute or a computed value in that position is opaque to a
  static check — it might resolve to a keyword list carrying `name:` at
  runtime, so it is left alone rather than guessed at:

      # not flagged — opts comes from another attribute; its resolved shape
      # is invisible here
      defmodule MyApp.Courses do
        @default_adapter_opts [name: __MODULE__]
        @adapter {Tesla.Adapter.Finch, @default_adapter_opts}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end

  ## Limitations

    * Only a literal keyword list in the attribute's opts position is
      inspected — anything else there is silently skipped rather than
      guessed at, an accepted false negative even when it genuinely carries
      `name:` at runtime. This covers a nested attribute reference
      (`@adapter {Tesla.Adapter.Finch, @default_adapter_opts}`), a call
      result, and a literal list whose entries are not `key: value` pairs
      (`@adapter {Tesla.Adapter.Finch, ["name"]}`, or a string-keyed
      `[{"name", __MODULE__}]`) — even though the latter provably can never
      carry `name:` at all.
    * Only a directly-authored `@attribute value` form is recognised. An
      attribute set through `Module.put_attribute/3` or injected by a macro
      (via `__using__`) is invisible to Credo and cannot be resolved.
    * An adapter tuple passed inline to `SharedUtils.HTTP.client/3` without
      ever being stored on the configured attribute
      (`SharedUtils.HTTP.client([], {Tesla.Adapter.Finch, []}, opts)`) is not
      checked — this package's house idiom always names the adapter tuple on
      an attribute first, and this check follows that idiom.
    * A bare-module attribute (`@adapter Tesla.Adapter.Finch`) always fires,
      even when a call site diverges from that house idiom and splices
      `name:` around the attribute itself
      (`SharedUtils.HTTP.client([], {@adapter, name: __MODULE__}, opts)`).
      Call sites are never inspected — only the attribute's own AST shape —
      so this is indistinguishable from a call site that supplies no name at
      all. An accepted false positive.
    * A bare-module attribute fires for the same reason when the pool name
      instead arrives per request via `opts: [adapter: [name: MyFinch]]` —
      Tesla merges `env.opts[:adapter]` over the adapter tuple's own opts at
      the highest precedence (`Tesla.Adapter.opts/3`), and
      `SharedUtils.HTTP.client/3` itself forwards `opts[:adapter]` the same
      way. Same accepted false positive as the call-site splice above: call
      sites are never inspected.
  """
  @explanation [check: @moduledoc]

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
    excluded_paths =
      params
      |> Params.get(:excluded_paths, __MODULE__)
      |> List.wrap()
      |> Enum.filter(&is_binary/1)

    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    adapter_modules =
      params
      |> Params.get(:adapter_modules, __MODULE__)
      |> List.wrap()
      |> Enum.filter(&elixir_module?/1)

    %{
      attribute: params |> Params.get(:attribute, __MODULE__) |> normalize_attribute(),
      adapter_modules: AstHelpers.resolve_aliases(source_file, adapter_modules),
      adapter_module_paths: Enum.flat_map(adapter_modules, &AstHelpers.module_paths/1)
    }
  end

  defp normalize_attribute(value) when is_atom(value) or is_binary(value), do: to_string(value)

  defp normalize_attribute(_other) do
    param_defaults() |> Keyword.fetch!(:attribute) |> to_string()
  end

  defp elixir_module?(module) when is_atom(module) do
    String.starts_with?(Atom.to_string(module), "Elixir.")
  end

  defp elixir_module?(_other), do: false

  defp atom_module_path(atom) do
    if elixir_module?(atom) do
      atom
      |> Atom.to_string()
      |> String.trim_leading("Elixir.")
      |> String.split(".")
      |> Enum.map(&String.to_atom/1)
    end
  end

  # Comparing the AST's atom attribute name via `Atom.to_string/1` avoids
  # ever turning a configured `:attribute` string back into an atom — the
  # same idiom `EctoMetricsRequiresAppAtom.split_module/1` uses to sidestep
  # `String.to_existing_atom/1` raising on a name never created elsewhere.
  defp traverse({:@, meta, [{attribute, _attr_meta, [value]}]} = ast, issues, context)
       when is_atom(attribute) do
    if Atom.to_string(attribute) === context.attribute and
         adapter_status(value, context) === :fires do
      {ast, [attribute_call(attribute, meta) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  # `@adapter {Module, opts}` — a dedicated-pool tuple. A literal keyword
  # list in opts is checked directly for `:name`; anything else (a nested
  # attribute, a call result) is opaque and left alone rather than guessed
  # at.
  defp adapter_status({{:__aliases__, _, module}, opts}, context) do
    if module in context.adapter_modules, do: keyword_status(opts), else: :silent
  end

  # `@adapter {:"Elixir.Module", opts}` — same tuple shape, but the module is
  # an Erlang-style atom literal rather than an alias path (see
  # `writing-credo-checks` on the three spellings of "module"). An absolute
  # atom is never subject to file-local `alias` resolution, so it is matched
  # against the unaliased `adapter_module_paths` rather than the
  # alias-widened `adapter_modules` the `__aliases__` clause above uses —
  # otherwise `alias Tesla.Adapter.Finch` would make `:"Elixir.Finch"` (the
  # unrelated top-level `Finch` module) match through the alias's bare local
  # name.
  defp adapter_status({module, opts}, context) when is_atom(module) do
    case atom_module_path(module) do
      nil -> :silent
      path -> if path in context.adapter_module_paths, do: keyword_status(opts), else: :silent
    end
  end

  # `@adapter Module` — the bare adapter module, no opts position on the
  # attribute itself. Fires under the assumed house idiom (see moduledoc);
  # a call site that splices name: around this bare value is an accepted
  # false positive (see Limitations) since call sites are never inspected.
  defp adapter_status({:__aliases__, _, module}, context) do
    if module in context.adapter_modules, do: :fires, else: :silent
  end

  # `@adapter :"Elixir.Module"` — same bare shape, atom-literal spelling.
  # Matched against `adapter_module_paths` for the same reason as the tuple
  # clause above.
  defp adapter_status(module, context) when is_atom(module) do
    case atom_module_path(module) do
      nil -> :silent
      path -> if path in context.adapter_module_paths, do: :fires, else: :silent
    end
  end

  # Anything else (a call result, a variable read) is opaque — its resolved
  # shape is invisible to a static check.
  defp adapter_status(_other, _context), do: :silent

  defp keyword_status(opts) do
    case AstHelpers.keyword_literal_has_key?(opts, :name) do
      true -> :silent
      false -> :fires
      :not_literal -> :silent
    end
  end

  defp attribute_call(attribute, meta) do
    %{trigger: "@#{attribute}", line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — Tesla.Adapter.Finch requires :name or the request raises KeyError; pass name: __MODULE__, matching a Finch pool started under that name",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
