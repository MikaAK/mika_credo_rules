# Wave 2 build — NoJasonDeriveOnEctoSchema (2026-07-12)

## Per-defmodule scoping: `scan_own_body` prunes nested defmodule subtrees

Per-module (not per-file) checks need two walks. The outer `Credo.Code.prewalk`
clauses on `{:defmodule, _, [_, [{:do, body} | _]]}` and keeps descending, so every
nested module hits the same clause independently. Each module's own body is then
scanned with `Macro.prewalk` that returns `{nil, acc}` on any `{:defmodule, _, _}`
node — `nil` has no children, so the nested subtree is pruned. Result: an inner
module neither inherits the outer `use Ecto.Schema` nor leaks its own `@derive`
upward, in either direction. Both facts (`use Ecto.Schema` present? which `@derive`s
are mine?) must come from the same pruned scan or the scopes disagree.

## Macro-injected aliases are invisible — document, don't pretend

`AstHelpers.resolve_aliases/2` only sees `alias` nodes in the file's AST. An alias
injected by a `__using__` macro cannot be resolved, so `@derive Encoder` under a
macro-provided alias is a known false negative. State it in the moduledoc as a
limitation instead of silently claiming coverage (same posture as the `apply/3`
note in NoMockingLibraries).

## Worktree fallback when EnterWorktree is unavailable

A subagent with a pinned cwd cannot `EnterWorktree` (create is blocked; `path`-switch
is refused when the pinned cwd is the repo root). Fallback that works:
`git worktree add .claude/worktrees/<name> -b worktree-<name>`, then do everything
via absolute paths and `cd <worktree> && mix ...` per Bash call. Also: worktrees
reap on zero-change turns — a build interrupted before its first file write loses
its worktree and must recreate it.

## Mutation pair: run/2 stub + targeted pruning-clause revert

Two mutations, two different proofs:

- **run/2 stub (`[]`)** — exactly the 11 positive tests failed, all 8 negatives
  passed: the suite can go red and the positives all pin the check.
- **Delete only the `{:defmodule, _, _} -> {nil, acc}` pruning clause** — exactly
  the 2 nesting-scope tests failed: the tests pin the scoping behaviour, not merely
  coexist with it.

Beware inert mutants: my first "stub" only added a no-op line — zero new failures
proves nothing until the mutant demonstrably changes behaviour. After restore:
`mix compile --force` + `git status --short` (stale-beam trap) before re-probing.

## `--checks` filters enabled checks — unregistered check dogfoods vacuously

`mix credo --checks "MikaCredoRules.NewCheck"` on a check not yet in `.credo.exs`
prints a green "running 0 checks" — vacuous. Dogfood an unregistered check with a
scratch `--config-file` (config named "default", map-form `checks: %{enabled: [...]}`),
confirm "running 1 check on N files", and prove the gate can go red by planting a
violating `.exs` fixture (non-`_test.exs` name in `test/` — Credo parses it, ExUnit
and `mix compile` ignore it), then remove it.
