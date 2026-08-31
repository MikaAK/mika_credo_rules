defmodule MikaCredoRules.NoHeexSigilInHologramModule do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      hologram_modules: [Hologram.Page, Hologram.Component],
      banned_sigils: [:sigil_H],
      banned_uses: [Phoenix.LiveView, Phoenix.Component]
    ],
    explanations: [
      params: [
        hologram_modules: """
        Modules whose `use` marks a `defmodule` as a Hologram module in scope
        for this check.
        """,
        banned_sigils: """
        Sigil node names (as they appear in the AST, e.g. `:sigil_H`) that must
        not be used inside a Hologram module.
        """,
        banned_uses: """
        Modules that must not be `use`d inside a Hologram module — Phoenix's
        template/LiveView primitives are incompatible with Hologram's own
        compiler and runtime.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.HologramModules

  @moduledoc """
  A Hologram module must not use `~H` (HEEx) sigils or `use Phoenix.LiveView`
  / `use Phoenix.Component` — Hologram and Phoenix.LiveView are different
  frameworks with incompatible compilers.

  Hologram compiles its own templates (`~HOLO`) to JavaScript for the client
  runtime. A `~H` sigil is Phoenix.LiveView's HEEx template, which Hologram's
  compiler cannot process; `use Phoenix.LiveView`/`use Phoenix.Component`
  bring in a `render/1`/template contract that Hologram never calls.

      # BAD — mixes LiveView's template engine into a Hologram page
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~H"<div/>"
      end

      # GOOD — Hologram's own template sigil
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO"<div/>"
      end

  Scoped per module, not per file — only a `defmodule` whose own body
  contains `use Hologram.Page`/`use Hologram.Component` is inspected, the
  same per-defmodule pattern `NoJasonDeriveOnEctoSchema` uses for `use
  Ecto.Schema`. A nested `defmodule` without its own Hologram `use` is a
  separate scope and is left alone — a plain LiveView module living
  side-by-side in the same file is never flagged.

  Every alias spelling of `Hologram.Page`/`Hologram.Component` and of
  `Phoenix.LiveView`/`Phoenix.Component` is resolved, including `as:`
  renames and shadowing by a project alias of the same bare name.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file, params)

    source_file
    |> HologramModules.hologram_module_bodies(context.hologram_modules)
    |> Enum.flat_map(&collect_violations(&1, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file, params) do
    banned_uses = Params.get(params, :banned_uses, __MODULE__)

    %{
      hologram_modules: Params.get(params, :hologram_modules, __MODULE__),
      banned_sigils: Params.get(params, :banned_sigils, __MODULE__),
      banned_use_modules: banned_uses,
      banned_use_paths: AstHelpers.resolve_aliases(source_file, banned_uses)
    }
  end

  defp collect_violations({_module_ast, body}, context) do
    body
    |> Macro.prewalk([], &traverse(&1, &2, context))
    |> elem(1)
  end

  defp traverse({:defmodule, _, _}, violations, _context), do: {nil, violations}

  # A `def`/`defp` head has the exact same AST shape as a call
  # (`{name, meta, args}`) — a function literally named `sigil_H`
  # (`def sigil_H(term, _modifiers)`) would otherwise be misread as a
  # banned sigil use. The head is dropped from traversal; the body is kept.
  defp traverse({def_or_defp, meta, [_head, body]}, violations, _context)
       when def_or_defp in [:def, :defp] do
    {{def_or_defp, meta, [{:__block__, [], []}, body]}, violations}
  end

  defp traverse({node_name, meta, args} = node, violations, context)
       when is_atom(node_name) and is_list(args) do
    updated_violations =
      cond do
        node_name in context.banned_sigils ->
          [sigil_violation(node_name, meta) | violations]

        node_name === :use ->
          case use_violation(args, meta, context) do
            nil -> violations
            violation -> [violation | violations]
          end

        true ->
          violations
      end

    {node, updated_violations}
  end

  defp traverse(node, violations, _context), do: {node, violations}

  defp sigil_violation(sigil, meta) do
    %{trigger: sigil_display(sigil), line_no: meta[:line], kind: :sigil}
  end

  defp sigil_display(sigil) do
    "~" <> (sigil |> Atom.to_string() |> String.trim_leading("sigil_"))
  end

  defp use_violation([module | _rest], meta, context) do
    if banned_use?(module, context) do
      %{trigger: use_display(module), line_no: meta[:line], kind: :use}
    end
  end

  defp use_violation([], _meta, _context), do: nil

  defp banned_use?({:__aliases__, _, segments}, context),
    do: strip_elixir_prefix(segments) in context.banned_use_paths

  defp banned_use?(module, context) when is_atom(module), do: module in context.banned_use_modules

  defp banned_use?(_other, _context), do: false

  defp use_display({:__aliases__, _, segments}),
    do: segments |> strip_elixir_prefix() |> Enum.join(".")

  defp use_display(module) when is_atom(module), do: inspect(module)

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(%{kind: :sigil} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a Hologram module — use the ~HOLO sigil instead, Hologram's compiler cannot process HEEx templates",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end

  defp issue_for(%{kind: :use} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a Hologram module — use Hologram.Page/Hologram.Component instead, they are different frameworks",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end
end
