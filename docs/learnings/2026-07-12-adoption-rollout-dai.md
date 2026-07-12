# Learnings — adoption rollout into developer_ai (un_dev), 2026-07-12

Worker: dai-credo. Lane: integrate `mika_credo_rules` into the `developer_ai` umbrella (remote `MikaAK/un_dev`) and land a green PR.

**PR:** https://github.com/MikaAK/un_dev/pull/49 — branch `add-mika-credo-rules`, base `main` @ `829dc9bc11a99043546dae28de82fa17bd43ed2f`.
**Worktree:** `/Users/mika/GitHub/dai-credo-wt` (left in place).

Commits (linear, no merges, no footers):

| SHA | Subject | What it holds |
|-----|---------|---------------|
| `36a4826feaf83810e25bcf7e68a0201304000915` | `chore: add mika_credo_rules credo checks` | 10× `apps/*/mix.exs`, `mix.lock`, `.credo.exs` |
| `098fd3f63270d25c5220e25a1c5c3613de87a545` | `fix: use is_nil over nil equality in tests` | 27 NoNilComparison fixes, 17 test files |
| `3ce682aabeab5b45e28a9ebf2d4ca53efb617581` | `fix: strict equality in sidebar active_link` | 1 StrictEquality fix |
| `e0dd7b6d54e4bcbe6aa168f7a110042ade41023a` | `style: wrap long lines in e2e test setup` | 8 pre-existing MaxLineLength |

Outcome: 233 issues found. 6 of 14 checks adopted, 8 omitted. Credo gate green; the one red CI job was pre-existing.

---

## 1. The big one: the repo's Credo was scanning ZERO files

`.credo.exs` at the umbrella root had:

```elixir
files: %{included: ["lib/", "test/"], excluded: [~r"/_build/", ~r"/deps/"]}
```

An umbrella root has **no `lib/` and no `test/`** — they live in `apps/*/`. So `mix credo` from the root printed `No files found!` and exited 0. CI's `credo.yml` runs exactly that from the root. **The Credo job had been passing vacuously for the life of the repo.**

This is the single most important thing to check first in any adopter. If you skip it, you "adopt" 14 checks that never execute, CI stays green, and everyone believes the rules are enforced.

Fix — make the glob work from BOTH the root and an app dir:

```elixir
included: ["lib/", "test/", "apps/*/lib/", "apps/*/test/"],
```

Credo resolves `included` relative to CWD, not to the config file. From the root, `apps/*/lib/` matches; from `cd apps/foo`, `lib/` matches and `apps/*/lib/` matches nothing. Keeping all four entries makes the same config correct for the root CI job AND the per-app gate the repo's CLAUDE.md documents (`cd apps/<app> && mix credo --strict`).

**Pre-flight for the next adopter:** run `mix credo --strict` at the root and *read the file count*. `running N checks on 0 files` means stop and fix `included` before anything else.

Side effect to expect: widening `included` surfaces **pre-existing violations of the repo's own stock checks**. Here it exposed 8 `Credo.Check.Readability.MaxLineLength` hits that had never been enforced at the root. Those are yours to fix now — the PR can't be green otherwise. Budget for it; it's not scope creep, it's the cost of turning the gate on.

## 2. Credo's map `enabled:` form runs ONLY the listed checks

The brief warned that stock defaults might also run and that `Credo.Check.Design.TagTODO` would double-report against `TodosNeedTickets`. It didn't happen. With

```elixir
checks: %{enabled: [ ...13 entries... ]}
```

the run reported `running 16 checks` = 3 stock (explicitly listed) + 13 MikaCredoRules. No stock defaults were auto-included, so **no TagTODO, no double-reporting, no `disabled:` block needed**.

Don't assume; just count. The `running N checks on M files` line in Credo's summary is the ground truth for both this and §1. If N is bigger than what you enabled, defaults are merging in and you need `disabled:`.

## 3. Per-app deps in an umbrella — mirror wherever `:credo` already lives

