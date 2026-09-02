defmodule MikaCredoRules.LowercaseErrorMessages do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      enforce_lowercase_first: false,
      functions: [
        :not_found,
        :bad_request,
        :internal_server_error,
        :unauthorized,
        :forbidden,
        :unprocessable_entity,
        :too_many_requests,
        :im_a_teapot,
        :service_unavailable,
        :conflict,
        :gone,
        :not_implemented,
        :bad_gateway,
        :gateway_timeout
      ]
    ],
    explanations: [
      params: [
        enforce_lowercase_first: """
        When `true`, also requires the message's first letter to be
        lowercase. Defaults to `false` — a proper noun as the first word
        ("GitHub is unreachable") would otherwise be a false positive, so
        this half of the rule is opt-in.
        """,
        functions: """
        A list of `ErrorMessage` constructor names whose first argument is
        checked when it is a string literal. Defaults to the 14 most common
        HTTP-status constructors — `ErrorMessage` ships 49 in total, so
        extend this list to cover the rest.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  `ErrorMessage` and `raise/2` message strings must not carry a trailing `.`
  or `!` — the caller composes them into larger sentences and log lines,
  where a stray terminator reads oddly.

      # BAD — trailing period
      defmodule MyApp.Users do
        def find(nil), do: ErrorMessage.not_found("User not found.")
      end

      # GOOD — no trailing punctuation
      defmodule MyApp.Users do
        def find(nil), do: ErrorMessage.not_found("user not found")
      end

  The same rule applies to `raise/2`, whether the message is passed
  positionally, through a `message:` keyword, or piped (`Mod |> raise(...)`,
  which folds `Mod` into `raise/1`'s first argument the same way any other
  `|>` call folds its LHS, giving the same two-arg shape as `raise Mod,
  ...`):

      # BAD — trailing bang
      defmodule MyApp.Users do
        def validate!(:invalid), do: raise(ArgumentError, "Bad input!")
      end

      # GOOD — no trailing punctuation
      defmodule MyApp.Users do
        def validate!(:invalid), do: raise(ArgumentError, "bad input")
      end

  By default only trailing punctuation is enforced — `:enforce_lowercase_first`
  additionally requires a lowercase first letter, and is off by default for
  the reason given above.

  A trailing `?` is left alone — a question reads fine as a sentence
  fragment. Only the first argument of a constructor call is inspected, and
  the trailing-punctuation half of the rule skips any string whose LAST
  segment is interpolation (`"missing: \#{id}"`), since the runtime value of
  the trailing character is unknowable statically. The lowercase-first half
  (`:enforce_lowercase_first`) is unaffected — it inspects the FIRST
  segment, which is always known statically, so it still fires on a string
  whose last segment is interpolation.

  Every issue is reported at the call itself — the constructor's module
  reference (`ErrorMessage`, or whatever alias/rename names it at the call
  site), or `raise`'s own keyword — never at the message literal, which
  carries no source position of its own. A multi-line constructor call's
  message can sit on a later line than the call; a piped call's message
  (its LHS) can sit on an earlier one. Either way, the reported line and
  column are the CALL's, not the message's.

  ## Limitations

    * Only the first argument of a constructor call is inspected — a bad
      trailing character inside a `details` argument is invisible.
    * `raise/2`'s exception module identity is never checked; any two-arg
      `raise` is in scope, not only ones naming a project exception. This
      only covers the bare `raise` spelling — the fully qualified
      `Kernel.raise(...)` is not recognised.
    * A bare `raise "message"` (arity 1, no exception module, not piped)
      and an unqualified, `import`ed constructor call are not recognised —
      module identity is resolved only for the qualified `ErrorMessage.<fun>`
      spelling.
    * A message built with a sigil (`~s(...)`) is not recognised — only a
      plain string literal or a `"...\#{...}"` interpolation is inspected.
      A non-interpolated heredoc lowers to a plain string literal, so it IS
      inspected — but its trailing newline normally defeats the
      trailing-punctuation half of the rule; only a heredoc using a
      line-continuation `\\` on its last content line (dropping that
      newline) can fire THAT half. An interpolated heredoc lowers to the
      same AST shape as any other interpolated string and is inspected the
      same way. The lowercase-first half (`:enforce_lowercase_first`) only
      inspects the first character, so it is unaffected by the trailing
      newline and can fire on any heredoc, interpolated or not.
    * `:enforce_lowercase_first` matches ASCII `[A-Z]` only.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context), [])
    |> Enum.reverse()
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file, params) do
    %{
      enforce_lowercase_first?: Params.get(params, :enforce_lowercase_first, __MODULE__),
      constructor_modules: constructor_modules(source_file),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  # A file that defines its own bare `ErrorMessage` module shadows the real
  # one for every unqualified reference in that file — resolve_aliases/2
  # alone cannot see this, since it only tracks `alias`, not `defmodule`.
  defp constructor_modules(source_file) do
    AstHelpers.resolve_aliases(source_file, [ErrorMessage]) --
      AstHelpers.defined_module_names(source_file)
  end

  # ErrorMessage.<constructor>(message, ...) — only the first argument is
  # ever a candidate; the rest (details, etc.) are never inspected. The
  # issue is anchored at the module reference's own AST position
  # (`alias_meta`) — the same node the sibling `NoBangMailerDeliver` check
  # anchors on — never at the message literal, which carries no metadata of
  # its own.
  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, [message | _rest]} =
           ast,
         violations,
         context
       ) do
    if module in context.constructor_modules and function in context.functions do
      {ast, record_violation(context, message, trigger(module, function), alias_meta, violations)}
    else
      {ast, violations}
    end
  end

  # message |> ErrorMessage.<constructor>(...) — the piped spelling. The
  # piped call's own args never include the implicit first argument, so its
  # node is rewritten to a block once consumed here (the exemplar pattern
  # is `NoCastAllKeys`'s piped `cast` handling) — this stops the standalone
  # clause above from re-examining the same call with a shifted argument
  # list once the walk descends into it. Anchored the same way as the
  # direct call, at the RHS constructor's own module reference.
  defp traverse(
         {:|>, pipe_meta,
          [lhs, {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args}]} = ast,
         violations,
         context
       ) do
    if module in context.constructor_modules and function in context.functions do
      {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
       record_violation(context, lhs, trigger(module, function), alias_meta, violations)}
    else
      {ast, violations}
    end
  end

  # Mod |> raise(message: "...") — the piped keyword spelling. `|>` folds the
  # LHS into `raise/1`'s first argument at macro-expansion time, which
  # Credo's parse-only AST never runs — so what Credo sees is `raise/1`
  # (arity 1) with the exception module sitting outside as the pipe's own
  # LHS, and `opts` (arity 1's lone argument) is `raise Mod, opts`'s keyword
  # list under a different AST shape.
  defp traverse({:|>, _pipe_meta, [_lhs, {:raise, meta, [opts]}]} = ast, violations, context)
       when is_list(opts) do
    {ast, record_message_key_violation(context, opts, meta, violations)}
  end

  # Mod |> raise("...") — the piped positional spelling, same desugaring.
  defp traverse({:|>, _pipe_meta, [_lhs, {:raise, meta, [message]}]} = ast, violations, context) do
    {ast, record_violation(context, message, "raise", meta, violations)}
  end

  # raise Mod, message: "..." — the keyword form of raise/2.
  defp traverse({:raise, meta, [_exception, opts]} = ast, violations, context)
       when is_list(opts) do
    {ast, record_message_key_violation(context, opts, meta, violations)}
  end

  # raise Mod, "..." — the positional form of raise/2. A non-string,
  # non-keyword second argument (a variable, say) is handled inside
  # `record_violation/5`, which is total over every AST shape it can be
  # handed.
  defp traverse({:raise, meta, [_exception, message]} = ast, violations, context) do
    {ast, record_violation(context, message, "raise", meta, violations)}
  end

  defp traverse(ast, violations, _context), do: {ast, violations}

  defp trigger(module, function), do: "#{Enum.join(module, ".")}.#{function}"

  defp record_message_key_violation(context, opts, meta, violations) do
    case AstHelpers.keyword_literal_has_key?(opts, :message) do
      true ->
        record_violation(context, Keyword.fetch!(opts, :message), "raise", meta, violations)

      _not_literal_or_missing ->
        violations
    end
  end

  defp record_violation(context, message, trigger, meta, violations) do
    cond do
      trailing_punctuation?(message) ->
        [violation(trigger, meta, :trailing_punctuation) | violations]

      context.enforce_lowercase_first? and starts_uppercase?(message) ->
        [violation(trigger, meta, :uppercase_first) | violations]

      true ->
        violations
    end
  end

  defp violation(trigger, meta, reason) do
    %{trigger: trigger, line_no: meta[:line], column: meta[:column], reason: reason}
  end

  defp trailing_punctuation?(message) do
    case last_literal_segment(message) do
      nil -> false
      text -> String.ends_with?(text, ".") or String.ends_with?(text, "!")
    end
  end

  defp starts_uppercase?(message) do
    case first_literal_segment(message) do
      nil -> false
      text -> String.match?(text, ~r/^[A-Z]/)
    end
  end

  # A plain string literal carries its trailing text directly. An
  # interpolated string (`{:<<>>, _, parts}`) can only be judged when its
  # LAST part is a plain binary segment — when the last part is itself the
  # interpolation, the runtime trailing character is unknowable statically.
  defp last_literal_segment(message) when is_binary(message), do: message
  defp last_literal_segment({:<<>>, _, parts}), do: parts |> List.last() |> literal_segment()
  defp last_literal_segment(_ast), do: nil

  defp first_literal_segment(message) when is_binary(message), do: message
  defp first_literal_segment({:<<>>, _, parts}), do: parts |> List.first() |> literal_segment()
  defp first_literal_segment(_ast), do: nil

  defp literal_segment(segment) when is_binary(segment), do: segment
  defp literal_segment(_non_literal_segment), do: nil

  defp issue_for(violation, issue_meta) do
    format_issue(issue_meta,
      message: "#{violation.trigger} found — #{reason_text(violation.reason)}",
      trigger: violation.trigger,
      line_no: violation.line_no,
      column: violation.column
    )
  end

  defp reason_text(:trailing_punctuation) do
    "error messages must not end with a trailing . or !; the caller composes them into larger sentences"
  end

  defp reason_text(:uppercase_first) do
    "error messages must start with a lowercase letter; the caller composes them into larger sentences"
  end
end
