defmodule MikaCredoRules.HologramCookieKeysMustBeStrings do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      hologram_modules: [Hologram.Page, Hologram.Component],
      functions: [:get_cookie, :put_cookie, :delete_cookie]
    ],
    explanations: [
      params: [
        hologram_modules: """
        Modules whose `use` marks a `defmodule` as a Hologram module in scope
        for this check.
        """,
        functions: """
        Local (unqualified) cookie function names to check. The key is always
        their 2nd positional argument (index 1) — `get_cookie(server, key)`,
        `put_cookie(server, key, value)`, `delete_cookie(server, key)`.
        """
      ]
    ]

  alias MikaCredoRules.HologramModules

  @moduledoc """
  A Hologram cookie key must be a string — an atom key errors at runtime.

  Session keys accept either atoms or strings, but cookie keys accept
  strings only. Passing an atom compiles fine and fails only when the
  `get_cookie`/`put_cookie`/`delete_cookie` call actually runs.

      # BAD — runtime error, cookie keys must be strings
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, :theme, "dark")
        end
      end

      # GOOD
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def command(:save, _params, server) do
          put_cookie(server, "theme", "dark")
        end
      end

  Scoped per module, not per file — only a `defmodule` whose own body
  contains `use Hologram.Page`/`use Hologram.Component` is inspected. Only a
  literal atom in the key position is flagged; a variable
  (`put_cookie(server, key, value)`) is left alone since its runtime value is
  unknown to a static check.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    hologram_modules = Params.get(params, :hologram_modules, __MODULE__)
    functions = Params.get(params, :functions, __MODULE__)

    source_file
    |> HologramModules.hologram_module_bodies(hologram_modules)
    |> Enum.flat_map(fn {_module_ast, body} -> collect_violations(body, functions) end)
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp collect_violations(body, functions) do
    body
    |> Macro.prewalk([], &traverse(&1, &2, functions))
    |> elem(1)
  end

  defp traverse({:defmodule, _, _}, violations, _functions), do: {nil, violations}

  # A piped call is consumed here: its key is the piped call's own 1st
  # argument (`lhs |> put_cookie(key, value)`), which becomes the 2nd
  # argument once `lhs` is prepended — the same position a standalone call
  # checks. The call's head is rewritten to `__block__` (keeping its
  # arguments traversable) so the standalone clause below never re-examines
  # the same call at the wrong argument position.
  defp traverse({:|>, pipe_meta, [lhs, {function, meta, args}]}, violations, functions)
       when is_atom(function) and is_list(args) do
    {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
     collect_call_violation(violations, function, [lhs | args], meta, functions)}
  end

  defp traverse({function, meta, args} = node, violations, functions)
       when is_atom(function) and is_list(args) do
    {node, collect_call_violation(violations, function, args, meta, functions)}
  end

  defp traverse(node, violations, _functions), do: {node, violations}

  defp collect_call_violation(violations, function, args, meta, functions) do
    if function in functions and atom_key?(args) do
      [%{trigger: Atom.to_string(function), line_no: meta[:line]} | violations]
    else
      violations
    end
  end

  defp atom_key?(args) do
    case Enum.at(args, 1) do
      key when is_atom(key) and key not in [nil, true, false] -> true
      _key -> false
    end
  end

  defp issue_for(violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found with an atom key — cookie keys must be strings, atom keys error at runtime",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end
end
