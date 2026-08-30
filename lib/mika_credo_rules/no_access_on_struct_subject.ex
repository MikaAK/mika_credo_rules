defmodule MikaCredoRules.NoAccessOnStructSubject do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      subject_names: [:changeset, :conn, :socket],
      excluded_paths: []
    ],
    explanations: [
      params: [
        subject_names: """
        A list of variable name atoms treated as known-struct subjects — an
        `Access` bracket read on a variable with one of these names is
        flagged.

        Defaults to `[:changeset, :conn, :socket]`.
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
  `Access` bracket reads must not be used on a struct.

  `changeset[:name]` compiles, but raises `UndefinedFunctionError` at runtime
  unless the struct's module implements the `Access` behaviour — most structs,
  including `Ecto.Changeset`, `Plug.Conn` and `Phoenix.LiveView.Socket`, do
  not. This is a runtime crash class, not a style preference.

      # BAD — raises UndefinedFunctionError at runtime
      changeset[:name]
      conn[:assigns]
      socket[:assigns]

      # GOOD
      Ecto.Changeset.get_field(changeset, :name)
      conn.assigns
      socket.assigns

  A plain map or keyword list is untouched — `Access` is exactly the right
  tool there:

      # GOOD — not flagged, these are maps/keywords
      params["id"]
      opts[:timeout]

  Two shapes count as a struct subject: a struct literal (`%MyApp.User{}`), or
  a variable whose name is in the configured `:subject_names` list. Full
  struct-type inference from a single-file AST check is out of reach, so the
  name heuristic is the only tractable form; the default list covers the three
  subjects this actually bites in practice.

  ## Limitations

  A nested access such as `opts[:a][:b]` is only ever checked at its
  outermost read when the inner subject (`opts`) matches — the outer read's
  subject is the *result* of the inner access, not a variable or struct
  literal, so it is never flagged regardless of what the inner value turns
  out to be at runtime.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      subject_names = Params.get(params, :subject_names, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, subject_names))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp traverse({{:., _, [Access, :get]}, call_meta, [subject, key]} = ast, issues, subject_names) do
    case subject_representation(subject, subject_names) do
      nil ->
        {ast, issues}

      subject_repr ->
        meta = subject_meta(subject) || call_meta
        {ast, [access(subject_repr, key, meta) | issues]}
    end
  end

  defp traverse(ast, issues, _subject_names), do: {ast, issues}

  defp subject_meta({_tag, meta, _rest}), do: meta
  defp subject_meta(_subject), do: nil

  defp subject_representation({:%, _, [{:__aliases__, _, module}, {:%{}, _, _fields}]}, _names) do
    "%" <> Enum.join(module, ".") <> "{}"
  end

  defp subject_representation({name, _, subject_context}, subject_names)
       when is_atom(name) and is_atom(subject_context) do
    if name in subject_names, do: Atom.to_string(name)
  end

  defp subject_representation(_subject, _subject_names), do: nil

  defp access(subject_repr, key, meta) do
    %{
      trigger: "#{subject_repr}[#{inspect(key)}]",
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(access, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{access.trigger} found — Access on a struct raises UndefinedFunctionError; use struct.field or Ecto.Changeset.get_field/2 instead",
      trigger: access.trigger,
      line_no: access.line_no,
      column: access.column
    )
  end
end