`:credo` was NOT in the root `mix.exs` (root deps were just `{:elixir_skills, "~> 0.1"}`); it was in each of the 10 `apps/*/mix.exs`. Adding `mika_credo_rules` only at the root would leave the per-app gate unable to resolve the checks.

Rule: **put `mika_credo_rules` exactly where `:credo` already is.** A one-line perl insert anchored on the credo line does all 10 at once and preserves each file's dep-block style:

```bash
perl -pi -e 's|^(\s*)\{:credo, "~> 1\.7", only: \[:dev, :test\], runtime: false\},$|$&\n$1\{:mika_credo_rules, github: "MikaAK/mika_credo_rules", only: [:dev, :test], runtime: false\},|' apps/*/mix.exs
```

`runtime: false` + `only: [:dev, :test]` means this dep **cannot** affect the app's supervision tree or runtime behaviour. Remember that — it's the argument that exonerates you when an unrelated CI test starts failing (see §7).

## 4. Triage by *files touched*, not issue count

The useful denominator for "is this check adoptable today" is **how many files it forces you to edit**, not how many issues it raises. Dump Credo JSON once and group both ways:

```bash
mix credo --strict --format=json > issues.json
# then: Counter(check) and defaultdict(set) of check -> filenames
```

Result for this repo (233 issues):

| Check | Issues | Files | Verdict |
|---|---|---|---|
| LoggerModulePrefixAndInspect | 62 | 32 | omit — mechanical but too much churn |
| NoSingleLetterVariables | 48 | 24 | omit — renames must chase every usage in scope |
| NoProcessSleepInTests | 43 | 7 | omit — each is a real `Process.monitor`/`assert_receive` refactor |
| NoApplicationEnvOutsideConfig | 31 | 16 | omit — architectural |
| NoNilComparison | 27 | 17 | **FIX** — purely mechanical |
| NoBlanketRescue | 6 | 4 | omit — intentional catch-alls |
| ErrorMessageRequired | 5 | 3 | omit — see §5 |
| NoMixEnvAtRuntime | 2 | 2 | omit — see §6 |
| StrictEquality | 1 | 1 | **FIX** |
| (stock) MaxLineLength | 8 | 6 | **FIX** — pre-existing, see §1 |

Note how badly issue-count and file-count disagree: `NoProcessSleepInTests` (43 issues) is only 7 files but is *harder* than `NoNilComparison` (27 issues, 17 files), because sleeps need per-test synchronization redesign while nil-compares are a regex. **Low file count does not mean easy.** Judge by the nature of the fix.

Zero-hit checks are free adoption — take them: `GenServerRequiresHandleContinue`, `NoMockingLibraries`, `RefuteOverAssertNot`, `TodosNeedTickets` all landed at 0 issues. That's 4 of the 6 adopted checks. **An adoption PR's value is partly in the checks that cost nothing but lock in existing good behaviour.**

Omitted checks were left in `.credo.exs` commented with a `# not yet adopted:` line *plus the reason*, not deleted. That keeps the backlog visible at the exact point someone would go to enable them.

## 5. ErrorMessageRequired is not mechanical when `error` is a free-form string field

This was the subtlest call. The 5 hits are pipeline nodes returning `{:error, "some literal"}`, which flow into `%{state | error: reason}`.

Two things make wrapping in `%ErrorMessage{}` a trap:

1. **The check only catches literal-binary tuples.** `{:error, "git add failed: #{output}"}` is a `{:<<>>, ...}` interpolation AST, not a bare binary, so it is NOT flagged. The same module therefore has flagged and unflagged raw-string errors side by side. Converting only the flagged ones makes `state.error` **type-inconsistent** — an `ErrorMessage` struct on some paths, a `String` on others.
2. **Tests string-match the field.** `parse_sprint_contracts_test.exs:87` does `assert result.error =~ "## Sprint:"`. `=~` on a struct raises. Wrapping that path breaks the test.

