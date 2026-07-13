# Learnings — NoCastAllKeys build (wave 2, 2026-07-12)

## Pipe-node head-rewrite: consume the piped call, keep its args traversable

A prewalk that handles `{:|>, _, [lhs, cast_call]}` at the pipe node will visit the same
`cast_call` node again standalone one level down — and in the standalone position the
"permitted arg" index is wrong (a piped `cast/4`'s opts sit where a standalone call's
permitted list sits). Pruning the whole pipe with `{nil, acc}` is worse: it kills descent
into `lhs`, silently dropping violations in chained pipes.

Fix: after examining the piped call, return the pipe with the call's **head rewritten to a
block** — `{{:|>, meta, [lhs, {:__block__, [], args}]}, acc}`. The args stay traversable
(nested violations still found), `lhs` still descends, and the standalone clause can never
re-match the consumed call. Three lines, removes the whole re-examination class.

## Positional-arg checks need an explicit piped/standalone rule

For `cast/3,4` the permitted list is **arg 3 standalone, arg 2 piped** (node arity 3–4 vs
2–3). Don't scan "last or 3rd" heuristically — encode the two positions as two
`permitted_arg(args, :standalone | :piped)` heads with arity guards, and state the rule in
the moduledoc. Any check that keys on an argument position has this same fork.

## `--checks` vacuous green: it filters `.credo.exs`, it doesn't enable

`mix credo --checks "MikaCredoRules.NoCastAllKeys"` on a check **not registered in
`.credo.exs`** prints `found no issues` after `running 0 checks`. A fifth false-green for
the verifying-skill catalogue: the flag selects from configured checks, it never adds one.
Always read `running N checks` — N=0 means the dogfood didn't happen. Workaround when the
config is off-limits: scratchpad config file (map form, name `"default"`) via
`--config-file`, plus a planted positive-control file (`mix credo <file> --config-file …`
accepted an absolute path) to prove the run can go red.

## Main-checkout builds coexisting with a sibling lane

The assigned worktree had been reaped; path-mapped writes landed in the **main checkout**,
shared live with the sibling lane building NoIdentityRewrap. Tells and coping:

- Credo's file count drifted 38 → 39 between runs — the sibling's new file. Diagnose count
  drift before trusting any sweep (diff `mix credo info --verbose` listings); don't assume
  your runs are the only writer.
- `mix compile --warnings-as-errors` compiles the sibling's in-progress files too; a
  foreign compile error can redden your gate. Scope `mix test` to your own test file, and
  attribute failures before reacting.
- Mutate-restore cycles are safe if strictly scoped to your own file and verified with
  `grep` for mutant residue + `git status --short` (expect only your and the sibling's
  untracked files).
