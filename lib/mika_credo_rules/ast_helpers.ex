defmodule MikaCredoRules.AstHelpers do
  @moduledoc """
  Shared AST matching for module identity across every check.

  Module identity is the package's most bug-prone concept — hand-rolling it
  shipped both a false negative (a wildcard module slot let `Enum.join/2` borrow
  an Ecto exemption) and a false positive (a literal path list missed
  `alias Ecto.Query`). Every function here is total over the AST shapes it is
  meant to recognise: it returns `nil`/`false` rather than raising on a shape
  it does not match.

  `module_paths/1` and `resolve_aliases/2` are NOT total over their `module`
  argument — they require a genuine Elixir module atom (one `Module.split/1`
  accepts). Passing an erlang-style atom module (e.g. `:maps` in a caller's
  `nilable_functions: [{:maps, :get, 2}]`) raises `ArgumentError` from
  `Module.split/1`.

  ## House idiom: pruning a subtree with `{nil, acc}`

  Returning `nil` as the AST from a `Credo.Code.prewalk/2` traversal stops the
  walk descending into that node's subtree. Use it to exempt a call's
  *arguments* (not its whole line), or to skip `@spec`/`@type` bodies. It is a
  return value, not logic — do not wrap it in a function.
  """

  @typedoc "An alias path as it appears in AST: `[:Ecto, :Query]` or `[Elixir, :Mix]`."
  @type module_path :: [atom()]

  @doc """
  Every AST spelling of `module`.

      iex> MikaCredoRules.AstHelpers.module_paths(Mix)
      [[:Mix], [Elixir, :Mix]]

      iex> MikaCredoRules.AstHelpers.module_paths(Ecto.Query)
      [[:Ecto, :Query], [Elixir, :Ecto, :Query]]

  Never wildcard the module position of a dot-call, and never hand-roll the
  `Elixir.`-prefixed variant — both mistakes have shipped bugs here.
  """
  @spec module_paths(module()) :: [module_path()]
  def module_paths(module) do
    parts = module |> Module.split() |> Enum.map(&String.to_atom/1)

    [parts, [Elixir | parts]]
  end

  @doc """
  Every name in `source_file` that resolves to one of `modules`.

  Starts from both spellings of each module (see `module_paths/1`) and folds the
  file's `alias` declarations — plain, `as:` renames, and multi-alias
  (`alias Foo.{Bar, Baz}`) — over that base.

  Alias resolution has two halves, and both are load-bearing:

    * **ADD** — `alias Ecto.Query` means the local name `[:Query]` now refers to
      `Ecto.Query`, so `[:Query]` joins the match set.
    * **REMOVE (shadowing)** — `alias MyApp.Application` means bare
      `[:Application]` no longer refers to Elixir's `Application`, so it leaves
      the match set. Only the bare spelling is removed — an explicit
      `Elixir.Application` is unambiguous and stays matched.

  Which half a caller exercises depends on segment count: single-segment base
  paths (`[:Application]`) are shadowable and need both; multi-segment paths
  (`[:Ecto, :Query]`) cannot be shadowed by a one-segment alias and only ever
  gain ADD entries. An add-only implementation silently breaks single-segment
  callers; a remove-happy one wrongly un-exempts multi-segment callers.

  Aliases are applied in source order, so a later alias overrides an earlier
  one for the same local name — matching Elixir's own last-alias-wins
  resolution. Aliases are collected into a flat, file-level table rather than
  a lexical scope stack. An alias declared inside one function is treated as applying to
  the whole file. Aliases injected by a macro (via `__using__`) are invisible
  to Credo and cannot be resolved.
  """
  @spec resolve_aliases(Credo.SourceFile.t(), [module()]) :: [module_path()]
  def resolve_aliases(source_file, modules) do
    base = Enum.flat_map(modules, &module_paths/1)

    source_file
    |> Credo.Code.prewalk(&collect_aliases/2)
    |> Enum.reverse()
    |> Enum.reduce(base, &apply_alias/2)
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}]} = ast, aliases) do
    {ast, [{[List.last(target)], target} | aliases]}
  end

  defp collect_aliases({:alias, _, [{:__aliases__, _, target}, opts]} = ast, aliases)
       when is_list(opts) do
    {ast, [{alias_name(target, opts), target} | aliases]}
  end

  defp collect_aliases(
         {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, inner_nodes}]} = ast,
         aliases
       ) do
    grouped_aliases =
      for {:__aliases__, _, inner} <- inner_nodes do
        {[List.last(inner)], base ++ inner}
      end

    {ast, grouped_aliases ++ aliases}
  end

  defp collect_aliases(ast, aliases), do: {ast, aliases}

  defp alias_name(target, opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _, name} -> name
      _ -> [List.last(target)]
    end
  end

  @doc """
  Every module name defined via `defmodule` in `source_file`, at any nesting depth.

  Returns the literal AST segments as written, not the fully qualified name —
  `defmodule Mock` nested inside `defmodule Sample` still returns `[:Mock]`, since
  Elixir's `defmodule` macro only qualifies the name against its enclosing module at
  expansion time, not in the raw AST.

  This is a third source of shadowing that `resolve_aliases/2` does not cover: a
  locally defined `defmodule Mock do ... end` emits the same `{:__aliases__, _,
  [:Mock]}` node as a reference to a banned single-segment name, so a caller that
  bans bare names needs this to tell "defines" apart from "references".
  """
  @spec defined_module_names(Credo.SourceFile.t()) :: [module_path()]
  def defined_module_names(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_defmodule_names/2)
    |> Enum.uniq()
  end

  defp collect_defmodule_names(
         {:defmodule, _meta, [{:__aliases__, _name_meta, name_segments}, _body]} = ast,
         names
       ) do
    {ast, [name_segments | names]}
  end

  defp collect_defmodule_names(ast, names), do: {ast, names}

  # An alias both ADDs and REMOVEs, and each half applies to qualified
  # extensions as well as the exact name. `alias Tesla.Adapter` makes
  # `Adapter.Finch` mean `Tesla.Adapter.Finch` (expansion — the house style
  # mandates exactly this namespace-alias idiom), while `alias MyApp.Ecto`
  # makes `Ecto.Query` mean `MyApp.Ecto.Query`, so the bare extension no
  # longer resolves to Elixir's `Ecto.Query` (shadowing). `Elixir.`-prefixed
  # spellings are absolute and never touched by either half.
  defp apply_alias({name, target}, paths) do
    target = strip_elixir_prefix(target)

    expanded =
      for path <- paths,
          rest = remainder_after_either_prefix(target, path),
          not is_nil(rest) do
        name ++ rest
      end

    shadowed =
      for path <- paths,
          rest = remainder_after_prefix(name, path),
          not is_nil(rest),
          (target ++ rest) not in paths,
          ([Elixir | target] ++ rest) not in paths do
        path
      end

    Enum.uniq(expanded ++ (paths -- shadowed))
  end

  defp remainder_after_either_prefix(target, path) do
    remainder_after_prefix(target, path) || remainder_after_prefix([Elixir | target], path)
  end

  defp remainder_after_prefix(prefix, path) do
    if List.starts_with?(path, prefix), do: Enum.drop(path, length(prefix)), else: nil
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  @doc """
  Default Ecto query DSL function names — the only calls whose loose (`==`/`!=`)
  or boolean-literal comparisons the query compiler accepts.
  """
  @spec ecto_query_functions() :: [atom()]
  def ecto_query_functions do
    [
      :dynamic,
      :from,
      :where,
      :or_where,
      :having,
      :or_having,
      :select,
      :select_merge,
      :on,
      :join,
      :query,
      :subquery,
      :in
    ]
  end

  @doc """
  True when `ast` is a call whose arguments are exempt from an operator check
  under the Ecto query DSL: a bare/imported call named in `ignored_functions`,
  or a call qualified on a module in `ecto_query_modules` (from
  `resolve_aliases/2`) named in `ignored_functions`.

  Qualified calls are only exempt on an Ecto.Query spelling — an ignored
  function name on another module (`Enum.join/2` sharing the `:join` name)
  never borrows the exemption.

  Only useful inside a `Credo.Code.prewalk/2` traverse: when this returns
  `true`, return `{nil, acc}` from the traverse clause to prune the call's
  *arguments* — returning `true` alone does not stop the walk.
  """
  @spec ecto_query_call?(Macro.t(), [module_path()], [atom()]) :: boolean()
  def ecto_query_call?(
        {{:., _, [{:__aliases__, _, module}, function]}, _, args},
        ecto_query_modules,
        ignored_functions
      )
      when is_atom(function) and is_list(args) do
    module in ecto_query_modules and function in ignored_functions
  end

  def ecto_query_call?({function, _, args}, _ecto_query_modules, ignored_functions)
      when is_atom(function) and is_list(args) do
    function in ignored_functions
  end

  def ecto_query_call?(_ast, _ecto_query_modules, _ignored_functions), do: false

  @doc """
  Whether a literal keyword-list AST contains `key`.

  Returns `:not_literal` when `ast` is not statically a keyword list — a
  variable, a module attribute reference, a function call, or a list holding
  anything other than atom-keyed pairs. Callers must treat `:not_literal` as
  "skip", not as "missing" — a non-literal option list is opaque to a static
  check, so flagging it would be a guess dressed up as a fact.

      iex> MikaCredoRules.AstHelpers.keyword_literal_has_key?([max_attempts: 3, queue: :default], :max_attempts)
      true

      iex> MikaCredoRules.AstHelpers.keyword_literal_has_key?([queue: :default], :max_attempts)
      false

      iex> MikaCredoRules.AstHelpers.keyword_literal_has_key?([], :max_attempts)
      false

      iex> MikaCredoRules.AstHelpers.keyword_literal_has_key?({:opts, [], nil}, :max_attempts)
      :not_literal

  Shared by every check that flags a missing key in a literal option list.
  `Keyword.keyword?/1` already recognises the shape of a literal keyword
  list — a 2-element tuple is unwrapped identically in the quoted AST and in
  a real runtime value — so there is nothing to hand-roll here.
  """
  @spec keyword_literal_has_key?(Macro.t(), atom()) :: true | false | :not_literal
  def keyword_literal_has_key?(ast, key) do
    if Keyword.keyword?(ast) do
      Keyword.has_key?(ast, key)
    else
      :not_literal
    end
  end

  @doc """
  Splits a `def`/`do` body into its top-level statements.

  Elixir represents a multi-statement body as `{:__block__, _, statements}`,
  but a single-statement body is the statement itself, with no wrapper. Checks
  that scan a body one top-level statement at a time need this normalization
  either way.

      iex> MikaCredoRules.AstHelpers.block_statements({:__block__, [], [1, 2]})
      [1, 2]

      iex> MikaCredoRules.AstHelpers.block_statements({:foo, [], []})
      [{:foo, [], []}]
  """
  @spec block_statements(Macro.t()) :: [Macro.t()]
  def block_statements({:__block__, _, statements}), do: statements
  def block_statements(statement), do: [statement]

  @doc """
  True when `source_file` has a literal `use <module>` for any of `modules`.

  Alias-aware via `resolve_aliases/2` — an alias that shadows one of `modules` (or
  renames another module onto its bare name) is honoured the same way a remote-call
  matcher honours it. In the common case (no aliasing) this matches the literal
  name.

  FILE-scoped, not `defmodule`-scoped — a `use GenServer` inside a nested
  `defmodule Inner do ... end` returns `true` for the whole file, including
  code in an outer, non-GenServer module. Not a regression: the check this
  guards (`GenServerRequiresHandleContinue`) was file-wide before this helper
  existed too. See `callback_clauses/2` for the same caveat on the other half
  of a typical caller pairing.
  """
  @spec uses_module?(Credo.SourceFile.t(), [module()]) :: boolean()
  def uses_module?(source_file, modules) do
    resolved = resolve_aliases(source_file, modules)

    Credo.Code.prewalk(source_file, &detect_use(&1, &2, resolved), false)
  end

  defp detect_use({:use, _, [{:__aliases__, _, path} | _]} = ast, found, resolved) do
    {ast, found or path in resolved}
  end

  defp detect_use(ast, found, _resolved), do: {ast, found}

  @doc """
  Every `def name(...)` clause in `source_file` whose name is in `entries`.

  FILE-scoped, not `defmodule`-scoped — the same as `uses_module?/2`'s `use`
  scan. A `def init(...)` inside a nested `defmodule Inner do ... end` is
  collected too, so a caller pairing this with `uses_module?/2` treats the
  OUTER module's `use GenServer` as covering the inner module's callback.

  Each entry in `entries` is either a bare atom (matches the name at any arity,
  any `when` guard) or a `{name, arity}` tuple (matches only that exact arity).
  Callers own a fixed set of callback names; most GenServer/GenStage callbacks
  (`handle_call/3`, `handle_info/2`, ...) have one real arity in practice, so
  name-only matching is the safe default — a stray same-named local helper of a
  different arity is matched too. `init/1` is the exception: `init` is common
  enough as a public helper name at OTHER arities that name-only matching
  creates false positives, so callers guarding `init/1` specifically should pass
  `init: 1` to pin the arity.
  """
  @spec callback_clauses(Credo.SourceFile.t(), [atom() | {atom(), pos_integer()}]) :: [Macro.t()]
  def callback_clauses(source_file, entries) do
    Credo.Code.prewalk(source_file, &collect_callback_clause(&1, &2, entries))
  end

  defp collect_callback_clause({:def, _, [head, _body]} = ast, clauses, entries) do
    if callback_head?(head, entries) do
      {ast, [ast | clauses]}
    else
      {ast, clauses}
    end
  end

  defp collect_callback_clause(ast, clauses, _entries), do: {ast, clauses}

  defp callback_head?({:when, _, [head | _guards]}, entries), do: callback_head?(head, entries)

  defp callback_head?({name, _, args}, entries) when is_atom(name) and is_list(args) do
    matches_callback_entry?(name, length(args), entries)
  end

  defp callback_head?(_head, _entries), do: false

  defp matches_callback_entry?(name, arity, entries) do
    Enum.any?(entries, fn
      {entry_name, entry_arity} -> entry_name === name and entry_arity === arity
      entry_name when is_atom(entry_name) -> entry_name === name
    end)
  end

  @doc """
  The literal keyword-list options of a `use module, opts` call, when `module`
  resolves to one of `module_paths` (see `resolve_aliases/2`) and `opts` is a
  literal keyword list.

  Returns `nil` when the call is for a different module, carries no options, or
  the options are not a literal list — a variable or module-attribute splat
  (`use Cache, @cache_opts`) cannot be inspected statically and is left alone by
  every caller.

      iex> {:use, [], [{:__aliases__, [], [:Cache]}, [adapter: Cache.ETS]]}
      ...> |> MikaCredoRules.AstHelpers.use_options([[:Cache], [Elixir, :Cache]])
      [adapter: Cache.ETS]

      iex> {:use, [], [{:__aliases__, [], [:Cache]}, {:@, [], [{:cache_opts, [], nil}]}]}
      ...> |> MikaCredoRules.AstHelpers.use_options([[:Cache], [Elixir, :Cache]])
      nil
  """
  @spec use_options(Macro.t(), [module_path()]) :: keyword() | nil
  def use_options({:use, _, [module, opts]}, module_paths) when is_list(opts) do
    if use_module?(module, module_paths), do: opts
  end

  def use_options(_ast, _module_paths), do: nil

  @doc """
  True when the `use`/`alias` module argument `module` resolves to one of
  `module_paths` (see `resolve_aliases/2`).

  Handles all three AST spellings of "module" (see `writing-credo-checks`):
  an `__aliases__` path, an `Elixir.`-prefixed atom, and any other atom
  (always `false` — an erlang module name can never resolve to an Elixir
  one).

  The `__aliases__` clause compares `segments` to `module_paths` directly,
  without stripping a leading `Elixir` segment — `module_paths/1` already
  contains the `[Elixir | parts]` spelling, so a literal `Elixir.Cache` in
  source still resolves correctly even when the bare name `Cache` has been
  shadowed by a project alias and removed from `module_paths` (only the bare
  spelling is ever removed by shadowing, see `resolve_aliases/2`).

      iex> MikaCredoRules.AstHelpers.use_module?({:__aliases__, [], [:Cache]}, [[:Cache], [Elixir, :Cache]])
      true

      iex> MikaCredoRules.AstHelpers.use_module?({:__aliases__, [], [Elixir, :Cache]}, [[Elixir, :Cache]])
      true
  """
  @spec use_module?(Macro.t(), [module_path()]) :: boolean()
  def use_module?({:__aliases__, _, segments}, module_paths), do: segments in module_paths

  def use_module?(module, module_paths) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest ->
        [Elixir | module |> Module.split() |> Enum.map(&String.to_atom/1)] in module_paths

      _erlang_name ->
        false
    end
  end

  def use_module?(_other, _module_paths), do: false
end
