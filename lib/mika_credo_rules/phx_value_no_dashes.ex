defmodule MikaCredoRules.PhxValueNoDashes do
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
  A multiword `phx-value-*` attribute key must use underscores, never
  dashes.

  LiveView takes the text after `phx-value-` VERBATIM as the param key:
  `phx-value-group-id` becomes `%{"group-id" => ...}` (the dash is kept,
  not converted). A handler clause pattern-matching on
  `%{"group_id" => group_id}` then never matches, and the click silently
  raises a `FunctionClauseError` instead of running.

      # BAD — never matches a %{"group_id" => _} handler clause
      ~H\"\"\"
      <button phx-click="delete" phx-value-group-id={@id}>Delete</button>
      \"\"\"

      # GOOD
      ~H\"\"\"
      <button phx-click="delete" phx-value-group_id={@id}>Delete</button>
      \"\"\"

  Single-word keys (`phx-value-id`, `phx-value-kind`) are unaffected — there
  is no dash to mistranslate.

  ## Limitations

  Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
  never read by Credo, so this check is blind to every `.html.heex` file.
  Only `~H`/`~F` sigils colocated inside a `.ex`/`.exs` module are covered.
  """
  @explanation [check: @moduledoc]

  @key_regex ~r/phx-value-([a-zA-Z0-9_-]+)(?=[=\s>])/

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      sigils = Params.get(params, :sigils, __MODULE__)

      source_file
      |> TemplateSigils.collect(sigils)
      |> Enum.flat_map(&dashed_key_matches/1)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded?(filename, params) do
    SourceFilter.matches_fragment?(filename, Params.get(params, :excluded_paths, __MODULE__))
  end

  defp dashed_key_matches(sigil) do
    @key_regex
    |> Regex.scan(sigil.body, return: :index)
    |> Enum.filter(&dashed_key?(sigil.body, &1))
    |> Enum.map(&build_match(sigil, &1))
  end

  defp dashed_key?(body, [_whole, {key_offset, key_length}]) do
    body |> binary_part(key_offset, key_length) |> String.contains?("-")
  end

  defp build_match(sigil, [{whole_offset, whole_length}, _key]) do
    %{
      trigger: binary_part(sigil.body, whole_offset, whole_length),
      line_no: TemplateSigils.line_at(sigil, whole_offset),
      column: TemplateSigils.column_at(sigil, whole_offset)
    }
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{match.trigger} found — use underscores in multiword phx-value keys " <>
          "(#{underscored_key(match.trigger)})",
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end

  # Only the key after the `phx-value-` prefix gets underscored — the
  # prefix's own dash (between "phx" and "value") must stay a dash.
  defp underscored_key("phx-value-" <> key), do: "phx-value-" <> String.replace(key, "-", "_")
end
