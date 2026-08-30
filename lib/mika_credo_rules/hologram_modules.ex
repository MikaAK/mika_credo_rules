defmodule MikaCredoRules.HologramModules do
  @moduledoc """
  Shared AST matching for "is this defmodule a Hologram module" scoping.

  Every Hologram-specific check in this package is scoped per module: only a
  `defmodule` whose OWN body (nested `defmodule`s excluded) contains a `use`
  of `Hologram.Page` or `Hologram.Component` is in scope — the same
  per-defmodule pattern `NoJasonDeriveOnEctoSchema` uses for `use
  Ecto.Schema`. This module is the single shared implementation of that
  scoping decision, plus the companion helper for locating a module's own
  callback clauses (e.g. `def action/3`) — used by checks that only apply
  inside actions, since actions run client-side while commands and `init/3`
  run on the server.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack, and aliases injected by a macro (via `__using__`) are
  invisible to Credo and cannot be resolved — the same limitations as every
  other alias-aware check in this package.
  """

  alias MikaCredoRules.AstHelpers

  @doc """
  Every `defmodule` in `source_file` whose OWN body contains a `use` of one
  of `hologram_modules`, paired with that module's own body AST.

  Nested `defmodule`s are excluded from the `use` search (they neither
  inherit their parent's `use` nor contribute their own), but are still
  visited by the outer traversal, so a Hologram module nested inside another
  Hologram module gets its own independent entry.
  """
  @spec hologram_module_bodies(Credo.SourceFile.t(), [module()]) :: [{Macro.t(), Macro.t()}]
  def hologram_module_bodies(source_file, hologram_modules) do
    context = %{
      modules: hologram_modules,
      paths: AstHelpers.resolve_aliases(source_file, hologram_modules)
    }

    source_file
    |> Credo.Code.prewalk(&collect_hologram_module(&1, &2, context))
    |> Enum.reverse()
  end

  defp collect_hologram_module(
         {:defmodule, _, [_name, [{:do, body} | _]]} = ast,
         modules,
         context
       ) do
    if hologram_module?(body, context) do
      {ast, [{ast, body} | modules]}
    else
      {ast, modules}
    end
  end

  defp collect_hologram_module(ast, modules, _context), do: {ast, modules}

  defp hologram_module?(body, context) do
    scan_own_body(body, false, fn
      {:use, _, [module | _]}, found -> found or module_matches?(module, context)
      _node, found -> found
    end)
  end

  defp module_matches?({:__aliases__, _, segments}, context),
    do: strip_elixir_prefix(segments) in context.paths

  defp module_matches?(module, context) when is_atom(module), do: module in context.modules

  defp module_matches?(_other, _context), do: false

  @doc """
  Every `def <name>` clause of arity 3 in `body` (a Hologram module's own
  body, nested `defmodule`s excluded) whose function name is in
  `callback_names`.

  Arity 3 is hardcoded because Hologram's `action/3` callback signature is
  fixed by the framework, not project-configurable.
  """
  @spec own_body_callback_clauses(Macro.t(), [atom()]) :: [Macro.t()]
  def own_body_callback_clauses(body, callback_names) do
    body
    |> scan_own_body([], fn
      {:def, _, [head, _clause_body]} = clause, clauses ->
        if callback_head?(head, callback_names), do: [clause | clauses], else: clauses

      _node, clauses ->
        clauses
    end)
    |> Enum.reverse()
  end

  defp callback_head?({:when, _, [head | _guards]}, callback_names),
    do: callback_head?(head, callback_names)

  defp callback_head?({name, _, args}, callback_names) when is_atom(name) and is_list(args) do
    length(args) === 3 and name in callback_names
  end

  defp callback_head?(_head, _callback_names), do: false

  @doc """
  Walks `body`, pruning nested `defmodule` subtrees — the shared per-module
  scoping primitive every Hologram check builds on. A nested module's
  `use`/`def`/attributes never leak into its parent's scope, and the parent's
  never leak down.
  """
  @spec scan_own_body(Macro.t(), acc, (Macro.t(), acc -> acc)) :: acc when acc: term()
  def scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc -> {nil, acc}
      node, acc -> {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments
end
