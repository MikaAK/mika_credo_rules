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
      put_cookie(server, :theme, "dark")

      # GOOD
      put_cookie(server, "theme", "dark")

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
    HologramModules.scan_own_body(body, [], &collect_node_violation(&1, &2, functions))
  end

  defp collect_node_violation({function, meta, args}, violations, functions)
       when is_atom(function) and is_list(args) do
    if function in functions and atom_key?(args) do
      [%{trigger: Atom.to_string(function), line_no: meta[:line]} | violations]
    else
      violations
    end
  end

  defp collect_node_violation(_node, violations, _functions), do: violations

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
