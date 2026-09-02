defmodule MikaCredoRules.NoDirectPhoenixPubSub do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: [
        :subscribe,
        :unsubscribe,
        :broadcast,
        :broadcast!,
        :local_broadcast,
        :broadcast_from,
        :broadcast_from!
      ],
      allowed_paths: ["pubsub", "pub_sub", "topics"],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming `Phoenix.PubSub` functions to ban. Defaults to
        `[:subscribe, :unsubscribe, :broadcast, :broadcast!, :local_broadcast,
        :broadcast_from, :broadcast_from!]`.
        """,
        allowed_paths: """
        A list of path fragments naming where the app's own PubSub wrapper
        module is expected to live. Each entry is trimmed of any leading or
        trailing `/` before matching, so `"pubsub"`, `"pubsub/"`,
        `"/pubsub"`, and `"/pubsub/"` all behave identically. An entry with
        no remaining internal `/` (e.g. `"pubsub"`) matches at a whole
        path-segment boundary (`lib/my_app/pubsub/courses.ex`) OR as a
        directory-name suffix (`lib/my_app/legacy_pubsub/courses.ex`,
        `lib/my_app_pub_sub/courses.ex`) — both forms apply to every such
        entry. An entry with an internal `/` (e.g. `"my_app/notifications"`)
        matches only as a literal, consecutive run of whole path segments —
        `"my_app/notifications"` matches `lib/my_app/notifications/courses.ex`
        but not `lib/my_app/my_app_notifications/x.ex`. Matching is against
        directory segments only — a single-file wrapper (`lib/my_app/pub_sub.ex`)
        is not matched by its basename and must be listed in `:excluded_paths`
        instead if it needs to call `Phoenix.PubSub` directly. A file matching
        any entry is exempt. Defaults to `["pubsub", "pub_sub", "topics"]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `["_test.exs", "test/"]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `Phoenix.PubSub` must be called through the app's own topic/wrapper module,
  never directly from application code. A wrapper module centralizes topic
  naming and payload shape, so every subscriber can rely on a consistent
  message format instead of each call site inventing its own topic string.

      # BAD — calls Phoenix.PubSub directly from a LiveView
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          Phoenix.PubSub.subscribe(MyApp.PubSub, "courses:\#{course_id}")
          {:ok, socket}
        end
      end

      # GOOD — routed through the app's own topic/wrapper module
      defmodule MyAppWeb.DashboardLive do
        def mount(_params, _session, socket) do
          MyApp.PubSub.Courses.subscribe_course(course_id)
          {:ok, socket}
        end
      end

  An aliased call resolves the same way — `alias Phoenix.PubSub` then a bare
  `PubSub.broadcast(...)` still fires, since the alias makes the bare name
  mean `Phoenix.PubSub` for the rest of the file. A project alias that
  shadows the bare name wins instead: once `alias MyApp.PubSub` is in force,
  the same-looking `PubSub.broadcast(...)` calls the app's own module, not
  Phoenix's, and stays silent.

      # BAD — aliased Phoenix.PubSub still resolves to the banned module
      defmodule MyAppWeb.DashboardLive do
        alias Phoenix.PubSub

        def refresh(id) do
          PubSub.broadcast(MyApp.PubSub, "dashboard:\#{id}", :refresh)
        end
      end

      # GOOD — a project alias to the app's own wrapper shadows the bare name
      defmodule MyAppWeb.DashboardLive do
        alias MyApp.PubSub

        def refresh(id) do
          PubSub.broadcast(id, :refresh)
        end
      end

  Files under `:allowed_paths` (default `["pubsub", "pub_sub", "topics"]`)
  are exempt — that is where the wrapper module itself is expected to live,
  e.g. `lib/my_app/pubsub/courses.ex`, `lib/my_app_pub_sub/courses.ex`, or
  `lib/my_app_web/topics/subscription_events.ex`. Test files
  (`:excluded_paths`, default `["_test.exs", "test/"]`) are exempt too.

  ## Limitations

  Only a literal `Phoenix.PubSub.function(...)` call, alias-aware, is
  recognised. A `Phoenix.PubSub` value held in a variable or module attribute
  (`pubsub = Phoenix.PubSub; pubsub.broadcast(...)`),
  `apply(Phoenix.PubSub, :broadcast, [...])`, and a bare call reached via
  `import Phoenix.PubSub` are all undetected.

  A project module is exempted purely by module identity, never by name
  resemblance — `MyApp.PubSub.Courses.subscribe_course(id)` stays silent
  because its module segments are not `Phoenix.PubSub`, regardless of what
  its own name contains.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack, and an alias injected by a macro (via `__using__`) is
  invisible to Credo and cannot be resolved.

  The default `:functions` list does not include `direct_broadcast/5`,
  `direct_broadcast!/5`, or `local_broadcast_from/5` — all three are real,
  exported `Phoenix.PubSub` entry points that call sites can reach directly.
  Add them to `:functions` if your app uses them.

  A nested `defmodule PubSub do ... end` is not treated as a shadowing
  source the way a file-level `alias` is: if a file both aliases
  `Phoenix.PubSub` and later defines its own nested `PubSub` module, a call
  resolved through the alias still fires even though Elixir's own
  nested-module aliasing would resolve the bare name to the local module
  instead.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    filename = source_file.filename

    if skip_path?(filename, excluded_paths(params), allowed_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)
  defp allowed_paths(params), do: Params.get(params, :allowed_paths, __MODULE__)

  defp skip_path?(filename, excluded_paths, allowed_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths) or
      allowed_path?(filename, allowed_paths)
  end

  # Two independent, boundary-safe match shapes, checked across the whole
  # :allowed_paths list — `SourceFilter.matches_fragment?/2` is NOT used here
  # because its prefix/suffix branches match on segment PREFIX
  # (`String.contains?(filename, "/pubsub")`), which would exempt anything
  # merely starting with "pubsub" inside a segment (`pubsub_migrations/`,
  # `pubsub_debug_live.ex`).
  #
  # Each entry is trimmed of a leading/trailing "/" ONCE, then classified on
  # the trimmed form: an entry with no remaining internal "/" (`"pubsub"`,
  # `"pubsub/"`, `"/pubsub"`, and `"/pubsub/"` all trim to the same
  # `"pubsub"`) is checked BOTH ways — as a literal whole segment
  # (`segment_path_match?/2`) AND as a segment-name suffix
  # (`SourceFilter.matches_segment_suffix?/2`, so it ALSO matches a segment
  # merely ending in it, such as `legacy_pubsub/`). An entry with an
  # internal "/" (`"my_app/notifications"`) only ever matches
  # `segment_path_match?/2` — `matches_segment_suffix?/2` checks
  # `String.ends_with?/2` per single path segment, so a suffix containing "/"
  # can never match inside one segment and would be a silent no-op there.
  defp allowed_path?(filename, allowed_paths) do
    segments = String.split(filename, "/")

    Enum.any?(allowed_paths, &path_entry_match?(segments, filename, &1))
  end

  defp path_entry_match?(segments, filename, allowed_path) do
    segment_path_match?(segments, allowed_path) or
      single_segment_suffix_match?(filename, allowed_path)
  end

  defp single_segment_suffix_match?(filename, allowed_path) do
    trimmed = String.trim(allowed_path, "/")

    not String.contains?(trimmed, "/") and
      SourceFilter.matches_segment_suffix?(filename, [trimmed])
  end

  # Matches `allowed_path` as a literal, consecutive run of whole path
  # segments — boundary-safe on BOTH ends since segments are compared for
  # equality, never substring-contained. A leading/trailing "/" on
  # `allowed_path` is ignored, so `"pubsub"`, `"pubsub/"`, `"/pubsub"`, and
  # `"/pubsub/"` all match the same directory.
  defp segment_path_match?(segments, allowed_path) do
    fragment_segments = allowed_path |> String.trim("/") |> String.split("/")
    fragment_length = length(fragment_segments)

    segments
    |> Enum.chunk_every(fragment_length, 1, :discard)
    |> Enum.any?(&(&1 === fragment_segments))
  end

  defp build_context(source_file, params) do
    %{
      modules: AstHelpers.resolve_aliases(source_file, [Phoenix.PubSub]),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module_segments}, function]}, _meta, args} = ast,
         calls,
         context
       )
       when is_list(args) do
    if module_segments in context.modules and function in context.functions do
      trigger = "#{Enum.join(module_segments, ".")}.#{function}"
      {ast, [call(trigger, alias_meta) | calls]}
    else
      {ast, calls}
    end
  end

  # The `Elixir.Phoenix.PubSub` bare-atom spelling of the module — a plain
  # atom in the module slot, not an `__aliases__` node (an erlang module call
  # produces the same dot-call shape, so a non-Elixir atom must resolve to
  # `nil` and fall through untouched).
  defp traverse({{:., _, [module_atom, function]}, meta, args} = ast, calls, context)
       when is_atom(module_atom) and is_list(args) do
    case elixir_atom_path(module_atom) do
      nil ->
        {ast, calls}

      module_segments ->
        if module_segments in context.modules and function in context.functions do
          # The module segment as literally written can be any quoted-atom
          # spelling (`:"Elixir.Phoenix.PubSub"`), so only the function name
          # after the dot is guaranteed to match the source text at `meta`'s
          # column — see `warn_on_missing_trigger/2` in Credo.Test.Case.
          {ast, [call(Atom.to_string(function), meta) | calls]}
        else
          {ast, calls}
        end
    end
  end

  defp traverse(ast, calls, _context), do: {ast, calls}

  defp elixir_atom_path(module_atom) do
    case Atom.to_string(module_atom) do
      "Elixir." <> _rest ->
        [Elixir | module_atom |> Module.split() |> Enum.map(&String.to_atom/1)]

      _erlang_name ->
        nil
    end
  end

  defp call(trigger, meta), do: %{trigger: trigger, line_no: meta[:line], column: meta[:column]}

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — call through your app's topic/wrapper module instead of Phoenix.PubSub directly",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
