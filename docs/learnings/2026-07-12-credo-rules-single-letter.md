# Learnings — NoSingleLetterVariables (lane #9, worker single-letter)

Commits: ea9b67a (feat) → 2cde19b (typespec + cond) → 703c6c9 (receive-after), merged to main.

## Root cause pattern: the overloaded arrow

One `{:->, _, [lhs, _body]}` traverse clause served five constructs with three different
binding semantics:

- `case`/`fn`/`receive`-do/`rescue` heads — PATTERNS, bind. Collect.
- `cond` heads and `receive`-`after` heads — EXPRESSIONS, use. Collecting them re-flags
  already-bound vars (`x = f(); cond do x > 10 ->` → two issues for one binding).
- typespec arrows `(a -> b)` in `@spec`/`@type`/`@callback` — TYPE VARIABLES, neither.
  Worst class: false positive on idiomatic code.

Lesson: when a check keys on an AST operator, enumerate every construct that produces
that operator BEFORE writing the traverse. `->` is the worst offender; `::` is second
(binary segment vs typespec). Grep `elixir syntax reference` mentally: same token,
different semantics per parent node.

## Fix shapes, ranked by how much subtree survives

- **Type-carrying attributes: prune whole subtree.** `{:@, _, [{attr, _, _}]}` when attr
  in `[:spec, :type, :typep, :opaque, :callback, :macrocallback]` → return `{nil, acc}`
  from prewalk. Nothing inside a typespec is ever a variable; descent has zero value.
- **Expression heads: neutralize the arrow, keep the descent.** Rewrite
  `{:->, meta, clause}` → `{:expression_clause, meta, clause}` in the RETURNED ast for
  clauses under the relevant key. The `:->` clause stops firing; Macro.prewalk still
  walks the renamed node's children, so a genuine binding inside a head
  (`(result = f()) > 1 -> result`) is still caught by the `:=` clause. Do NOT discard
  the head subtree — that trades FP for FN.
- Generalized helper: `neutralize_arrows_under(sections, key)` — cond passes `:do`,
  receive passes `:after`. Receive do-heads stay untouched (patterns). One helper, two
  call sites, semantics chosen by keyword key.

Key insight enabling the neutralize trick: Credo prewalk discards the rewritten AST and
keeps only the accumulator — mutating the tree mid-walk is free steering, not corruption.

## Flag out-of-scope defects, don't fix silently

Spotted the receive-after FP while fixing cond (same defect class). Did NOT fix it in
that commit — reported it to the architects with the exact mirror-fix shape and asked
for a ruling. Ruling came back "it's real, fix it"; the fix landed in its own commit
with its own red test. Right call for two reasons: reviewers diff against contracts, and
unrequested scope makes clean-pass verdicts ambiguous; and if the hunch had been wrong
(e.g. after-heads deliberately in scope), silent fixing would have been a regression.
Cost of asking: one message. Cost of guessing wrong: a review round.

## Binding-site vs usage discipline

The check's whole value hangs on flagging DECLARATIONS, not uses. Walk only binding
sites: `=` lhs, `<-` lhs, pattern-position `->` lhs, def-family heads
(def/defp/defmacro/defmacrop/defguard/defguardp — extract params through the `:when`
wrapper). Within a pattern, controlled recursion with explicit stop clauses:

- `^pin` → stop (usage of existing binding; flagged where bound)
- `when` → drop last arg (guard is usage territory), collect the rest
- `::` → left side only (binary size specs use existing vars)

Do NOT copy Credo's own `Readability.VariableNames` recursion: its generic
`Tuple.to_list` descent flags guard usages, and its def clause only matches 2-arity
heads (1-arity params silently unchecked). Reference implementations show the approach,
not the correctness bar.

Dedupe by `{name, line}` via `Enum.uniq/1` on plain maps — prewalk revisits nested `=`
alias patterns (`def foo(%{a: x} = params)`) and would double-report without it. Watch
for dedupe MASKING bugs: the "binding inside cond head" test passed pre-fix only because
dedupe collapsed the double-collect; keep such tests as pinning guards and say so in the
report rather than counting them as TDD evidence.

## Misc

- `binding` is a Kernel macro — can't name a helper `binding/2`. Used `bound_variable`.
- Mutation proof beats coverage: flipped `String.length(...) === 1` → `=== 2`, 16/19
  tests failed with specific mismatches. Restore via Edit, not `git checkout` — a
  never-committed file has no checkout target.
- Shared scratchpad is shared: sibling worker clobbered my `smoke.exs`. Namespace
  scratch files per lane (`smoke_single_letter.exs`).
- Smoke corpus caveat (echoing lane #4): this repo's lib/ is single-letter-free, so
  "0 FPs" was weak evidence alone; the regression tests carrying reviewer-supplied
  repro snippets were the real FP proof.
