defmodule MikaCredoRules.NoClickHandlerOnNonInteractiveElement do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      non_interactive_tags: [
        "span",
        "div",
        "p",
        "li",
        "td",
        "th",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6"
      ],
      bindings: ["phx-click", "$click"],
      escape_attributes: ["role", "tabindex"],
      sigils: [:sigil_H, :sigil_F],
      excluded_paths: []
    ],
    explanations: [
      params: [
        non_interactive_tags: """
        Tag names with no native click semantics. Defaults to
        `["span", "div", "p", "li", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6"]`.
        """,
        bindings: """
        Attribute names that count as a click handler. Defaults to
        `["phx-click", "$click"]`.
        """,
        escape_attributes: """
        Attribute names that, when ALL present on the same opening tag,
        exempt it from being flagged. Defaults to `["role", "tabindex"]`.
        """,
        sigils: """
        Which sigil names count as template bodies. Defaults to
        `[:sigil_H, :sigil_F]`.
        """,
        excluded_paths: """
        Path fragments, matched at a segment boundary, whose files are
        skipped entirely. Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter
  alias MikaCredoRules.TemplateSigils

  @moduledoc """
  A click binding on a non-interactive element (`<span>`, `<div>`, ...)
  must use a native interactive element instead, unless it also carries
  the ARIA attributes that make it keyboard- and screen-reader-accessible.

  A `<span phx-click="...">` is invisible to keyboard navigation and
  assistive tech — it never receives focus, has no default role, and
  `Tab`/`Enter` do nothing. A native `<button>` gets all of that for free.

      # BAD
      ~H\"\"\"
      <span class="pill" phx-click="show_findings">click</span>
      \"\"\"

      # GOOD
      ~H\"\"\"
      <button type="button" aria-label="Show findings" phx-click="show_findings">click</button>
      \"\"\"

  An element that legitimately needs the click binding (a full-card click
  target, a modal backdrop) is not flagged once it carries BOTH `role=`
  and `tabindex=` — the escape hatch is a conjunction, not a flat ban,
  because those two attributes are exactly what restores keyboard/AT
  accessibility to a non-native element.

  An opening tag may span multiple lines; this check scans from `<tag` to
  its matching `>` regardless of how many lines that spans.

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo, so this check is blind to every `.html.heex` file.
  A `>` character appearing inside a quoted attribute value (e.g.
  `title="a > b"`) would incorrectly end the tag scan early; this is
  accepted as a rare edge case rather than handled with a full attribute
  parser.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> TemplateSigils.collect(context.sigils)
      |> Enum.flat_map(&flagged_tags(&1, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp build_context(params) do
    %{
      non_interactive_tags: Params.get(params, :non_interactive_tags, __MODULE__),
      bindings: Params.get(params, :bindings, __MODULE__),
      escape_attributes: Params.get(params, :escape_attributes, __MODULE__),
      sigils: Params.get(params, :sigils, __MODULE__)
    }
  end

  defp flagged_tags(sigil, context) do
    context.non_interactive_tags
    |> Enum.flat_map(&opening_tags(sigil, &1))
    |> Enum.filter(&clickable_without_escape?(&1, context))
    |> Enum.map(&build_match(sigil, &1))
  end

  defp opening_tags(sigil, tag) do
    regex = Regex.compile!("<" <> Regex.escape(tag) <> "\\b[^>]*>")

    regex
    |> Regex.scan(sigil.body, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      %{tag: tag, offset: offset, text: binary_part(sigil.body, offset, length)}
    end)
  end

  defp clickable_without_escape?(%{text: text}, context) do
    has_binding?(text, context.bindings) and
      not all_escape_attributes?(text, context.escape_attributes)
  end

  defp has_binding?(text, bindings), do: Enum.any?(bindings, &String.contains?(text, &1))

  defp all_escape_attributes?(text, escape_attributes) do
    Enum.all?(escape_attributes, &String.contains?(text, "#{&1}="))
  end

  defp build_match(sigil, %{tag: tag, offset: offset}) do
    %{
      trigger: "<#{tag}",
      line_no: TemplateSigils.line_at(sigil, offset),
      column: TemplateSigils.column_at(sigil, offset)
    }
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{match.trigger} with a click binding found — use a native " <>
          "<button type=\"button\"> (or add role and tabindex)",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end
end
