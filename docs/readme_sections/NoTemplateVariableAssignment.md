### `NoTemplateVariableAssignment`

A `<% var = ... %>` EEx assignment tag inside a `~H`/`~F` template body disables HEEx
change tracking for every dynamic part that reads the variable, so those parts are
recomputed and re-sent on every diff instead of being skipped when nothing changed.

```elixir
# BAD
~H"""
<% user = @current_user %>
<p>{user.name}</p>
"""

# GOOD
~H"""
<p>{@current_user.name}</p>
"""
```

Compute the value where it belongs instead: `assign/3` in `mount/3` or `handle_event/3`,
or a function component, so it participates in change tracking the same as every other
assign. A discard assignment (`<% _ = something %>`) still fires — the shape on the page
is identical to a real assignment, and singling out `_` for a pass would need a second
regex for a case rare enough not to earn one.

**Limitations:** Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
never read by Credo (`Credo.Sources.@default_sources_glob` is `~w(** *.{ex,exs})`), so
this check is **blind to every `.html.heex` file**. Only `~H`/`~F` sigils colocated
inside a `.ex`/`.exs` module are covered.

This is also a raw-text regex scan of the sigil body, not an EEx parser, so it only
recognizes a bare-identifier left-hand side. A destructuring assignment
(`<% {first, second} = compute_pair() %>`) is a measured false negative, and so is a
second assignment sharing a tag with the first (`<% a = 1; b = 2 %>` only reports
`a =`) — the regex requires `<%` to be followed directly by a single identifier, not
a pattern, and scans each `<%` opener once. An output tag (`<%= user = @current_user
%>`) is deliberately silent by design, not a gap: the regex only matches a plain `<%`
opener, never `<%=`.

Measured false positive: a `<%!-- ... --%>` HEEx comment still fires when its text
happens to contain `<% var = ... %>` — this is a raw-text scan of the sigil body, not
an EEx parser, so it has no notion that `<%!-- --%>` wraps its contents as a comment
never evaluated at runtime (same class of gap as `NoRawMarkupInTemplates`'s `<svg`
inside an HTML comment).

A `#` inside a `~H`/`~F` heredoc is template string content, not a comment token, so
`# credo:disable-for-next-line` placed directly above the `~H"""` line never
suppresses an issue reported from inside the body — the issue's line is inside the
template, past that anchor. Suppress with `# credo:disable-for-lines:N` or
`# credo:disable-for-this-file` placed above the enclosing `def` instead (see
`NoRawMarkupInTemplates`'s Limitations section for the full explanation of why).

| Param | Default | Meaning |
|---|---|---|
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies. |
| `excluded_paths` | `[]` | Path fragments naming files this check skips. |
