defmodule MikaCredoRules.NoBarePatternMatchOnFallible do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      tags: [:ok, :error],
      excluded_paths: ["_test.exs", "test/", "application.ex"]
    ],
    explanations: [
      params: [
        tags: """
        A list of atoms that mark a 2-tuple as fallible. A `=` match whose left-hand
        side is a 2-tuple starting with one of these atoms is inspected.

        Defaults to `[:ok, :error]`.
        """,
        excluded_paths: """
        A list of path fragments exempt from the check, matched at a path-segment
        boundary (see `MikaCredoRules.SourceFilter.matches_fragment?/2`).

        Defaults to `["_test.exs", "test/", "application.ex"]` — `assert {:ok, _} =
        call()` is the correct test idiom (a crash *is* the assertion), and a
        boot-time `{:ok, pid} = Supervisor.start_link(...)` in `application.ex` is a
        deliberate crash-on-boot.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A bare `=` match against a fallible-tagged call must be handled explicitly with
  `case` or `with`, not left to crash with an opaque `MatchError`.

  `{:ok, user} = Accounts.fetch(id)` works right up until `Accounts.fetch/1`
  returns `{:error, reason}`, at which point it crashes with a `MatchError` that
  says nothing about *why* the call failed — no error reason, no context. Handle
  the failure path explicitly instead.

      # BAD — a MatchError with no context if the call fails
      def sync(id) do
        {:ok, user} = Accounts.fetch(id)
        broadcast(user)
      end

      # GOOD
      def sync(id) do
        with {:ok, user} <- Accounts.fetch(id) do
          broadcast(user)
        end
      end

  Only a match whose right-hand side is an actual call — a local call, a remote
  call, or a pipe — is flagged. Rebinding an already-tagged value reads as a
  shape assertion, not a missed failure path, and is left alone:

      # GOOD — the right-hand side is a variable, not a call
      def log(result) do
        {:ok, user} = result
        broadcast(user)
      end

  A `case`/`fn` clause head that binds the whole matched value alongside a shape
  (`{:ok, _} = result -> ...`) is a pattern, not a statement, and is never
  flagged — only the clause body is inspected. `<-` in `with` and `for` is a
  different construct entirely and is never matched:

      # GOOD — `=` in a case clause head is a pattern, not a statement
      case fetch(id) do
        {:ok, _} = result -> handle(result)
        {:error, _} = error -> error
      end

  ## Limitations

  Only a literal local call, remote call, or pipe on the right-hand side is
  considered a call. A control-flow expression (`case`, `if`, `cond`, `for`, a
  `fn`) is never flagged, even when it ultimately returns a fallible-tagged
  tuple — the bare-match risk lives at the call boundary, and control-flow
  bodies are outside this check's scope.
  """
  @explanation [check: @moduledoc]

  @non_call_heads [
    :%{},
    :%,
    :{},
    :<<>>,
    :fn,
    :&,
    :__aliases__,
    :__block__,
    :case,
    :cond,
    :if,
    :unless,
    :with,
    :for,
    :receive,
    :try,
    :quote,
    :super
  ]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_file?(source_file.filename, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      tags = Params.get(params, :tags, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, tags))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_file?(filename, params) do
    SourceFilter.matches_fragment?(filename, excluded_paths(params))
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  # A `case`/`fn` clause head is a pattern, not a statement — `{:ok, _} = result
  # -> ...` binds the whole matched value alongside a shape and must not be
  # treated as a missed-failure-path match. The head is discarded here; the
  # body is still walked normally by the outer prewalk.
  defp traverse({:->, meta, [_head, body]}, matches, _tags) do
    {{:->, meta, [[], body]}, matches}
  end

  defp traverse({:=, meta, [lhs, rhs]} = ast, matches, tags) do
    if fallible_pattern?(lhs, tags) and call?(rhs) do
      {ast, [%{line_no: meta[:line], column: meta[:column], tag: elem(lhs, 0)} | matches]}
    else
      {ast, matches}
    end
  end

  defp traverse(ast, matches, _tags), do: {ast, matches}

  defp fallible_pattern?(lhs, tags) do
    is_tuple(lhs) and tuple_size(lhs) === 2 and elem(lhs, 0) in tags
  end

  defp call?({:|>, _, [_lhs, _rhs]}), do: true
  defp call?({{:., _, [_target, _function]}, _, args}) when is_list(args), do: true

  defp call?({name, _, args}) when is_atom(name) and is_list(args),
    do: name not in @non_call_heads

  defp call?(_rhs), do: false

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "{:#{match.tag}, _} = call found — handle the failure with `case` or `with`",
      trigger: "=",
      line_no: match.line_no,
      column: match.column
    )
  end
end
