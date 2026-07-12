---
name: verifying-credo-checks
description: Use when testing, reviewing, or claiming done on a custom Credo check in this repo — before trusting a "found no issues" result, after any mutate-restore cycle, when configuring .credo.exs, or when a check's message names an external module/function. Catalogues the four false-greens this package actually shipped.
---

# Verifying Credo Checks

> **A check that cannot fire is indistinguishable from a check with nothing to report.**
> Both print `found no issues`.

You probably already know to plant a positive control and mutation-test the suite. This skill
exists for the failures that are **not derivable** — the ones that cost this package real bugs
and near-misses even with careful review.

For writing checks, see **`writing-credo-checks`**.

## 1. Stale beam — the worst near-miss of the build

After a `run/2`-stub → restore, `mix credo` **kept running the stubbed `.beam` from the build
cache**. Probes returned 0 issues. The reviewer was one step from filing false-negative blockers
against two clean lanes.

```bash
# after ANY mutate-restore cycle, before ANY probe:
mix compile --force
git status --short      # confirm no residue
```

Nothing in the output tells you the beam is stale. This is invisible without the habit.

## 2. `files:` param is INERT under `Credo.Test.Case`

`param_defaults[:files]` prunes at Credo's **pipeline** level. `Credo.Test.CheckRunner` calls
`run_on_all_source_files/3` directly (`check.ex:411-418` maps over every file with no
filtering), so the pruning never happens under test.

**A check scoped only by `files:` passes its entire suite while doing nothing in production.**
Correctness must live in a `run/2` guard on `source_file.filename`.

**Sub-trap:** Credo's `files:` globs don't match **absolute** paths. A probe using `/tmp/...`
appears to pass. Always probe with project-relative paths.

## 3. `.credo.exs` config name is load-bearing

- **The config MUST be named `"default"`.** Credo selects by name; any other name is **silently
  ignored** and Credo runs its own stock checks instead — printing a green result that executed
  **none** of yours. (A 14-check dogfood sweep once ran zero of them this way.)
- **`checks:` is ADDITIVE — but only in the LIST form.** `checks: [ ... ]` merges with Credo's
  ~70 defaults; the map form `checks: %{enabled: [ ... ]}` runs ONLY the listed checks, no
  defaults. Don't reason from the form — read `running N checks on M files` in the output: N
  bigger than what you listed means defaults merged in (list form → you need the TagTODO
  disable); N equal means map form and no `disabled:` block is needed.
- Consequence (list form): `TodosNeedTickets` double-reports against default-on
  `Credo.Check.Design.TagTODO`. Consumers need `disabled: [{Credo.Check.Design.TagTODO, []}]`.
- **Read the file count too.** `running N checks on 0 files` means the `included` globs match
  nothing — `included` resolves relative to CWD, not the config file, so an umbrella root with
  `included: ["lib/", "test/"]` scans zero files and the whole config passes vacuously (a real
  repo's Credo CI job did this for its entire life). Umbrella configs need
  `["lib/", "test/", "apps/*/lib/", "apps/*/test/"]` to work from both the root and app dirs.

## 4. Ground-truth every reference a check emits

If a message says "use `SharedUtils.Map.atomize_keys/1` instead" — **grep the real source**.
Five of eight such pointers in one check were wrong (`atomize_keys` is in `Enum`; `deep_merge`
didn't exist at all).

A dev obeying the check gets `UndefinedFunctionError`, and redirecting them correctly is the
check's *entire purpose*. **No lane test catches this**: tests assert the message's *format*,
never its *truth*. Applies to every module name, function pointer, config key, and URL.

## 5. Adversarial lookalikes — real corpora can't produce them

A real-world corpus by construction contains **no adversarial lookalike paths**. That is exactly
how a naive `String.contains?` matcher shipped to main.

| Fragment | Lookalike that must still be checked |
|---|---|
| `test/` | `lib/latest/helpers.ex` |
| `mix/tasks/` | `lib/vendor/remix/tasks/thing.ex` |
| `web/` | `lib/webhooks/handler.ex` |

`String.ends_with?("_test.exs")` is inherently boundary-safe. Only *fragment* matching needs this.

## 6. Docs are executable, not aspirational

Every `# BAD` example in a `@moduledoc` or the README is a **claim that the check fires on it**.
A BAD example that doesn't fire teaches users the wrong mental model — and nothing in the test
suite checks this, because doc examples live in heredocs (string literals, never AST call nodes).

Lift each BAD block into a fixture and run its own check against it:

```elixir
code
|> Credo.SourceFile.parse("lib/s.ex")   # or "test/s_test.exs" for test-scoped checks
|> MyCheck.run([])
|> case do
  [] -> raise "BAD example does not fire — the docs are lying"
  issues -> issues
end
```

Mind the filename: a test-scoped check (`NoProcessSleepInTests`, `RefuteOverAssertNot`) will
correctly stay silent if you parse its BAD example under `lib/`. Wrong filename → false FAIL.

Same discipline as everything else here — **prove the gate can go red**: feed it a GOOD example
where a BAD one belongs and confirm it reports FAIL. (Run against all 14 checks: 14/14 fire; the
gate reports FAIL when handed a `===` example in place of a `==` one.)

## 7. Prefer a `run/2` stub over deleting the file

Reverting the check file gives a **compile error** (module undefined) — a wrong-reason RED that
a genuinely weak suite sails through. Stub instead, keeping the module compilable:

```elixir
def run(_source_file, _params \\ []), do: []
```

**Stronger still — targeted revert:** revert only the *fixed line*, confirm *exactly* the
regression test fails and nothing else. Restoring the naive path matcher produced exactly 2
failures, both boundary tests — proving the tests **pin the bug** rather than merely coexisting
with the fix.

## 8. Probe for over-correction after every false-positive fix

An FP fix routinely opens an FN. This happened: the `Enum.join` FN fix introduced the
`alias Ecto.Query` FP; the alias fix then had to preserve the FN fix.

**Re-probe every previously-closed direction on every re-review** — not just the newest fix.

- Fixed `cond`-head FP → does a real `(v = f()) > 1 -> v` binding still flag? (must: yes)
- Fixed `Process.flag` FP → does `Process.sleep` in `init/1` still flag? (must: yes)
- Fixed `alias Ecto.Query` FP → does `alias MyApp.Query` still flag? (must: yes)

## Diagnostic tells

| Symptom | Means |
|---|---|
| Identical failure counts across suites of **different sizes** | Your harness is broken, not the code |
| A mutation produces **zero** new failures | The mutant may be inert — confirm it changes behaviour before blaming the tests |
| Reported test count doesn't reproduce | The quoted run is stale; re-run before believing any of it |

## Review notes

- **`completed` ≠ merge-ready.** Lanes self-certify; the merge gate is an evaluator's PASS.
- **Never mutate a live worktree.** `git status --porcelain` first — a dirty tree means the
  author is mid-edit and your review is a snapshot of a moving target.
- **Verify the merged delta, not just the reviewed commit.**
- **Pre-agree acceptance criteria** on fix lanes — publish the case matrix before work starts.
- **Report your own errors.** An evaluator who hides mistakes is worth less than no evaluator.
