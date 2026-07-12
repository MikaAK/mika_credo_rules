# Learnings — strict-equality lane, mika_credo_rules build (2026-07-12)

Role: worker, lane #1 — `MikaCredoRules.StrictEquality` (port of `BlitzCredoChecks.StrictComparison`).
Merged commit: `0900144`. Three refinement rounds. All three findings were module-matching bugs — none were operator-detection bugs. Detecting `==` is trivial; deciding *whose* `==` is exempt is the whole check.

---

## 1. Port improvement: subtree prune beats line-number whitelist

Blitz exempts Ecto DSL by collecting every line number inside query macros (`recurse_lines`) and rejecting issues on those lines. Line granularity = false negative for any loose comparison SHARING a line with a query call:

```elixir
if(mode == :all, do: query, else: where(query, [u], u.deleted == false))
#  ^^^^^^^^^^^^ blitz misses this — where/3 whitelisted the whole line
```

Replacement: in `Credo.Code.prewalk`, return `{nil, acc}` for exempt calls. `Macro.prewalk` never descends into a leaf, so exemption scope === call arguments exactly. ~4 lines, strictly more precise, no filter pass. Test "still reports a loose comparison beside a query call on the same line" locks it.

**Rule:** when porting a check, ask what GRANULARITY the original whitelists at. Line-based whitelisting is almost always an approximation of "this subtree" — prune the subtree instead.

---

## 2. Round 1: wildcard module position = false NEGATIVE (`Enum.join`)

My qualified-call prune clause:

```elixir
defp traverse({{:., _, [_, function]}, _, args} = ast, ...)   # _ = ANY module
```

`:join` in the ignore list → `Enum.join(names, if(left == right, ...))` silently exempted its arguments. Function names collide across modules constantly (`join`, `select`, `query`, `from` are everywhere). A wildcard module position converts a function-name allowlist into a universal one.

Fix: qualified calls only exempt when module is `[:Ecto, :Query]` / `[Elixir, :Ecto, :Query]`. Bare/imported calls keep name-only matching (that's the `import Ecto.Query` path — correct).

**Rule:** never match dotted calls by function name alone. `{{:., _, [_, function]}, _, _}` with a name-list check is a bug template.

---

## 3. Round 3: the round-1 fix created a false POSITIVE (`alias Ecto.Query`)

Exact-module matching broke the aliased spelling:

```elixir
alias Ecto.Query
Query.where(query, [u], u.age == ^age)   # AST module is [:Query] — flagged
```

Worst FP class: the flagged code is UN-FIXABLE by the user — Ecto's DSL rejects `===`, so following the check's advice breaks the query.

Fix: per-file alias fold (canonical check's `collect_aliases`/`apply_alias` shape, lane #13's generalized 3-form version): `alias Ecto.Query`, `alias Ecto.Query, as: Q`, `alias Ecto.{Query, ...}` all fold local names onto the exempt base. Kept local to the file per instruction — extraction is post-merge (task #16).

Two meta-lessons:

- **Module identity in Credo is never one pattern.** Any module has ≥4 spellings: bare, `Elixir.`-prefixed, aliased, alias-renamed (+multi-alias). The canonical check solved this for `Application` on day one; I matched 2 of 4 spellings and shipped rounds 2-and-3 worth of bugs from the gap. If a check cares about a specific module, it needs the alias fold from the first commit.
- **Disclosing the known edge early was right.** I flagged the `alias Ecto.Query` gap in my round-1 re-report as a "known remaining scope edge." Reviewer later confirmed it as a real FP with a repro — but the disclosure meant it was a known-tradeoff-turned-finding, not a hidden defect. Cheap insurance: one paragraph in the report vs. looking like you didn't understand your own matcher.

**Rule (tension to manage):** exact-module matching fixes FNs but creates FPs on aliased spellings; name-only matching fixes FPs but creates FNs on collisions. The stable point is exact-module + alias fold. Nothing simpler survives review.

---

## 4. `column:` metadata — Credo pins to the FIRST trigger occurrence on the line

Without `column:` in `format_issue`, Credo locates the issue by searching the line for the trigger string. Mixed line:

```elixir
where(query, [u], u.age == 18) && flag == true
#                        ^col 29         ^col 44 — the actual violation
```

Issue rendered at col 29 — INSIDE the exempt Ecto comparison. RED test proved it empirically: `left: 29, right: 44`. Fix is free: operator AST meta already carries `column:` (Credo parses with `columns: true` — `deps/credo/lib/credo/code.ex:89`), just thread `meta[:column]` through.

**Rule:** any check whose trigger can appear >1× per line (operators especially) must pass `column:`. Trigger-string search is a fallback, not a locator.

---

## 5. Patterns that worked

- **TDD on reviewer findings**: every round started with a RED test reproducing the finding (`got none` / `left: 29, right: 44` / 3× refute_issues failures). RED output doubles as confirmation the finding is real — round 2's column repro confirmed the reviewer's claim exactly before any fix.
- **CLI smoke via external `--config-file`** (scratchpad config + fixture): proves the check fires through Credo's real engine, not just `Credo.Test.Case`, without ever touching the repo's `.credo.exs`. Positive control (must flag) + negative control (must not flag) in one fixture. Note: `--config-file` APPENDS to default config (70 checks ran) — fine for smoke, but don't mistake "no issues" for "my check ran"; keep the positive control.
- **Single amended commit per lane** (`6d0aeff` → … → merged `0900144`): reviewer always re-reviews one coherent diff, no fixup archaeology.
- **`for {:__aliases__, _, inner} <- inner_nodes`** comprehension in multi-alias expansion: pattern filter drops weird AST shapes instead of crashing the check on them (`Enum.map` + narrow head would raise).

## Anti-patterns avoided

- Faithful-port trap: didn't copy blitz's `Mix.env() == :prod` exact-AST special case; generalized to either-operand (atoms can't coerce under `==`; runtime `Mix.env/0` misuse is lane #4's rule). Stated the intent in the moduledoc when the reviewer asked — an exemption wider than the contract needs its rationale written down or it reads as an accident.
- Didn't extract the alias fold to a shared helper mid-build despite 2 lanes needing it — parallel lanes editing a shared file = merge conflict factory. Duplication receipt goes to the post-merge task instead.
- Didn't widen `ignored_functions` beyond reviewer-confirmed FPs (`having`/`or_having`/`select`/`select_merge` added only after the round-2 finding showed real Ecto rejected by the check's own advice).
