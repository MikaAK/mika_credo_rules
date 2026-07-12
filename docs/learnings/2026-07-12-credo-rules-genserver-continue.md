# Learnings — GenServerRequiresHandleContinue (lane #12, 2026-07-12)

Worker: genserver-continue. Hardest rule of the set (heuristic). One refinement cycle. Merged at 7bccaf3.

## 1. Heuristic-rule calibration: contract-correct ≠ right outcome

Contract said: flag remote call outside allow-list when no `{:continue, _}` in clause. Implemented exactly. Reviewer reproduced FP on `Process.flag(:trap_exit, true)` — THE standard GenServer idiom, present in huge fraction of real init/1s. `Logger.*` same. Contract-correct, adoption-killer.

Lesson: heuristic lint rule must be calibrated against real-idiom corpus BEFORE shipping, not only against contract test plan. Cheap calibration: mentally run rule over the reference GenServers in the very skill that motivates the rule (elixir-genserver-init examples use Process.flag, Logger, Task.async_nolink). If skill's GOOD examples flag → rule miscalibrated. Do this at plan time, not at review time.

## 2. Function-level tuple grants beat module-wide allowance

Fix options: (a) allow Process wholesale, (b) `{Module, :function}` tuple entries. Ruling: (b). Reason — pin property: `Process.sleep/1` in init/1 must STAY flagged; it blocks, and nothing else catches it outside test files. Module-wide grant loses exactly the call the rule exists for.

Mechanics: allow-list mixes shapes — bare module (normalized to `Module.split` string path or erlang atom) and `{module, function}` tuple. Membership check is two `not in`s: `module not in allowed and {module, function} not in allowed`. No collision — paths are lists, erlang modules atoms, tuples tuples. Erlang tuple form (`{:ets, :new}`) fell out free from same normalization.

Lesson: when an allow-list fix threatens a rule's core detection, split grant granularity instead of widening. Pin the preserved detection with an explicit regression test (`assert issue.trigger === "Process.sleep"`) — that test IS the ruling, encoded.

## 3. Access desugar: bracket access is a remote call with a BARE ATOM module

`opts[:url]` desugars to `{{:., _, [Access, :get]}, _, [opts, :url]}` — module slot is bare atom `:"Elixir.Access"`, NOT `{:__aliases__, _, [:Access]}`. Any AST matcher for "remote call to module X" that only handles `__aliases__` nodes either misses these or (worse) treats them like erlang atoms → FP on every bracket access. Same shape appears for string interpolation (`Kernel.to_string` bare atom).

Fix: normalize atom targets — `"Elixir." <> _` prefix → `Module.split`; else keep as erlang atom. One helper (`normalize_atom_module/1`) shared between param entries and AST targets keeps the two representations converging.

Lesson: three spellings of "module" in AST — `__aliases__` path, Elixir-prefixed atom, erlang atom. Normalize all three to one internal representation at collection time; comparisons stay dumb.

## 4. Per-clause evaluation

Contract violation definition was function-level ("no clause returns {:continue, _}") but test plan said "any violating clause flags" — conflict. Chose per-clause: each init/1 clause judged independently; `{:continue, _}` in clause A does not excuse blocking work in clause B. Semantically right — each clause is a separate code path; `def init(%{eager: true})` blocking is a bug even when the default clause defers. One issue per violating clause, anchored at first disallowed call (fix is singular: add continue / move work — flagging every call in clause = noise).

Lesson: when contract prose and contract test plan disagree, implement the semantically stronger reading, document the decision in moduledoc, surface it explicitly in the completion report as "flag if you disagree". Reviewer confirmed silently — decision documentation prevented a refinement cycle.

## 5. File-level `use GenServer` detection

Detection is one boolean prewalk over the file: literal `use GenServer` (or `use Elixir.GenServer`) anywhere → every `def init/1` in file checked. No per-module scoping, mirrors canonical check's flat file-level alias table.

Quantified limitation, both directions:
- FP requires ONE file containing BOTH a GenServer module AND a sibling/nested non-GenServer module defining `init/1` that makes disallowed remote calls without a `{:continue, _}` tuple. House style bans multiple modules per file outright, so incidence in target codebases ≈ 0.
- FN: `use` injected via another macro's `__using__` invisible (Credo doesn't macro-expand) — same blindness as canonical check's alias limitation; no cheap fix exists.

Smoke evidence the stance is safe: run/2 over this repo's own 7 files (including test file whose heredoc fixtures CONTAIN `use GenServer` as strings) → 0 issues, no crash — heredocs are string literals, not AST, so fixture-heavy test files don't self-flag.

## Process notes

- TDD both cycles: RED 12/12 undefined-module, GREEN 12/12; refinement RED 3/16 (trap_exit, Logger, tuple param), GREEN 16/16. Final: 41/41 suite, credo --strict clean, --warnings-as-errors clean.
- Trigger omits arity deliberately — piped calls lie about arity in raw AST (`opts |> Repo.load()` shows /1).
- `Enum.join(path, ".")` on alias paths crashes on non-atom segments (`__MODULE__.Sub`) — treat paths with non-atom segments as unresolvable/local at collection, avoids both the crash and a dubious flag.
- Task-store fallback: worker env had no TaskGet/TaskUpdate tools; contract retrieved from ~/.claude/tasks/session-<id>/12.json directly. Status flips delegated to main.
