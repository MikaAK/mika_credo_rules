# Credo Rules Cycle — Reviewer Learnings (architect-review)

Date: 2026-07-12
Scope: external evaluator, 13 Credo check lanes + 1 post-merge fix lane.
Outcome: 13/13 PASS to clean-pass rule. 4 real bugs caught pre-merge, 1 caught post-merge.

---

## META-LESSON: clean against real code ≠ correct

> **A check that cannot fire is indistinguishable from a check with nothing to report.**

Both print `found no issues`. Every real bug this cycle, and every mistake I made, reduces to
this. Four distinct causes, one identical reassuring output:

| Cause | Why it printed 0 | Where it bit |
|---|---|---|
| Inert corpus | pattern absent from corpus | #4's own FP smoke; my #5/#8 probe |
| Stale beam | compiled check was still the gutted stub | nearly filed 2 bogus blockers (#3/#12) |
| Naive substring | check silently exempted itself | #4 shipped FN; #11 latent |
| Dead `files:` param | guard never ran under `Credo.Test.Case` | #10 false-green test |

**Defense: adversarial positive control on EVERY probe.** Real code proves you don't fire on
*reality*. Only a planted edge case proves you fire at the *boundary*. Never report a clean
result you haven't proven capable of being dirty.

---

## Traps (each cost a near-miss or a real miss)

### 1. Inert corpus
Ran a new check over 287 real `.ex` files → 0 issues. Meaningless: the corpus contained none of
the target pattern. #4's worker made the same error — smoke-tested `NoMixEnvAtRuntime` against a
4-file repo with **zero Mix tasks**, i.e. structurally incapable of surfacing the FP class it was
meant to rule out.

**Fix:** every corpus run pairs with a planted violation. If the control doesn't fire, the run
proves nothing. Verify the corpus *contains* the pattern (`grep -rl` it) before trusting a 0.

### 2. Stale-beam false green (worst near-miss)
After `run/2`-stub → restore, `mix credo` still ran the **stubbed** `.beam` from the build cache.
Probes on #3/#12 returned 0 issues. I was one step from filing false-negative blockers against
two clean lanes.

**Fix:** `mix compile --force` after ANY mutate-restore cycle, before any probe.

### 3. Wrong-file stub batch (my error)
Batched the TDD stub across 10 lanes using `ls lib/mika_credo_rules/*.ex | head -1` — the
*alphabetically first* file. That's `no_application_env_outside_config.ex` (the canonical check)
in 7/10 lanes. I stubbed the wrong module and the results were garbage.

**Tell that caught it:** identical `17 failures` across suites of *different sizes*. Identical
numbers across non-identical inputs = your harness, not the code.

**Fix:** target each lane's check file explicitly. Never glob.

### 4. Naive substring path matching (shipped to main)
`String.contains?(filename, "mix/tasks/")` exempts `lib/vendor/remix/tasks/thing.ex` — an
ordinary module, no `use Mix.Task`, ships in the release, calls `Mix.env()`. **Silently exempt.**
A false negative on the exact prod crash the check exists to prevent. An FP annoys you; this lies
to you — strictly worse.

I passed this check. My FP corpus was real-world code, which by construction contains no
adversarial lookalike paths.

**Fix — boundary matcher:**
```elixir
defp fragment_matches?(filename, fragment) do
  String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
    String.contains?(filename, "/#{fragment}")
end
```
**Lookalike-probe rule:** every path/name-fragment matcher gets an adversarial lookalike input
(`latest/` vs `test/`, `remix/tasks/` vs `mix/tasks/`), not just a real-corpus run.
`String.ends_with?("_test.exs")` is inherently boundary-safe — suffix matching has no
interior-substring failure mode.

### 5. Dead `files:` param → false-green test (#10)
`param_defaults[:files]` prunes at Credo's *pipeline* level, before `run/2`. Under
`Credo.Test.Case` that pruning never happens (`Credo.Test.CheckRunner` calls
`run_on_all_source_files/3` directly; `check.ex:411-418` maps over every file with no filtering).

Result: a check whose scoping lived only in `files:` **passes its entire test suite while doing
nothing in production.** #10's test asserted `excluded_files: []` re-enables flagging; proven
false in a project-relative CLI run.

**Fix:** correctness guard lives in `run/2` against `source_file.filename`. `files:` is
production pruning only — never the sole mechanism.

**Sub-trap:** Credo's `files:` globs don't match **absolute** paths. My first #10 probe used
`/tmp/...` and appeared to pass. Always probe with project-relative paths.

---

## Patterns that worked

### run/2-stub beats file-revert as TDD proof
Contract said "revert the lib file, confirm tests fail." For Credo checks that's a **compile
error** (module undefined) — a wrong-reason RED that a genuinely weak suite would sail through.

Instead: stub `run/2` to return `[]`, keeping the module compilable. Assertions must go RED.
```elixir
def run(_source_file, _params \\ []), do: []
```
Every lane: 6–17 of N tests went red. Restore, `compile --force`, verify `git status` clean.

### Targeted revert-proof (strongest evidence of the cycle)
Better than stubbing the whole check: revert **only the fixed line**, run the suite, confirm
*exactly* the regression test fails.

#4-fix: naive matcher restored → **exactly 2 failures**, both boundary tests, nothing else. That
proves the test *pins the bug*, not merely that it passes. A test that passes proves nothing; a
test that fails when you reintroduce the bug proves everything.

### Ground-truth every claimed reference
#11's messages pointed at `SharedUtils.Map.atomize_keys/1` (actually in `Enum`),
`SharedUtils.Map.deep_merge/2` (**doesn't exist**). 5 of 8 defaults wrong. A dev obeying the
check gets `UndefinedFunctionError` — the check's *entire purpose* is redirecting them correctly.

Caught by grepping the real SharedUtils source, not by reading the check. **Verify claimed
external references against the source, always.**

### Pre-agree acceptance criteria on fix lanes
For #4-fix I published a 5-case matrix (exploit flags / conventional task silent / umbrella task
silent / `use Mix.Task` off-path silent / ordinary lib flags) *before* the worker started. Landed
in one round, zero ambiguity about "fixed."

### Verify the merged delta, not just the reviewed commit
#13 merged as `845d500`, I reviewed `956ccc3`. Diffed them: exactly one `# credo:disable-for-this-file`
line. Trust but diff — a passed review is not a licence for what lands.

### Report your own errors
I disclosed the wrong-file stub batch and the fact that I'd mutated two live worktrees mid-edit.
An evaluator who hides mistakes is worth less than no evaluator. Disclosure also let the affected
workers verify nothing was lost.

---

## Anti-patterns caught in lanes

- **File-level suppression on a per-item rule** (#2): Blitz's `TodosNeedTickets` returns `[]` for
  the *whole file* once any ticket URL appears. A straight port inherits that and passes naive
  tests. Probe: ticketed TODO at line N + bare TODO at N+5 → the second **must** flag.
- **Linter advice that breaks the code** (#1): flagging `==` inside Ecto `having`/`select` — Ecto
  **rejects `===`**. Obeying the check yields a compile error.
- **Wrong column → points at the exempt token** (#1): no `column:` in `format_issue` ⇒ Credo pins
  every `==` on a line to the *first* one. On `where(q, [u], u.age == 18) && flag == true` the one
  real violation got reported at the **Ecto** `==` — the one comparison you must not touch.
- **Fix trades one bug for another** (#1 rounds 1–3): FN fix introduced an alias FP; alias fix had
  to preserve the FN fix. **Re-probe every previously-closed direction on every re-review**, not
  just the newest fix.
- **Overly-broad grant** (#12): granting `{Process, :flag}` must not grant `Process.sleep`. Tuple
  grants must be function-precise. Verified both.

---

## Process notes

- **`completed` ≠ merge-ready.** Lanes self-flipped to `completed` (incl. one I'd returned
  NEEDS_REFINEMENT). Merge gate must be `metadata.review == "PASS"`, set by the evaluator only.
  Self-certification is exactly what an external evaluator exists to prevent.
- **Never mutate a live worktree.** `git status --porcelain` before touching anything; a dirty
  tree means the worker is mid-edit and your review is a snapshot of a moving target. Twice I
  held a merge because the reviewed commit wasn't the worker's final state (#11, #4-fix).
- **`checks:` in `.credo.exs` is ADDITIVE** to Credo's ~69 defaults, not a replacement (1 listed →
  70 ran). Consequence: `TodosNeedTickets` double-reports with default-on
  `Credo.Check.Design.TagTODO`. Consumers need `disabled: [{Credo.Check.Design.TagTODO, []}]`.
- **Dogfood with a planted fixture.** All 14 checks vs own source → 0 issues. Only trustworthy
  because a planted one-violation-per-check fixture lit up all 14 first.

---

## For #16 (SourceFilter extraction)

`fragment_matches?` is hand-rolled in **three** lanes (#4-fix, #10, #11). That is exactly how one
drifts back to `String.contains?` and silently reopens the FN. Extract to a single shared impl,
and ship it with the lookalike-path test (`lib/vendor/remix/tasks/thing.ex`) as its regression
pin. Review the extraction adversarially — collapsing three copies into one is precisely the
change that can reintroduce the bug that was just pinned.