So the honest fix is to migrate *every* error path in those nodes (plus their tests) to `ErrorMessage` — architectural, well out of scope for an adoption PR. Omitted.

**Transferable rule:** before enabling `ErrorMessageRequired`, grep the consumer for `\.error =~`, `<> state.error`, or anything treating the error as a string. If the error value is a free-form string field rather than a return contract, the check needs a dedicated migration, not an adoption PR. Its natural home is code that returns `{:ok, _} | {:error, _}` from context functions — not a graph node's `state.error` slot.

## 6. NoMixEnvAtRuntime fires on compile-time-only `Mix.env()` — by design, but it reads as a false positive

Both hits are module-body branches evaluated once at compile time, when Mix *is* available:

- `apps/developer_ai_web/lib/developer_ai_web/endpoint.ex:16` — `if Mix.env() === :dev do plug Tidewave end`
- `apps/developer_ai_icons/lib/developer_ai_icons.ex:19` — `if Mix.env() === :prod do` toggling compile-time SVG inlining vs runtime disk reads

Neither leaves a `Mix.env()` call in the compiled beam, so neither is the release-time `UndefinedFunctionError` the check is named for. The check's moduledoc says it flags these intentionally (ban Mix in lib entirely, for auditability) — that's a defensible stance, but adopters will read it as a false positive, and the "fix" is not mechanical: it needs a per-env config entry and, for the icons case, changes dev/prod behaviour semantics. Only 2 hits and I still omitted it, because a behaviour-changing edit is worse than an un-adopted check.

**For the package:** consider a param like `allow_module_body: true`, or at minimum lead the check's docs with "this flags compile-time module-body usage too, on purpose". Every adopter will hit this and think the check is broken.

## 7. Distinguishing "I broke CI" from "CI was already broken"

`Test & Coverage` failed on the PR: 6 failures, all `LocalTicketing.WatcherTest` — `unknown registry: LocalTicketing.Watcher.Registry` and a `handle_continue/2` shutdown at `watcher.ex:57`.

The exoneration chain, in order of strength:

1. **Diff argument.** `git diff origin/main -- apps/local_ticketing/` = one `runtime: false, only: [:dev, :test]` dep line. Such a dep cannot alter a supervision tree.
2. **Local run.** The same test file passes locally (3 tests, 0 failures) — so it's environmental (Linux inotify / FileSystem backend / registry start race), not logical.
3. **Base-commit proof — the decisive one.** `gh run list --branch main --workflow test.yml` showed `failure` for the last 5 runs, *including headSha `829dc9bc`, the exact commit my branch forks from*. Pulling that run's log showed the identical `LocalTicketing.Watcher.Registry` terminating at the identical `watcher.ex:57`.

Failure counts differed (2 on main, 6 on mine) — that's flakiness in the same broken test, not a new bug. **Don't let a differing failure count talk you out of a pre-existing diagnosis; match on the crash site, not the tally.**

Do this check *before* touching anything. Reflexively "fixing" a red job you didn't cause is the anti-pattern here — it balloons the diff and buries the real signal.

