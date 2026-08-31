# credo:disable-for-this-file MikaCredoRules.TodosNeedTickets
defmodule MikaCredoRules.TodosNeedTickets do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      tags: ["TODO", "FIXME", "OPTIMIZE", "HACK", "REVIEW"],
      ticket_url: "http",
      require_uppercase: false
    ],
    explanations: [
      params: [
        tags: """
        A list of tag words treated as todos. Each tag matches as a whole word —
        matching is case-insensitive, so a default entry like `"TODO"` matches
        `TODO`, `Todo` and `todo` alike, but not `TODOs` or `HACKney`, where a
        letter, digit or underscore immediately follows the tag.
        """,
        ticket_url: """
        The substring a line must contain to count as a ticket reference. The
        default of `"http"` accepts any `http://` or `https://` URL. Set it to your
        tracker's URL prefix (e.g. `"https://linear.app/company/issue/"`) so only
        real tickets count.
        """,
        require_uppercase: """
        When `true`, a tag must be spelled in uppercase and immediately followed by
        a colon (`TODO:`) — `todo:` and `Todo:` are reported even when ticketed.
        Defaults to `false`.
        """
      ]
    ]

  alias Credo.Check.Design.TagHelper

  @moduledoc """
  Every todo comment must reference a ticket URL on the same or an adjacent line.

  A todo without a ticket has no owner, no priority and no deadline — it is a wish,
  not a plan. Every annotation comment (`TODO`, `FIXME`, `OPTIMIZE`, `HACK`,
  `REVIEW` by default) must carry a ticket URL on its own line, the line directly
  above it or the line directly below it.

      # BAD — nothing tracks this
      # TODO: make this faster

      # BAD — the ticket URL is not adjacent to the todo
      # TODO: make this faster
      def work, do: :ok
      # https://linear.app/company/issue/443

      # GOOD — the ticket URL on the same line
      # TODO: make this faster, see https://linear.app/company/issue/443

      # GOOD — the ticket URL on the next line
      # TODO: make this faster
      # https://linear.app/company/issue/443

      # GOOD — the ticket URL on the previous line
      # https://linear.app/company/issue/443
      # TODO: make this faster

  Each tag matches as a whole word, not a prefix — a trailing letter, digit or
  underscore means the comment is prose, not an annotation:

      # GOOD — "TODOs" is a word, not the tag "TODO"
      # TODOs remaining before release

      # BAD — the tag itself, still needs a ticket
      # TODO: remaining work

  Doc attributes (`@doc`, `@moduledoc`, `@shortdoc`) that start with a tag word are
  flagged too. Line adjacency means nothing inside a doc string, so a doc todo
  passes when the same doc string contains a ticket URL anywhere.

  By default any `http://` or `https://` URL counts as a ticket reference. Set the
  `:ticket_url` param to your tracker's URL prefix so only real tickets count:

      {MikaCredoRules.TodosNeedTickets, ticket_url: "https://linear.app/company/issue/"}

  Setting `:require_uppercase` to `true` additionally requires the tag itself to be
  spelled in uppercase and immediately followed by a colon. This is a formatting
  check, independent of ticketing — it fires even when the todo already carries a
  ticket URL:

      # BAD (require_uppercase: true) — lowercase tag, reported even though ticketed
      # todo: make this faster, see https://linear.app/company/issue/443

      # GOOD (require_uppercase: true) — uppercase tag with a colon
      # TODO: make this faster, see https://linear.app/company/issue/443
  """
  @explanation [check: @moduledoc]

  @doc_attribute_names [:doc, :moduledoc, :shortdoc]
  @tag_boundary "(?![A-Za-z0-9_])"

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    tags = Params.get(params, :tags, __MODULE__)
    ticket_url = Params.get(params, :ticket_url, __MODULE__)
    require_uppercase = Params.get(params, :require_uppercase, __MODULE__)
    source_lines = source_lines(source_file)
    todo_tags = todo_tags(source_file, tags)

    missing_ticket_issues =
      todo_tags
      |> Enum.reject(&ticketed?(&1, source_lines, ticket_url))
      |> Enum.map(&issue_for(&1, issue_meta, ticket_url))

    casing_issues = casing_issues(todo_tags, tags, require_uppercase, issue_meta)

    missing_ticket_issues ++ casing_issues
  end

  defp casing_issues(_todo_tags, _tags, false, _issue_meta), do: []

  defp casing_issues(todo_tags, tags, true, issue_meta) do
    todo_tags
    |> Enum.map(&casing(&1, tags))
    |> Enum.reject(&(is_nil(&1) or &1.compliant?))
    |> Enum.map(&casing_issue_for(&1, issue_meta))
  end

  # Extracts how the tag itself was spelled — its written casing and whether a
  # colon immediately follows — from the trigger text. `nil` when the tag word
  # cannot be found (should not happen, since `text` already matched one of
  # `tags` when it was collected).
  defp casing({_type, line_no, text}, tags) do
    case Enum.find_value(tags, &extract_tag_casing(text, &1)) do
      {written, has_colon?} ->
        %{
          line_no: line_no,
          written: written,
          compliant?: uppercase_with_colon?(written, has_colon?)
        }

      nil ->
        nil
    end
  end

  defp uppercase_with_colon?(written, has_colon?) do
    written === String.upcase(written) and has_colon?
  end

  # Not anchored to `\A` — `TagHelper`'s trigger keeps the character before
  # the comment marker, so a tag appended directly onto code with no
  # separating space would otherwise never match and silently skip the
  # casing check.
  defp extract_tag_casing(text, tag) do
    regex = Regex.compile!("\\s*(?:#\\s*)?(#{Regex.escape(tag)})(:?)", "i")

    case Regex.run(regex, text) do
      [_full, written, colon] -> {written, colon === ":"}
      nil -> nil
    end
  end

  defp casing_issue_for(violation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{violation.written} found — annotation tags must be uppercase followed by a colon (TODO: …)",
      trigger: violation.written,
      line_no: violation.line_no
    )
  end

  defp todo_tags(source_file, tags) do
    comment_tags(source_file, tags) ++ doc_tags(source_file, tags)
  end

  defp comment_tags(source_file, tags) do
    tags
    |> Enum.flat_map(&comment_tags_for(source_file, &1))
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {line_no, _line, trigger} -> {:comment, line_no, trigger} end)
  end

  # `TagHelper`'s own regex has no trailing word boundary, so a widened tag
  # like `HACK` or `OPTIMIZE` fires on ordinary prose (`hackney`, `optimized`).
  # Filter its output rather than reimplementing comment scanning.
  defp comment_tags_for(source_file, tag) do
    source_file
    |> TagHelper.tags(tag, false)
    |> Enum.filter(&tag_word_boundary?(&1, tag))
  end

  defp tag_word_boundary?({_line_no, _line, trigger}, tag) do
    regex = Regex.compile!("#\\s*#{Regex.escape(tag)}#{@tag_boundary}", "i")
    trigger =~ regex
  end

  defp doc_tags(source_file, tags) do
    tags
    |> Enum.flat_map(&doc_tags_for(source_file, &1))
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {line_no, doc_string} -> {:doc, line_no, doc_string} end)
  end

  # Mirrors the anchored regex Credo.Check.Design.TagHelper uses for doc
  # attributes: the doc string must start with the tag word.
  defp doc_tags_for(source_file, tag) do
    regex = Regex.compile!("\\A\\s*#{tag}#{@tag_boundary}:?\\s*.+", "i")

    Credo.Code.prewalk(source_file, &doc_traverse(&1, &2, regex))
  end

  defp doc_traverse({:@, _, [{name, meta, [string]} | _]} = ast, doc_todos, regex)
       when name in @doc_attribute_names and is_binary(string) do
    if string =~ regex do
      {nil, [{meta[:line], String.trim_trailing(string)} | doc_todos]}
    else
      {ast, doc_todos}
    end
  end

  defp doc_traverse(ast, doc_todos, _regex), do: {ast, doc_todos}

  defp ticketed?({:comment, line_no, _trigger}, source_lines, ticket_url) do
    adjacent_lines = (line_no - 1)..(line_no + 1)

    Enum.any?(adjacent_lines, &line_references_ticket?(source_lines, &1, ticket_url))
  end

  defp ticketed?({:doc, _line_no, doc_string}, _source_lines, ticket_url) do
    String.contains?(doc_string, ticket_url)
  end

  defp line_references_ticket?(source_lines, line_no, ticket_url) do
    source_lines
    |> Map.get(line_no, "")
    |> String.contains?(ticket_url)
  end

  defp source_lines(source_file) do
    source_file
    |> SourceFile.source()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Map.new(fn {line, line_no} -> {line_no, line} end)
  end

  defp issue_for({:comment, line_no, trigger}, issue_meta, ticket_url) do
    build_issue(issue_meta, line_no, trigger, ticket_url)
  end

  defp issue_for({:doc, line_no, doc_string}, issue_meta, ticket_url) do
    build_issue(issue_meta, line_no, doc_string, ticket_url)
  end

  defp build_issue(issue_meta, line_no, trigger, ticket_url) do
    format_issue(issue_meta,
      message:
        "#{trigger} found — todos must reference a ticket URL (matching \"#{ticket_url}\") " <>
          "on the same or an adjacent line",
      trigger: trigger,
      line_no: line_no
    )
  end
end
