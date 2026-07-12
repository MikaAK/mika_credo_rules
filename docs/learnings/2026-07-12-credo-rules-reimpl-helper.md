# Learnings — NoReimplementedHelper (2026-07-12)

Worker: reimpl-helper. Check: `MikaCredoRules.NoReimplementedHelper`. Two refinement
rounds, both folded into one commit via amend.

## Data correctness = code correctness for pointer-class checks

This rule class emits a replacement pointer as its product: "defp atomize_keys found —
already exists as SharedUtils.Enum.atomize_keys/1, use it". Mechanism was flawless —
TDD green, credo clean, zero false positives — and the check was still broken, because
5 of 8 default pointers named functions that don't exist (`SharedUtils.Map.deep_merge/2`,
`SharedUtils.Random.random_string/1`, wrong modules for atomize/stringify/pluck). Dev
obeys the check → `UndefinedFunctionError`. Worse than no check: it actively misroutes.

Lesson: when a check's output is DATA (a pointer, a suggested module, a config key),
that data needs the same verification discipline as the traverse logic. Contract map
came from the sprint spec; spec was wrong; tests dutifully pinned the wrong strings.
TDD proves code matches tests — never that tests match reality. For pointer-class
defaults, verify each entry against the referenced source before writing the test:

```bash
grep -rn "def atomize_keys\|defdelegate atomize_keys" $SHARED_UTILS/lib
head -1 $SHARED_UTILS/lib/enum.ex   # confirm defmodule name too
```

## Verify the reviewer's correction table too

Reviewer supplied a 5-row correction table and said "do not trust this table blindly
either." Grepped every row against `learn_elixir_umbrella/apps/shared_utils/lib`:
defs + arities + `defmodule` heads. All 5 correct, plus confirmed the 3 unchanged
entries and confirmed `deep_merge`/`random_string` truly absent (zero defs). Table was
right — the habit is the point. A correction accepted on authority is the same failure
mode as the original spec bug, one hop removed. Cost: one grep + one `head -1`,
~30 seconds. Cite file:line in the re-report so the reviewer can spot-check the
verification itself.

## Naive substring exclusion goes dark on real source

`String.contains?(filename, fragment)` for path exclusion is a trap: consumer sets
`excluded_paths: ["test/"]` → `lib/latest/helpers.ex` silently exempt ("la**test/**").
Check stops firing on production code with zero signal. Fix is the boundary-aware
matcher already used elsewhere in this package (ErrorMessageRequired):

```elixir
defp fragment_matches?(filename, fragment) do
  String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
    String.contains?(filename, "/#{fragment}")
end
```

Two ripples worth knowing:

- Leading-slash fragments break under the boundary matcher: `"/legacy/"` becomes
  `contains?("//legacy/")` — never matches. Fragments must be written bare
  (`"legacy/"`); one existing test fixture had to change with the semantics.
- Regression test shape: file `lib/latest/helpers.ex` + `excluded_paths: ["test/"]`
  must still FLAG. Under the naive impl this is RED (wrongly exempt) — perfect
  one-test driver for the fix. Pair with a `starts_with?` positive
  (`test/support/helpers.exs` exempt) so both arms are pinned.

## Worktree-reap recovery

Spawn worktree (`agent-ad3f347...`) was auto-pruned mid-task — harness reaps
worktrees with no tracked changes, and a lane that has only run `deps.get`/`mix test`
has none (deps/_build gitignored). Next bash call landed in the main repo on `main`.

Recovery: detect via `git worktree list` + `git branch --show-current`, then
`git worktree add .claude/worktrees/<lane> -b worktree-<lane> main` and continue.
Rules that made it safe: verify branch before every write-phase, never commit on
`main`, report the recreated path/branch to the lead so review targets the right lane.
Prevention: touch a tracked file (or make the first RED commit) early if setup is
long — a dirty worktree doesn't get reaped.

## Process notes

- Amend-fold kept one commit per lane across two refinement rounds; reviewer sees
  final code once. Only safe because the lane branch was unpushed and single-author.
- `%{^name => replacement}` pin-match in a case over the functions map: lookup +
  destructure in one clause, `nil` name (macro-generated `def unquote(x)`) falls
  through to no-issue.
- Session spawned without TaskGet/TaskUpdate tools despite agent-type spec — worked
  the contract relayed over SendMessage and had the lead flip statuses. Protocol
  survives missing tooling if the report carries full evidence (RED/GREEN excerpts,
  gate outputs, hashes).
