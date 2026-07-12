# Learnings — TodosNeedTickets (Task #2, 2026-07-12)

Worker: todos-tickets. Check: `MikaCredoRules.TodosNeedTickets`.
Commit on main: `42c8dfd` (worktree commit `1db7371`, lane-merged).
Files: `lib/mika_credo_rules/todos_need_tickets.ex`, `test/mika_credo_rules/todos_need_tickets_test.exs`.

## Port-vs-rewrite discovery

Biggest finding. Blitz `TodosNeedTickets` = FILE-level suppression: ONE ticket URL
anywhere in file → ALL todos in file pass. Load-bearing failure case: file with 10
todos + 1 URL at bottom → Blitz reports zero. Contract ruled per-todo adjacency
instead: URL on same line, line above, or line below. Result: rewrite, not port —
only the tag-detection seam (TagHelper) survived from Blitz.

Lesson: "port check X" contracts hide semantic bugs in the original. Read the
original's suppression logic FIRST, present the semantics to the architect BEFORE
implementing. The pin test ("one ticketed + one unticketed todo → exactly one
issue") is what forced the rewrite decision into code.

## TagHelper limits (credo 1.7.19, `Credo.Check.Design.TagHelper`)

- `tags/3` returns same 3-tuple shape `{line_no, line, trigger}` for comment hits
  AND doc-attribute hits — indistinguishable downstream. Needed different
  suppression rules per kind, so: `TagHelper.tags(source_file, tag, false)` for
  comments only + own prewalk for doc attrs. Own tuples tagged `{:comment, ...}` /
  `{:doc, ...}`, multi-clause dispatch.
- Doc-attribute regex is ANCHORED: `\A\s*TAG:?\s*.+` — doc must START with tag
  word. Tag mid-docstring invisible. Mirrored same regex for parity with credo's
  own TagTODO.
- Comment regex `(\A|[^\?])#\s*TAG:?\s*.+` needs `.+` after tag → bare `# TODO`
  (no trailing text) never flagged. Also `# TODOLIST` false-positives (`:?\s*` both
  optional). Inherited, documented as known limitation, not fixed.
- Tag matching is case-insensitive (`Regex.compile!(..., "i")`) → default tags
  `["Todo", "TODO", "Fixme", "FIXME"]` collapse to 2 effective patterns; every hit
  arrives twice → `Enum.uniq_by(&elem(&1, 0))` per kind is mandatory or you emit
  duplicate issues per line.

## Raw-source scanning vs clean_charlists

TagHelper's comment scan runs on `Credo.Code.clean_charlists_strings_and_sigils/1`
output — string/sigil contents blanked (comments preserved). Two consequences:

- `"TODO: x"` inside a string literal never becomes a tag — free string-safety,
  test it, don't reimplement it.
- Contract ruled adjacency window scans RAW source lines. Trade-off accepted: URL
  inside a string literal on the adjacent line counts as a ticket reference
  (disclosed in README limitations). Cleaned-source window would fix that but
  architect ruled raw. Either way: 1-based line map
  (`Enum.with_index(1) |> Map.new/1`) matches TagHelper's `index + 1` convention.

## ticket_url nil-raise trap

Blitz default `ticket_url: nil` + `raise` in `run/2` when unset. Two traps:

1. Raise inside `run/2` does NOT surface as raise through `Credo.Test.Case.run_check/3`
   — test runner goes `run_on_all_source_files` → `Task.async_stream`, so the
   exception becomes a Task EXIT in the test process (`assert_raise` misses it;
   `catch_exit` would be needed). If you must test a raising check, call
   `Check.run(source_file, params)` directly.
2. Real credo runs rescue check errors per-file (`do_run_on_source_file` try/rescue,
   reraise only when `exec.crash_on_error`) → a raising check degrades noisily.

Resolution made both moot: default `"http"` as the contains-matcher — accepts any
http(s) URL out of the box, param narrows to tracker prefix. One code path, no nil
clause, no raise, drop-in enableable. Pattern worth reusing: prefer a permissive
default value over a required-param raise in credo checks.

## Root-fix own TagTODO hit, don't suppress

`MIX_ENV=test mix credo --strict` flagged my own file: credo's built-in
`Design.TagTODO` (active — repo `.credo.exs` checks list MERGES with defaults, 70
checks ran; assumption that a list replaces defaults was wrong). Cause: moduledoc
began `"Todo comments must..."` → anchored doc regex hit. The `# TODO` examples
inside the moduledoc string were invisible (strings cleaned in comment scan) — only
the doc-start word mattered. Fix: reword first line to "Every todo comment must…" —
zero suppression added for TagTODO. Kept `# credo:disable-for-this-file
MikaCredoRules.TodosNeedTickets` header (Blitz precedent, contract-blessed) for when
this check itself gets enabled with a narrowed `ticket_url` that its own example
URLs won't match.

Anti-pattern avoided: reaching for disable comments when a one-word rewording kills
the trigger at the root.

## Misc gotchas

- `Credo.SourceFile.parse/2` outside test/credo-runner needs
  `Application.ensure_all_started(:credo)` — `Credo.Service.SourceFileAST`
  GenServer must be up (credo dep is `runtime: false`). Bit me in the smoke script.
- Smoke via direct `run/2` over repo sources bypasses `credo:disable-for-this-file`
  handling (that lives in credo's runner) — good: proves zero false positives
  without the header's help. Ran defaults + narrowed `ticket_url`; 0 issues both.
- TDD RED for a new check = whole-suite `UndefinedFunctionError` on
  `run_on_all_source_files/3` (not `run/2`) — the `use Credo.Check`-generated
  callback is what `Credo.Test.CheckRunner` calls first.
