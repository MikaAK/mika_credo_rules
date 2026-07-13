# Learnings — rule mining from session transcripts (lane session-miner)

Written by the lead on the miner's behalf — Explore-type agents have no Write tool
(shutdown-skill Phase 0 gap: read-only agent types cannot author their own learnings).
Content distilled from the miner's final report.

Task: mine ~/.claude/projects session transcripts across five repos for evidence-backed
candidate Credo checks (fed the wave-2 build: commit `737a09f`).

## The doc-echo inflation trap (the headline)

`~/.claude/skills/elixir-code-style` is injected into ~40 sessions. **Any naive grep for a
rule NAMED in an injected skill doc counts the doc itself, not incidents.** "45% flake" and
"cyclic compilation" matched 40 sessions with ZERO real occurrences — pure echo of the
skill text being re-shown per session. Distinguish three evidence classes and count only
the first two:

1. **Crash tracebacks** (`BadBooleanError ... got: "ra-316"` at a real file:line)
2. **Live-code violations** (grep the repo itself, read the hits — e.g. 7 unguarded
   `function_exported?` sites in opgg)
3. **Doc text / planning chatter** — discard; it inflates any rule that is already codified

The most-documented rules produce the MOST false mining signal, precisely because they are
repeated into every session.

## Honest negatives are deliverables

- The N+1/missing-preload check class had **zero** real incidents despite hard grepping —
  every hit was skill-doc echo. Reported as "do NOT build on this evidence."
- Explicit "we should have a credo rule for X" wishes: essentially zero. The entire
  candidate list was inferred from failures, not requested — stated up front so the lead
  could pitch it honestly.

A mining report that only lists positives silently overstates its mandate.

## Method notes

- Sessions are 10–100MB jsonl; grep-first (`grep -a -o/-c` with targeted patterns), extract
  surrounding JSON only for hits, never read whole files.
- The strongest candidate profile: rule already codified in a skill doc + live violations
  in shipping code + a diagnosed incident. (EnsureLoadedBeforeExported hit all three:
  documented ~45% flake, 7 guarded vs 7 unguarded sites in one repo — "known and
  half-applied" is the ideal new-check evidence.)
- Count distinct sessions/repos, not raw hits — one incident echoed across three worktree
  sessions is one incident (deploy-ex embedded-schema error appeared in 3 sessions, 1 real).
