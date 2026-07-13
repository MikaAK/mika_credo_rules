# Learnings — rule mining from convention gaps (lane gap-miner)

Written by the lead on the miner's behalf — Explore-type agents have no Write tool
(shutdown-skill Phase 0 gap). Content distilled from the miner's final report.

Task: diff documented workspace conventions (CLAUDE.md files, elixir-* skills, AGENTS.md)
against existing check coverage (14 MikaCredoRules + stock Credo + blitz) to find
enforceable gaps. Fed the wave-2 build (`737a09f`).

## Dedup against the FULL existing surface before proposing anything

Roughly half the documented conventions were already covered — but by checks that are
**OFF by default** in stock Credo (NegatedIsNil, PipeChainStart, BlockPipe, SinglePipe,
UnsafeToAtom). The right deliverable for those is "enable stock in the consumer config,"
not a new check. A proposal list that skips this pass produces duplicate checks; one that
includes it produces config one-liners. Keep the "covered-by" drop list in the report so
the lead can verify the dedup rather than trust it.

## Detectability findings worth keeping

- **Capture-parens style (`&(&1.id)` vs `& &1.id`) is NOT AST-distinguishable** — identical
  AST; would need raw-source matching. Don't promise it as an AST check.
- **A transforming `defdelegate` is syntactically impossible** — the convention "don't use
  defdelegate when args need transformation" has nothing to detect; the violation cannot be
  written. Some documented rules are self-enforcing.
- Several candidates (Kernel.-prefix, boolean-literal comparison, ensure_loaded-guard,
  raw-ETS, Task.async-in-GenServer) are all **remote-call checks** — batching any three
  justifies resurrecting the shared `AstHelpers.remote_call` helper (held at `1ea1255`)
  alias-aware, rather than re-implementing per check.

## Ranking axis

Order candidates by (mechanical detectability, FP risk, likelihood of landing at 0 issues
on a mature repo) — NOT by how important the convention sounds. The adoption learnings
show tier is a property of the check; a proposal predicted to land in the hundreds
(do_-prefix ban) is a different product than one predicted green (cast(Map.keys)).
