# Learnings — ErrorMessageRequired (lane #10, worker error-message)

Commits: lane 198f152 (amended from 8b98dfb after dead-param finding, merged).

## 2-tuple literals carry no AST metadata

`{:error, "not found"}` quotes to itself — a plain 2-tuple, no meta slot. Only 3+-tuples become `{:{}, meta, args}` call forms. Consequence: no line number available on the node you're flagging. Probe first (`Credo.Code.ast/1` on a snippet) — don't assume every AST node has meta.

Fix shape: prewalk with map accumulator `%{line: nil, issues: []}`, update `line` from every `{_form, meta, _args}` with `meta[:line]`, stamp issues with last-seen line. Precision: exact for one-liner defs and `->` clause bodies (arrow node carries the clause line, visited pre-order before its body); off-by-a-bit for multi-line def bodies (reports the `def` line). Document approximation in moduledoc instead of building token-level tracking.

Second consequence of no-meta: keyword pairs are AST-IDENTICAL to tuple literals — `[error: "x"]` and `[{:error, "x"}]` parse to the same term, `%{error: "x"}` map pairs too. Undecidable at AST level. Chose false negative (never flag pairs inside list/map literals) over false positive (`%{error: "..."}` is common Phoenix JSON). Documented FN in moduledoc + README. Rule: when two source spellings collapse to one AST, a lint must pick a side and write it down.

## Match-position neutralization — construction flags, matching passes

`case ThirdParty.call() do {:error, "expired"} -> :retry` must NOT flag — third-party libs legitimately return string-reason tuples; matching them is unavoidable. Only construction is the smell.

Mechanism: `Macro.prewalk` continues into the RETURNED node, so the traverse fn can rewrite match positions out of the walk: left of `->`/`<-`/`=` and def/defp/defmacro/defmacrop heads replaced with a sentinel atom, expression side kept. ~15 lines, no parent-tracking machinery.

Mutation testing exposed overlapping defenses: disabling arrow-neutralization alone → only 1 test RED, because case-clause patterns arrive as a LIST `[pattern]` and the pair-neutralization list clause also covers them. Know which layer actually protects which position before claiming a mutation "proves" a test.

## files: + excluded_files dead-param trap (shipped, caught in review)

Shipped `param_defaults: [files: %{excluded: [...]}, excluded_files: [...]]` — belt and suspenders. Wrong: under `Credo.Test.Case` the `files:` param is INERT (test check-runner never consults it), but in production it prunes files at pipeline level BEFORE `run/2`. So my test "excluded_files: [] re-enables test-file flagging" was green in the suite and dead in prod — consumer sets `excluded_files: []`, `files:` already ate the file, gets nothing. Exact green-tests-dead-param trap: the test only passed because the mechanism it contradicts doesn't run under test.

Reviewer exposed it with a prod-relative probe: run the check through Credo's real pipeline (project-relative paths, `Credo.Check.Runner`) instead of `Credo.Test.Case`, compare issue counts. Test harness said 1, production said 0.

Fix: single scoping mechanism — drop `files:` entirely, `run/2` filename guard owns exclusion. Moduledoc states the omission is deliberate and why. Rule: never default two mechanisms where one runs in an environment the other can't be tested in. If a param can't go RED under your test harness, it can't be shipped as a default.

## Boundary matcher (became package-wide standard)

Naive `String.contains?(filename, fragment)` exempts `lib/latest/foo.ex` under `"test/"` — substring matches mid-word. Shape that shipped (adopted by lanes #4 and #11 after the naive-substring bug surfaced in theirs):

```elixir
String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
  String.contains?(filename, "/#{fragment}")
```

Ends-with covers `_test.exs` suffixes, starts-with covers root-relative `test/...`, slash-prefixed contains covers umbrella `apps/x/test/...` without the mid-word hole.

## Misc gotchas

- Scratchpad is session-shared across team workers: my `smoke.exs` got overwritten mid-run by another lane's script (stack trace named THEIR module). Unique-suffix any scratchpad filename in team runs.
- `git checkout <file>` cannot restore an untracked file — mutation-testing a not-yet-committed file needs an explicit backup copy to restore from.
- perl `s///` replacement strings interpolate `@word` as an empty array — mutation C silently became a compile error and reported "0 failures" (no test ran). Grep for the `tests,` summary line and treat its ABSENCE as inconclusive, not pass.
- `Credo.SourceFile.parse/2` in one-off scripts needs `Application.ensure_all_started(:credo)` first.
- Escape interpolation in @moduledoc heredocs AND in test snippet heredocs (`\#{...}`) or the doc/example interpolates at compile time.
