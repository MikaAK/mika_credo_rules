### `NoDataMigrationInSchemaMigration`

A migration must not mix DDL with data DML in the same `change`/`up` body. A migration
that both alters the schema and rewrites data holds the DDL's lock across the data
rewrite — every row the `UPDATE`/`INSERT`/`DELETE`/`MERGE` touches sits behind the same
transaction as the `create`/`alter`/`drop` — and it can't be safely retried, since
re-running a partially-applied migration re-runs the DDL too. Split the data step into
its own migration, an Oban job, or a `mix run` task.

```elixir
# BAD — the UPDATE shares a transaction with the alter's lock
def change do
  alter table(:users) do
    add :status, :string
  end

  execute "UPDATE users SET status = 'active' WHERE status IS NULL"
end

# GOOD — the data rewrite moves to its own migration
def change do
  alter table(:users) do
    add :status, :string
  end
end

# BAD — repo().update_all is the same shape as an execute() UPDATE
def up do
  create index(:users, [:status])
  repo().update_all(MyApp.User, set: [status: "active"])
end

# GOOD — a pure data migration, on its own, is legitimate
def change do
  execute "UPDATE users SET status = 'active' WHERE status IS NULL"
end
```

Both `execute/1,2` string literals (matched case-insensitively against
`UPDATE`/`INSERT`/`DELETE`/`MERGE` at the start of the SQL, including the leading literal
segment of a heredoc that goes on to interpolate) and
`repo().update_all/insert_all/delete_all` count as the data-DML half. For the `repo()`
spellings, piped into (`from(...) |> repo().update_all(...)`) or called directly makes no
difference; `execute/1,2` is only recognised called directly (see Limitations). The DDL
half is `create`, `create_if_not_exists`, `alter`, `drop`, `drop_if_exists`, or `rename`
on a `table(...)`/`index(...)`/`unique_index(...)` target. Only `def change` and `def up`
are scanned — `def down` is exempt, since it only ever reverses what `up` already
committed. A `rescue`/`after`/`else`/`catch` clause on `def change`/`def up` does not
shrink what's scanned — the `do` body is still scanned the same as without one.

**Limitations:** `execute/1,2`'s SQL must be a plain double-quoted string, a heredoc, or
a heredoc/string whose leading literal segment (before its first `#{...}`) contains the
DML keyword; a sigil literal (`~s(...)`), a variable, or a DML keyword that only appears
inside or after an interpolation is invisible to this check. `execute/1,2` piped into
(`sql |> execute()`) is invisible to this check — unlike the `repo()` spellings, only the
directly-called form is recognised. Only the bare, unqualified `execute(...)` and
`repo().update_all/insert_all/delete_all` spellings are recognised — a qualified
`Ecto.Migration.execute(...)` call is not. The DDL half only recognises a
`table(...)`/`index(...)`/`unique_index(...)` target — `create constraint(...)` does not
count as DDL for this check. Both halves must live directly in the scanned `change`/`up`
body — moving the DML into a helper `defp` called from `change`/`up` (an ordinary
refactor) hides it from this check. The DDL half must be a
`table(...)`/`index(...)`/`unique_index(...)` call target — a DDL statement written as
raw SQL (`execute "CREATE TABLE ..."`) is not recognised as the DDL half. The DML regex
anchors at the very start of the SQL string with no multiline flag — a leading SQL
comment line (e.g. in a heredoc) before the `UPDATE`/`INSERT`/`DELETE`/`MERGE` keyword
hides the match.

| Param | Default | Meaning |
|---|---|---|
| `included_paths` | `["migrations/"]` | Path fragments (segment-boundary match) treated as migration directories |
