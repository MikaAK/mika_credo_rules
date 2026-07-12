# Learnings — architect-abstractions, mika_credo_rules build (2026-07-12)

Role: abstraction monitor + contract validator across 13 parallel check-building lanes.

---

## 1. "Green" is a claim, not evidence — four times over

Four separate times this cycle, something reported success while doing nothing. Same shape every time: a mechanism that *looks* active and is silently inert.

| # | What claimed green | What was actually happening |
|---|---|---|
| 1 | 4 sprint contracts scoping via Credo's `files:` param | `files:` is inert under `Credo.Test.Case` — only the production engine honours it. Tests asserting "does not fire in lib/foo.ex" could never pass. |
| 2 | `NoReimplementedHelper` with `excluded_paths: ["test/"]` | Naive `String.contains?` — `lib/latest/helpers.ex` contains `"test/"` inside `"la-**test**/"`. Check silently skipped real source. |
| 3 | `NoReimplementedHelper`'s replacement pointers | 5 of 8 named SharedUtils modules that don't exist. A check whose entire product is "use X instead" where X is fictional. |
| 4 | My own dogfood sweep: `found no issues` | Credo selects the config named `"default"`. Mine was named `"dogfood"` → silently ignored, fell back to stock checks. **My 14 checks never ran.** |

**#4 is the one that matters**, because I was the one auditing for exactly this class of bug and my audit tool had the bug. I nearly reported "0 issues, ship it" on a run that executed none of our checks.

**The only thing that caught it: mutation testing the gate itself.** Strip `NoMockingLibraries`' disable header → the check *must* fire. It didn't. That single probe is what separated a real green from a fake one.

**Rule:** before trusting any gate's green, make it go red on purpose. If you can't produce a red, you don't have a gate — you have a decoration. This applies to the gate you just built, not only the code under test.

---

## 2. Parallel lanes silently re-derive each other's logic — and get it wrong

Thirteen lanes, no cross-talk by design. Great for throughput; the cost is concentrated and predictable.

| Concept | Hand-rolled copies | Correct | Bugs shipped |
|---|---|---|---|
| module identity matching | 5 | — | `Enum.join` false-negative; `alias Ecto.Query` false-positive |
| alias resolution | 2 | 1 (`NoMockingLibraries` — the superset) | (the FP above) |
| path-fragment matching | 3 | 1 (`ErrorMessageRequired`) | naive `contains?` in 2 checks |

**3 concepts, 10 copies, 4 production bugs.** Every single bug was a lane re-deriving something a sibling lane *in the same package* had already gotten right.

