### `FormlessPhxChange`

A `phx-change` binding on a bare `<input>`/`<select>`/`<textarea>` reaches LiveView's JS
fine — `phx-change` is read straight off the input (`input.getAttribute(phxChange)` in
`live_socket.js`), independent of form membership — but two hops later `View.pushInput/6`
throws `"form events require the input to be inside a form"` (`view.js`) because
`inputEl.form` is `null` for an element that is not form-associated. In a real browser this
surfaces as an uncaught JS `Error` in the console, not a silently swallowed event. To be
form-associated, the element must either be a DOM descendant of a
`<form>`/`<.form>`/`<.simple_form>`, or carry an HTML `form="<id>"` attribute referencing one
elsewhere in the document (which this check also treats as exempt).

```elixir
# BAD
~H"""
<input type="text" phx-change="update_q" />
"""

# GOOD
~H"""
<.form for={@form} phx-change="update_q">
  <input type="text" name="q" />
</.form>
"""
```

Wrap the element in `<.form>` (or `<form>`/`<.simple_form>`), moving `phx-change` onto the
form itself if it is not there already.

**Limitations:** Credo only lints `.ex`/`.exs` files — a `.html.heex` template file is
never read by Credo (`Credo.Sources.@default_sources_glob` is `~w(** *.{ex,exs})`), so
this check is **blind to every `.html.heex` file**. Only `~H`/`~F` sigils colocated inside
a `.ex`/`.exs` module are covered.

This is a raw-text scan of the whole sigil body, not an HTML parser with offset tracking,
so it cannot tell which elements a `<.form>` actually wraps. The moment ANY `:form_markers`
substring appears anywhere in the sigil, the ENTIRE sigil is exempted — including a second,
genuinely formless input elsewhere in the same body that the form does not wrap. Precisely
locating what a `<.form>` wraps needs a real HTML parser tracking open/close tags and their
offsets, which this check does not have.

Measured false positive: a field-group function component whose own `~H` body has no form
marker still fires even when every caller wraps it in `<.form>` — idiomatic Phoenix
slot/component decomposition, e.g. a sibling `address_fields/1` rendered from `render/1`'s
`<.form>`. The form-marker exemption is scanned per sigil, never across the sigils of the
functions that compose it.

Measured false positive: Surface's `<Form>` component (`:sigil_F`) is not in the default
`:form_markers` list — its raw input children fire by default, because Surface capitalizes
the tag and the defaults only cover HEEx's `<.form`/`<form`/`<.simple_form` spellings. A
Surface repo must add `"<Form"` to `:form_markers`.

Measured false positive: a module-qualified (remote) form function component, e.g.
`<Phoenix.Component.form for={@form}>` or `<MyAppWeb.CoreComponents.form for={@form}>`,
matches no default `:form_markers` entry either — every default marker anchors `<`
immediately before the tag word, so a fully-qualified module path between `<` and `.form`
never matches, and a raw input inside one fires. Add `".form"` (and `".simple_form"` if
used remotely) to `:form_markers` — the marker is matched anywhere in the sigil body, so
the bare suffix also matches the qualified call.

Measured false positive: `<%!-- <input phx-change="..." /> --%>` (a HEEx comment) and
`<!-- <input phx-change="..." /> -->` (an HTML comment) both still fire — same class of gap
as `NoRawMarkupInTemplates`'s `<svg` inside an HTML comment.

The mirror gap also exists: a `:form_markers` substring left inside a commented-out
`<.form>` (HEEx or HTML comment) still exempts the whole sigil, silencing a genuinely
formless input elsewhere in the same body.

An opening tag is bounded by `[^>]*` up to the next `>`, so a `>` character inside a quoted
or interpolated attribute value (e.g. `value={if @count > 1, do: "many"}`) would incorrectly
end the tag scan early, silencing any `phx-change` that follows on the same tag — accepted as
a rare edge case, same as `NoClickHandlerOnNonInteractiveElement`.

The `phx-change` attribute regex is matched against the whole opening-tag text, not
attribute-aware, so `phx-change` appearing inside a different attribute's quoted value (e.g.
`placeholder=" phx-change='x'"`) also fires — same class of gap as
`NoRawMarkupInTemplates`'s `style="..."` prose false positive.

Measured false negative: the mirror image of the gap above also exists on the `form=`
attribute regex. It too is matched against the whole opening-tag text, not attribute-aware,
so a `form=` substring appearing inside a different attribute's quoted value (e.g.
`placeholder="pick a form='x' value"` or `title="a form='b'"`) is read as a genuine
form-association and silences a control that is not actually form-associated in the DOM —
it still throws in a real browser. The same raw-text match also treats an empty `form=""`
(naming no form owner at all) as form-associated, for the same reason.

Suppressing an issue reported inside a sigil body works the same way as every other sigil
check in this package — see `NoRawMarkupInTemplates`'s Limitations section for the two
escapes that actually work (a HEEx-comment-wrapped pragma inside the sigil does not).

| Param | Default | Meaning |
|---|---|---|
| `sigils` | `[:sigil_H, :sigil_F]` | Which sigil names count as template bodies. |
| `form_markers` | `["<.form", "<form", "<.simple_form"]` | Substrings whose presence anywhere in the sigil exempts the whole sigil, matched at a text boundary (so `<.form_group>` does not match `<.form`). A Surface repo scanning `~F` must add `"<Form"` — matching is case-sensitive. A module-qualified form component like `<Phoenix.Component.form>` needs a bare `".form"` entry. |
| `excluded_paths` | `[]` | Path fragments naming files this check skips. |
