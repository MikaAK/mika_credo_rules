### `NoUnboundBlockAssignment`

An `if`/`case`/`cond`/`unless` used as a statement — an element of a block
that is not the block's own last expression — must not end a branch in a bare
assignment. The binding is scoped to that branch and never escapes the block,
so the assignment is silently lost. This is the classic
`socket = assign(...)` LiveView bug.

```elixir
# BAD — `socket` inside the `if` never reaches the return value
def handle(socket, val) do
  if connected?(socket) do
    socket = assign(socket, :val, val)
  end

  {:noreply, socket}
end

# GOOD — bind the `if`'s own result instead
def handle(socket, val) do
  socket = if connected?(socket), do: assign(socket, :val, val), else: socket
  {:noreply, socket}
end
```

`case` and `cond` branches, and `unless`, are checked the same way. An
`if`/`case`/`cond`/`unless` that IS the last expression of its enclosing
block is only safe if that enclosing block's own value is itself used —
being the last expression of a NESTED `if`/`case`/`cond`/`unless` is not
enough, since a discarded outer value discards the inner one too; the check
chases a branch's tail through nested `if`/`case`/`cond`/`unless` to any
depth. Also not flagged: an assignment that the branch itself goes on to use
before the block ends.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `[]` | Path fragments exempt from the check, matched at a path-segment boundary — the bug is exactly as real in a test as anywhere else, so nothing is exempt by default. |

**Limitations.** Only a bare single-variable left-hand side is recognised —
a destructuring tail assignment (`{a, b} = compute()`) is not flagged,
assigning to the wildcard `_` or any `_`-prefixed name (`_socket`) is never
flagged (an explicit discard, matching the compiler's own unused-variable
convention), and `var!(socket) = ...` (unquoted assignment inside a macro
body) is not flagged either — its left-hand side is a `var!/1` call, not a
bare variable node. A branch's tail is chased through nested
`if`/`case`/`cond`/`unless` to any depth; an assignment buried inside a
`with`/`try`/`receive` whose own last expression is the bare assignment is
not chased through. Only the bare macro spelling is recognised — a
fully-qualified call (`Kernel.if/2`, `Kernel.case/2`) is not.
