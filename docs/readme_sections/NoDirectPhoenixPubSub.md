### `NoDirectPhoenixPubSub`

`Phoenix.PubSub` must be called through the app's own topic/wrapper module,
never directly from application code. A wrapper module centralizes topic
naming and payload shape, so every subscriber can rely on a consistent
message format instead of each call site inventing its own topic string.

```elixir
# BAD — calls Phoenix.PubSub directly from a LiveView
Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:#{course_id}")

# GOOD — routed through the app's own topic/wrapper module
MyApp.PubSub.Courses.subscribe_course(course_id)
```

An aliased call resolves the same way — `alias Phoenix.PubSub` then a bare
`PubSub.broadcast(...)` still fires, since the alias makes the bare name mean
`Phoenix.PubSub` for the rest of the file. A project alias that shadows the
bare name wins instead: once `alias MyApp.PubSub` is in force, the
same-looking `PubSub.broadcast(...)` calls the app's own module, not
Phoenix's, and stays silent. Files under `:allowed_paths` (default
`["pubsub", "pub_sub", "topics"]`) are exempt — that is where the wrapper
module itself is expected to live, e.g. `lib/my_app/pubsub/courses.ex`,
`lib/my_app_pub_sub/courses.ex`, or `lib/my_app_web/topics/subscription_events.ex`.
Each entry is trimmed of any leading or trailing `/` before matching, so
`"pubsub"`, `"pubsub/"`, `"/pubsub"`, and `"/pubsub/"` all behave identically.
An entry with no remaining internal `/` matches both a whole path segment
named that AND a segment merely ending in it (`"pubsub"` also matches
`legacy_pubsub/`); an entry with an internal `/` matches only as a literal,
consecutive run of whole segments. Matching is against directory segments
only — a single-file wrapper (`lib/my_app/pub_sub.ex`) must be listed in
`:excluded_paths` instead. Test files (`:excluded_paths`, default
`["_test.exs", "test/"]`) are exempt too.

**Limitations:** only a literal `Phoenix.PubSub.function(...)` call,
alias-aware, is recognised. A `Phoenix.PubSub` value held in a variable or
module attribute (`pubsub = Phoenix.PubSub; pubsub.broadcast(...)`),
`apply(Phoenix.PubSub, :broadcast, [...])`, and a bare call reached via
`import Phoenix.PubSub` are all undetected. A project module is exempted
purely by module identity, never by name resemblance —
`MyApp.PubSub.Courses.subscribe_course(id)` stays silent because its module
segments are not `Phoenix.PubSub`, regardless of what its own name contains.
The default `:functions` list does not include `direct_broadcast/5`,
`direct_broadcast!/5`, or `local_broadcast_from/5` — add them if your app
uses them. A nested `defmodule PubSub do ... end` is not treated as a
shadowing source the way a file-level `alias` is, so a call resolved through
an earlier `alias Phoenix.PubSub` still fires even inside a file that later
defines its own nested `PubSub` module.

| Param | Default | Meaning |
|---|---|---|
| `functions` | `[:subscribe, :unsubscribe, :broadcast, :broadcast!, :local_broadcast, :broadcast_from, :broadcast_from!]` | `Phoenix.PubSub` functions to flag. |
| `allowed_paths` | `["pubsub", "pub_sub", "topics"]` | Paths where the app's own PubSub wrapper module may call `Phoenix.PubSub` directly. |
| `excluded_paths` | `["_test.exs", "test/"]` | Path fragments naming files this check skips. |
