### `DataloaderRequiresQueryFunction`

`Dataloader.Ecto.new/1,2` must set `query:` — without it, association loads
fall back to `Dataloader.Ecto`'s own default query function, which discards
every GraphQL filter, order, and paginate argument the caller passes.

```elixir
# BAD — no query function, so filter args on association loads are dropped
Dataloader.Ecto.new(MyApp.Repo)

# GOOD — filter args flow through EctoShorts.CommonFilters
Dataloader.Ecto.new(MyApp.Repo, query: &EctoShorts.CommonFilters.convert_params_to_filter/2)
```

A piped construction (`MyApp.Repo |> Dataloader.Ecto.new(query: ...)`) is
handled the same way: the pipe's right-hand call carries one fewer argument
than the call actually has (the repo is the pipe's left-hand side, not a call
argument), so the true arity is re-derived as `1 + length(args)` and the opts
— when present — are inspected exactly like the non-piped form. A piped call
with `query:` set stays silent; one missing it is flagged the same as its
non-piped equivalent, at its own true arity.

Only a literal opts keyword list is inspected — opts held in a variable or
built by a helper function is invisible to a static check and left alone
rather than guessed at (an accepted false negative), whether the call is
piped or not. `Dataloader.KV.new/1,2` is a different source type with no
query-function contract and is never matched. Alias-aware on
`Dataloader.Ecto`: an `alias`, an `as:` rename, and the fully qualified
`Elixir.Dataloader.Ecto` spelling are all resolved.

**Limitations:** opts held in a variable or module attribute
(`Dataloader.Ecto.new(MyApp.Repo, @opts)`) is invisible and silently
skipped — the same is true under a pipe
(`MyApp.Repo |> Dataloader.Ecto.new(opts)`).

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
