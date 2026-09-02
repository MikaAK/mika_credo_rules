defmodule MikaCredoRules.NoTemplateVariableAssignment do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      sigils: [:sigil_H, :sigil_F],
      excluded_paths: []
    ],
    explanations: [
      params: [
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
  A `<% var = ... %>` EEx assignment tag inside a `~H`/`~F` template body
  disables HEEx change tracking for every dynamic part that reads the
  variable, so those parts are recomputed and re-sent on every diff instead
  of being skipped when nothing changed.

      # BAD
      ~H\"\"\"
      <% user = @current_user %>
      <p>{user.name}</p>
      \"\"\"

      # GOOD
      ~H\"\"\"
      <p>{@current_user.name}</p>
      \"\"\"

  Compute the value where it belongs instead: `assign/3` in `mount/3` or
  `handle_event/3`, or a function component, so it participates in change
  tracking the same as every other assign.

  A discard assignment (`<% _ = something %>`) still fires — the shape on
  the page is identical to a real assignment, and singling out `_` for a
  pass would need a second regex for a case rare enough not to earn one.

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo (`Credo.Sources.@default_sources_glob` is
  `~w(** *.{ex,exs})`), so this check is **blind to every `.html.heex`
  file**. Only `~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are
  covered.

  This is a raw-text regex scan of the sigil body, not an EEx parser, so
  it only recognizes a bare-identifier left-hand side. A destructuring
  assignment (`<% {first, second} = compute_pair() %>`) is a measured
  false negative, and so is a second assignment sharing a tag with the
  first (`<% a = 1; b = 2 %>` only reports `a =`) — the regex requires
  `<%` to be followed directly by a single identifier, not a pattern, and
  scans each `<%` opener once. An output tag (`<%= user = @current_user
  %>`) is deliberately silent by design, not a gap: the regex only matches
  a plain `<%` opener, never `<%=`.

  Measured false positive: a `<%!-- ... --%>` HEEx comment still fires
  when its text happens to contain `<% var = ... %>` — this is a raw-text
  scan of the sigil body, not an EEx parser, so it has no notion that
  `<%!-- --%>` wraps its contents as a comment never evaluated at
  runtime (same class of gap as `NoRawMarkupInTemplates`'s `<svg` inside
  an HTML comment).

  A `#` inside a `~H`/`~F` heredoc is template string content, not a
  comment token, so `# credo:disable-for-next-line` placed directly above
  the `~H\"\"\"` line never suppresses an issue reported from inside the
  body — the issue's line is inside the template, past that anchor.
  Suppress with `# credo:disable-for-lines:N` or `# credo:disable-for-this-file`
  placed above the enclosing `def` instead (see `NoRawMarkupInTemplates`'s
  Limitations section for the full explanation of why).
  """
  @explanation [check: @moduledoc]

  @assignment_regex ~r/<%\s*([a-z_][A-Za-z0-9_]*[?!]?)\s*=(?![=~])/

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if SourceFilter.matches_fragment?(source_file.filename, excluded_paths) do
      []
    else
      run_on_source(source_file, params)
    end
  end

  defp run_on_source(source_file, params) do
    sigils = Params.get(params, :sigils, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> TemplateSigils.collect(sigils)
    |> Enum.flat_map(&assignment_matches/1)
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp assignment_matches(sigil) do
    @assignment_regex
    |> Regex.scan(sigil.body, return: :index)
    |> Enum.map(&build_match(sigil, &1))
  end

  defp build_match(sigil, [{full_offset, full_length}, {name_offset, _name_length}]) do
    trigger_length = full_offset + full_length - name_offset
    raw_trigger = binary_part(sigil.body, name_offset, trigger_length)

    %{
      trigger: clamp_to_first_line(raw_trigger),
      line_no: TemplateSigils.line_at(sigil, name_offset),
      column: TemplateSigils.column_at(sigil, name_offset)
    }
  end

  defp clamp_to_first_line(trigger) do
    case String.split(trigger, "\n", parts: 2) do
      [first_line, _rest] -> String.trim_trailing(first_line)
      [only_line] -> only_line
    end
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "#{match.trigger} found — #{fix_message()}",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end

  defp fix_message do
    "assign the value with assign/3 (or compute it in a function component) " <>
      "instead of a <% %> block; a template variable assignment disables HEEx " <>
      "change tracking, forcing that part to be recomputed and re-sent on " <>
      "every render"
  end
end
