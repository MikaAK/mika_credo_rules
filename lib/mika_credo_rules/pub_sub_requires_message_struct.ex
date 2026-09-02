defmodule MikaCredoRules.PubSubRequiresMessageStruct do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: [:broadcast, :broadcast!, :local_broadcast, :broadcast_from, :broadcast_from!],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the `Phoenix.PubSub` broadcast functions whose
        payload argument is checked. Defaults to
        `[:broadcast, :broadcast!, :local_broadcast, :broadcast_from, :broadcast_from!]`.

        A function name ending in `_from` (with or without a trailing `!`) is
        treated as taking a `from` pid as its second argument, shifting the
        payload one position later than the other functions — matching
        `Phoenix.PubSub.broadcast_from/4,5`'s real signature. `direct_broadcast`
        and `direct_broadcast!` are recognized the same way even without an
        `_from` suffix, matching their own real signature. Adding a
        differently-shaped function under this param (one that shifts the
        payload for a reason other than a leading `from` pid) mismeasures its
        payload position.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries — see `MikaCredoRules.SourceFilter.matches_fragment?/2`).

        Defaults to `["_test.exs", "test/"]`, exempting test files — a
        broadcast in a test commonly asserts directly on the payload shape
        subscribers receive, rather than exercising the message struct a
        production broadcaster is expected to build.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `Phoenix.PubSub` broadcast payload must be a message struct, never a bare
  atom, tuple, or map literal.

  Subscribers pattern-match on the broadcast payload — `%MyApp.PubSub.Message{}`
  keeps that match compiler-checked, so renaming or adding a field is caught at
  compile time everywhere it is matched on. A bare atom, tuple, or map literal
  gives subscribers nothing to match against but the payload's runtime shape,
  and a refactor that changes that shape fails silently at every subscriber.

      # BAD — bare atom payload
      Phoenix.PubSub.broadcast(MyApp.PubSub, topic, :updated)

      # BAD — bare tuple payload
      Phoenix.PubSub.broadcast(pubsub, topic, {:course_updated, course})

      # BAD — bare map payload, no message struct
      Phoenix.PubSub.broadcast(pubsub, topic, %{event: :updated})

      # GOOD — payload is a message struct
      Phoenix.PubSub.broadcast(pubsub, topic, %MyApp.PubSub.Message{event: :updated})

  `broadcast_from`/`broadcast_from!` take the payload one argument later than
  `broadcast`/`broadcast!`/`local_broadcast`, because they also take the
  sending `from` pid — both are checked at the right position:

      # BAD — bare atom payload, broadcast_from
      Phoenix.PubSub.broadcast_from(pubsub, self(), topic, :updated)

      # GOOD — payload is a message struct
      Phoenix.PubSub.broadcast_from(pubsub, self(), topic, %MyApp.PubSub.Message{event: :updated})

  A call is checked when it resolves to `Phoenix.PubSub` under this file's own
  alias declarations — a literal `Phoenix.PubSub.broadcast(...)`, or the
  aliased `PubSub.broadcast(...)` under `alias Phoenix.PubSub` (see Limitations
  below for how that resolution can misfire when a local name is reused).
  This check runs everywhere that module is called directly, including inside
  a project's own PubSub wrapper module — whether broadcasts should be routed
  through a wrapper at all is a separate concern this check does not enforce,
  so there is no path exemption for a `pubsub/`-named directory.

      # GOOD — not flagged, the receiver isn't Phoenix.PubSub
      MyApp.PubSub.broadcast(pubsub, topic, :updated)

  ## Limitations

    * Alias resolution is file-wide, not lexical (see
      `MikaCredoRules.AstHelpers.resolve_aliases/2`) — when two modules in the
      same file each `alias` a different target onto the same local name
      `PubSub`, only the *last* such alias in the file is honored for every
      `PubSub.broadcast(...)` call in the file, regardless of which module the
      call is actually in. This can both over-report (a call that truly
      resolves to a project's own `PubSub` wrapper gets flagged as
      `Phoenix.PubSub`) and under-report (a real `Phoenix.PubSub.broadcast`
      call is missed because a later, unrelated alias shadowed it).
    * A variable payload (`Phoenix.PubSub.broadcast(pubsub, topic, message)`) is
      never flagged — whether `message` is a struct at runtime is outside a
      single-file AST check's reach.
    * A list literal payload is undetected — this check only recognises the
      atom/tuple/map shapes named in its moduledoc; a string, number, or
      charlist payload is undetected for the same reason.
    * `%{base | field: value}` map-update syntax is treated as a bare map
      literal, even when `base` is already a message struct at runtime — the
      check cannot see past the update syntax to `base`'s type.
    * Only a literal `Module.function(...)` (dotted `__aliases__` spelling) or
      piped `x |> Module.function(...)` call is matched —
      `apply(Phoenix.PubSub, :broadcast, [...])`, an unqualified `broadcast(...)`
      reached via `import Phoenix.PubSub`, and the atom-spelled module form
      `:"Elixir.Phoenix.PubSub".broadcast(...)` are all undetected.
    * `local_broadcast_from`, `direct_broadcast`, and `direct_broadcast!` are
      genuine `Phoenix.PubSub` broadcast functions but are absent from the
      default `:functions` list — they are unchecked unless added to that
      param explicitly.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
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

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(source_file, params) do
    %{
      functions: Params.get(params, :functions, __MODULE__),
      pubsub_modules: AstHelpers.resolve_aliases(source_file, [Phoenix.PubSub])
    }
  end

  # A piped broadcast is consumed here: its payload is checked at the piped
  # position (one argument earlier than a standalone call, since the pubsub
  # name is piped in rather than written as the first argument), and the
  # call's head is rewritten to a block (arguments stay traversable) so the
  # standalone clause below never re-examines the same call at the wrong
  # position.
  defp traverse({:|>, pipe_meta, [lhs, piped_call]} = ast, issues, context) do
    case broadcast_call(piped_call, context) do
      {meta, function, args} ->
        {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
         collect_broadcast(issues, function, args, :piped, meta)}

      nil ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, context) do
    case broadcast_call(ast, context) do
      {meta, function, args} ->
        {ast, collect_broadcast(issues, function, args, :standalone, meta)}

      nil ->
        {ast, issues}
    end
  end

  defp broadcast_call(
         {{:., _, [{:__aliases__, _, module_segments}, function]}, meta, args},
         context
       )
       when is_list(args) do
    if function in context.functions and module_segments in context.pubsub_modules do
      {meta, function, args}
    end
  end

  defp broadcast_call(_ast, _context), do: nil

  defp collect_broadcast(issues, function, args, position, meta) do
    case payload_argument(function, args, position) do
      {:ok, payload} ->
        if offending_payload?(payload) do
          [broadcast(function, payload, meta) | issues]
        else
          issues
        end

      :error ->
        issues
    end
  end

  # In `Module.broadcast(pubsub, topic, payload)` the payload is the 3rd
  # argument (index 2); `broadcast_from`/`broadcast_from!` take a `from` pid
  # first, shifting it to the 4th (index 3), and `direct_broadcast`/
  # `direct_broadcast!` shift it there too (they take a leading `node_name`
  # instead, but land the payload at the same index). Piping the pubsub name
  # in (`pubsub |> Module.broadcast(topic, payload)`) drops it from the
  # call's own argument list, shifting the payload one index earlier.
  defp payload_argument(function, args, position) do
    index = payload_index(function) - piped_offset(position)
    min_arity = index + 1

    if index >= 0 and length(args) in min_arity..(min_arity + 1) do
      {:ok, Enum.at(args, index)}
    else
      :error
    end
  end

  defp payload_index(function) do
    if shifted_payload_function?(function), do: 3, else: 2
  end

  defp shifted_payload_function?(function) do
    name = function |> Atom.to_string() |> String.trim_trailing("!")
    String.ends_with?(name, "_from") or name === "direct_broadcast"
  end

  defp piped_offset(:piped), do: 1
  defp piped_offset(:standalone), do: 0

  defp offending_payload?(payload) do
    case payload do
      value when is_atom(value) -> true
      {:__aliases__, _meta, _segments} -> true
      {:{}, _meta, _elements} -> true
      {_first, _second} -> true
      {:%{}, _meta, fields} -> not struct_literal?(fields)
      _other -> false
    end
  end

  defp struct_literal?(fields) do
    Enum.any?(fields, fn
      {:__struct__, _value} -> true
      _other -> false
    end)
  end

  defp broadcast(function, payload, meta) do
    %{
      display: Macro.to_string(payload),
      function: function,
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(broadcast, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{broadcast.function} payload #{broadcast.display} found — broadcast payloads must " <>
          "be a message struct (e.g. %MyApp.PubSub.Message{}), never a bare atom, tuple, or map literal",
      trigger: to_string(broadcast.function),
      line_no: broadcast.line_no,
      column: broadcast.column
    )
  end
end
