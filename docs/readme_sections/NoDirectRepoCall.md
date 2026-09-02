### `NoDirectRepoCall`

Contexts must call `EctoShorts.Actions`, never `Repo` directly — the house rule
with the longest incident history. A raw `Repo.insert/1` scattered across
contexts duplicates the changeset pipeline, error mapping, and filtering that
`EctoShorts.Actions` already centralizes.

```elixir
# BAD — context calls Repo directly
%User{} |> User.changeset(attrs) |> MyApp.Repo.insert()

# GOOD — context calls EctoShorts.Actions
EctoShorts.Actions.create(User, attrs)
```

A repo module is identified by its last alias segment *as written at the call
site* — `MyApp.Repo.insert(changeset)` and, under `alias MyApp.Repo`,
`Repo.insert(changeset)` are both caught, piped or not, as is a
differently-named repo such as `Schemas.JobsRepo.delete_all(query)`.
`Repo.transaction/1` and `Repo.transact/2` are exempt by default (see
`:allowed_functions`), as are `Repo.query/2`, `Repo.query!/2`,
`Repo.checkout/2`, `Repo.disconnect_all/2`, `Repo.config/0`,
`Repo.start_link/1`, `Repo.stop/1`, and `Repo.load/2` — raw SQL and pool
management with no `EctoShorts.Actions` call to redirect to. This is a fixed
allowlist of those specific functions, not a rule that exempts every
function with no Actions equivalent (see Limitations). A module that itself
defines a repo (`use Ecto.Repo`) is exempt entirely, including every call
inside it. Tests, seeds, and migrations are out of scope by default (see
`:excluded_paths`).

| Param | Default | Meaning |
|---|---|---|
| `repo_suffixes` | `["Repo"]` | Suffixes identifying a repo module by its last alias segment |
| `allowed_functions` | `[:transaction, :transact, :query, :query!, :checkout, :disconnect_all, :config, :start_link, :stop, :load]` | Repo functions that may be called directly |
| `excluded_paths` | `["_test.exs", "test/", "priv/repo/", "migrations/"]` | Path fragments exempt from the check (segment-boundary matched) |

**Limitations:** module identity is a naming heuristic, not alias resolution,
the same as `NoBangMailerDeliver` — `alias MyApp.Reporting, as: Repo` would
flag an unrelated module's calls, and renaming a real repo alias away from the
`Repo` suffix (`alias MyApp.Repo, as: DB`) makes it invisible. The heuristic
runs in both directions on the suffix itself: any module merely ending in
`Repo` is caught, Ecto or not (`GitHub.Repo.fetch(name)`), while a repo built
on a house wrapper instead of a literal `use Ecto.Repo` (`use MyApp.RepoBase,
...`) is not recognised as a repo-defining module and stays in scope. Only a
literal `Module.function(...)` call at the call site is recognised — no
import-based `Repo` idiom exists in this house style, so an unqualified call
is never flagged; an injected repo (`@repo.insert!()`, `repo().insert()`) or
`apply(Repo, :insert, [x])` is also undetected, as is
`defdelegate insert(cs), to: MyApp.Repo` and a call through a non-literal
alias segment (`__MODULE__.Repo.insert(...)`,
`unquote(schema).Repo.insert(...)` inside a macro). `:allowed_functions`
deliberately omits `Repo.aggregate/3` — it sits closer to the CRUD surface
`EctoShorts.Actions` covers, so it still fires with the Actions message by
default. `:allowed_functions` is a fixed list, not "every function with no
Actions equivalent" — bulk DML (`Repo.insert_all/3`, `Repo.update_all/2`,
`Repo.delete_all/2`), `Repo.preload/2`, `Repo.exists?/2`, and a house repo
wrapper function such as `Repo.insert_or_upsert_many/3` also have none, yet
still fire by default; add whichever ones a given context has no better
option for.
