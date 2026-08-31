# Learnings — wave-3 adversarial review (16 lanes, 16 reviewers)

Every build lane got an external reviewer running the `verifying-credo-checks` protocol
plus per-lane adversarial probes. **All 16 lanes self-reported green; all 16 came back
REFINE.** Zero lanes passed clean. The gap between "my suite is green" and "this check is
correct" is the entire subject of this file.

## The reviewers' green was worth more than the builders' green — because of what they ran

Builders ran the suite, the mutation proof, and the doc gate. Reviewers ran those *and*:

- **the real Credo pipeline**, not `Credo.Test.Case` — a scratch `--config-file` with a
  planted violating fixture. This is what caught a heredoc off-by-one that every unit test
  agreed with, because the unit test asserted the same wrong line the code produced.
- **real corpora**, 800–2700 files. This is what turned "68% false positive" from an
  opinion into a number, and what proved a check's only real-world hit was a false
  positive.
- **`ASSERT_TRIGGERS=1`** — and then read Credo's source to find that
  `warn_on_missing_trigger/2` only fires when `issue.column` is set. Four checks pass no
  column, so their green ASSERT_TRIGGERS runs validated nothing. **A gate that skips
  silently when a field is nil is indistinguishable from a gate that passed.**

## The recurring defect classes (ranked by how many lanes hit them)

1. **Path-fragment defaults that can never match** — 5 lanes. `"_web/"`, `"_api/"`,
   `"_icons/"`, `"seeds"`: every one was written as a fragment and matched nothing real,
   because `matches_fragment?/2` anchors a fragment to the *start* of a segment while all
   four names are *suffixes* of an app directory. Three lanes independently hand-rolled a
   per-segment `String.ends_with?` matcher to work around it. Extracted as
   `SourceFilter.matches_segment_suffix?/2`. **When three lanes write the same helper, the
   helper was missing from the shared module — that is the signal, not the duplication.**
2. **Advice that does not compile or changes behaviour** — 5 lanes. `|> Kernel.++(x)`
   flagged with "call `++` directly" (a SyntaxError); `<<"GET ", rest>>` told to become
   `"GET " <> rest` (binds an integer byte vs a string, and changes match semantics);
   `<td phx-click>` told to become a `<button>` (invalid HTML); an `aria-hidden` modal
   backdrop told to add `role`+`tabindex` (a WCAG violation). Every one satisfied its spec.
   **The review budget belongs on "what valid code does this wrongly flag, and does the fix
   compile", not on coverage.**
3. **Piped calls read at the wrong argument index** — 3 lanes. A pipe leaves the call node
   at one lower arity, so an index-based read hits the wrong slot: a cookie check both
   missed the framework's primary idiom *and* fired on correct code, and an arity-0 test
   fired on a call that already passed its argument. The house fix already exists in
   `no_cast_all_keys.ex` (consume at the pipe node, rewrite the head to `__block__`).
4. **Docs that lie** — 6 lanes. A documented suppression escape hatch that provably cannot
   work (a `#` inside a heredoc is never a comment token). A BAD example that is not valid
   Elixir. A BAD example the check does not fire on, with a test *named* "reports the
   moduledoc BAD example" asserting `refute_issues`. A "there are no other exemptions"
   claim next to a new exemption. **Every BAD example is a claim the check fires on it —
   run them, and run the README's copies too.**
5. **Params that crash or are inert** — 3 lanes. A legal `functions: [{Foo, :metrics}]`
   raised `ArgumentError` and aborted the whole run; a `supervisor_modules` param was
   ignored by one of its own two matcher clauses; an `operators` param was capped by a
   hardcoded guard so half its values were silently no-ops. **Probe every param with a
   legal-but-unusual value; a check that aborts the run is worse than a check with a bad
   finding.**

## The bug the reviewers found that no lane owned

`AstHelpers.resolve_aliases/2` applied a file's aliases in **reverse source order**, so
the *first* alias for a local name won. Elixir's rule is last-alias-wins. Reproduced as a
matched pair — an FP and an FN from the same two lines in opposite order — by a reviewer
probing an unrelated check. Pre-existing on main, inherited by 8 shipped checks and every
new one. Fixed centrally rather than in any lane.

**A per-lane review finds per-lane bugs. The shared-helper bugs surface only because a
reviewer follows a finding out of its lane — budget for that, and route the fix to one
branch instead of letting each lane patch around it.**

## Reviewers disclosing their own errors kept the findings usable

Nearly every reviewer retracted at least one finding on measurement: a "dead test" that
was a `grep -c` matching `assert_issues` as well as `assert_issue`; an FP filed against
code that does not compile (`{:ok, x} = ^pinned`); a "missing scoping" concern refuted by
the reviewer against 938 real test files; a vacuous `running 5 checks on 0 files` green
one reviewer nearly reported from, caught by reading the file count. One reviewer used
`git checkout main -- <file>` for a differential, which *stages* the file, and briefly
left the worktree on main's code — caught from `git status` in the same turn.

A reviewer who hides mistakes is worth less than no reviewer; every retraction above made
the surviving findings more trustworthy, not less.
