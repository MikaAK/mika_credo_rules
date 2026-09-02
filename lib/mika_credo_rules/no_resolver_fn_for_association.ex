defmodule MikaCredoRules.NoResolverFnForAssociation do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments naming files this check skips, matched on
        path-segment boundaries. Defaults to `["_test.exs", "test/"]` —
        schema test fixtures routinely stub a trivial `resolve` fn with no
        Dataloader wired up.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `resolve` anonymous function whose entire body is `{:ok, root.field}` (or
  `{:ok, Map.get(root, :field)}`) defeats Dataloader batching — it issues one
  query per parent object instead of one batched query for the whole list.
  Both the direct-call form and the `resolve:` keyword-option form are
  matched.

      # BAD — one query per parent instead of a batched load
      field :owner, :user do
        resolve fn root, _args, _info ->
          {:ok, root.owner}
        end
      end

      # BAD — same idiom, as a `resolve:` keyword option
      field :owner, :user, resolve: fn root, _args, _info -> {:ok, root.owner} end

      # GOOD — batches through Dataloader
      field :owner, :user do
        resolve dataloader(Accounts)
      end

      # GOOD — real computation, not a trivial pass-through
      field :owner, :user do
        resolve fn root, _args, _info ->
          {:ok, format_owner(root.owner)}
        end
      end

  Only the simple shape is matched: the fn must have exactly 3 parameters —
  the arity Absinthe binds to `(source, args, info)` — and the flagged
  variable must be the fn's FIRST parameter, referenced directly. At any
  other arity the check is silent: Absinthe binds parameter 1 to `args`
  itself at 2-arity, not the parent/source, so `fn args, _info -> {:ok,
  args.message} end` is a different idiom, not a parent access; 1-arity
  and 4-or-more-arity clauses are not valid Absinthe resolvers at all.
  Only the LAST expression of the clause body is inspected; an earlier
  statement in the same body that
  does not touch the first parameter (a log call, a reassignment of some
  OTHER variable) is never looked at and does not exempt the fn — but a body
  that reassigns the first parameter itself before the final expression
  (`root = Repo.preload(root, :owner); {:ok, root.owner}`) is left alone
  entirely, since the check's own advice (drop the resolver) would also drop
  that reassignment and change what the field returns — a destructuring
  reassignment that binds the same name (`{root, _meta} =
  MyApp.Repo.preload_with_meta(root, :owner)`) counts too. A destructured first
  parameter (`fn %{owner: owner}, _args, _info -> {:ok, owner} end`), a
  `Map.get/2` call with anything other than an atom literal key, or
  computation wrapping the field access in that final expression (`{:ok,
  format(root.owner)}`) is a different idiom and is left alone. `{:ok,
  root}` (passing the whole parent straight through) is also a distinct
  idiom, not the batching bug this check exists to catch. A
  `resolve(&Resolvers.thing/3)` capture or a `resolve(dataloader(Source))`
  call is never matched.

  The `resolve:` keyword form is matched only as a keyword-list argument of
  a plain local call (`field`, `value`, `subscription`, and similar
  Absinthe DSL macros) — the last argument, or the last argument before a
  trailing `do...end` block when the call has one (`field :owner, :user,
  resolve: fn ... end do description "..." end`). Elixir operators (`=`,
  `++`, `&&`, `|>`, ...), a 3-or-more-element tuple literal (`{:a, :b,
  [resolve: fn ...]}`, which Elixir quotes under the same `:{}` head), and
  module attribute assignments (`@anything ...`, not only `@resolve fn
  ... end`) quote to the same atom-head-plus-args shape as a local call
  and are excluded, whatever their body — `table = [resolve: fn ...]`,
  `[name: :a] ++ [resolve: fn ...]`, `{:a, :b, [resolve: fn ...]}`, and
  `@dispatch_table [resolve: fn ...]` are never matched. A
  `%{resolve: fn ...}` map literal and a `Keyword.merge(..., resolve: fn
  ...)` call to a qualified function are a different construct and are
  never matched either. `Map.get/2` is recognised under any alias,
  `Elixir.`-prefixed spelling, or local shadowing (a file-level `alias` or
  a nested `defmodule Map`).

  ## Limitations

    * Only a fn with exactly one clause is inspected — a guarded or
      multi-clause fn is silently skipped rather than guessed at.
    * Only a 3-arity clause (`fn source, args, info -> ... end`) is
      inspected. Absinthe binds parameter 1 to the arguments map at
      2-arity, not the parent/source, so a 2-arity resolve fn is always
      skipped, whatever its body references; 1-arity and 4-or-more-arity
      clauses are not valid Absinthe resolvers and are skipped too.
    * The first parameter must be a plain variable; a fn that destructures
      it (a map or tuple pattern) is silently skipped, even when the
      destructured binding is used the same way a plain parameter would be.
    * A resolve fn piped in rather than passed as a direct call argument
      (`fn root, _args, _info -> {:ok, root.owner} end |> resolve()`) is not
      matched — the pipe's raw AST carries no arguments on the `resolve`
      call node to inspect.
    * The keyword form's `resolve:` text is located by scanning the fn's
      own source line — when the keyword and the fn it points to are split
      across lines, no such text exists on the fn's line and the issue is
      reported with no trigger token (`Credo.Issue.no_trigger/0`) rather
      than a wrong or missing column.
    * The "drop the resolver" half of the message's advice assumes the
      accessed field name already matches the enclosing `field`'s
      identifier. Absinthe's default resolution (and `dataloader/1`) reads
      by field name, so on `field :creator, :user do resolve fn post, _,
      _ -> {:ok, post.author} end end` dropping the resolver would change
      what the field returns — the check does not compare the two.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      map_paths =
        AstHelpers.resolve_aliases(source_file, [Map]) --
          AstHelpers.defined_module_names(source_file)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, source_file, map_paths))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # `@name value` (any attribute assignment, not only `@resolve fn ... end`)
  # quotes to `{:@, _, [{:name, _, [value]}]}` — an atom-head-plus-args
  # 3-tuple nested inside another one. The INNER node alone
  # (`{:name, _, [value]}`) is itself indistinguishable from a plain local
  # call, so without pruning here the keyword-form clause below would
  # inspect an attribute's value as if `:name` were a DSL macro (e.g.
  # `@dispatch_table [resolve: fn ...]` would read as a call named
  # `dispatch_table` whose trailing arg is the `resolve:` keyword list).
  # An attribute READ (`@name`, no value) quotes with `nil` in that slot
  # instead of a list and does not match here. A module attribute's value
  # is never a resolve call, whatever it is.
  defp traverse(
         {:@, _meta, [{attr_name, _attr_meta, [_value]}]} = _ast,
         issues,
         _source_file,
         _map_paths
       )
       when is_atom(attr_name) do
    {nil, issues}
  end

  defp traverse(
         {:resolve, meta, [{:fn, _fn_meta, [clause]}]} = ast,
         issues,
         _source_file,
         map_paths
       ) do
    case pass_through_field(clause, map_paths) do
      {var, field, rendered} ->
        {ast,
         [resolve_call(meta[:line], meta[:column], "resolve", var, field, rendered) | issues]}

      nil ->
        {ast, issues}
    end
  end

  # `resolve: fn ... end` as a keyword-list value — matched only when that
  # list is a LOCAL call's argument (`field`, `value`, `subscription`,
  # ...), not an Elixir operator's, and not a 3+-element tuple literal's. A
  # map literal's pairs list (`%{resolve: fn ...}`) IS `args` itself with no
  # extra wrapping list, and a qualified call (`Keyword.merge(...)`) has a
  # `{:., ...}` head instead of a bare atom — both fail the guards below and
  # never reach here. `:__block__` (a bare multi-statement body) is excluded
  # so a stray list literal that merely happens to be a block's last
  # statement is never mistaken for a call argument. Operators (`=`, `++`,
  # `&&`, `|>`, ...) and a 3+-element tuple literal (`{:a, :b, [resolve: fn
  # ...]}`, which Elixir quotes under the `:{}` head) quote to the exact
  # same atom-head-plus-args shape as a call — `table = [resolve: fn ...]`,
  # `[a] ++ [resolve: fn ...]`, and `{:a, :b, [resolve: fn ...]}` would
  # otherwise read as a call whose trailing arg is the `resolve:` keyword
  # list — so `Macro.operator?/2` (arity-aware, unlike a hardcoded name
  # list) plus an explicit `:{}` exclusion rule them out before the search
  # below.
  defp traverse({call_name, _call_meta, args} = ast, issues, source_file, map_paths)
       when is_atom(call_name) and call_name !== :__block__ and call_name !== :{} and
              is_list(args) and args !== [] do
    if Macro.operator?(call_name, length(args)) do
      {ast, issues}
    else
      {ast, keyword_form_issues(args, issues, source_file, map_paths)}
    end
  end

  defp traverse(ast, issues, _source_file, _map_paths), do: {ast, issues}

  defp keyword_form_issues(args, issues, source_file, map_paths) do
    case args |> drop_trailing_do_block() |> List.last() |> find_resolve_keyword() do
      {fn_meta, clause} ->
        case pass_through_field(clause, map_paths) do
          {var, field, rendered} ->
            {line_no, column, trigger} = locate_resolve_keyword(source_file, fn_meta)
            [resolve_call(line_no, column, trigger, var, field, rendered) | issues]

          nil ->
            issues
        end

      nil ->
        issues
    end
  end

  # A call with a `do...end` block (`field :owner, :user, resolve: fn ...
  # end do description "..." end`) appends a synthetic `[do: ...]` keyword
  # list as the true last argument, pushing the `resolve:`-carrying attrs
  # list one slot earlier — every block form always carries a `:do` key
  # (with optional `:else`/`:rescue`/`:catch`/`:after` alongside it), so
  # that key's presence is what marks the synthetic list, not its keys'
  # names.
  defp drop_trailing_do_block(args) do
    if do_block?(List.last(args)) do
      Enum.drop(args, -1)
    else
      args
    end
  end

  defp do_block?(list) when is_list(list), do: Enum.any?(list, &match?({:do, _}, &1))
  defp do_block?(_not_a_list), do: false

  defp find_resolve_keyword(keyword_list) when is_list(keyword_list) do
    Enum.find_value(keyword_list, fn
      {:resolve, {:fn, fn_meta, [clause]}} -> {fn_meta, clause}
      _other -> nil
    end)
  end

  defp find_resolve_keyword(_not_a_keyword_list), do: nil

  # `resolve: fn ... end` inside a keyword list carries no AST metadata on
  # the `:resolve` key itself — only the raw source text has the trigger's
  # real column. Same idiom as `no_hardcoded_secret_literals.ex`'s
  # `locate/2`. The `fn` node's own meta (always present) gives a real line
  # and column to search from: when "resolve:" text sits on that line
  # before the fn — the common case, and the only case when two keyword
  # forms share one line — report it precisely, picking the occurrence
  # closest to THIS fn. When it doesn't (the keyword spans multiple lines),
  # fall back to `Issue.no_trigger()` with the fn's own real column rather
  # than asserting a `"resolve"` trigger on a line that doesn't contain it.
  defp locate_resolve_keyword(source_file, fn_meta) do
    line = fn_meta[:line]
    fn_column = fn_meta[:column]
    line_text = Credo.SourceFile.line_at(source_file, line)

    last_resolve_key =
      line_text
      |> :binary.matches("resolve:")
      |> Enum.filter(fn {start, _length} -> start < fn_column - 1 end)
      |> List.last()

    case last_resolve_key do
      {start, _length} -> {line, start + 1, "resolve"}
      nil -> {line, fn_column, Issue.no_trigger()}
    end
  end

  defp pass_through_field({:->, _, [args, body]}, map_paths) when length(args) === 3 do
    first_param = args |> List.first() |> param_name()
    statements = AstHelpers.block_statements(body)

    if first_param && rebinds_var?(statements, first_param) do
      nil
    else
      statements |> List.last() |> field_access(first_param, map_paths)
    end
  end

  defp pass_through_field(_clause, _map_paths), do: nil

  # A resolve fn that reassigns its first parameter before the final
  # expression (a preload, say) is no longer a trivial pass-through —
  # dropping the resolver, the check's own advice, would also drop that
  # reassignment and change behaviour. Skip rather than mislead. The
  # reassignment need not be a bare `var = ...` — a destructuring pattern
  # that binds the same name (`{root, _meta} = ...`, `%{root: root} = ...`)
  # is reassigning it just the same, so the LHS pattern is walked for any
  # occurrence of the var as a plain variable reference.
  defp rebinds_var?(statements, var) do
    Enum.any?(statements, fn
      {:=, _, [lhs, _rhs]} -> pattern_binds_var?(lhs, var)
      _other -> false
    end)
  end

  defp pattern_binds_var?(pattern, var) do
    {_pattern, binds?} =
      Macro.prewalk(pattern, false, fn
        {:^, _meta, _args}, acc ->
          {nil, acc}

        {^var, _meta, context} = node, _acc when is_nil(context) or is_atom(context) ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    binds?
  end

  defp param_name({name, _meta, context})
       when is_atom(name) and name !== :_ and (is_nil(context) or is_atom(context)) do
    name
  end

  defp param_name(_other), do: nil

  defp field_access({:ok, {{:., _, [{var, _, context}, field]}, _, []}}, first_param, _map_paths)
       when is_atom(var) and (is_nil(context) or is_atom(context)) and is_atom(field) do
    if var === first_param, do: {var, field, "#{var}.#{field}"}
  end

  defp field_access(
         {:ok,
          {{:., _, [{:__aliases__, _, module_segments}, :get]}, _, [{var, _, context}, field]}},
         first_param,
         map_paths
       )
       when is_atom(var) and (is_nil(context) or is_atom(context)) and is_atom(field) do
    if module_segments in map_paths and var === first_param do
      {var, field, "Map.get(#{var}, :#{field})"}
    end
  end

  defp field_access(_last_expr, _first_param, _map_paths), do: nil

  defp resolve_call(line_no, column, trigger, var, field, rendered) do
    %{
      line_no: line_no,
      column: column,
      trigger: trigger,
      var: var,
      field: field,
      rendered: rendered
    }
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "resolve fn found — {:ok, #{call.rendered}} issues one query per parent object; " <>
          "use dataloader(Source), or drop the resolver only if the field name already " <>
          "matches :#{call.field} — Absinthe's default resolution reads by field identifier",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
