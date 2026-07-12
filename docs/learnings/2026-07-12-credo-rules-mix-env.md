# Learnings — NoMixEnvAtRuntime (lane #4, worker mix-env)

Commits: lane 565d748 (merged), post-merge fix 1739167 (`fix-mix-env-boundary`, amended from 22a103f).

## Premature report = process bug

Reported "done" mid-amendment: HEAD stale, tree dirty, 3 RED tests in working tree. Reviewer diffed against wrong snapshot, wasted a full review cycle. Rule: done = committed + clean tree + fresh green gates against THAT commit. Never report while a contract amendment is in flight — finish, commit, re-verify, then report. Tested state must equal committed state (`git status --short` empty) or the numbers mean nothing.

## Mix.Task exemption amendment

First cut flagged Mix.env() everywhere outside .exs. Wrong: Mix tasks only ever run under Mix, never in a release — 6 real FPs in deploy_ex/lib/mix/tasks/. Fix was two-layer: AST detection (`use Mix.Task` anywhere in file → whole file exempt, both `[:Mix, :Task]` and `[Elixir, :Mix, :Task]`, with/without opts) plus `excluded_paths` param (default `["mix/tasks/"]`) for task-adjacent helpers that don't `use Mix.Task`. Pattern: when a check targets "code that ships in releases", enumerate what compiles-but-never-ships (mix tasks, .exs) before writing the traverse.

## Inert-corpus lesson — smoke must contain the pattern it rules out

My first smoke ran the check over this repo's own lib/ — zero Mix.env() calls anywhere, so "0 false positives" was vacuously true. Reviewer's acceptance criterion pointed at deploy_ex/lib: 124 files, 7 containing Mix.env(). That corpus proved both directions — 6/6 mix/tasks files silent (FPs eliminated) AND lib/deploy_ex/config.ex:6 still flagged (TP preserved). Anti-pattern: smoke-testing a checker against a corpus that can't trigger it. A useful FP smoke corpus must contain (a) the pattern in exempt positions and (b) the pattern in flagged positions.

## Boundary-matcher bug + lookalike pin

`Enum.any?(paths, &String.contains?(filename, &1))` is a latent hole: `excluded_paths: ["test/"]` silently exempts `lib/latest/foo.ex`; even the DEFAULT tripped on `lib/vendor/remix/tasks/thing.ex` ("re**mix/tasks/**thing"). Same bug class hit lane #11. House fix shape (same as ErrorMessageRequired):

```elixir
String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
  String.contains?(filename, "/#{fragment}")
```

Pin BOTH directions in tests: custom-param lookalike (`["test/"]` vs `lib/latest/`) and default-param lookalike (`remix/tasks/`). Revert-proof the pin: restore naive matcher → exactly the 2 boundary tests RED, exemption sanity tests green → restore. A regression test that never went RED under the bug proves nothing.

## use Mix.Task file-level detection stance

Detection is whole-file (prewalk/3, boolean acc), not per-module scope. Being wrong requires one file defining both a Mix task and an ordinary runtime module — one-module-per-file house style makes this moot. Same flat-over-lexical tradeoff as the canonical check's alias table; document the limitation in the moduledoc instead of building scope tracking nobody needs. Related stances documented rather than special-cased: module attributes (`@env Mix.env()`) still flagged (compile-time-safe but bakes env invisibly — use Application.compile_env); `test/support/*.ex` still flagged (opt out via `excluded_paths: ["test/support/"]`). Default posture: strict check + documented opt-out beats silent exemption.

## Misc gotchas

- Credo one-off scripting: `Credo.SourceFile.parse/2` needs `Application.ensure_all_started(:credo)` — GenServer services (Credo.Service.SourceFileAST) aren't up under plain `mix run`.
- `Credo.Test.Case.to_source_file/2` second arg sets the filename — that's the whole .ex/.exs exemption test mechanism.
- RED for a brand-new check module fails as `UndefinedFunctionError ... run_on_all_source_files/3` (Credo.Check-generated fn), not a clean assertion failure. Expected; still valid RED.
- Negative-control tests (e.g. "flags mix/tasks when excluded_paths: []") are green before AND after the change — fine, but label them as controls in the report so reviewers don't count them as TDD evidence.
