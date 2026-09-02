### `NoSyncMailerDeliverInWeb`

Web-layer code — controllers and LiveViews — must not deliver mail inline. A
synchronous `Mailer.deliver/1` call blocks the request on the mail adapter's
round trip, and `deliver!/1` on top of that crashes the request on any
transient adapter failure. Enqueue an Oban worker instead: delivery gets its
own retries and the request returns immediately.

```elixir
# BAD — apps/my_app_web/lib/my_app_web/controllers/signup_controller.ex
MyApp.Mailer.deliver(Emails.welcome(user))

# GOOD — apps/my_app_web/lib/my_app_web/controllers/signup_controller.ex
%{user_id: user.id} |> SendWelcomeEmail.new() |> Oban.insert()
```

A mailer module is identified by its last alias segment *as written at the
call site* — `MyApp.Mailer.deliver(email)` and, under `alias MyApp.Mailer`,
`Mailer.deliver!(email)` are both caught, piped or not. An unqualified
`deliver(email)`, as written under `import MyApp.Mailer`, is caught by name
alone — as is a mailer injected as a dependency, `@mailer.deliver(email)` or
`mailer.deliver(email)`. A plain field or attribute read with no parentheses
— `assigns.deliver`, `conn.deliver` — is not a call and is never flagged. In
scope: any file matching `included_paths` — a directory whose name ends in
`_web` (e.g. `apps/my_app_web/...`), a directory named `controllers`/`live`,
or a file whose name ends in `_live.ex` or `_controller.ex`. A `_test.exs`
file, and any file under a `test/` path segment, is always out of scope,
even one that otherwise matches, because it never runs as part of handling
a live request. A `deliver!` call in a
web-layer file is also reported by `NoBangMailerDeliver`, with different
advice — the Oban fix this check asks for subsumes that one.

**Limitations:** module identity is a naming heuristic, so an `as:` rename
that drops the suffix (`alias MyApp.Mailer, as: Notifier`) is invisible.
Wherever the module is not a literal alias — an unqualified `deliver(email)`,
an injected `@mailer.deliver(email)` or `mailer.deliver(email)` — identity
comes from the function name alone, so an unrelated `deliver/1` on those
shapes is flagged; narrow `functions` if that bites. Indirection through
`apply(MyApp.Mailer, :deliver, [email])`, or a module spelled as an
`:"Elixir.MyApp.Mailer"` atom or an erlang-style atom (`:mailer`) rather than
an alias path, evades every clause here and is silently missed. So does an
alias path whose first segment is itself computed —
`__MODULE__.Mailer.deliver(email)` or `@base.Mailer.deliver(email)` — rather
than a literal alias.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:deliver, :deliver!]` | Mailer delivery functions to flag inside a web-layer file. |
| `module_suffixes` | `["Mailer"]` | Suffixes identifying a mailer module by its last alias segment. |
| `included_paths` | `["_web/", "controllers/", "live/", "_live.ex", "_controller.ex"]` | Path fragments and file suffixes marking a file as web-layer. |
