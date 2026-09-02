### `EmailRequiresTextBody`

A Swoosh email built with `html_body/2` needs a matching `text_body/2`, or it
renders empty in a text-only client. `html_body/2` and `text_body/2` set
independent parts of a multipart message — setting only the HTML part means
any client that prefers or requires plain text shows a blank body instead of
falling back sensibly.

```elixir
# BAD — no text fallback
defmodule MyApp.Emails.Welcome do
  import Swoosh.Email

  def welcome(user) do
    new() |> subject("Welcome!") |> html_body("<h1>Welcome!</h1>")
  end
end

# GOOD — both parts set
defmodule MyApp.Emails.Welcome do
  import Swoosh.Email

  def welcome(user) do
    new()
    |> subject("Welcome!")
    |> html_body("<h1>Welcome!</h1>")
    |> text_body("Welcome!")
  end
end
```

The check is a module-level heuristic, scoped to each top-level `defmodule`
or `defimpl` in the file: if `html_body/2` is called anywhere in the scope's
body — including inside a nested `defmodule` — and `text_body/2` is never
called anywhere in that same body, one issue is reported at the first
`html_body` call site. A definition head — `def html_body(...)`, a bodiless
multi-clause head (`def html_body(user, greeting \\ "Hi")`), or a
`defdelegate html_body(...), to: ...` — is not a call and is never counted,
nor is a bare variable, or a module-attribute definition or read whose own
name is `@html_body`/`@text_body` (`@html_body "<h1>..."`) — the
attribute's own name collides with the call shape, not evidence of a real
call. A real `html_body`/`text_body` call nested inside a differently-named
attribute's value (`@base new() |> text_body(body)`) is still counted
normally. Both functions are matched by bare, unqualified name — the shape
`import Swoosh.Email` produces — piped or not, so `email |> html_body(body)`
and `html_body(email, body)` are both caught: piping drops the implicit
first argument from the AST, so a genuine call is seen with either one
argument (piped) or two (direct, matching Swoosh's real `html_body/2`). A
call with zero, three, or more arguments is not counted.

**Limitations:** a module-qualified call — `Swoosh.Email.html_body(email,
body)` — is invisible; only the bare, unqualified name is matched. The
module body is scanned flat, not per nested `defmodule` or `defimpl`: a
nested scope that itself calls `text_body/2` satisfies the whole enclosing
scope. Keep one Swoosh email per top-level module to get an accurate scope.
A top-level `defprotocol` is never opened as its own scope either — moot in
practice, since a protocol definition may only declare function heads,
never bodies with real calls. Only the body of a top-level `defmodule` or
`defimpl` is ever scanned: code outside any such block — a bare script
invoking `html_body/2` at the top level of a `.exs` file, for instance —
opens no scope and is never checked at all. `Swoosh.Email.new/1` accepts
`text_body:`/`html_body:` as keyword options, applied the same as calling
the two functions directly; the check does not read `new/1`'s options, so a
module that sets the text body only this way is still flagged for a later
`html_body` call, and a module that sets only the HTML body this way is not
flagged at all. The match is name-only: `import Swoosh.Email` is not
required, and the two functions are matched independently by name. A local
helper function named `html_body/1` or `html_body/2` with nothing to do
with Swoosh is indistinguishable from the real one and will be flagged. The
same is true in reverse, and is the more dangerous direction: a local
helper function named `text_body`, called with one or two arguments
anywhere in the scope, satisfies the check even when it never touches the
email being built — silencing a genuine unset HTML-only email instead of
flagging it.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments and suffixes naming files this check skips. |
