defmodule MikaCredoRules.EctoSchemaRequiresTypeT do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      schema_modules: [Ecto.Schema],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        schema_modules: """
        A list of modules whose `use` counts as declaring an Ecto schema,
        alias-aware (see `MikaCredoRules.AstHelpers.resolve_aliases/2`).
        Defaults to `[Ecto.Schema]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `["_test.exs", "test/"]` — a schema
        struct built only for a test fixture has no Dialyzer caller relying
        on `t()`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Every `Ecto.Schema` module must define `@type t :: %__MODULE__{}` for
  Dialyzer.

  Without it, every function returning a struct from this schema is typed as
  a bare `map()` (or left unspeced) to Dialyzer — a caller matching the
  wrong field name, or passing the wrong struct entirely, gets no static
  warning. `@type t :: %__MODULE__{}` gives Dialyzer the struct shape once,
  for every `@spec` that returns it.

      # BAD — no @type t for Dialyzer
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end

      # GOOD — @type t documents the struct shape for Dialyzer
      defmodule MyApp.User do
        use Ecto.Schema

        @type t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end

  `embedded_schema` modules use the same `use Ecto.Schema` and are checked
  identically. The check is scoped per module, not per file — a nested
  `defmodule` inside a schema file is judged on its own body: it is only
  flagged when it declares its own `use Ecto.Schema` and calls `schema`/
  `embedded_schema` itself, and it must define its own `@type t` even when
  an enclosing module already has one.

  A module whose `use Ecto.Schema` never reaches an actual `schema`/
  `embedded_schema` call is not flagged — most commonly a base module that
  injects `use Ecto.Schema` for its callers from inside a `quote` block (a
  `quote` block is pruned from the enclosing module's own body, the same
  way a nested `defmodule` is), or a bare `use Ecto.Schema` with no schema
  block at all. Neither has a struct, so `@type t :: %__MODULE__{}` would
  not compile there.

  ## Limitations

    * Only a type literally named `t`, arity 0, declared via `@type`,
      `@opaque`, or `@typep` (`@type t :: ...`, `@opaque t :: ...`,
      `@type t() :: ...`, etc.), satisfies the check — a differently named
      type alias for the same struct is not recognized.
    * Aliases are resolved from a flat, file-level table rather than a
      lexical scope stack, and an alias injected by a macro (via
      `__using__`) is invisible to Credo.
    * A schema built through a project base wrapper (a module that itself
      calls `use Ecto.Schema`, e.g. `use MyApp.Schema`) is invisible under
      the default `schema_modules: [Ecto.Schema]` — list the wrapper too,
      e.g. `schema_modules: [Ecto.Schema, MyApp.Schema]`.
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
    %{schema_paths: AstHelpers.resolve_aliases(source_file, schema_modules(params))}
  end

  defp schema_modules(params), do: Params.get(params, :schema_modules, __MODULE__)

  # Each defmodule is its own scope: only its own body (nested defmodules
  # excluded) decides whether it declares a schema and whether it defines its
  # own @type t. Nested defmodules are still visited by the outer prewalk, so
  # each gets the same treatment independently.
  defp traverse({:defmodule, _, [_name, [{:do, body} | _]]} = ast, issues, context) do
    case find_schema_use(body, context.schema_paths) do
      nil ->
        {ast, issues}

      use_info ->
        if schema_declared?(body) and not type_t_defined?(body) do
          {ast, [use_info | issues]}
        else
          {ast, issues}
        end
    end
  end

  defp traverse(ast, issues, _context), do: {ast, issues}

  # Walks a module body, pruning nested defmodule subtrees and quote blocks —
  # a nested module neither inherits the outer `use`/`@type t` nor
  # contributes its own, and a `use`/`schema` call written inside a `quote`
  # block belongs to whatever module later expands it, not to the module
  # doing the quoting (a `__using__` macro base has no struct of its own).
  # A def/defmacro head has the same `{atom, meta, args}` shape as a real
  # call — `defmacro schema(source, do: block)` (Ecto's own signature, see
  # deps/ecto/lib/ecto/schema.ex) has a last arg that is a `do:` keyword list
  # just like a genuine `schema "users" do ... end` invocation. The head is
  # never a real call, so it is pruned like a nested defmodule/quote; the
  # do-block body is still walked normally for nested use/@type t.
  defp scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc ->
        {nil, acc}

      {:quote, _, _}, acc ->
        {nil, acc}

      {def_kind, meta, [_head | rest]} = node, acc
      when def_kind in [:def, :defp, :defmacro, :defmacrop] ->
        {{def_kind, meta, [nil | rest]}, fun.(node, acc)}

      node, acc ->
        {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp schema_declared?(body) do
    scan_own_body(body, false, fn node, found -> found or schema_call?(node) end)
  end

  # The head atom of a `def schema(x)` clause or a `@spec schema(atom())` type
  # signature has the same `{:schema, meta, args}` shape as a genuine `schema`
  # call — only a real call's last argument is a `do:` keyword list, since
  # both `schema/2` and `embedded_schema/1` are always written with a do-block.
  defp schema_call?({call, _, args}) when call in [:schema, :embedded_schema] and is_list(args) do
    match?([{:do, _} | _], List.last(args))
  end

  defp schema_call?(_node), do: false

  defp find_schema_use(body, schema_paths) do
    scan_own_body(body, nil, fn node, acc -> acc || schema_use_info(node, schema_paths) end)
  end

  defp schema_use_info({:use, meta, [module | _]}, schema_paths) do
    if AstHelpers.use_module?(module, schema_paths) do
      %{
        line_no: meta[:line],
        column: meta[:column],
        trigger: use_trigger(module, meta),
        module_name: module_display_name(module)
      }
    end
  end

  defp schema_use_info(_node, _schema_paths), do: nil

  # A parenthesized `use(Ecto.Schema)` shifts the source text at this column
  # to "use(Ecto.Schem..." — the composed "use <Module>" trigger would not
  # match the ASSERT_TRIGGERS source slice there. `token_metadata: true`
  # (set by Credo.Code.ast/1) marks a parenthesized call with a `:closing`
  # meta key; fall back to the bare "use" token, which matches at this
  # column regardless of spelling (mirrors CacheRequiresSandboxOption's
  # `trigger: "use"`).
  defp use_trigger(module, meta) do
    if Keyword.has_key?(meta, :closing) do
      "use"
    else
      use_trigger(module)
    end
  end

  defp use_trigger({:__aliases__, _, segments}),
    do: "use #{Enum.map_join(segments, ".", &to_string/1)}"

  # An atom-spelled module (`use :"Elixir.Ecto.Schema"`) has no `__aliases__`
  # segments to render as a trigger that matches the source text at this
  # column — `inspect/1`'s dotted form would not appear literally in the
  # source. "use" is the one token that's both meaningful and guaranteed to
  # sit at this exact column.
  defp use_trigger(module) when is_atom(module), do: "use"

  defp module_display_name({:__aliases__, _, segments}),
    do: Enum.map_join(segments, ".", &to_string/1)

  # `use_module?/2` only ever passes an atom here when it is `Elixir.`-prefixed
  # (an erlang module name can never resolve to an Ecto.Schema alias — see
  # `AstHelpers.use_module?/2`), so `inspect/1` always renders the dotted form,
  # e.g. `inspect(:"Elixir.Ecto.Schema")` #=> "Ecto.Schema".
  defp module_display_name(module) when is_atom(module), do: inspect(module)

  defp type_t_defined?(body) do
    scan_own_body(body, false, fn node, found -> found or type_t_node?(node) end)
  end

  defp type_t_node?({:@, _, [{call, _, [{:"::", _, [{:t, _, args}, _]}]}]})
       when call in [:type, :opaque, :typep] and (is_nil(args) or args === []),
       do: true

  defp type_t_node?(_node), do: false

  defp issue_for(use_info, issue_meta) do
    format_issue(issue_meta,
      message: "use #{use_info.module_name} found — add @type t :: %__MODULE__{} for Dialyzer",
      trigger: use_info.trigger,
      line_no: use_info.line_no,
      column: use_info.column
    )
  end
end
