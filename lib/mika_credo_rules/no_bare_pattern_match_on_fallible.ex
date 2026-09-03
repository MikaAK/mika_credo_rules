defmodule MikaCredoRules.NoBarePatternMatchOnFallible do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      tags: [:ok, :error],
      allowed_functions: [:start_link, :start],
      excluded_paths: ["_test.exs", "test/", "/application.ex", "priv/repo/"]
    ],
    explanations: [
      params: [
        tags: """
        A list of atoms that mark a 2-tuple as fallible. A `=` match whose left-hand
        side is a 2-tuple starting with one of these atoms is inspected.

        Defaults to `[:ok, :error]`.
        """,
        allowed_functions: """
        A list of function-name atoms whose calls may be bare-matched, whatever module
        they live on. Process-start functions are the canonical entries: a start
        failure is a boot problem, so crashing at the match site is exactly the right
        behaviour — `{:ok, pid} = Task.start_link(fn -> ... end)` is the idiom, and
        rewriting it as a handled failure path (or worse, swapping to a raw
        `spawn_link` to appease the check) makes the code strictly worse.

        Matched on the final call of the right-hand side (through pipes), qualified
        or unqualified.

        Defaults to `[:start_link, :start]`.
        """,
        excluded_paths: """
        A list of path fragments exempt from the check, matched at a path-segment
        boundary (see `MikaCredoRules.SourceFilter.matches_fragment?/2`).

        Defaults to `["_test.exs", "test/", "/application.ex", "priv/repo/"]` —
        `assert {:ok, _} = call()` is the correct test idiom (a crash *is* the
        assertion), a boot-time `{:ok, pid} = Supervisor.start_link(...)` in
        `application.ex` is a deliberate crash-on-boot, and so is a broken seed
        script under `priv/repo/`.
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

  Process-start calls are the deliberate exception. A start failure is a boot
  problem — crashing at the match site is exactly right, and the crash carries
  the start error in its `MatchError`. `:allowed_functions` (default
  `[:start_link, :start]`) exempts them by function name, on any module:

      # GOOD — a failed start SHOULD crash here; do not "handle" it,
      # and never swap to a raw spawn_link to appease this check
      def start_link(opts) do
        {:ok, pid} = Task.start_link(fn -> init_table(opts) end)
        {:ok, pid}
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

  A `=` inside a `quote do ... end` body is indistinguishable from real code
  to this check and is flagged even though it is macro-generated AST, not a
  runtime match.
  """
  @explanation [check: @moduledoc]

  @non_call_heads [
    :%{},
    :%,
    :{},
    :<<>>,
    :fn,
    :&,
    :^,
    :||,
    :<>,
    :@,
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
      allowed = Params.get(params, :allowed_functions, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, {tags, allowed}))
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
  defp traverse({:->, meta, [_head, body]}, matches, _context) do
    {{:->, meta, [[], body]}, matches}
  end

  defp traverse({:=, meta, [lhs, rhs]} = ast, matches, {tags, allowed}) do
    if fallible_pattern?(lhs, tags) and call?(rhs) and not allowed_call?(rhs, allowed) do
      {ast, [%{line_no: meta[:line], column: meta[:column], tag: elem(lhs, 0)} | matches]}
    else
      {ast, matches}
    end
  end

  defp traverse(ast, matches, _context), do: {ast, matches}

  # A pipe's riskiness lives in its final call — `fn -> ... end |> Task.start_link()`
  # is an allowed call exactly when `Task.start_link(...)` is.
  defp allowed_call?({:|>, _, [_lhs, rhs]}, allowed), do: allowed_call?(rhs, allowed)

  defp allowed_call?({{:., _, [_target, function]}, _, args}, allowed) when is_list(args),
    do: function in allowed

  defp allowed_call?({name, _, args}, allowed) when is_atom(name) and is_list(args),
    do: name in allowed

  defp allowed_call?(_rhs, _allowed), do: false

  defp fallible_pattern?(lhs, tags) do
    is_tuple(lhs) and tuple_size(lhs) === 2 and elem(lhs, 0) in tags
  end

  defp call?({:|>, _, [_lhs, _rhs]}), do: true

  # An anonymous function call (`fun.()`) carries a 1-element dot target list
  # (just the function), not `[target, function_name]` — always a call.
  defp call?({{:., _, [_fun]}, _, args}) when is_list(args), do: true

  defp call?({{:., _, [target, _function]}, call_meta, args}) when is_list(args) do
    not parenless_field_read?(call_meta, target) and not access_bracket_read?(call_meta)
  end

  defp call?({name, _, args}) when is_atom(name) and is_list(args),
    do: name not in @non_call_heads

  defp call?(_rhs), do: false

  # `state.result` (no parens) desugars to the same dot-call shape as a real
  # remote call, distinguished only by `no_parens: true` in the call's own
  # meta. `Module.fun` (no parens) is still a genuine call — only a field
  # read on a non-module target is exempt.
  defp parenless_field_read?(call_meta, target) do
    Keyword.get(call_meta, :no_parens, false) and not module_reference?(target)
  end

  # `opts[:key]` desugars to `Access.get(opts, :key)`, tagged `from_brackets:
  # true` on the call — a rebind, not a risky call.
  defp access_bracket_read?(call_meta), do: Keyword.get(call_meta, :from_brackets, false)

  defp module_reference?({:__aliases__, _, _}), do: true
  defp module_reference?(_target), do: false

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: "{:#{match.tag}, _} = call found — handle the failure with `case` or `with`",
      trigger: "=",
      line_no: match.line_no,
      column: match.column
    )
  end
end
