# Learnings — RefuteOverAssertNot (lane #8, worker refute-assert)

Commit: lane 79dd5a7 (merged, zero refinement rounds).

## `assert x not in y` — AST identity, pre-review FP catch

`assert x not in [1, 2]` and `assert not (x in [1, 2])` compile to the IDENTICAL AST:
`{:assert, _, [{:not, _, [{:in, _, [x, list]}]}]}`. Verified with `Code.string_to_quoted!/1`
before writing the traverse — not assumed. Consequence: a naive `{:not, _, _}` match flags
every idiomatic membership assertion in a codebase. Ruling: exempt the whole shape via a
specific traverse clause ordered BEFORE the general negation clause; accept that the rare
explicit `assert not (x in y)` spelling escapes. Document the tradeoff in moduledoc + pin
with a `refute_issues` test. Pattern: for any operator-targeting check, enumerate Elixir's
sugar forms that desugar to your target operator (`not in` → `not`+`in`) BEFORE writing the
matcher — the surface syntax and the AST are not 1:1, and only AST inspection tells you
which spellings collide.

Adjacent trap, same lesson: `assert a !== b` / `assert a != b` are operators `:!==`/`:!=`,
NOT `:!` — no collision, but only because the atom differs. Regression test pins it so a
future "loosen the match" edit can't start flagging negated comparisons.

## Mutation-proving the filename guard

Green scoping tests prove nothing about the guard being load-bearing. Proof: mutate
`if test_file?(source_file.filename, test_files(params)) do` → `if true do`, re-run —
EXACTLY 2 failures ("does not report assert ! in a lib file", "skips _test.exs files once
no longer in :test_files"), zero collateral. Restore → 12/12 green. The "exactly N, named"
part is the signal: it proves those two tests exist solely to hold that guard, and nothing
else silently depends on it. Gotcha: `git checkout -- <file>` can't restore an untracked
(never-committed) file — mutation-then-restore on brand-new files needs the mutation
scripted reversibly (I used a python string-replace in, Edit back out) or a preliminary
commit first.

## Flag relay inconsistencies, don't silently pick

Lead's amendment specified param `test_files` (default `["_test.exs"]`); a later addendum
offhandedly called it `test_file_suffixes`. Two defensible readings = a coin-flip if
resolved silently, and the reviewer diffing against the OTHER reading burns a refinement
round on a name. Did: implement per the explicit amendment (it was the deliberate naming
decision; the addendum's focus was the negative test), then flag the conflict in every
report — architect-review, architect-abstractions, main — as "used X per amendment, say if
rename wanted". Cost: one sentence. Result: zero refinement rounds. Rule: when relayed
instructions disagree, pick the most-authoritative source, state the conflict and your
resolution in the same report — never make the reviewer discover the discrepancy.

## Misc

- `files:` param is dead under `Credo.Test.Case`: `Test.CheckRunner.run_check/3` calls
  `check.run_on_all_source_files/3` directly; `Params.files_included/files_excluded` are
  only consulted by `Credo.Check.Runner` (real CLI). A check whose scoping must be
  testable needs the filter inside `run/2` (canonical `config_files` suffix pattern).
  Verified by reading deps/credo 1.7.19 source, not docs.
- Heredoc test fixtures containing `assert !valid?()` are string literals in the host
  file's AST, not call nodes — a checker never sees them. Smoke over this repo's own
  test/ (which is full of such fixtures) is therefore a real no-FP corpus for THIS check,
  unlike the inert-corpus trap lane #4 hit.
- Trigger text "assert not" makes the house message format read oddly ("assert not found
  — use refute..."). Kept canonical plain-trigger format anyway; consistency across checks
  beats prose nicety in one message.
