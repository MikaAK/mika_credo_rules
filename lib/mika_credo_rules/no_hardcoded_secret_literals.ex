defmodule MikaCredoRules.NoHardcodedSecretLiterals do
  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [
      patterns: [
        {"Stripe key", ~r/^(sk|pk|rk)_(live|test)_[0-9A-Za-z]{10,}$/},
        {"Stripe webhook secret", ~r/^whsec_[0-9A-Za-z]{10,}$/},
        {"AWS access key", ~r/^AKIA[0-9A-Z]{16}$/},
        {"Slack token", ~r/^xox[baprs]-[0-9A-Za-z-]{10,}$/},
        {"GitHub token", ~r/^(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{20,}$/},
        {"GitHub fine-grained token", ~r/^github_pat_[0-9A-Za-z_]{20,}$/},
        {"PEM private key", ~r/^-----BEGIN [A-Z ]*PRIVATE KEY-----/},
        {"Bearer token", ~r/^Bearer [A-Za-z0-9._-]{40,}$/}
      ],
      excluded_paths: []
    ],
    explanations: [
      params: [
        patterns: """
        A list of `{label, regex}` pairs. Any string literal matching a regex
        is reported with its label — the matched text is never echoed. This
        list REPLACES the default; re-list any defaults you still want.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]` — the check runs on every file,
        including `config/*.exs` and `mix.exs`, since those are exactly where
        secrets get hardcoded.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  String literals must not be hardcoded credentials — read secrets from
  `Application` config or an environment variable instead.

  A committed key is compromised the moment it reaches version control:
  rotating it after the fact does not undo the exposure, and CI mirrors, forks
  and local clones all keep a copy. This check matches known credential shapes
  (Stripe, AWS, Slack, GitHub, PEM private keys, long `Bearer` tokens) against
  every string literal in every file, including `config/*.exs` and `mix.exs`.

      # BAD — committed to version control the moment this file is saved
      @auth_header "Bearer xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

      # GOOD — read at runtime, never committed
      def auth_header, do: "Bearer " <> Application.get_env(:my_app, :api_token)

  The matched secret is never echoed in the issue message — only which pattern
  matched (e.g. "Stripe key"), so running this check does not itself leak the
  credential into CI logs.

  The examples above use the `Bearer` shape on purpose. A realistic Stripe or AWS
  literal in a doc block is itself detected by GitHub's secret scanning and blocks
  the push, so examples here must demonstrate a shape no scanner claims.

  Heredocs and the static segments of an interpolated string are scanned the
  same as a plain literal — `"sk_live_\#{key}"` still exposes the static
  `"sk_live_"` prefix as a segment, though that prefix alone is too short to
  match a default pattern (every default requires 10+ trailing characters).
  `@moduledoc` and `@doc` attribute values are skipped, since check and
  library documentation legitimately shows a credential's *shape* without
  being a real one.

  ## Limitations

  Patterns are anchored (`^`/`$`) against the whole literal, so a credential
  concatenated from parts (`"sk_live_" <> rest`) or built through
  interpolation is not detected — an accepted false negative, since static
  analysis cannot know the runtime value. Anchoring also means a credential
  embedded as a substring of a longer literal (e.g. inside a full HTTP header
  string) is not detected either; widen a pattern through `:patterns` if a
  project's usage needs that.
  """
  @explanation [check: @moduledoc]

  @skipped_attributes [:moduledoc, :doc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      patterns = Params.get(params, :patterns, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, patterns), %{line: nil, matches: []})
      |> Map.fetch!(:matches)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp traverse({:@, _, [{attribute, _, _}]}, acc, _patterns)
       when attribute in @skipped_attributes do
    {nil, acc}
  end

  defp traverse(ast, acc, patterns) do
    acc = remember_line(acc, ast)

    if is_binary(ast) do
      {ast, record_match(ast, acc, patterns)}
    else
      {ast, acc}
    end
  end

  defp remember_line(acc, {_form, meta, _args}) when is_list(meta) do
    case meta[:line] do
      nil -> acc
      line -> %{acc | line: line}
    end
  end

  defp remember_line(acc, _ast), do: acc

  defp record_match(literal, acc, patterns) do
    case matching_pattern(literal, patterns) do
      nil -> acc
      label -> %{acc | matches: [%{label: label, line_no: acc.line} | acc.matches]}
    end
  end

  defp matching_pattern(literal, patterns) do
    Enum.find_value(patterns, fn {label, regex} ->
      if Regex.match?(regex, literal), do: label
    end)
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{match.label} found — never commit secrets; read them from Application config or an environment variable instead",
      trigger: match.label,
      line_no: match.line_no
    )
  end
end
