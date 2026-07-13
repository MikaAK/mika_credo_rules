# Wave 2 build: SingleModulePerFile — learnings

## Single-mechanism scoping: one `excluded_paths` param covers fragments AND suffixes

The spec offered two params (`excluded_paths` + `test_files`) or a fold. Folded: one
`excluded_paths` param, default `["test/", "test/support/", "_test.exs"]`, checked once in
`run/2` via `SourceFilter.matches_fragment?/2`. This works because `fragment_matches?/2`
already includes an `ends_with?` half — a suffix entry like `_test.exs` matches through it,
boundary-safe by construction. One param, one guard, one SourceFilter call; nothing for the
two mechanisms to disagree about. Document the dual role in the param explanation so a
consumer overriding it knows suffixes belong in the same list.

## Prune `quote` subtrees — a quoted `defmodule` is not a module in this file

`quote do defmodule ... end` defines the module at the macro's *call site*, not in the file
being analyzed. Without `{nil, acc}` pruning on `{:quote, _, args} when is_list(args)`, every
module-generating macro FPs. The `is_list(args)` guard matters: `{:quote, _, nil}` is a
variable named `quote`, not the special form.

## Counting "after the first" survives nesting for free

Prewalk is pre-order depth-first, so the first-visited `defmodule` is the outermost/first in
file order for both sibling and nested layouts. Collect all, `Enum.reverse() |> Enum.drop(1)`
— no nesting-depth bookkeeping needed. Mutation check (drop the `drop(1)`) failed 9/12 tests,
so the suite pins the counting, not just coexists with it.

## Dogfood trap: `--checks` silently matches nothing for an unregistered check

`.credo.exs` here uses list-form `checks:` enumerating all checks. A brand-new check not yet
registered → `mix credo --checks "MikaCredoRules.SingleModulePerFile"` prints
`running 0 checks on 37 files ... found no issues` — a false green. When the config is
untouchable (build isolation), dogfood via a scratchpad config instead:

```bash
mix credo --config-file /path/to/scratch_credo.exs   # name MUST be "default"; map-form checks
```

Then verify the output says `running 1 check`, and prove the green can go red with a live
probe: plant a temporary two-module file under `lib/`, confirm the issue fires at the second
module's line, delete the probe. Without the probe, "found no issues" is indistinguishable
from "check never ran".

## Shared scratchpads are shared

A sibling lane repurposed the scratchpad dogfood config mid-session. Name scratch files
per-check (`dogfood_<check>.exs`) instead of generically when lanes run in parallel.
