# mika_credo_rules — package scaffold + `NoApplicationEnvOutsideConfig`

Date: 2026-07-10
Status: approved

## Goal

Stand up `mika_credo_rules` as a publishable Credo check package (modeled on
`blitz_credo_checks`) and ship its first rule: application environment may only be
read or written from a config module.

## Motivation

Scattered `Application.get_env/2,3` calls make configuration unauditable and
untestable. Centralizing every env read and write in a single `MyApp.Config` module
per umbrella app gives one place to see what the app is configured by, one place to
stub in tests, and one place to catch a missing key at boot instead of at 3am.

## Package structure

```
lib/mika_credo_rules.ex                                    # @moduledoc false namespace
lib/mika_credo_rules/no_application_env_outside_config.ex  # rule #1
test/mika_credo_rules/no_application_env_outside_config_test.exs
.credo.exs                                                 # self-lint
.formatter.exs
CHANGELOG.md
README.md
mix.exs
```

`mix.exs` carries hex `package/0` + `docs/0` metadata. Deps:

| dep | scope | why |
|---|---|---|
| `credo ~> 1.7` | `runtime: false` | the check behaviour + `Credo.Test.Case` |
| `ex_doc` | `:dev, :test`, `runtime: false` | hexdocs |
| `dialyxir` | `:test`, `runtime: false` | type checking |
| `excoveralls` | `:test`, `runtime: false` | coverage |

`doctor` and `ex_check` from blitz are dropped — not earning their keep.

## Rule: `MikaCredoRules.NoApplicationEnvOutsideConfig`

`base_priority: :high`, `category: :design`.

### Behavior

Flags every call to a configured `Application` env function, unless the source file
is a config module.

**Config module detection is by filename.** A file is a config module when its path
ends with any suffix in `config_files`. Default `["config.ex"]`, so:

```
apps/my_app/lib/my_app/config.ex   → exempt
lib/my_app/config.ex               → exempt
apps/my_app/lib/my_app/worker.ex   → checked
```

Filename beats module-name detection here because it is one string comparison, works
identically in umbrella and single apps, and does not require the walker to track the
enclosing `defmodule` scope.

### Params

| param | default | meaning |
|---|---|---|
| `config_files` | `["config.ex"]` | path suffixes treated as config modules |
| `functions` | see below | `Application` functions that count as env access |
| `files.excluded` | `[]` | standard Credo escape hatch |

`functions` default — the complete env surface, reads and writes:

```elixir
[
  :get_env, :fetch_env, :fetch_env!, :get_all_env,
  :compile_env, :compile_env!,
  :put_env, :put_all_env,
  :delete_env
]
```

`Application.get_application/1`, `app_dir/1,2`, `spec/1,2` are untouched — they are
not env access.

### Exemptions

None beyond config modules. Test files, `application.ex`, and `mix.exs` are all
checked. `Application.put_env/3` in a test is precisely the anti-pattern the
workspace conventions already forbid — the rule should catch it. Anyone who wants an
exemption adds one via `config_files` or the standard `files.excluded`.

### Algorithm

1. If `source_file.filename` ends with any `config_files` suffix, return `[]` —
   short-circuit, no walk.
2. Otherwise `Credo.Code.prewalk/2` over the AST, collecting AST nodes shaped
   `{{:., _, [{:__aliases__, _, [:Application]}, fun}]}, meta, args}` where
   `fun in functions`.
3. Emit one issue per call site, with line number and arity from `length(args)`.

**Message:**

```
Application.put_env/3 found — application env must only be read or written from a config module (e.g. MyApp.Config)
```

### Known limitation

Aliased calls (`alias Application, as: App` then `App.get_env/2`) are not detected.
Resolving aliases requires scope tracking the walker does not do. Documented in the
README; not worth the complexity for a pattern nobody writes.

## Testing

`Credo.Test.Case` — `run_check/2`, `assert_issue/1`, `assert_issues/1`,
`refute_issues/1`. TDD: every case red before green.

| case | expectation |
|---|---|
| `get_env` in `lib/my_app/worker.ex` | 1 issue |
| `compile_env` in a worker | 1 issue |
| `put_env` in a worker | 1 issue |
| every default function, one file | 9 issues |
| `get_env` + `compile_env` in `lib/my_app/config.ex` | no issues |
| `Application.app_dir/1` in a worker | no issues |
| `Application.get_application/1` in a worker | no issues |
| `config_files: ["settings.ex"]` | `settings.ex` clean, `config.ex` flagged |
| `functions: [:get_env]` | `put_env` clean, `get_env` flagged |
| `get_env` in `test/my_app/worker_test.exs` | 1 issue (strict, no test exemption) |
| three calls in one file | 3 issues, correct line numbers |

## Verification

```bash
cd /Users/mika/GitHub/mika_credo_rules
mix test
mix format --check-formatted
mix credo --strict
mix dialyzer
```

## Out of scope

- Additional rules — this package ships one and grows later.
- Publishing to hex — scaffold the metadata, do not `mix hex.publish`.
- Alias resolution (see Known limitation).
