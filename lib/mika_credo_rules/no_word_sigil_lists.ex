defmodule MikaCredoRules.NoWordSigilLists do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      sigils: [:sigil_w, :sigil_W],
      excluded_paths: []
    ],
    explanations: [
      params: [
        sigils: """
        A list of sigil node atoms to ban. Defaults to `[:sigil_w, :sigil_W]`,
        the interpolating and non-interpolating word-list sigils.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips. A fragment
        matches when the source file's path starts with it, ends with it, or
        contains it after a directory separator.

        Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Word lists must be written as list literals, never the `~w`/`~W` sigil.

  `~w(a b)` and `["a", "b"]` compile to the identical list; `~w(a b)a` and
  `[:a, :b]` likewise. The sigil saves a few characters of quoting and costs
  more than it saves: `grep '"customer_id"'` finds the bracket form and misses
  the sigil, so a field's call sites can't be enumerated reliably, and the
  difference between `~w(a b)` and `~w(a b)a` is one easily-missed character
  where `["a"]` vs `[:a]` cannot be misread.

      # BAD
      @enforce_keys ~w(id type changes)a
      Map.take(changes, ~w(customer_id customer_name))

      # GOOD
      @enforce_keys [:id, :type, :changes]
      Map.take(changes, ["customer_id", "customer_name"])

  ## Adoption note

  `~w` is widespread idiomatic Elixir, and this rule is absolute rather than
  situational — every existing `~w`/`~W` site in a mature codebase will be
  reported the first time this check is enabled, not just newly written code.
  Adopt with a baseline (fix the reported sites, or exempt them through
  `:excluded_paths`) rather than expecting a clean run immediately.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      sigils = Params.get(params, :sigils, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, sigils))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp traverse({sigil, meta, [{:<<>>, _, _}, _modifiers]} = ast, sightings, sigils)
       when is_atom(sigil) do
    if sigil in sigils do
      {ast, [sighting(sigil, meta) | sightings]}
    else
      {ast, sightings}
    end
  end

  defp traverse(ast, sightings, _sigils), do: {ast, sightings}

  defp sighting(sigil, meta) do
    %{
      trigger: sigil_trigger(sigil),
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp sigil_trigger(sigil), do: "~" <> String.trim_leading(Atom.to_string(sigil), "sigil_")

  defp issue_for(sighting, issue_meta) do
    format_issue(issue_meta,
      message: "#{sighting.trigger} found — use a list literal instead of a word sigil",
      trigger: sighting.trigger,
      line_no: sighting.line_no,
      column: sighting.column
    )
  end
end
