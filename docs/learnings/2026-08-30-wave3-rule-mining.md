# Learnings — wave-3 rule mining (process + skills → checks)

Four parallel miners read the `/harness` process corpus (command, 18 reference files,
13 agent definitions, test-harness + evaluator + team-template skills) and every
`elixir-*` skill, and proposed ~120 candidate checks. 53 were selected and built.

## Process docs yield fewer checks than they look like they will

The harness corpus is ~120k characters and almost none of it is lintable — it is about
orchestration, evidence, and gates, not code shape. The lintable residue was small and
specific: template primitives, `FactoryEx` over `Repo` writes in tests, bare
`{:ok, _} = call()`, monolithic HEEx components, and the `.credo.exs` config-name trap.
The single most valuable line in the whole corpus was the one that nominated itself:
cross-role-disciplines names a pre-push grep gate for `<button`/`style=`/hex colors and
calls it "a Credo-check candidate". **Mine the material for places where it asks for a
check, not for places where it states a rule.**

## Skills are the opposite: dense, and mostly already covered

Roughly half of every skill's rules were already enforced — by shipped MikaCredoRules
checks, by stock Credo (often a check that is OFF by default), or by the compiler under
`--warnings-as-errors`. Three verdict classes, not one:

- **covered-and-on** → drop silently.
- **covered-but-off** → the deliverable is a config line, not a check. Eleven house
  conventions resolved this way (`AliasAs`, `BlockPipe`, `PipeChainStart`, `SinglePipe`,
  `OneArityFunctionInPipe`, `StrictModuleLayout`, `UnsafeToAtom`, `NegatedIsNil`,
  `PassAsyncInTestCases`, `SkipTestWithoutComment`, `Specs`).
- **compiler-covered** → two rules ("bind the result of an `if` block", "`@doc` on a
  `defp`") produce warnings today; a check would be pure duplication.

A proposal list that skips this pass produces duplicate checks. Keep the drop list in the
report so the lead can verify the dedup rather than trust it.

## Measure the AST before promising a check

Every miner was told to verify rather than reason, and each returned a fact that changed
a decision:

- `%{:a => 1}` and `%{a: 1}` parse to **identical** AST — the "shorthand atom keys" rule
  is token-level only, not AST. Same for `[{:a, 1}]` vs `[a: 1]`.
- `~w(a b)a` **is** a clean AST node (`:sigil_w`), so that rule is trivially checkable —
  and `mix format` leaves all three of those forms alone, so the formatter is not already
  handling them.
- `for x <- xs, do: side_effect()` in statement position produces **no** compiler warning,
  so the discarded-comprehension rule is not covered by warnings-as-errors.
- `~H` bodies survive into the AST as plain binaries, so HEEx-content checks are ordinary
  AST checks — but Credo's source glob is `**/*.{ex,exs}`, so standalone `.html.heex`
  files are unreachable no matter what the check does.

## Rank by mechanics, never by how important the rule sounds

The ordering axis that produced a buildable list was (mechanical detectability, low FP
risk, likelihood of landing at 0 on a mature repo). Ranking by importance would have put
"single point of truth for a resource" and "tests are behavioural first" at the top —
both unlintable — and buried `PhxValueNoDashes`, a one-regex check for a real shipped
`FunctionClauseError` class.

## Honest negatives are deliverables

Several conventions were reported as **not lintable** with the reason attached, and that
was worth more than a weak check: "single point of truth" has no syntactic signature
(only its cache and HTTP slices are tractable, and those became two checks); "behavioural
first, unit second" is invisible at the assert node; `assert {:ok, _}` is AST-identical
to the correct idiom that follows it with value assertions. One proposed check —
"every lib module has a sibling test file" — was rejected on measurement: 54% of one
repo's modules would fire, and the rule contradicts the harness's own behavioural-first
test guidance, which prefers tests named after the public context.

## Doc-conflict discovery is a mining side effect worth capturing

Two skills disagreed with each other, and both disagreements were load-bearing for a
proposed check:

- `elixir-genserver-init` says subscribe in `init/1` ("messages published in the window
  are lost forever"); `elixir-distributed` says subscribe in `handle_continue` and its own
  FeedServer reference does exactly that. A `NoDeferredRegistration` check would flag the
  reference implementation of a sibling skill. **Not built.**
- `elixir-cache` says "never raw `:ets`, tests included"; `elixir-distributed` builds its
  whole feed design on `:ets.new/insert/lookup` and tells you to *improve* those calls.
  `NoRawEts` shipped as explicitly opt-in/architectural with that conflict documented in
  its own moduledoc rather than silently picking a side.

A third conflict was a plain factual error, found by ground-truthing a fix pointer:
`elixir-genserver-init` recommended `Task.async_nolink/1`, which **does not exist** —
only `Task.Supervisor.async_nolink/2,3,4,5` does. The skill was corrected. Any check whose
message names a function must resolve that function against real source; the check that
found this was about to emit the same nonexistent name.
