defmodule MikaCredoRules.NoPhxBindingsInHoloTemplate do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      hologram_modules: [Hologram.Page, Hologram.Component],
      excluded_paths: []
    ],
    explanations: [
      params: [
        hologram_modules: """
        Modules whose `use` marks a `defmodule` as a Hologram module in scope
        for this check.
        """,
        excluded_paths: """
        A list of path fragments to exempt from the check, segment-boundary
        matched. Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.HologramModules
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `~HOLO` template must not use Phoenix's `phx-*` bindings or EEx tags —
  Hologram has its own template syntax.

  Hologram templates bind events with `$click`/`$change`/`$submit` and
  interpolate with `{@var}`. Both `phx-*` attributes and `<%= %>`/`<% %>` EEx
  tags are Phoenix.LiveView/HEEx syntax that Hologram's compiler does not
  understand — they render as literal text rather than doing anything.

      # BAD
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO(<button phx-click="save"><%= @label %></button>)
      end

      # GOOD
      defmodule MyApp.ProductPage do
        use Hologram.Page

        def template, do: ~HOLO(<button $click="save">{@label}</button>)
      end

  Scoped per module, not per file — only a `defmodule` whose own body
  contains `use Hologram.Page`/`use Hologram.Component` is inspected, and
  within it only `~HOLO` sigil bodies; a `~H` (HEEx) sigil living
  side-by-side is left alone (see `NoHeexSigilInHologramModule`, which bans
  the sigil itself).

  One issue is reported per offending match, at the line inside the template
  where it occurs — not the line of the `~HOLO` sigil itself.
  """
  @explanation [check: @moduledoc]

  @phx_binding_regex ~r/\bphx-[a-z-]+=/
  @eex_tag_regex ~r/<%=?/

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if SourceFilter.matches_fragment?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      hologram_modules = Params.get(params, :hologram_modules, __MODULE__)

      source_file
      |> HologramModules.hologram_module_bodies(hologram_modules)
      |> Enum.flat_map(fn {_module_ast, body} -> collect_violations(body) end)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp collect_violations(body) do
    HologramModules.scan_own_body(body, [], &collect_sigil_violations/2)
  end

  defp collect_sigil_violations({:sigil_HOLO, meta, [{:<<>>, _, parts}, _modifiers]}, violations) do
    content = sigil_content(parts)
    base_line = meta[:line] + heredoc_offset(meta[:delimiter])

    violations
    |> collect_matches(content, base_line, @phx_binding_regex, :phx_binding)
    |> collect_matches(content, base_line, @eex_tag_regex, :eex_tag)
  end

  defp collect_sigil_violations(_node, violations), do: violations

  defp sigil_content(parts) do
    parts
    |> Enum.filter(&is_binary/1)
    |> Enum.join()
  end

  # `meta[:line]` points at the `~HOLO"""` line itself for a heredoc sigil —
  # the content starts on the NEXT line. A single-line sigil (`~HOLO"..."`)
  # has its content on the same line as the sigil, so no offset is needed.
  defp heredoc_offset(delimiter) when byte_size(delimiter) === 3, do: 1
  defp heredoc_offset(_delimiter), do: 0

  defp collect_matches(violations, content, base_line, regex, kind) do
    regex
    |> Regex.scan(content, return: :index)
    |> Enum.reduce(violations, fn [{start, length} | _], acc ->
      violation = %{
        trigger: binary_part(content, start, length),
        line_no: base_line + newlines_before(content, start),
        kind: kind
      }

      [violation | acc]
    end)
  end

  defp newlines_before(content, index) do
    content
    |> binary_part(0, index)
    |> String.graphemes()
    |> Enum.count(&(&1 === "\n"))
  end

  defp issue_for(%{kind: :phx_binding} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a ~HOLO template — use $click/$change/$submit bindings instead of phx-* attributes",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end

  defp issue_for(%{kind: :eex_tag} = violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.trigger} found in a ~HOLO template — use {@var} interpolation instead of EEx tags",
      trigger: violation.trigger,
      line_no: violation.line_no
    )
  end
end
