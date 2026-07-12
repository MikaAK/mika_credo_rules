# Learnings — NoProcessSleepInTests (lane #5, worker: sleep-tests)

Sprint: 2026-07-12 credo-rules build. Check: `MikaCredoRules.NoProcessSleepInTests`
(`lib/mika_credo_rules/no_process_sleep_in_tests.ex` + test). Merged to main.

## 1. `files:` param is INERT under `Credo.Test.Case`

Credo's per-check `files: %{included:, excluded:}` param only filters in the CLI
pipeline, never in the test harness:

- Filter applied: `deps/credo/lib/credo/check/runner.ex:42-64` —
  `Params.files_included/3` + `Credo.Sources.filename_matches?/2`, prunes source
  files BEFORE `run_on_source_file/3`.
- Test harness: `deps/credo/lib/credo/test/check_runner.ex` —
  `run_check/3` calls `check.run_on_all_source_files(exec, source_files, params)`
  directly. No files filtering anywhere on that path.
- Generated `run_on_all_source_files` (`deps/credo/lib/credo/check.ex:398-421`)
  just Task.async_streams `run_on_source_file` over everything it is given.

Consequence: a check scoped ONLY by `files:` cannot be negative-tested with
`run_check/2` — "does not flag lib files" tests pass vacuously against the wrong
mechanism or fail outright. Scope gate must live inside `run/2` (canonical
`NoApplicationEnvOutsideConfig` does this with `config_files`; SetLogLevel in blitz
does it with `String.ends_with?(filename, "/endpoint.ex")` — its `files:` default
is belt only, run/2 is suspenders).

## 2. Why `files:` got dropped from param_defaults (one scoping mechanism)

Contract initially allowed keeping `files:` as "production pruning" next to the
`test_files` run/2 guard. Dropped it. Reason: two scoping mechanisms that must
agree = silent-failure footgun. Scenario:

1. User overrides `test_files: ["_spec.exs"]` in .credo.exs.
2. Default `files: %{included: ["**/*_test.exs", ...]}` still active — user has no
   reason to know it exists.
3. Pipeline (runner.ex:42) prunes spec files before run/2 ever sees them.
4. Check silently never fires in production. All the check's own tests still green
   (harness ignores `files:`). Zero signal.

How I knew, method not luck: did NOT trust the param name or the SetLogLevel
precedent. Greped deps/credo for where `files_included` is actually consumed,
traced both call paths (CLI runner vs Test.CheckRunner), confirmed asymmetry with
file:line evidence BEFORE writing the check. Rule: for any framework knob a check
depends on, read the consumer of the knob in deps source, both in production and
test paths. Param names describe intent, not mechanism.

Outcome: deviation flagged in report with reasoning; reviewer endorsed; lane #10
kept its `files:` copy and it turned out a production dead-param. Reasoning from
deps source beat both architects' initial allowance.

## 3. Mutation-proving the filename guard (revert-proof, executed on merged main)

Green tests alone don't prove the negative tests are load-bearing. Cycle run
post-merge on main:

1. Baseline: `mix test` → 0 failures (full suite green).
2. Mutate: `test_file?/2` body → `true` (guard neutralized — the realistic
   regression: someone breaks/removes scoping).
3. `mix test test/mika_credo_rules/no_process_sleep_in_tests_test.exs` →
   `15 tests, 4 failures`, exactly the 4 guard-dependent tests, no others:
   - does not report Process.sleep in a lib file
   - does not report :timer.sleep in a lib file
   - does not report a test support file that is not a test module
   - no longer flags _test.exs files once :test_files is overridden
4. Restore: `git checkout -- lib/...`, `git status` clean, `mix test` →
   `265 tests, 0 failures`.

Mutant killed by specific expected tests = negative coverage proven real, not
theater. Positive tests unaffected by the mutation, as predicted — they don't
depend on the guard, only on traversal. Cost: ~1 minute. Do this for every check
whose value is "does NOT fire on X".

## Smaller notes

- Heredoc test fixtures containing `Process.sleep(...)` are string literals in the
  host file's AST — prewalk sees binaries, not call nodes. Self-lint of this repo
  produces zero false positives without any special-casing. Verified empirically
  (`Credo.SourceFile.parse` + `run/2` on the repo's own files), not just reasoned.
- `{module, function}` tuple param covers Elixir + erlang spellings in one list;
  expand Elixir modules to both `[:Process]` and `[Elixir, :Process]` AST part
  lists at run start. Canonical check needed two params only because erlang's env
  function NAMES differ — don't copy a two-param surface when names coincide.
- `String.to_atom/1` on `Module.split` parts is fine when input is a check param
  (bounded, developer-authored .credo.exs); `String.to_existing_atom/1` is the
  WRONG fix there — name-part atoms of a legitimately configured module may never
  have been interned, and the check would crash mid-lint.
