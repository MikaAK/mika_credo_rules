### `VerifiedRoutesRequired`

A navigation call's `to:` option must be a `~p` verified-route sigil, never
a plain string. A hand-typed path string is only checked when the browser
hits it — a typo in a route segment or a renamed live route surfaces as a
404 in production. `~p"/courses/#{id}"` is checked by the router at compile
time instead: a path that does not match any route is a compiler warning at
build time (an error under `--warnings-as-errors`).

```elixir
# BAD — a typo here is a runtime 404, not a build-time warning
{:noreply, push_navigate(socket, to: "/courses/#{id}")}

# GOOD — the router checks this route exists at compile time
{:noreply, push_navigate(socket, to: ~p"/courses/#{id}")}
```

The same applies to a plain literal, not only an interpolated one —
`redirect(conn, to: "/login")` is flagged the same as an interpolated path.
Bare (`push_navigate(socket, to: "/x")`), piped
(`socket |> push_navigate(to: "/x")`), and qualified
(`Phoenix.LiveView.push_navigate(socket, to: "/x")`) forms are all matched,
and only the `to:` option is checked — `external:` takes a full URL, which
`~p` cannot express, so a plain string there is left alone. A variable or
module attribute under `to:` is left alone too, since it cannot be
statically proven to be an unchecked literal. A `~s` or `~S` sigil under
`to:` is treated the same as a plain string.

**Limitations:** matching is by function name alone, regardless of which
module a qualified call names — a same-named function defined on an
unrelated module is flagged the same as `Phoenix.Controller.redirect/2`,
whether called bare or qualified. Narrow `:functions` if that bites. A route
string built by a helper (`to: build_path(id)`) is invisible to this check
— only what is statically a binary, an interpolated `<<>>` node, a
`~s`/`~S` sigil, or a `<>` concatenation anchored on a binary literal
(`to: "/courses/" <> id`) is caught.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:push_navigate, :push_patch, :redirect, :live_redirect]` | Navigation functions whose `to:` option is checked. |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
