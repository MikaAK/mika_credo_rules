# Learnings — logger-inspect lane, mika_credo_rules build (2026-07-12)

Role: worker lane #3 — `MikaCredoRules.LoggerModulePrefixAndInspect`.
Commits: `c12111c` on main (merged); built as `51dea91` → amended `f74bb95` after one NEEDS_REFINEMENT round.

---

## 1. Interpolation AST shape — one seam, match it in one place

`"a #{expr} b"` parses to a `:<<>>` node whose parts are plain binaries interleaved
with `::` segments:

```elixir
{:<<>>, meta, [
  "a ",
  {:"::", _, [
    {{:., _, [Kernel, :to_string]}, [from_interpolation: true, ...], [expr]},
    {:binary, _, nil}
  ]},
  " b"
]}
```

Gotchas inside that shape:

- Dot target is the **literal atom `Kernel`**, not `{:__aliases__, _, [:Kernel]}`.
  Pattern-match `[Kernel, :to_string]` directly.
- `from_interpolation: true` exists in meta but pattern-matching the structural
  `Kernel.to_string` wrapper is enough — no need to read meta.
- Plain literal `Logger.info("x")` is a **bare binary arg**, not `:<<>>`. Separate
  clause needed (`when is_binary(message)`).
- Segments carry own line meta; call-site meta line is what you want for issues.

Rule applied: `interpolation?/1` + `interpolated_expression/1` are the ONLY two
functions that know this shape. Elixir-upgrade AST drift touches one place.

Verify empirically before coding: `elixir -e 'Code.string_to_quoted(...) |> IO.inspect'`
took 30 seconds and killed all guessing.

## 2. Qualified-call resolution in allowed_expression? (refinement finding #1)

First cut: `allowed_expression?({name, _, _}) when is_atom(name)` — covers variables,
`__MODULE__`, and local calls in one head. Elegant, wrong. `Kernel.inspect(value)`
has a **tuple** head (`{:., ...}`) → fell to catch-all → false positive.

Fix: resolve the function name out of qualified calls before the membership test:

```elixir
defp allowed_expression?({{:., _, [_module, function]}, _, _args}, allowed)
     when is_atom(function),
  do: function in allowed
```

Bonus properties for free: works for erlang-style `:mod.fn(x)`, and for any
user-supplied `allowed_interpolations` entry spelled qualified
(`MyApp.Format.format_value(x)` with `:format_value` allowed). Anonymous-call
`fun.()` has a 1-element dot list → doesn't match 2-element pattern → correctly
falls through.

Anti-pattern named: "atom-head pattern covers everything" — it covers everything
*local*. Every allow-list on AST expressions needs an explicit qualified-call clause.

## 3. Lazy fn form — normalize the message, then share every downstream check

`Logger.debug(fn -> "..." end)` AST: `{:fn, _, [{:->, _, [[], body]}]}`. One
normalizer before analysis:

```elixir
defp message_body({:fn, _, [{:->, _, [[], body]}]}), do: body
defp message_body(message), do: message
```

Everything downstream (`check_message` binary / `:<<>>` / unverifiable dispatch)
then works identically for both forms — zero duplicated logic. Non-literal fn body
(`fn -> build_message() end`) falls into the unverifiable clause and is skipped,
same as variable/attr/call messages. Skip-what-you-can't-verify beats guessing.

## 4. Prefix index-0 tightening (refinement finding #2)

Contract wording said "first **interpolated** segment must be `__MODULE__`" — I
implemented exactly that (`Enum.find(segments, &interpolation?/1)`). Reviewer ruled
the house convention is a **prefix**: `"processing #{__MODULE__} ..."` and
`"[worker] #{__MODULE__}: ..."` must flag. Fix is stricter AND simpler:

```elixir
defp module_prefix?([first_segment | _rest]), do: module_interpolation?(first_segment)
defp module_prefix?(_segments), do: false
```

Lesson: when contract wording and the convention it encodes diverge, the literal
reading is usually the looser one. Implement literal, flag divergence early, expect
the ruling to go strict. Also: state the strict rule explicitly in the moduledoc —
"must literally start with the interpolation, literal before it is flagged" —
so nobody re-litigates from the doc.

## 5. Mutation probes — and the no-op mutant trap

Two probes on the shipped check, both killed:

- inverted allow-logic (`not allowed_expression?` → `allowed_expression?`) → 13 failures
- inverted prefix condition (`not module_prefix?` → `module_prefix?`) → 13 failures

Trap hit on the way: first mutation attempt via two sed expressions moved `not` from
line N+1 to end of line N — **semantically identical code, 25/25 green**. Looked like
a survived mutant; was a no-op mutant. Rule: after mutating, read the mutated lines
and confirm the semantics actually changed before interpreting a green run. Backup
via `cp` to scratchpad beats `git checkout` for untracked files.

Refinement round got revert-proofing free: the 4 new RED tests ran against the old
implementation — the old code IS the mutant, RED output is the kill evidence.

## 6. Operational gotchas

- **`Credo.SourceFile.parse/2` outside test needs Credo services.** Standalone smoke
  script dies with `GenServer.call(Credo.Service.SourceFileAST, ...)` no-process.
  Fix: `Application.ensure_all_started(:credo)` first line. Cheap way to run one
  check over the repo's own files without touching `.credo.exs`.
- **Shared scratchpad collides across parallel lanes.** My `smoke.exs` got
  overwritten by another lane's script mid-run (their check name in my stack trace
  was the tell). Prefix scratch files with the lane name (`smoke_logger_inspect.exs`).
- **Test snippets containing `#{}` need `~S"""`.** Plain heredocs interpolate inside
  the TEST file. Same for moduledoc BAD/GOOD examples: escape as `\#{` or the doc
  itself interpolates at compile time.
- **`mix format --check-formatted <file> <file>`** scopes formatting to just the
  lane's files — satisfies the "no repo-wide format" rule while catching the one
  98-col line the formatter wanted split.
- **RED for a not-yet-existing check** is `UndefinedFunctionError ... run_on_all_source_files/3`
  from `Credo.Test.Case.run_check/3` — expected shape, don't mistake it for a
  test-harness problem.

## 7. What the canonical-check template bought

Mirroring `NoApplicationEnvOutsideConfig` structurally (use-block → moduledoc →
`run/2` → prewalk traverse → violation maps → `issue_for`/`format_issue`) meant the
reviewer only had to review the *rule logic*, not the scaffolding. Deliberate
non-reuse: its alias-resolution machinery is private and cross-file edits were
forbidden — `alias Logger, as: Log` documented as a limitation instead of half-copied.
If a shared `AstHelpers`/alias-resolver extraction lands (see architect-abstractions
learnings §2), this check is a ready consumer.
