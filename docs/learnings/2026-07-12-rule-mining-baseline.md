# Learnings — stock/blitz coverage baseline (lane dedup-baseline)

Written by the lead on the miner's behalf — Explore-type agents have no Write tool
(shutdown-skill Phase 0 gap). Content distilled from the miner's final report.

Task: enumerate stock Credo (v1.7) + blitz_credo_checks coverage with default-enabled
flags, as the dedup baseline for new-check proposals.

## Where Credo's default-enabled set actually lives

Credo's own root `.credo.exs` is **embedded at compile time**
(`lib/credo/execution/task/append_default_config.ex` → `File.read!(".credo.exs")`).
The `disabled:` "Controversial and experimental (opt-in)" block there IS the
authoritative OFF-by-default list — read it from the dep source, don't guess from docs.

## Two config-reading traps

- **Commented-out config examples look like coverage but aren't.** `Refactor.MapInto` and
  `Warning.UnusedOperation` appear only as commented-out lines in the default config —
  neither enabled nor in the opt-in list. Treat as OFF; counting them as live coverage
  would wrongly kill a proposal.
- **Deprecated ≠ available.** `Refactor.CaseTrivialMatches` is deprecated upstream ("might
  do more harm than good") — don't count deprecated checks as live coverage either.

## Baseline shape that made the dedup usable

One line per check (`CheckName | what it flags`), OFF-by-default flagged inline, split by
source (stock consistency/design/readability/refactor/warning + blitz). The consumer of
this table needs exactly three answers per convention: covered-and-on, covered-but-off
(→ enable, don't write), or uncovered (→ candidate). Note: blitz_credo_checks present in
cfx/lex/opgg worktree deps, absent in dai — per-repo dep presence matters for "covered".
