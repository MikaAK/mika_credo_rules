defmodule MikaCredoRules.NoRawMarkupInTemplates do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      rules: [:inline_style, :hex_color, :inline_svg, :raw_tag],
      banned_tags: [],
      allow_dynamic_style: true,
      sigils: [:sigil_H, :sigil_F],
      excluded_paths: ["_icons/", "icons/"]
    ],
    explanations: [
      params: [
        rules: """
        Which markup rules run inside every `~H`/`~F` body. Defaults to all
        four: `:inline_style`, `:hex_color`, `:inline_svg`, `:raw_tag`.
        """,
        banned_tags: """
        Raw tag names flagged by the `:raw_tag` rule (e.g. `["button"]` in a
        repo with a `<.button>` primitive). Defaults to `[]`, so `:raw_tag`
        is effectively off until a repo opts a tag in.
        """,
        allow_dynamic_style: """
        When `true` (default), a dynamic `style={...}` expression is allowed
        and only a literal `style="..."` attribute is flagged. When `false`,
        both forms are flagged.
        """,
        sigils: """
        Which sigil names count as template bodies. Defaults to
        `[:sigil_H, :sigil_F]`.
        """,
        excluded_paths: """
        Path fragments, matched at a segment boundary, whose files are
        skipped entirely. Defaults to `["_icons/", "icons/"]` — the app
        that legitimately owns raw `<svg>` markup.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter
  alias MikaCredoRules.TemplateSigils

  @moduledoc """
  Raw HTML primitives inside a `~H`/`~F` template body must go through the
  project's design system instead of being hand-rolled.

  A literal `style="..."` attribute, a hardcoded hex color, or an inline
  `<svg>` bypasses the Tailwind theme / design tokens / icon component the
  rest of the app relies on — the next redesign has to hunt down every
  ad-hoc copy instead of changing one token.

      # BAD
      ~H\"\"\"
      <div style="width: 30%">
        <svg viewBox="0 0 24 24"><path d="M0 0"/></svg>
        <span class="bg-[#1d4ed8]">badge</span>
      </div>
      \"\"\"

      # GOOD
      ~H\"\"\"
      <div class="w-1/3">
        <.icon name="check" />
        <.badge tone="info">badge</.badge>
      </div>
      \"\"\"

  Four independent rules, each toggleable via `:rules`:

    * `:inline_style` — a literal `style="..."` attribute. A dynamic
      `style={...}` expression is allowed by default (`allow_dynamic_style:
      true`) — the primitives skill's two sanctioned exceptions (a computed
      percentage width, an API-returned hex color) are both interpolated.
    * `:hex_color` — a 6-digit hex color (`#1d4ed8`). 3-digit hex is
      deliberately NOT matched: `href="#abc"` anchor fragments are
      indistinguishable from a 3-digit color and would be a constant false
      positive.
    * `:inline_svg` — a literal `<svg` tag.
    * `:raw_tag` — any tag name in `:banned_tags` (empty by default, so this
      rule is a no-op until a repo opts specific tags in, e.g. `["button"]`
      once it has a `<.button>` primitive).

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo (`Credo.Sources.@default_sources_glob` is
  `~w(** *.{ex,exs})`), so this check is **blind to every `.html.heex`
  file**. Only `~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are
  covered.

  Suppression works inside a template exactly like anywhere else, via a
  HEEx comment wrapping the disable pragma:

      <%!-- # credo:disable-for-next-line MikaCredoRules.NoRawMarkupInTemplates --%>
      <svg viewBox="0 0 24 24">...</svg>
  """
  @explanation [check: @moduledoc]

  @style_regex ~r/(?<=\s)style="/
  @dynamic_style_regex ~r/(?<=\s)style=\{/
  @hex_color_regex ~r/#[0-9a-fA-F]{6}\b/
  @svg_regex ~r/<svg\b/

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
      |> Enum.flat_map(&matches_for_sigil(&1, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp build_context(params) do
    %{
      rules: Params.get(params, :rules, __MODULE__),
      banned_tags: Params.get(params, :banned_tags, __MODULE__),
      allow_dynamic_style: Params.get(params, :allow_dynamic_style, __MODULE__),
      sigils: Params.get(params, :sigils, __MODULE__)
    }
  end

  defp matches_for_sigil(sigil, context) do
    Enum.flat_map(context.rules, &matches_for_rule(&1, sigil, context))
  end

  defp matches_for_rule(:inline_style, sigil, context), do: inline_style_matches(sigil, context)
  defp matches_for_rule(:hex_color, sigil, _context), do: hex_color_matches(sigil)
  defp matches_for_rule(:inline_svg, sigil, _context), do: inline_svg_matches(sigil)
  defp matches_for_rule(:raw_tag, sigil, context), do: raw_tag_matches(sigil, context)

  defp inline_style_matches(sigil, context) do
    regexes =
      if context.allow_dynamic_style,
        do: [@style_regex],
        else: [@style_regex, @dynamic_style_regex]

    Enum.flat_map(regexes, &scan(sigil, &1, :inline_style, fn _text -> "style=" end))
  end

  defp hex_color_matches(sigil), do: scan(sigil, @hex_color_regex, :hex_color, & &1)

  defp inline_svg_matches(sigil), do: scan(sigil, @svg_regex, :inline_svg, fn _text -> "<svg" end)

  defp raw_tag_matches(sigil, context) do
    Enum.flat_map(context.banned_tags, &raw_tag_matches_for(sigil, &1))
  end

  defp raw_tag_matches_for(sigil, tag) do
    regex = Regex.compile!("<" <> Regex.escape(tag) <> "\\b")
    scan(sigil, regex, :raw_tag, fn _text -> "<#{tag}" end)
  end

  defp scan(sigil, regex, rule, trigger_fun) do
    regex
    |> Regex.scan(sigil.body, return: :index)
    |> Enum.map(fn [{offset, length} | _] ->
      build_match(sigil, offset, length, rule, trigger_fun)
    end)
  end

  defp build_match(sigil, offset, length, rule, trigger_fun) do
    matched_text = binary_part(sigil.body, offset, length)

    %{
      rule: rule,
      trigger: trigger_fun.(matched_text),
      line_no: TemplateSigils.line_at(sigil, offset),
      column: TemplateSigils.column_at(sigil, offset)
    }
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "#{match.trigger} found — #{fix_for(match.rule)}",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end

  defp fix_for(:inline_style),
    do: "use a Tailwind utility class instead of an inline style attribute"

  defp fix_for(:hex_color), do: "use a design token instead of a hardcoded hex color"
  defp fix_for(:inline_svg), do: "use the <.icon> component instead of an inline <svg>"

  defp fix_for(:raw_tag),
    do: "use the project's primitive component instead of a raw tag"
end
