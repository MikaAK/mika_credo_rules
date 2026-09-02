### `PubSubRequiresMessageStruct`

A `Phoenix.PubSub` broadcast payload must be a message struct, never a bare
atom, tuple, or map literal. Subscribers pattern-match on the payload —
`%MyApp.PubSub.Message{}` keeps that match compiler-checked, so renaming or
adding a field is caught everywhere it is matched on. A bare literal gives
subscribers nothing but a runtime shape to match against, and a refactor that
changes that shape fails silently at every subscriber.

```elixir
# BAD — bare atom payload
Phoenix.PubSub.broadcast(pubsub, topic, :updated)

# BAD — bare tuple payload
Phoenix.PubSub.broadcast(pubsub, topic, {:course_updated, course})

# GOOD — payload is a message struct
Phoenix.PubSub.broadcast(pubsub, topic, %MyApp.PubSub.Message{event: :updated})
```

A call is checked when it resolves to `Phoenix.PubSub` under the file's own
alias declarations — a literal `Phoenix.PubSub.broadcast(...)`, or the aliased
`PubSub.broadcast(...)` under `alias Phoenix.PubSub`, piped or not (see
Limitations below for how that resolution can misfire when a local name is
reused). `broadcast_from`/`broadcast_from!` take the payload one argument
later than `broadcast`/`broadcast!`/`local_broadcast` (they also take the
sending `from` pid), and both positions are checked correctly. This check runs
everywhere `Phoenix.PubSub` is called directly, including inside a project's
own PubSub wrapper module — whether broadcasts should be routed through a
wrapper at all is a separate concern this check does not enforce, so there is
no path exemption for a `pubsub/`-named directory. Test files are exempt by
default, since a test commonly asserts on the payload shape subscribers
receive rather than exercising a production broadcaster's message struct.

**Limitations:** alias resolution is file-wide, not lexical — when two
modules in the same file each `alias` a different target onto the same local
name `PubSub`, only the *last* such alias in the file is honored for every
`PubSub.broadcast(...)` call in the file, regardless of which module the call
is actually in; this can both over-report (a call to a project's own `PubSub`
wrapper gets flagged as `Phoenix.PubSub`) and under-report (a real
`Phoenix.PubSub.broadcast` call is missed). A variable or function-call
payload is never flagged — this is a static, single-file AST check, so
whether it evaluates to a struct at runtime is out of reach. A list, string,
number, or charlist literal payload is undetected — only the atom/tuple/map
shapes shown above are recognised. `%{base | field: value}` map-update syntax
is treated as a bare map literal even when `base` is already a message
struct. `apply(Phoenix.PubSub, :broadcast, [...])`, an unqualified
`broadcast(...)` reached via `import Phoenix.PubSub`, and the atom-spelled
module form `:"Elixir.Phoenix.PubSub".broadcast(...)` are all undetected.
`local_broadcast_from`, `direct_broadcast`, and `direct_broadcast!` are
genuine `Phoenix.PubSub` broadcast functions but are absent from the default
`:functions` list — they are unchecked unless added to that param explicitly.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:broadcast, :broadcast!, :local_broadcast, :broadcast_from, :broadcast_from!]` | The `Phoenix.PubSub` functions whose payload argument is checked |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments/suffixes exempt from this check |
