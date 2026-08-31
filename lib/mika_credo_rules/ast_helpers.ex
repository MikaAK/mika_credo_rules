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

  defp apply_alias({name, target}, paths) do
    target = strip_elixir_prefix(target)
    resolves_to_target? = target in paths or [Elixir | target] in paths
    paths = paths -- [name]

    if resolves_to_target?, do: [name | paths], else: paths
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
end
