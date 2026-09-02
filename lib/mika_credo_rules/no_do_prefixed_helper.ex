defmodule MikaCredoRules.NoDoPrefixedHelper do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      excluded_paths: []
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A public/private pair split only by a `do_` prefix — `def process/1`
  calling `defp do_process/1` — hides what the private half actually does
  behind a name that just repeats the public one. Find a descriptive name
  instead.

      # BAD — the prefix says nothing the caller couldn't already guess
      defmodule MyApp.Importer do
        def process(row) do
          do_process(row, [])
        end

        defp do_process(row, acc) do
          [row | acc]
        end
      end

      # GOOD — the name describes the work
      defmodule MyApp.Importer do
        def process(row) do
          normalize_row(row, [])
        end

        defp normalize_row(row, acc) do
          [row | acc]
        end
      end

  Both `def name` + `defp do_name` and `defp name` + `defp do_name` pairs are
  flagged, at the `defp do_name` head. A `defp do_name` with no sibling
  `name` definition anywhere in the module is left alone: a `do_`-prefixed
  helper with no twin is usually a recursion accumulator
  (`do_process(rest, [head | acc])`), not a naming smell. Definitions are
  collected per module in a first pass, then compared, so the pair is found
  regardless of which one is defined first in the source. A multi-clause
  `defp do_name` is flagged once, at its earliest clause — not once per
  clause.

  Scoping is per module: a nested `defmodule` is its own scope, so a pair
  split across an outer module and a nested one is not flagged, and neither
  is a pair split across two sibling modules in one file. A `defimpl`,
  `defprotocol`, or `quote` block is likewise its own scope, independent of
  the module it is written inside — so a `def` injected by a `__using__`
  macro's `quote` block pairs only with a `do_name` also injected by that
  same `quote` block, never with an unrelated `do_name` living in the
  module the `quote` happens to be written inside.

  ## Limitations

    * Matching is by name only, not arity — `def process/1` pairs with
      `defp do_process/3` just as readily as with `defp do_process/1`.
    * Only `def` and `defp` are considered; `defmacro`/`defmacrop` and
      `defdelegate` are never collected as a sibling or as a trigger, even
      though `defdelegate name(x), to: Other` does define `name/1`. A
      `def do_name` head is never flagged directly — a public function's
      name is part of its API, not a naming choice this check can veto —
      even when a sibling `name` exists.
    * A metaprogrammed head (`def unquote(name)(args)`) has no static name
      and is invisible to this check — neither collected as a sibling name
      nor as a `do_`-prefixed candidate.
  """
  @explanation [check: @moduledoc]

  @do_prefix "do_"

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # Each defmodule is its own scope: only its own body (nested defmodules
  # excluded) decides which names it defines and which do_-prefixed defp
  # heads it owns. Nested defmodules are still visited by the outer prewalk,
  # so each gets the same treatment independently.
  defp traverse({:defmodule, _, [_name, [{:do, body} | _]]} = ast, helpers) do
    {ast, scoped_flags(body) ++ helpers}
  end

  defp traverse({:defprotocol, _, [_name, [{:do, body} | _]]} = ast, helpers) do
    {ast, scoped_flags(body) ++ helpers}
  end

  # `args` is only a keyword-arg list for a real `defimpl`/`quote` call.
  # `defimpl`/`quote` used as a bare variable (a function parameter, a
  # reference like `quote.last`) parses to the same 3-tuple with `args`
  # `nil` — the `is_list` guard sends that case to the catch-all clause
  # instead of `scope_from_last_do_block/3`, which would otherwise crash
  # calling `List.last(nil)`.
  defp traverse({:defimpl, _, args} = ast, helpers) when is_list(args) do
    scope_from_last_do_block(ast, args, helpers)
  end

  # A `quote` block is its own scope too: a `def`/`defp` it injects belongs
  # to whatever module `use`s the macro, not to the module the `quote` is
  # lexically written inside — so it must neither leak names out to the
  # enclosing module nor inherit the enclosing module's names in.
  defp traverse({:quote, _, args} = ast, helpers) when is_list(args) do
    scope_from_last_do_block(ast, args, helpers)
  end

  defp traverse(ast, helpers), do: {ast, helpers}

  # `defimpl P, for: S, do: (...)` merges `:do` into the same keyword list
  # as `:for`, so it is not in head position — `defimpl P, for: S do ... end`
  # and bare `quote do ... end` both keep `:do` as the only key. Looking it
  # up by key instead of position handles every shape uniformly.
  defp scope_from_last_do_block(ast, args, helpers) do
    case args |> List.last() |> keyword_do_block() do
      nil -> {ast, helpers}
      body -> {ast, scoped_flags(body) ++ helpers}
    end
  end

  defp keyword_do_block(kw) when is_list(kw), do: Keyword.get(kw, :do)
  defp keyword_do_block(_not_a_keyword_list), do: nil

  # A `defp do_name` with several clauses is one naming smell, not one per
  # clause — dedupe by name, keeping the earliest line.
  defp scoped_flags(body) do
    names = collect_names(body)
    candidates = collect_do_defp_heads(body)

    candidates
    |> Enum.filter(&(&1.sibling in names))
    |> Enum.sort_by(& &1.line_no)
    |> Enum.uniq_by(& &1.name)
  end

  defp collect_names(body) do
    scan_own_body(body, MapSet.new(), fn
      {keyword, _, [head | _]}, names when keyword in [:def, :defp] ->
        case head_name_and_meta(head) do
          nil -> names
          {name, _meta} -> MapSet.put(names, Atom.to_string(name))
        end

      _node, names ->
        names
    end)
  end

  defp collect_do_defp_heads(body) do
    scan_own_body(body, [], fn
      {:defp, _, [head | _]}, heads ->
        case head_name_and_meta(head) do
          nil -> heads
          {name, head_meta} -> add_do_defp_head(heads, name, head_meta)
        end

      _node, heads ->
        heads
    end)
  end

  defp add_do_defp_head(heads, name, meta) do
    case do_sibling(name) do
      nil ->
        heads

      sibling ->
        [
          %{name: name, sibling: sibling, line_no: meta[:line], column: meta[:column]}
          | heads
        ]
    end
  end

  defp head_name_and_meta({:when, _, [head | _]}), do: head_name_and_meta(head)
  defp head_name_and_meta({name, meta, _args}) when is_atom(name), do: {name, meta}
  defp head_name_and_meta(_head), do: nil

  defp do_sibling(name) do
    name_string = Atom.to_string(name)

    if String.starts_with?(name_string, @do_prefix) do
      case String.replace_prefix(name_string, @do_prefix, "") do
        "" -> nil
        stripped -> stripped
      end
    end
  end

  # Walks a module body, pruning nested defmodule/defimpl/defprotocol/quote
  # subtrees — each of those is its own scope, so an outer scope neither
  # inherits its definitions nor contributes its own.
  defp scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc -> {nil, acc}
      {:defimpl, _, _}, acc -> {nil, acc}
      {:defprotocol, _, _}, acc -> {nil, acc}
      {:quote, _, _}, acc -> {nil, acc}
      node, acc -> {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp issue_for(helper, issue_meta) do
    trigger = Atom.to_string(helper.name)

    format_issue(issue_meta,
      message:
        "#{trigger} found — do_-prefixed helper next to `#{helper.sibling}`, find a descriptive name instead",
      trigger: trigger,
      line_no: helper.line_no,
      column: helper.column
    )
  end
end
