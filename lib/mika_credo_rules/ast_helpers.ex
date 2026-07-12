defmodule MikaCredoRules.AstHelpers do
  @moduledoc """
  Shared AST matching for module identity across every check.

  Module identity is the package's most bug-prone concept — hand-rolling it
  shipped both a false negative (a wildcard module slot let `Enum.join/2` borrow
  an Ecto exemption) and a false positive (a literal path list missed
  `alias Ecto.Query`). Every function here is total: it returns `nil`/`false`
  rather than raising on shapes it does not recognise.

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

  Aliases are collected into a flat, file-level table rather than a lexical
  scope stack. An alias declared inside one function is treated as applying to
  the whole file. Aliases injected by a macro (via `__using__`) are invisible
  to Credo and cannot be resolved.
  """
  @spec resolve_aliases(Credo.SourceFile.t(), [module()]) :: [module_path()]
  def resolve_aliases(source_file, modules) do
    base = Enum.flat_map(modules, &module_paths/1)

    source_file
    |> Credo.Code.prewalk(&collect_aliases/2)
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

  defp apply_alias({name, target}, paths) do
    target = strip_elixir_prefix(target)

    cond do
      target in paths -> [name | paths]
      name in paths -> paths -- [name]
      true -> paths
    end
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments
end
