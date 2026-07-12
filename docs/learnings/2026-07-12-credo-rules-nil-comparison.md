# Learnings — NoNilComparison lane (Task #7, 2026-07-12)

Worker: nil-comparison. Lane: fresh Credo check `MikaCredoRules.NoNilComparison`. Zero refinement rounds; reviewer grep ground-truth matched output exactly (0 FP, 0 FN).

## 1. nil-literal AST distinction — no false-positive risk

In Elixir AST, literal `nil` is the bare atom `nil`. Variables are 3-tuples `{:value, meta, context}` — context slot often `nil`, but the NODE itself never is. So `is_nil(lhs) or is_nil(rhs)` on operator args distinguishes literal-nil operand from everything else with zero ambiguity:

```elixir
# value == nil  →  {:==, meta, [{:value, [line: 2], nil}, nil]}
#                                ^ 3-tuple, not nil      ^ literal nil

defp traverse({operator, meta, [lhs, rhs]} = ast, acc, operators)
     when is_atom(operator) and (is_nil(lhs) or is_nil(rhs)) do
```

Non-risks verified by tests:
- `"nil"` string literal ≠ atom nil — not matched.
- `case value do nil -> ...` — pattern clause is `{:->, _, [[nil], body]}`, no operator node — not matched.
- `Map.get(map, :key, nil)` — arg-position nil sits under `{:., ...}` call node with 3 args — head wants exactly `[lhs, rhs]` AND operator filter (`:foo`/`{:., ...}` not in `[:==, :!=, :===, :!==]`) — not matched.
- 2-tuple literals `{nil, x}` stay plain 2-tuples in AST (only 3+ tuples become `{:{}, meta, args}`) — shape never matches.

Broad head + runtime `operator in operators` check (param, so can't go in guard) beats enumerating operator heads: one clause, param-configurable.

## 2. Guards come free — prewalk descends into `:when`

No special guard handling needed. `def fallback(value) when value == nil` AST nests the comparison inside `{:when, _, [args, guard]}`, and `Credo.Code.prewalk/2` walks every node — the `{:==, meta, [lhs, nil]}` inside the guard is the SAME shape as in a body. Same for case-clause guards (`other when other !== nil ->`). One traverse clause covers bodies + def guards + clause guards. Tests pinned all three.

Corollary: any operator-shaped Credo check gets guard coverage automatically. Don't write `:when`-specific clauses unless you need to EXEMPT guards.

## 3. Ecto needs no whitelist here

`BlitzCredoChecks.StrictComparison` whitelists query macros because `==` is required inside Ecto queries. Nil comparison is opposite: Ecto itself rejects `field == nil` at compile time ("comparison with nil is forbidden... use is_nil/1"). So no query exemption — `is_nil/1` is the required spelling both in and out of queries. Check contract before copying whitelist machinery from sibling checks.

## 4. Worktree-reap recovery pattern

Mid-task, harness auto-clean pruned my worktree (`git worktree list` no longer showed it; branch deleted; dir wiped to empty). My freshly written test file survived only because Write recreated the dir. Symptoms → diagnosis → recovery:

Symptoms:
- `mix test path` → "Paths given did not match" (bash cwd silently fell back to main repo root)
- `cd <worktree> && mix test` → "Could not find a Mix.Project" (no mix.exs — dir gutted)
- `ls <worktree>` shows only files YOU wrote after the reap

Recovery (lost ~3 min, zero work lost):
1. `cp` surviving uncommitted files to scratchpad FIRST — before touching the dir.
2. Confirm reap: `git -C <main-repo> worktree list` + `git branch --list <lane-branch>` (both empty for my lane).
3. `rm -rf <worktree-dir>` (worktree add refuses non-empty dirs).
4. `git -C <main-repo> worktree add <dir> -b <same-branch-name> <main-head-sha>` — reuse the exact branch name so downstream tooling (task metadata, reviewer instructions) stays valid.
5. Restore files from scratchpad, `mix deps.get`, re-run gates, continue.

Prevention notes for the harness:
- Reap happened between my baseline run and first Write — likely "auto-cleaned if unchanged" logic saw a clean tree. Committing a WIP marker early, or writing the RED test before any long pause, keeps the tree dirty and reap-proof.
- Workers should treat "mix can't find project" + "cwd reset" as a reap signal, not a path typo — check `git worktree list` before debugging paths.
- Always Write with absolute paths into the worktree; that's what saved the test file here.

## 5. Process notes

- No TaskGet/TaskUpdate in worker toolset this run — coordinator relayed contract and flipped status by proxy via SendMessage. Worked, but added a round-trip; roster should either grant task tools or inline the contract in the dispatch payload.
- Exact-message assertions (`assert issue.message === "..."`) over `=~` mattered: `"=== nil found"` CONTAINS `"== nil found"` as substring, so `=~` cannot distinguish the two operators. Substring assertions on operator-family messages are a false-green trap.
- `Credo.SourceFile.parse/2` outside a Credo run needs `Application.ensure_all_started(:credo)` (interning GenServer) — required for smoke scripts that run a check standalone over repo files.
