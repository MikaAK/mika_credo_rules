# Wave 2 build learnings — NoIdentityRewrap (2026-07-12)

- **Guard `Enum.all?` against empty clause lists.** `Enum.all?([], &identity_clause?/1)` is
  vacuously true, so a degenerate `case` with no clauses would flag. The traverse guard
  requires `is_list(clauses) and clauses !== []` before the identity sweep. (`case x do end`
  parses its do-block as `{:__block__, [], []}`, not a list, so the shape match alone catches
  most of it — the guard makes it explicit.)
- **Identity = structural equality after recursive meta-strip.** `Macro.prewalk` blanking
  `meta` on every `{form, meta, args}` node (guarded by `is_list(meta)`) makes a pattern and
  body on different lines compare `===` equal. Nested nodes (struct/map patterns spanning
  lines) come free — no per-shape handling needed.
- **Encode spec exemptions as explicit non-identity clauses, even when structurally
  automatic.** A `{:when, _, _}` head and a `{:__block__, _, _}` body would never equal their
  counterparts anyway, but dedicated `identity_clause?/1` clauses returning `false` document
  the intent (guard = deliberate filter; block = does work) and survive refactors that might
  weaken the structural argument.
- **Pins need no special case.** `^x -> x` differs structurally (`{:^, _, [x]}` vs `x`), and a
  pin in a *body* isn't compilable code — the structural comparison covers the spec's pin
  exemption for free.
- **Mutation `Enum.all?` → `Enum.any?` failed exactly the 5 negatives that pin the
  all-clauses semantics** (transforming clause, guard, multi-expression body, re-tag
  fallback, pinned pattern) and nothing else — the suite pins the bug rather than coexisting
  with the fix. The "renamed body vars" negative survives the mutant (no clause is identity),
  so it pins a different axis.
- **Dogfood vacuous-green reconfirmed:** `mix credo --checks "NewCheck"` on an unregistered
  check prints `running 0 checks` and passes green. Dogfood new checks via
  `--config-file` with a `name: "default"` config listing the check (map/`enabled` form →
  `running 1 check`), plus a planted positive-control probe.
