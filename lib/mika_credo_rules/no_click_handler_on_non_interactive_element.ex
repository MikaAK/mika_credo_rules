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
      bindings: ["phx-click"],
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
        `["phx-click"]`. A Hologram repo wanting this check's protection
        must configure both `sigils: [:sigil_HOLO]` and `bindings:
        ["$click"]` together — the defaults never combine to scan Hologram
        templates, since `sigils` defaults to `[:sigil_H, :sigil_F]`.
        `MikaCredoRules.NoPhxBindingsInHoloTemplate` covers Hologram
        templates independently of this check.
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
  target) is not flagged once it carries BOTH `role=` and `tabindex=` — the
  escape hatch is a conjunction, not a flat ban, because those two
  attributes are exactly what restores keyboard/AT accessibility to a
  non-native element.

  An `aria-hidden="true"` element (e.g. a modal backdrop the user never
  navigates to directly) is exempted independently of `role`/`tabindex` —
  pairing `role`+`tabindex` with `aria-hidden="true"` would itself be a
  WCAG violation, so satisfying the conjunction escape is not an option
  for this case.

  An opening tag may span multiple lines; this check scans from `<tag` to
  its matching `>` regardless of how many lines that spans.

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo, so this check is blind to every `.html.heex` file.
  A `>` character appearing inside a quoted attribute value (e.g.
  `title="a > b"`) would incorrectly end the tag scan early; this is
  accepted as a rare edge case rather than handled with a full attribute
  parser.

  Suppressing an issue reported inside a sigil body works the same way as
  every other sigil check in this package — see the "Limitations" section
  of `MikaCredoRules.NoRawMarkupInTemplates` for the two escapes that
  actually work (a HEEx-comment-wrapped pragma inside the sigil does not).
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
      not all_escape_attributes?(text, context.escape_attributes) and
      not aria_hidden?(text)
  end

  # `aria-hidden="true"` exempts a tag on its own, independently of
  # `escape_attributes` — satisfying role+tabindex on an aria-hidden element
  # would itself be a WCAG violation, so the two escapes can never combine.
  defp aria_hidden?(text), do: String.contains?(text, "aria-hidden=\"true\"")

  defp has_binding?(text, bindings), do: Enum.any?(bindings, &binding_present?(text, &1))

  defp binding_present?(text, binding) do
    String.contains?(text, "#{binding}=\"") or String.contains?(text, "#{binding}={")
  end

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
        "#{match.trigger} with a click binding found — put the click on a native " <>
          "<button type=\"button\"> INSIDE it (or add role and tabindex)",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end
end