Two lanes that never saw each other's code produced **byte-identical** helpers. That's not duplication to tidy up later — it's a correctness tax being paid in real bugs, and it's the whole argument for the `SourceFilter` / `AstHelpers` extraction (task #16, release-gated).

**Rule:** in parallel-lane builds, the abstraction monitor's job is not "spot repetition." It's "find where lane B re-derived lane A's logic and got a *different answer*." The divergences are the bugs; the identical copies are just the receipt.

---

## 3. False positives are the failure mode that kills a linter

Of the 5 defects I found in lane code, **4 were false positives**. That ratio isn't accidental — check authors optimise for catching violations, so the gaps land on the "wrongly flags valid code" side.

A false negative means the linter missed something. A false positive on **un-fixable code** means the user disables the rule. `alias Ecto.Query` → `Query.where(q, [u], u.age == ^age)` was being flagged, and `==` is the *only* operator Ecto's query compiler accepts. That rule would have been globally disabled within a day.

**Rule:** for any new lint rule, the review budget goes disproportionately into "what valid code does this wrongly flag?" — and every FP fix must be probed for over-correction (does the fix open a false negative?). Every fix I verified this cycle got both probes:
- `cond`-head FP fixed → but does `(v = f()) > 1 -> v` still bind `v`? (yes)
- `Process.flag` FP fixed → but does `Process.sleep` in `init/1` still flag? (yes)
- `Ecto.Query` alias FP fixed → but does `alias MyApp.Query` still flag? (yes — a lazy fix would have silenced it)

---

## 4. I caused a bug by over-specifying an implementation

I prescribed the exact matcher shape for `StrictEquality`'s fix: `module in [[:Ecto, :Query], [Elixir, :Ecto, :Query]]`. It closed the `Enum.join` false-negative and **opened** a false positive — under `alias Ecto.Query`, the AST module is `[:Query]`, matching neither.

The worker flagged the edge in their report and asked whether to handle it. I'd already shipped them a shape, so the shape is what they built.

The architect brief says: *constrain deliverables, not paths.* I should have written the **test** ("`alias Ecto.Query` + `Query.where(...)` must not flag") and let the implementer find the shape. Instead I wrote the code, got it subtly wrong, and the error propagated exactly as principle 19 predicts.

**Rule:** when correcting a lane, hand over the failing test case, not the fix. If the only way to verify a correction is to read the implementation, the correction was over-specified.

---

## 4b. What contract validation MISSED — and the pattern behind the misses

I validated all 13 contracts and caught the blocking `files:` defect. I also missed things, and the misses share a shape worth naming.

| Miss | Why I missed it |
|---|---|
| `NoReimplementedHelper`'s 8 default replacement pointers — **5 named SharedUtils modules that don't exist** (`atomize_keys` lives in `Enum`, not `Map`, etc.) | I validated the contract for *Credo-API feasibility* and never asked whether the **data it ships is true**. The contract handed me the full list. A check whose entire product is "use X instead" is worse than useless when X is fictional — it speaks with authority and sends every consumer somewhere that doesn't exist. |
| Naive `String.contains?` path exclusion in 2 lanes | I reviewed the *scoping mechanism* (guard in `run/2` — correct) and never probed the *matcher inside it*. Right structure, wrong predicate. |
| My "you MAY keep `files:` for production pruning" allowance | Reasoned from what the API nominally offers, not how it behaves. See §5. |

**The pattern: I checked whether things were *buildable*, not whether they were *true*.** Feasibility review is not correctness review. A contract can be perfectly implementable against the library API and still specify data that is false, a predicate that is wrong, or an affordance that is inert.

**Rule:** for any contract that ships **reference data** — module names, function pointers, error codes, config keys, URLs — verify each entry against the authoritative source *at contract time*. That verification is cheap (one grep of the catalog) and it is exactly the class of error that no test in the lane will ever catch, because the lane's tests assert the message *format*, not the message's *truth*.

---

## 4c. Alias resolution has two halves, and which one you need depends on segment count

Discovered when `StrictEquality`'s worker noted, almost in passing, that their `apply_alias` was the "add-only subset" of `NoMockingLibraries`'. That throwaway remark was a load-bearing correctness constraint on the planned shared helper.

- **ADD** — `alias Ecto.Query` means the local name `[:Query]` now refers to `Ecto.Query`, so `[:Query]` must **join** the match set.
- **REMOVE (shadowing)** — `alias MyApp.Application` means bare `[:Application]` no longer refers to Elixir's `Application`, so `[:Application]` must **leave** the match set.

Which half a check needs is determined by whether its base module path is **single-segment**:

| Check | Base path | Shadowable? | Needs |
|---|---|---|---|
| `NoApplicationEnvOutsideConfig` | `[:Application]` | yes (one segment) | ADD **and** REMOVE |
| `StrictEquality` | `[:Ecto, :Query]` | no (two segments) | ADD only |

This is why `StrictEquality`'s add-only fold is *correct*, and why `alias MyApp.Query` is still (correctly) flagged there.

**The trap:** a shared `resolve_aliases/2` must implement **both** halves, because it serves both kinds of caller. Extracting naively from *either* lane ships a silent regression into every adopter — an add-only implementation breaks the canonical check; a remove-happy one wrongly un-exempts `StrictEquality`. Had the extraction happened before this surfaced, the bug would have landed in 7 checks simultaneously.

**Rule:** before promoting a lane's implementation into a shared helper, enumerate every *caller's* requirements — not just the donor lane's. The donor's version is correct **for the donor**; that is not the same as correct.

---

## 5. The implementer has better information than the architect on implementation details

I told 4 lanes they "MAY keep `files:` in `param_defaults` for production pruning." The `sleep-tests` worker pushed back **in their completion report**:

> "Dropped `files:` despite contract 'optionally keep' — default pipeline glob would silently override user's custom `test_files` in production runs, and has zero effect under `Credo.Test.Case`. One scoping mechanism, not two disagreeing ones."

They were right. I was reasoning from *what the API nominally offers*; they were reasoning from *how the param actually behaves in production*. I under-weighted it, and architect-review had to prove it later — costing a review round.

**Rule:** this is not "workers are sometimes right." It's directional: on implementation-behaviour questions, the person who has to make the thing work has strictly better information than the person who specified it. Push-back in a completion report is a high-signal event, not noise to be acknowledged and moved past.

---

## 6. Task-list edits are not a delivery mechanism

I corrected 6 sprint contracts in the task list before workers spawned. **Workers cannot `TaskGet`** — their spawn environments have no task tools. Contract text reaches them only through the lead. My corrections were invisible; they landed only because the lead relayed them independently.

Related: `SendMessage` failing with "No agent named X is reachable" does **not** mean the agent doesn't exist. It meant they weren't peers of mine. I inferred "not yet spawned," which was wrong, and it cost a round-trip.

**Rule:** know your delivery channel before writing the correction. Update the task list as system-of-record, but assume the worker never sees it — route anything worker-bound explicitly through whoever owns their prompt.

---

## 7. What the abstraction monitor role should actually do

Concretely, what earned its keep:

1. **Validate contracts against the *library source*, not the docs.** The `files:` defect was found by tracing `Credo.Test.CheckRunner.run_check/3` → `run_on_all_source_files/3` → `run/2` and confirming `Params.files_included/3` is only ever called from the production runner. That's 10 minutes of reading `deps/` and it saved 4 lanes a wasted TDD cycle.
2. **Run executable probes, never read-and-reason.** Every one of the 5 defects came from *running* the check against a synthetic snippet and looking at the output. Not one came from reading the code and spotting a flaw.
3. **Re-verify every "fixed" against the original reproduction.** Workers self-report green in good faith and are sometimes still wrong (#11's path bug survived a "fixed" report because the round only addressed the pointer bug).
4. **Sweep for the *pattern*, not just the reported instance.** The path-boundary bug was reported in `NoReimplementedHelper`; grepping every lane for the same shape found it in `NoMixEnvAtRuntime` too — a lane nobody had flagged.
5. **Dogfood the whole set together.** 13 lanes each tested their check against their own fixtures. Nobody ran all 14 against real code until I did, which is where the self-reference problem surfaced.

---

## Candidate skill updates

- **`test-harness`** — add "mutation-prove the gate" to the verification protocol: any new quality gate must be shown to go red before its green is trusted. Add "unreachable ≠ nonexistent" to the agent-messaging notes.
- **`elixir-testing`** — the "prove a hardened test CATCHES the bug" section already covers this for tests; extend the same rule to *tooling configuration* (linter configs, CI gates). The Credo `--config-name` trap is a concrete, reusable example.
- **New skill candidate: `elixir-credo-checks`** — writing custom Credo checks is now a well-understood domain in this workspace and has non-obvious traps worth capturing: `files:` is inert under `Credo.Test.Case`; config `name:` must be `"default"` or the config is silently ignored; a config named `"default"` *merges* with Credo's built-ins (69 + yours) while any other name *replaces*; `Credo.Code.prewalk` returning `{nil, acc}` prunes a subtree; both `try/rescue` and `def...rescue` expose `rescue:` in one keyword list; alias resolution needs both ADD and REMOVE halves depending on whether the base path is single-segment.
