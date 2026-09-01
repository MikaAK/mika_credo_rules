defmodule MikaCredoRules.NoHardcodedSecretLiterals do
  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [
      patterns: [
        {"Stripe key", ~r/(sk|pk|rk)_(live|test)_[0-9A-Za-z]{10,}/},
        {"Stripe webhook secret", ~r/whsec_[0-9A-Za-z]{10,}/},
        {"AWS access key", ~r/AKIA[0-9A-Z]{16}/},
        {"Slack token", ~r/xox[baprs]-[0-9A-Za-z-]{10,}/},
        {"GitHub token", ~r/(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{20,}/},
        {"GitHub fine-grained token", ~r/github_pat_[0-9A-Za-z_]{20,}/},
        {"PEM private key", ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/},
        {"Bearer token", ~r/Bearer [A-Za-z0-9._-]{40,}/}
      ],
      excluded_paths: []
    ],
    explanations: [
      params: [
        patterns: """
        A list of `{label, regex}` pairs. Any string literal matching a regex
        anywhere in its text is reported with its label — the matched text is
        never echoed. This list REPLACES the default; re-list any defaults
        you still want.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]` — nothing is exempted by this
        check itself. Whether `config/*.exs` is actually scanned depends on
        Credo's own `files.included`, not this param: most `.credo.exs`
        files (including this package's own) scope `files.included` to
        `["lib/", "test/", "mix.exs"]`, which never reaches `config/`. Add
        `"config/"` to `files.included` to cover it — exactly where secrets
        are most often hardcoded.
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
  every string literal Credo hands it. Nothing is exempted by this check's own
  `:excluded_paths` by default — but `config/*.exs` is only scanned if Credo's
  own `files.included` reaches it (most `.credo.exs` files, including this
  package's own, scope `files.included` to `["lib/", "test/", "mix.exs"]`,
  which never reaches `config/`); widen `files.included` to cover it.

      # BAD — committed to version control the moment this file is saved
      @auth_header "Bearer xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

      # GOOD — read at runtime, never committed
      def auth_header, do: "Bearer " <> Application.get_env(:my_app, :api_token)

  The matched secret is never echoed in the issue message — only which pattern
  matched (e.g. "Stripe key"), so running this check does not itself leak the
  credential into CI logs. The issue carries no `:trigger` either
  (`Credo.Issue.no_trigger/0`), for the same reason.

  The examples above use the `Bearer` shape on purpose. A realistic Stripe or AWS
  literal in a doc block is itself detected by GitHub's secret scanning and blocks
  the push, so examples here must demonstrate a shape no scanner claims.

  A pattern matches anywhere in a literal, not only the whole string — a
  Stripe key embedded inside a full URL or a Bearer token inside a full
  `"Authorization: Bearer ..."` header is caught the same as a bare literal.
  Heredocs, the static segments of an interpolated string, and a charlist
  sigil (`~c"sk_live_..."`, whose AST carries its content as a plain binary)
  are all scanned the same as a plain string literal — `"sk_live_\#{key}"`
  still exposes the static `"sk_live_"` prefix as a segment, though that
  prefix alone is too short to match a default pattern (every default
  requires 10+ trailing characters). `@moduledoc`, `@doc` and `@typedoc`
  attribute values are skipped, since check and library documentation
  legitimately shows a credential's *shape* without being a real one.

  ## Limitations

  A credential concatenated from parts (`"sk_live_" <> rest`) or built
  entirely through interpolation is not detected — an accepted false
  negative, since only the static pieces of the source are ever visible to a
  check, and static analysis cannot know a runtime value.
  """
  @explanation [check: @moduledoc]

  @skipped_attributes [:moduledoc, :doc, :typedoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      patterns = Params.get(params, :patterns, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, patterns), [])
      |> Enum.map(&issue_for(&1, source_file, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp traverse({:@, _, [{attribute, _, _}]}, matches, _patterns)
       when attribute in @skipped_attributes do
    {nil, matches}
  end

  defp traverse(ast, matches, patterns) when is_binary(ast) do
    case matching_pattern(ast, patterns) do
      nil -> {ast, matches}
      label -> {ast, [%{label: label, literal: ast} | matches]}
    end
  end

  defp traverse(ast, matches, _patterns), do: {ast, matches}

  defp matching_pattern(literal, patterns) do
    Enum.find_value(patterns, fn {label, regex} ->
      if Regex.match?(regex, literal), do: label
    end)
  end

  defp issue_for(match, source_file, issue_meta) do
    {line_no, column} = locate(source_file, match.literal)

    format_issue(issue_meta,
      message:
        "#{match.label} found — never commit secrets; read them from Application config or an environment variable instead",
      trigger: Issue.no_trigger(),
      line_no: line_no,
      column: column
    )
  end

  # The AST carries the literal's runtime value, not its position — 2-tuples
  # and list elements have no metadata to read a real line/column from. The
  # real position is found by searching the file's own source text instead.
  defp locate(source_file, literal) do
    first_line = literal |> String.split("\n") |> List.first()

    source_file
    |> Credo.SourceFile.source()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value({1, nil}, &locate_in_line(&1, first_line))
  end

  defp locate_in_line(_line_and_index, ""), do: nil

  defp locate_in_line({line, index}, needle) do
    case :binary.match(line, needle) do
      {start, _length} -> {index, start + 1}
      :nomatch -> nil
    end
  end
end
