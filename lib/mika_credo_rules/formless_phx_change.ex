defmodule MikaCredoRules.FormlessPhxChange do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      sigils: [:sigil_H, :sigil_F],
      form_markers: ["<.form", "<form", "<.simple_form"],
      excluded_paths: []
    ],
    explanations: [
      params: [
        sigils: """
        Which sigil names count as template bodies. Defaults to
        `[:sigil_H, :sigil_F]`.
        """,
        form_markers: """
        Substrings whose presence ANYWHERE in the sigil body exempts the
        whole sigil from this check, matched at a text boundary so a
        longer identifier like `<.form_group>` or `<.formatting_help>`
        does not match the `<.form` marker. Defaults to
        `["<.form", "<form", "<.simple_form"]`. A Surface repo scanning
        `~F` templates must add `"<Form"` to this list — matching is
        case-sensitive, and the defaults only match HEEx's
        `<.form`/`<form`/`<.simple_form` spellings, never Surface's
        capitalized `<Form>`. A module-qualified (remote) form component
        like `<Phoenix.Component.form>` also needs a bare `".form"` entry
        added — no default anchors past a fully-qualified module path.
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
  A `phx-change` binding on a bare `<input>`/`<select>`/`<textarea>` reaches
  LiveView's JS fine — `phx-change` is read straight off the input
  (`input.getAttribute(phxChange)` in `live_socket.js`), independent of form
  membership — but two hops later `View.pushInput/6` throws `"form events
  require the input to be inside a form"` (`view.js`) because `inputEl.form`
  is `null` for an element that is not form-associated. In a real browser
  this surfaces as an uncaught JS `Error` in the console, not a silently
  swallowed event. To be form-associated, the element must either be a DOM
  descendant of a `<form>`/`<.form>`/`<.simple_form>`, or carry an HTML
  `form="<id>"` attribute referencing one elsewhere in the document (which
  this check also treats as exempt).

      # BAD
      ~H\"\"\"
      <input type="text" phx-change="update_q" />
      \"\"\"

      # GOOD
      ~H\"\"\"
      <.form for={@form} phx-change="update_q">
        <input type="text" name="q" />
      </.form>
      \"\"\"

  Wrap the element in `<.form>` (or `<form>`/`<.simple_form>`), moving
  `phx-change` onto the form itself if it is not there already.

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo (`Credo.Sources.@default_sources_glob` is
  `~w(** *.{ex,exs})`), so this check is **blind to every `.html.heex`
  file**. Only `~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are
  covered.

  This is a raw-text scan of the whole sigil body, not an HTML parser with
  offset tracking, so it cannot tell which elements a `<.form>` actually
  wraps. The moment ANY `:form_markers` substring appears anywhere in the
  sigil, the ENTIRE sigil is exempted — including a second, genuinely
  formless input elsewhere in the same body that the form does not wrap.
  Precisely locating what a `<.form>` wraps needs a real HTML parser
  tracking open/close tags and their offsets, which this check does not
  have.

  Measured false positive: a field-group function component whose OWN
  `~H` body has no form marker still fires even when every caller wraps
  it in `<.form>` — idiomatic Phoenix slot/component decomposition, e.g. a
  sibling `address_fields/1` rendered from `render/1`'s `<.form>`. The
  form-marker exemption is scanned per sigil, never across the sigils of
  the functions that compose it, because that needs cross-function,
  cross-sigil analysis this raw-text scan does not do.

  Measured false positive: Surface's `<Form>` component (`:sigil_F`) is not
  in the default `:form_markers` list — its raw input children fire by
  default, because Surface capitalizes the tag and the defaults only cover
  HEEx's `<.form`/`<form`/`<.simple_form` spellings. A Surface repo must
  add `"<Form"` to `:form_markers` (see the param explanation above).

  Measured false positive: a module-qualified (remote) form function
  component, e.g. `<Phoenix.Component.form for={@form}>` or
  `<MyAppWeb.CoreComponents.form for={@form}>`, matches no default
  `:form_markers` entry either — every default marker anchors `<`
  immediately before the tag word, so a fully-qualified module path
  between `<` and `.form` never matches, and a raw input inside one fires.
  Add `".form"` (and `".simple_form"` if used remotely) to `:form_markers`
  — the marker is matched anywhere in the sigil body, so the bare suffix
  also matches the qualified call.

  Measured false positive: `<%!-- <input phx-change="..." /> --%>` (a
  HEEx comment) and `<!-- <input phx-change="..." /> -->` (an HTML
  comment) both still fire — this is a raw-text scan with no notion that
  either comment syntax wraps its contents as markup that is never
  rendered (same class of gap as `NoRawMarkupInTemplates`'s `<svg` inside
  an HTML comment).

  The mirror gap also exists: a `:form_markers` substring left inside a
  commented-out `<.form>` (HEEx or HTML comment) still exempts the whole
  sigil, silencing a genuinely formless input elsewhere in the same body —
  same raw-text scan, no notion of comments in either direction.

  An opening tag is bounded by `[^>]*` up to the next `>`, so a `>`
  character inside a quoted or interpolated attribute value (e.g.
  `value={if @count > 1, do: "many"}`) would incorrectly end the tag scan
  early, silencing any `phx-change` that follows on the same tag — this is
  accepted as a rare edge case rather than handled with a full attribute
  parser, same as `NoClickHandlerOnNonInteractiveElement`.

  The `phx-change` attribute regex is matched against the whole opening-tag
  text, not attribute-aware, so `phx-change` appearing inside a DIFFERENT
  attribute's quoted value (e.g. `placeholder=" phx-change='x'"`) also
  fires — same class of gap as `NoRawMarkupInTemplates`'s `style="..."`
  prose false positive.

  Measured false negative: the mirror image of the gap above also exists
  on the `form=` attribute regex. It too is matched against the whole
  opening-tag text, not attribute-aware, so a `form=` substring appearing
  inside a DIFFERENT attribute's quoted value (e.g.
  `placeholder="pick a form='x' value"` or `title="a form='b'"`) is read
  as a genuine form-association and silences a control that is not
  actually form-associated in the DOM — it still throws in a real browser.
  The same raw-text match also treats an empty `form=""` (naming no form
  owner at all) as form-associated, for the same reason.

  Suppressing an issue reported inside a sigil body works the same way as
  every other sigil check in this package — see the "Limitations" section
  of `MikaCredoRules.NoRawMarkupInTemplates` for the two escapes that
  actually work (a HEEx-comment-wrapped pragma inside the sigil does not).
  """
  @explanation [check: @moduledoc]

  @tags ["input", "select", "textarea"]
  @phx_change_attribute_regex ~r/\sphx-change\s*=\s*["'{]/
  @form_attribute_regex ~r/\sform\s*=\s*["'{]/

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
      |> Enum.reject(&form_marker_present?(&1, context.form_markers))
      |> Enum.flat_map(&flagged_tags/1)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp build_context(params) do
    %{
      sigils: Params.get(params, :sigils, __MODULE__),
      form_markers: Params.get(params, :form_markers, __MODULE__)
    }
  end

  defp form_marker_present?(sigil, form_markers) do
    Enum.any?(form_markers, &marker_matches?(sigil.body, &1))
  end

  defp marker_matches?(body, marker) do
    regex = Regex.compile!(Regex.escape(marker) <> "(?!\\w)")
    Regex.match?(regex, body)
  end

  defp flagged_tags(sigil) do
    @tags
    |> Enum.flat_map(&opening_tags(sigil, &1))
    |> Enum.filter(&phx_change?/1)
    |> Enum.reject(&form_associated?/1)
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

  defp phx_change?(%{text: text}) do
    Regex.match?(@phx_change_attribute_regex, text)
  end

  defp form_associated?(%{text: text}) do
    Regex.match?(@form_attribute_regex, text)
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
      message: "#{match.trigger} with phx-change found outside a form — #{fix_message()}",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end

  defp fix_message do
    "wrap it in <.form>/<form>/<.simple_form> (or move phx-change onto the " <>
      "form) so the change event reaches the server instead of throwing " <>
      "\"form events require the input to be inside a form\""
  end
end
