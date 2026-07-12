# Learnings — NoMockingLibraries (lane #13, worker no-mocking-2)

Commits: 8921d2e (RED test), 956ccc3 (impl), 845d500 (self-exempt header). Merged to main.

## Worktree reap → commit-early protocol

This lane is a REPLACEMENT — predecessor's worktree got reaped BEFORE any work landed. Reaper deletes worktrees that show zero changes at a turn boundary; fresh lane with only reads/skill-loads looks empty → gone. Protocol pioneered here, worked: commit the RED test as commit #1, immediately after VERIFY-RED, before writing any lib code. Worktree never again empty at any boundary. Bonus: RED-first commit doubles as tamper-proof TDD evidence — reviewer sees test exists in history before impl commit. Rule for future lanes: first commit within the first work turn, even if it is only the failing test.

## Generalized alias resolution — package superset

Contract asked exact-segment `__aliases__` matching only. Test-first exposed the gap: `alias MyApp.{Mock, Worker}` then bare `Mock.build()` — bare `[:Mock]` node exact-matches banned `Mock`, FP on project's own module. Repos that predate the no-mocking rule are EXACTLY the repos with legacy `MyApp.Mock` modules, so FP class is real, not theoretical.

Fix = canonical check's file-level alias-table fold (collect_aliases → apply_alias reduce), extended beyond canonical:

- multi-alias curly collection: `alias MyApp.{Mock, Factory}` → entries `[:Mock] → [:MyApp, :Mock]` (canonical lacked curly)
- shadowing: alias target NOT banned but name collides → name removed from banned set (bare `Mock` now means `MyApp.Mock`, silent)
- rename tracking: `alias Mox, as: M` → `[:M]` added to banned set, `M.stub(...)` flags
- traverse-side prunes (`{nil, acc}` return): curly node expanded then pruned so inner bare `[:Mock]` fragment never visited standalone; `alias X, as: Y` node checks target then prunes so `as:` name doesn't double-report same line

Other lanes copied this as the alias-resolution superset. If a third check needs it, extract collect_aliases/apply_alias/strip_elixir_prefix into a shared helper module — three copies is the threshold.

## Predict your own self-hit

First completion report flagged it before any reviewer: check's own `param_defaults: [modules: [Mox, Hammox, Mock, Mimic, Patch]]` compiles to real `__aliases__` nodes → check flags its own file 5× once self-enabled. Dogfood sweep later confirmed exactly that, verbatim. Lesson: any config-driven checker whose defaults NAME the banned pattern will self-flag — run the check against its own source during smoke and put the finding in the report proactively. Cheap to predict, expensive for a reviewer to discover. Note the canonical check dodges this by storing `[:Application]` as plain atom lists, not module aliases — but module-literal params are the better UX for `.credo.exs` consumers, so header suppression is the right trade.

## Disable-header suppression is runner-level, not run/2

`# credo:disable-for-this-file MikaCredoRules.NoMockingLibraries` above `defmodule` (blitz todos_need_tickets precedent). Mechanism matters: suppression happens in Credo's runner via config_comment_map filtering — `run/2` still PRODUCES the issues. Consequences:

- direct `run/2` smoke scripts bypass the comment; they will show "issues" the CLI never reports. Don't panic, don't special-case param_defaults in traversal.
- proving the comment load-bearing: (a) self-enable via scratchpad `--config-file` with only this check → `running 1 check on 6 files ... found no issues`; (b) raw `run/2` on the file → 5 issues with AND without the comment → suppression provably comes from the header, zero logic change.
- `mix credo --checks Foo` alone runs 0 checks when Foo isn't in `.credo.exs` — the flag FILTERS the registered list, doesn't add. Must pair with `--config-file` that registers the check.

## Misc gotchas

- Heredoc test fixtures are inert: banned names inside `"""` source strings are binaries in the TEST file's AST, not `__aliases__` nodes — test file never self-flags.
- `Elixir.Mox` parses as `{:__aliases__, _, [Elixir, :Mox]}` — strip leading `Elixir` atom before segment comparison (2-line helper, mirrors canonical `@fully_qualified_application`).
- Module params normalize via `module |> Module.split() |> Enum.map(&String.to_atom/1)` — works for multi-segment custom bans (`MyLib.Mocking`); erlang atoms (`:meck`) need the separate `erlang_modules` param since `Module.split/1` raises on them.
- Flagging only `__aliases__` nodes gives exactly one issue per reference for free — `Mox.defmock(...)`, `import Mox`, `use Mimic` all contain exactly one `[:Mox]`/`[:Mimic]` node. No dot-call clause needed for Elixir modules; dot-call clause only for erlang atoms.
- Verify AST shape assumptions with a 5-line `elixir -e 'Code.string_to_quoted!(...)'` before writing the traverse — curly-alias inner-node shape was non-obvious and drove the whole prune design.
