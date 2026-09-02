### `NoSharedUtilsHTTPOutsideApiApps`

`SharedUtils.HTTP` is the shared HTTP transport — domain code must call its
app's dedicated `*_api` wrapper module instead of reaching for the transport
directly. Calling the transport from ordinary domain code bypasses whatever
auth headers, base URL, and error mapping the wrapper app centralizes, and
couples every caller to the transport's raw request/response shape instead
of a stable per-service contract.

```elixir
# BAD — domain code calls the transport directly
defmodule MyApp.Courses do
  def fetch(id) do
    SharedUtils.HTTP.get("https://example.com/courses/#{id}", [])
  end
end

# GOOD — domain code calls its app's dedicated wrapper
defmodule MyApp.Courses do
  def fetch(id) do
    MyApp.CoursesApi.fetch(id)
  end
end
```

Aliasing the transport doesn't help — the alias is resolved back to the
banned module before matching, the same as a fully qualified call. Only
files under one of `:allowed_paths` are exempt: a dedicated `*_api` wrapper
app (`git_hub_api/`, matched by directory-name suffix, not only a directory
literally named `_api`), `shared_utils` itself, and tests.

Only the functions that actually make a request are banned (see `:functions`
for the default list). A bare reference to the module elsewhere — a
supervision child spec, the Tesla-client-builder call the wrapper itself is
built from — is left alone, because it either has no wrapper equivalent or
the wrapper must reach it to exist. `@spec`/`@type`/`@typep`/`@opaque`/
`@callback`/`@macrocallback` bodies are pruned entirely and never inspected,
so a typespec referencing the transport module is never flagged either.

A defmodule whose own body declares `@behaviour SharedUtils.HTTP` — the
sanctioned shape for building a wrapper, documented in `SharedUtils.HTTP`'s
own moduledoc — IS the wrapper, so its own request-verb calls are exempt
entirely, even outside an `*_api` path:

```elixir
# not flagged — this module is the wrapper being built
defmodule MyApp.VendorClient do
  @behaviour SharedUtils.HTTP

  @impl SharedUtils.HTTP
  def new(opts), do: SharedUtils.HTTP.client([], nil, opts)

  def fetch(url), do: SharedUtils.HTTP.get(new(), url, [])
end
```

**Limitations:** only the `__aliases__` call shape is matched — the
Elixir-prefixed atom spelling (`:"Elixir.SharedUtils.HTTP".get(url)`) and
`apply/3` dynamic dispatch are both invisible. A transport reference injected
as a dependency (`@http.get(url)`, or a variable holding the module) carries
no module segments to resolve and is invisible too — only a literal alias or
fully qualified call is matched. The `@behaviour` wrapper exemption is a
literal-attribute match: a module with the same shape but no `@behaviour
<one of :modules>` declaration is still flagged. Only calls inside a
`defmodule` body are collected — a call at the top level of a `.exs` script,
or inside a `defimpl` block, is invisible.

| Param | Default | Meaning |
|---|---|---|
| `modules` | `[SharedUtils.HTTP]` | Modules banned as the shared HTTP transport, alias-aware. Only a call whose function name is also in `:functions` is flagged. A defmodule declaring `@behaviour` naming one of these modules is exempt entirely. A non-Elixir-module entry (a string, or an erlang-style atom) is silently ignored rather than raising. |
| `functions` | `[:get, :post, :patch, :delete, :request]` | Function names that count as making a request — the request verbs `SharedUtils.HTTP` actually delegates to Tesla. A bare reference to the module elsewhere (child spec, client builder, typespec) is left alone. |
| `allowed_paths` | `["_api/", "shared_utils/", "_test.exs", "test/"]` | Path fragments naming files this check skips. An entry starting with `_` also matches as an app-directory-name suffix, not only a literal fragment. |
