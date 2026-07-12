# credo:disable-for-this-file MikaCredoRules.TodosNeedTickets
defmodule MikaCredoRules.TodosNeedTickets do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      tags: ["Todo", "TODO", "Fixme", "FIXME"],
      ticket_url: "http"
    ],
    explanations: [
      params: [
        tags: """
        A list of tag words treated as todos. Matching is case-insensitive, so the
        default list collapses to TODO and FIXME in any casing.
        """,
        ticket_url: """
        The substring a line must contain to count as a ticket reference. The
        default of `"http"` accepts any `http://` or `https://` URL. Set it to your
        tracker's URL prefix (e.g. `"https://linear.app/company/issue/"`) so only
        real tickets count.
        """
      ]
    ]

  alias Credo.Check.Design.TagHelper

  @moduledoc """
  Every todo comment must reference a ticket URL on the same or an adjacent line.

  A todo without a ticket has no owner, no priority and no deadline — it is a wish,
  not a plan. Every TODO/FIXME comment must carry a ticket URL on its own line, the
  line directly above it or the line directly below it.

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

  Doc attributes (`@doc`, `@moduledoc`, `@shortdoc`) that start with a tag word are
  flagged too. Line adjacency means nothing inside a doc string, so a doc todo
  passes when the same doc string contains a ticket URL anywhere.

  By default any `http://` or `https://` URL counts as a ticket reference. Set the
  `:ticket_url` param to your tracker's URL prefix so only real tickets count:

      {MikaCredoRules.TodosNeedTickets, ticket_url: "https://linear.app/company/issue/"}
  """
  @explanation [check: @moduledoc]

  @doc_attribute_names [:doc, :moduledoc, :shortdoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    tags = Params.get(params, :tags, __MODULE__)
    ticket_url = Params.get(params, :ticket_url, __MODULE__)
    source_lines = source_lines(source_file)

    source_file
    |> todo_tags(tags)
    |> Enum.reject(&ticketed?(&1, source_lines, ticket_url))
    |> Enum.map(&issue_for(&1, issue_meta, ticket_url))
  end

  defp todo_tags(source_file, tags) do
    comment_tags(source_file, tags) ++ doc_tags(source_file, tags)
  end

  defp comment_tags(source_file, tags) do
    tags
    |> Enum.flat_map(&TagHelper.tags(source_file, &1, false))
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {line_no, _line, trigger} -> {:comment, line_no, trigger} end)
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
    regex = Regex.compile!("\\A\\s*#{tag}:?\\s*.+", "i")

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