Useful: `gh run view <id> --log-failed` truncates oddly for some jobs; `gh api repos/<owner>/<repo>/actions/jobs/<job_id>/logs` returns the raw log and greps reliably (use `grep -a`, it's binary-ish).

## 8. Repo CI gates can contradict your instructions — CI wins, then tell the lead

The brief said: PR body must be *very light*, **no headings**. The repo has `.github/workflows/scope-gate.yml` → `.github/scripts/scope_gate.sh`, which **fails the PR unless the body contains a `## Declared Scope` section** listing globs that match every changed file.

Direct conflict. Resolution: the hard CI gate wins (the PR must end green), keep everything *else* light, and surface the deviation in the report. Don't silently drop either constraint.

`Scope: open` disables the gate entirely — I didn't use it. Declaring real globs respects the gate's intent and costs 5 lines:

```markdown
## Declared Scope
- `.credo.exs`
- `mix.lock`
- `apps/*/mix.exs`
- `apps/*/test/**`
- `apps/developer_ai_web/lib/developer_ai_web/components/sidebar.ex`
```

**Validate the globs locally before pushing** by running the repo's own gate script against your diff — don't burn a CI cycle guessing:

```bash
PR_BODY_FILE=/tmp/pr_body.md BASE_REF=origin/main bash .github/scripts/scope_gate.sh
# → "scope-gate: clean"
```

(It prints `shopt: globstar: invalid shell option` on macOS bash 3.2. Harmless — inside `[[ x == pat ]]`, `*` already spans `/`, so matching is correct anyway, and CI's bash 5 has globstar.)

## 9. `gh pr edit --body-file` silently fails on this repo — use the REST API

`gh pr edit 49 --body-file X` printed only a Projects-classic GraphQL deprecation warning, exited 0-ish, and **did not change the body**. Verified twice via `gh pr view 49 --json body`. The GraphQL mutation path touches `repository.pullRequest.projectCards`, which is deprecated and errors out.

Workaround — REST PATCH, which also correctly fires the `edited` event that re-triggers the scope-gate workflow:

```bash
gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -F body=@/path/to/body.md --jq '.body'
```

`-F key=@file` reads file contents as the value. **Always read the body back after setting it** — a silent no-op here costs a full CI round-trip to notice.

## 10. Mechanical fixes: script them, but transform per-flagged-line

For the 27 `NoNilComparison` hits I drove the edits straight off `issues.json` (file + line_no), applying a regex to *only those lines* rather than a blind repo-wide `sed`:

```python
m = re.match(r'^(\s*)assert (.+?) === nil\s*$', line)  # → assert is_nil(\2)
m = re.match(r'^(\s*)assert (.+?) !== nil\s*$', line)  # → refute is_nil(\2)
```

Two details worth carrying forward:

- **`!== nil` becomes `refute is_nil(x)`, not `assert not is_nil(x)`** — the latter immediately trips `RefuteOverAssertNot`. The checks interact; fixing one naively creates a hit in another. Fix toward the idiom both checks want.
- Print any line that fails to match instead of skipping silently. All 27 matched; a silent skip would have been an invisible false-green.

Same approach for the 8 MaxLineLength hits (all the identical `|> Workspace.changeset(%{...})` one-liner): parse the map out of the flagged line, re-emit it multi-line. Process line numbers **descending** when an edit changes a file's line count, so earlier targets stay valid.

Verification: ran every modified non-e2e test file (linear_api 9, developer_ai 82, developer_ai_pg 21, developer_ai_service 21, plus pipeline node tests 17) — all green — then `mix credo --strict` (0 issues, 484 files) and `mix compile --warnings-as-errors` (clean). The e2e Wallaby files were map-wrapping only and were left to CI.

## 11. Checklist for the next adopter repo

1. `mix credo --strict` at the root → **read the file count**. 0 files means `included` is broken (§1). Fix before adopting anything.
2. Find where `:credo` lives (root vs per-app) and mirror `mika_credo_rules` there (§3).
3. Pre-flight the check list against deps: no `:error_message` → drop `ErrorMessageRequired`; a mocking lib in use → drop `NoMockingLibraries`; no SharedUtils → drop `NoReimplementedHelper` (its pointers reference it). Here: SharedUtils absent → `NoReimplementedHelper` omitted outright.
4. Enable everything else, dump `--format=json`, group by check **and by file count** (§4).
5. Fix the mechanical checks; omit the architectural ones with a `# not yet adopted:` + reason, in place in `.credo.exs`.
6. Expect to inherit pre-existing stock-check violations the moment the glob is fixed (§1). Fix them; they're the entry fee.
7. Before "fixing" any red CI job, prove whether it's red on your base commit (§7).
8. Read the repo's own CI gates (`.github/workflows/`) before writing the PR body (§8).
