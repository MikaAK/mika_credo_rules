### `LowercaseErrorMessages`

`ErrorMessage` constructor calls and `raise/2` message strings must not carry
a trailing `.` or `!` — the caller composes them into larger sentences and
log lines, where a stray terminator reads oddly. Only the first argument of a
constructor call is inspected, and the trailing-punctuation half of the rule
skips any string whose LAST segment is interpolation (`"missing: #{id}"`),
since the runtime value of the trailing character is unknowable statically —
the lowercase-first half still inspects such a string's FIRST segment, which
is always known statically.

```elixir
# BAD — trailing period
ErrorMessage.not_found("User not found.")

# GOOD — no trailing punctuation
ErrorMessage.not_found("user not found")

# BAD — trailing bang, positional
raise ArgumentError, "Bad input!"

# BAD — trailing bang, via a message: keyword
raise ArgumentError, message: "Bad input!"

# GOOD — no trailing punctuation
raise ArgumentError, "bad input"
```

The same rule applies to a piped `raise` (`Mod |> raise("...")` or
`Mod |> raise(message: "...")`) — piping folds `Mod` into `raise/1`'s first
argument, giving the same two-arg shape as `raise Mod, ...`.

A trailing `?` is left alone. By default only trailing punctuation is
enforced; `enforce_lowercase_first: true` additionally requires the first
letter to be lowercase, off by default because a proper noun as the first
word ("GitHub is unreachable") would otherwise be a false positive.

Every issue is reported at the call itself — the constructor's module
reference, or `raise`'s own keyword — never at the message literal, which
carries no source position of its own. A multi-line constructor call's
message can sit on a later line than the call; a piped call's message (its
LHS) can sit on an earlier one. Either way, the reported line and column are
the CALL's, not the message's.

**Limitations:** only the first argument of a constructor call is inspected —
a bad trailing character inside a `details` argument is invisible. `raise/2`'s
exception module identity is never checked; any two-arg `raise` is in scope —
but only the bare `raise` spelling, not the fully qualified `Kernel.raise(...)`.
A bare `raise "message"` (arity 1, no exception module, not piped) and an
unqualified, `import`ed constructor call are not recognised — module identity
is resolved only for the qualified `ErrorMessage.<fun>` spelling. A message
built with a sigil (`~s(...)`) is not recognised — only a plain string literal
or a `"...#{...}"` interpolation is inspected. A non-interpolated heredoc
lowers to a plain string literal, so it IS inspected — but its trailing
newline normally defeats the trailing-punctuation half of the rule; only a
heredoc using a line-continuation `\` on its last content line (dropping that
newline) can fire that half. An interpolated heredoc lowers to the same AST
shape as any other interpolated string and is inspected the same way. The
lowercase-first half only inspects the first character, so it is unaffected
by the trailing newline and can fire on any heredoc, interpolated or not.
`enforce_lowercase_first` matches ASCII `[A-Z]` only.

| Param | Default | Meaning |
|---|---|---|
| `enforce_lowercase_first` | `false` | Also requires a lowercase first letter. |
| `functions` | the 14 most common `ErrorMessage` HTTP-status constructors (`ErrorMessage` ships 49) | Constructor names whose first argument is checked. |
