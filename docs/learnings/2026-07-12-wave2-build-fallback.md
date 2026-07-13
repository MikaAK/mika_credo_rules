# Learnings — NoAtomStringKeyFallback (2026-07-12, wave 2)

Worker: no-atom-string-key-fallback. Check: `MikaCredoRules.NoAtomStringKeyFallback`.
22 tests green first run; dogfood 0; mutation → exactly 2 targeted failures.

## Spec correction: `||` is LEFT-associative

The build spec claimed `m["k"] || m[:k] || default` parses right-associative as
`{:||, _, [m["k"], {:||, _, [m[:k], default]}]}`. It doesn't. Verified with
`Code.string_to_quoted!/1` before writing the traverse:

```elixir
{:||, _, [{:||, _, [m["k"], m[:k]]}, default]}   # (a || b) || c
```

Probe the parser before trusting any spec's AST shape — one `elixir -e` line
settled it. (Same lesson as the skill's "enumerate every construct" rule, applied
to associativity.)

## Adjacent-pair enumeration via spine walks

Don't hardcode either associativity. At each `{:||, _, [left, right]}` node,
compare `spine_tail(left)` (rightmost leaf of the left `||` subtree) against
`spine_head(right)` (leftmost leaf of the right `||` subtree):

```elixir
defp spine_tail({:||, _, [_left, right]}), do: spine_tail(right)
defp spine_tail(ast), do: ast
```

Every `||` node is the boundary between its subtrees, so tail-vs-head enumerates
exactly the adjacent pairs of the flattened chain — head-of-chain, tail-of-chain,
and explicitly parenthesized right-nesting all fire from one rule, each pair at
most once (prewalk visits every `||` node; only the boundary node for a given
pair matches). Tested all three shapes plus a chained single-issue pin via
`assert_issue`.

## Dogfood trap: `--checks` on an unregistered check runs ZERO checks

`mix credo --checks "MikaCredoRules.NoAtomStringKeyFallback"` printed
`found no issues` — with `running 0 checks on 37 files`. `--checks` FILTERS the
config's enabled set; a check absent from `.credo.exs` matches nothing, and the
green is vacuous. New variant of verifying-skill §3's config false-greens.

- Always read the `running N checks` line; N must be ≥ 1 before trusting green.
- When `.credo.exs` is off-limits, dogfood via `--config-file <scratch>.exs`
  (name `"default"`, map `checks: %{enabled: [...]}` form → runs only yours).
- Then prove the gate can go red: temp positive-control file in `lib/`, expect
  1 issue at the right file:line:column, delete it.

## Worktree reaping mid-build

My agent worktree was reaped after a transient session error (zero-change turn —
known harness quirk), and cwd reset to the repo root. Recovery:

- Don't adopt another agent's worktree — the surviving one held a sibling's
  untracked files (`git status` before touching anything).
- `EnterWorktree` can't create from a pinned-cwd subagent, and can't `path`-switch
  from the repo root either. Manual fallback works fine:
  `git worktree add .claude/worktrees/<name> -b worktree-<name> main`, then
  operate by absolute paths / `cd <worktree> && mix ...` per command.
- Re-run `mix deps.get` in the new worktree; re-verify exemplar files there
  rather than trusting reads from the reaped tree (main had advanced a commit).
- Scratchpad is shared across concurrent agents — name temp files uniquely
  (a sibling's `dogfood_credo.exs` was already there).

## Smaller notes

- Bracket access is `{{:., _, [Access, :get]}, _, [subject, key]}` — bare `Access`
  atom module slot, exactly as the writing skill warns; one clause covers it.
- Subject identity: strip ALL meta then `===` —
  `Macro.prewalk(ast, &Macro.update_meta(&1, fn _ -> [] end))`. Handles dotted
  subjects (`socket.assigns[...]`) where line/column/`no_parens` noise differs.
- Key literals fall out of AST typing for free: literal atoms are atoms, literal
  strings are binaries, variables/interpolations are 3-tuples → guard clauses on
  `is_atom`/`is_binary` need no extra "is this a literal" machinery.
- `Map` is single-segment → `AstHelpers.resolve_aliases(source_file, [Map])`
  gives both halves (add `as:` renames, drop `alias MyApp.Map` shadowing) with
  no new code; tested both directions.
