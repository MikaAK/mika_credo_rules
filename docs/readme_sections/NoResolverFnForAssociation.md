### `NoResolverFnForAssociation`

A `resolve` anonymous function whose entire body is `{:ok, root.field}` (or
`{:ok, Map.get(root, :field)}`) defeats Dataloader batching — it issues one
query per parent object instead of one batched query for the whole list.
Both the direct-call form and the `resolve:` keyword-option form are
matched.

```elixir
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
```

Only the simple shape is matched: the fn must have exactly 3 parameters —
the arity Absinthe binds to `(source, args, info)` — and the flagged
variable must be the fn's FIRST parameter, referenced directly. At any
other arity the check stays silent: Absinthe binds parameter 1 to `args`
itself at 2-arity, not the parent/source, so `fn args, _info -> {:ok,
args.message} end` is a different idiom, not a parent access; 1-arity and
4-or-more-arity clauses are not valid Absinthe resolvers at all. Only the
LAST expression of the clause body is inspected; an earlier statement that
does not touch the first parameter (a log call, a reassignment of some
OTHER variable) is never looked at and does not exempt the fn — but a body
that reassigns the first parameter itself before the final expression is
left alone entirely, since the check's own advice (drop the resolver) would
also drop that reassignment and change what the field returns — a
destructuring reassignment that binds the same name (`{root, _meta} = ...`)
counts too. A destructured first parameter, a `Map.get/2` call keyed by
anything other than an atom literal, or computation wrapping the field
access in that final expression is a different idiom and is left alone.
`{:ok, root}` (passing the whole parent straight through), a
`resolve(&Resolvers.thing/3)` capture, and a `resolve(dataloader(Source))`
call are never matched. The `resolve:` keyword form is matched only as a
keyword-list argument of a plain local call (`field`, `value`,
`subscription`, and similar Absinthe DSL macros) — the last argument, or
the last argument before a trailing `do...end` block when the call has
one. Elixir operators (`=`, `++`, `&&`, `|>`, ...), a 3-or-more-element
tuple literal (`{:a, :b, [resolve: fn ...]}`), and module attribute
assignments (`@anything ...`, not only `@resolve fn ... end`) quote to
the same shape as a local call and are excluded, whatever their body —
`table = [resolve: fn ...]`, `[name: :a] ++ [resolve: fn ...]`, `{:a,
:b, [resolve: fn ...]}`, and `@dispatch_table [resolve: fn ...]` are
never matched. A `%{resolve: fn ...}` map literal and a
`Keyword.merge(..., resolve: fn ...)` call to a qualified function are a
different construct and are never matched either. `Map.get/2` is
recognised under any alias, `Elixir.`-prefixed spelling, or local
shadowing.

**Limitations:** only a fn with exactly one clause, exactly 3 parameters,
and a plain (non-pattern) first parameter is inspected — a guarded or
multi-clause fn, a 2-arity or 1-arity or 4-or-more-arity clause (2-arity
binds parameter 1 to `args`, not the source; the others are not valid
Absinthe resolvers), or one that destructures its first parameter (`fn
%{source: root}, _args, _info -> ... end`), is silently skipped rather than
guessed at. A resolve fn piped in rather than passed as a direct call argument
(`fn root, _args, _info -> {:ok, root.owner} end |> resolve()`) is not
matched either — the pipe's raw AST carries no arguments on the `resolve`
call node to inspect. The keyword form's `resolve:` text is located by
scanning the fn's own source line — when the keyword and the fn it points
to are split across lines, the issue is reported with no trigger token
rather than a wrong or missing column. The message's "drop the resolver"
advice assumes the accessed field name already matches the enclosing
`field`'s identifier — Absinthe's default resolution (and `dataloader/1`)
reads by field name, so dropping the resolver when the two differ (`field
:creator, :user do resolve fn post, _, _ -> {:ok, post.author} end end`)
would change what the field returns; the check does not compare the two.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
