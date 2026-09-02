### `HttpWrapperRequiresPoolName`

A Finch-backed adapter attribute must carry a dedicated pool `name:`.
`Tesla.Adapter.Finch.call/2` requires `:name` — it calls
`Keyword.fetch!(opts, :name)`, so an adapter tuple with no `name:` (or no
opts at all) compiles cleanly but raises `KeyError` the instant a request
actually goes out. Setting `name: __MODULE__` on the `@adapter` attribute —
matching a Finch pool started under that same name, typically via
`SharedUtils.HTTP.child_spec(name: __MODULE__)` in the wrapper's own
`child_spec/1` — is what keeps the attribute usable at runtime.

```elixir
# BAD — no opts at all, so nothing can carry name:
defmodule MyApp.Courses do
  @adapter Tesla.Adapter.Finch

  def new(opts \\ []) do
    SharedUtils.HTTP.client([], @adapter, opts)
  end
end

# GOOD — a dedicated pool
defmodule MyApp.Courses do
  @adapter {Tesla.Adapter.Finch, name: __MODULE__}

  def new(opts \\ []) do
    SharedUtils.HTTP.client([], @adapter, opts)
  end
end
```

Only the attribute's own opts position is ever inspected. When it is a
literal keyword list, it is checked for `:name` directly. When the whole
attribute is just the bare adapter module — no tuple, no opts position on
the attribute itself — the check assumes the house idiom holds (the full
adapter tuple, `name:` included, lives on the attribute) and fires the same
as an empty opts list. A nested attribute or a computed value in the tuple's
opts position is opaque to a static check and is left alone rather than
guessed at.

This check targets the `@adapter` attribute itself and never a
`SharedUtils.HTTP.get/post/delete/patch/request` call site. An earlier
version of this spec proposed flagging those calls directly for a missing
`name:` opt; that direction was dropped because `SharedUtils.HTTP`'s verb
functions `defdelegate ..., to: Tesla`, and Tesla builds the request `Env`
via `struct(Env, options ++ [...])` — `struct/2` silently drops any key it
does not already define, so a bare `name:` at the top level of a call's
opts list would be discarded rather than doing anything. The adapter tuple
(or a per-request `opts: [adapter: [...]]`, see Limitations) is where a
pool name actually has to live, which is why this check inspects `@adapter`
instead. Call sites that route through `SharedUtils.HTTP` outside an
API-wrapper app are covered by the sibling `NoSharedUtilsHTTPOutsideApiApps`
check.

**Limitations:** only a literal keyword list in the attribute's opts
position is inspected — anything else there is silently skipped rather than
guessed at, an accepted false negative even when it genuinely carries
`name:` at runtime. This covers a nested attribute reference
(`@adapter {Tesla.Adapter.Finch, @default_adapter_opts}`), a call result,
and a literal list whose entries are not `key: value` pairs
(`@adapter {Tesla.Adapter.Finch, ["name"]}`, or a string-keyed
`[{"name", __MODULE__}]`) — even though the latter provably can never carry
`name:` at all. Only a directly-authored `@attribute value` form is
recognised — an attribute set through `Module.put_attribute/3` or injected
by a macro is invisible to Credo. An adapter tuple passed inline to
`SharedUtils.HTTP.client/3` without ever being stored on the configured
attribute is not checked — this package's house idiom always names the
adapter tuple on an attribute first, and this check follows that idiom. A
bare-module attribute (`@adapter Tesla.Adapter.Finch`) always fires, even
when a call site diverges from that idiom and splices `name:` around the
attribute itself (`{@adapter, name: __MODULE__}`), or when the pool name
instead arrives per request via `opts: [adapter: [name: MyFinch]]` (Tesla
merges `env.opts[:adapter]` over the adapter tuple's own opts at the
highest precedence, and `SharedUtils.HTTP.client/3` forwards `opts[:adapter]`
the same way) — call sites are never inspected, only the attribute's own
AST shape, so both are indistinguishable from a call site that supplies no
name at all. An accepted false positive.

| Param | Default | Meaning |
|---|---|---|
| `attribute` | `:adapter` | The module attribute name that holds the Tesla adapter tuple. |
| `adapter_modules` | `[Tesla.Adapter.Finch]` | Adapter modules whose opts are checked for a dedicated pool `name:`, alias-aware. |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips (matched on segment boundaries). |
