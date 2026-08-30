defmodule MikaCredoRules.MonolithicTemplateComponent do
  use Credo.Check,
    base_priority: :normal,
    category: :refactor,
    param_defaults: [
      max_lines: 60,
      sigils: [:sigil_H, :sigil_F],
      excluded_paths: []
    ],
    explanations: [
      params: [
        max_lines: """
        The number of physical lines a `~H`/`~F` body may span before it is
        flagged. Defaults to `60`.
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
  A `~H`/`~F` template body that spans too many lines almost certainly
  contains multiple logical phases that should be their own function
  components.

  A single sprawling template is harder to read top-to-bottom, harder to
  reuse a piece of, and hides how many distinct concerns it actually
  renders.

      # BAD — one sigil, three phases (header / groups / rows), 90 lines
      def progress(assigns), do: ~H\"\"\"
        ...90 lines...
      \"\"\"

      # GOOD
      def progress(assigns) do
        ~H\"\"\"
        <.progress_header {assigns} />
        <.lesson_group_card :for={g <- @groups} group={g} />
        \"\"\"
      end

  This is a decomposition nudge, not a strict correctness rule — the exact
  threshold is a heuristic. `max_lines` defaults to 60, buying headroom
  over a stricter "over ~40 lines with 2+ phases" prose guideline (only the
  line-count half of that guideline is mechanically checkable).

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo, so this check is blind to every `.html.heex` file.
  Only `~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are covered
  (which also means a legitimately long, single-purpose whole-page
  `.html.heex` template is not the false-positive risk it would otherwise
  be). The `trigger:` reported is always the literal string `"~H"`, even
  for a `~F` match — the check does not track which sigil letter matched.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      max_lines = Params.get(params, :max_lines, __MODULE__)
      sigils = Params.get(params, :sigils, __MODULE__)

      source_file
      |> TemplateSigils.collect(sigils)
      |> Enum.filter(&(TemplateSigils.line_count(&1) > max_lines))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp issue_for(sigil, issue_meta) do
    line_count = TemplateSigils.line_count(sigil)

    format_issue(issue_meta,
      message:
        "~H sigil spanning #{line_count} #{pluralize_line(line_count)} found — " <>
          "decompose into smaller function components",
      trigger: "~H",
      line_no: sigil.line_no
    )
  end

  defp pluralize_line(1), do: "line"
  defp pluralize_line(_line_count), do: "lines"
end
