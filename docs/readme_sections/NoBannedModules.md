### `NoBannedModules`

Generic, param-driven module ban — the reusable shape behind `NoMockingLibraries`.
Some libraries must never appear in a codebase, however they're referenced —
`use`, `alias`, a remote call, or a bare mention in an attribute all count. The
default list bans `Guardian` and `Joken`: this project authenticates with
Redis-backed session tokens (see `elixir-auth-sessions`), not JWTs, so either
library issuing or signing a session token is itself the bug. Code that
instead VERIFIES a third-party issuer's JWTs (an Auth0/JWKS integration, for
example) is a legitimate, deliberate exception to the default — opt those
files out with `excluded_paths` rather than disabling the check outright.

```elixir
# BAD — a JWT library wired up directly
use Guardian, otp_app: :my_app

# GOOD — Redis-backed session tokens
MyApp.Sessions.create(user)
```

An explicit alias still resolves back to the banned module — `alias Guardian`
followed by a bare `Guardian.encode_and_sign(user)` fires twice, once for the
alias itself and once for the call. A banned module's submodules count too —
`use Joken.Config` is Joken's own canonical entry point, so it still bans on
the `Joken` entry, the same as `Guardian.Plug.Pipeline` bans on `Guardian`.
Banned modules are matched by segment prefix, so `MyApp.Guardian` is a
different, unrelated module (the banned name is a LATER segment, not the
first) and is never flagged. Alias resolution is aware of an alias of the
banned module ITSELF (`alias Guardian` then a bare `Guardian`), but not of an
alias of one of its submodules — see Limitations. A locally defined module
shadows a banned bare name the same way a project `alias` does — a nested
`defmodule Guardian do ... end` deregisters the bare name, and every
submodule beneath it, for the rest of that file, so a stub or fake by that
name is never mistaken for the real library. The fully-qualified
`Elixir.Guardian` spelling, written as a dotted alias, always still fires,
shadowed or not; the `:"Elixir.Guardian"` atom spelling fires too, but only
as a dot-call's module receiver or a bare attribute value (`@behaviour
:"Elixir.Guardian"`), not in every AST position.

**Limitations:** module identity is a naming heuristic, the same as
`NoMockingLibraries` and `NoBangMailerDeliver` — it matches AST module
references, not what a library actually does. A string or atom that merely
mentions a banned name (`"Guardian token expired"`, `:guardian_error`) is never
flagged, and `mix.exs` dependency declarations (`{:guardian, "~> 2.0"}`) are
ordinary lowercase Hex-package atoms, not module references, so they never
match either. Aliases are resolved from a flat, file-level table rather than a
lexical scope stack, and an alias injected by a macro (via `__using__`) is
invisible to Credo and cannot be resolved. Alias resolution only registers an
alias whose target EXACTLY matches a banned entry — `alias Guardian.Plug`
does not register the local name `Plug` as a `Guardian` reference (only
`Guardian` itself is a banned entry, not `Guardian.Plug`), so a later bare
`Plug.sign_in(...)` is silent; writing `Guardian.Plug.sign_in` out in full
still matches, since that needs no alias resolution at all. A project `alias`
naming the banned module itself is a second shadowing source, alongside
`defmodule`: `alias MyApp.Guardian` deregisters the bare `Guardian` name
file-wide, so a later bare `Guardian.encode_and_sign(user)` is silent — but
the `Elixir.Guardian` and `:"Elixir.Guardian"` spellings still fire
regardless, since those are matched against the module's unaliased identity,
never the shadowed one. `defmodule` shadowing is file-level the same way: a
nested stub defined inside one top-level module deregisters the bare name for
every other top-level module
in that file too, not only its own — and a top-level, single-segment
`defmodule Guardian do ... end` shadows the bare name file-wide the same as a
nested one would. A banned module held in a variable or module attribute
value, reached via `apply/3`, or referenced by a dynamically built alias is
not recognised — only a literal AST reference to the module's name is. The
`modules` param expects `{module, reason}` tuples of genuine Elixir modules —
an erlang-style atom (`:meck`) or a bare module with no `reason` tuple raises
when the check reads its params, rather than being silently ignored; this
check offers no `erlang_modules` param the way `NoMockingLibraries` does.

| Param | Default | Meaning |
|---|---|---|
| `modules` | `[{Guardian, "no JWT here — sessions are Redis tokens (elixir-auth-sessions)"}, {Joken, "no JWT here — sessions are Redis tokens (elixir-auth-sessions)"}]` | `{module, reason}` tuples to ban (and every submodule beneath each `module`); `reason` is appended to the issue message. `module` must be a genuine Elixir module — an erlang-style atom or a bare module with no tuple raises. |
| `excluded_paths` | `[]` | Path fragments naming files this check skips (segment-boundary matched). Empty by default — a banned module is banned everywhere, tests included. |
