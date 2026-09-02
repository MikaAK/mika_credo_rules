defmodule MikaCredoRules.NoSyncMailerDeliverInWeb do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      functions: [:deliver, :deliver!],
      module_suffixes: ["Mailer"],
      included_paths: ["_web/", "controllers/", "live/", "_live.ex", "_controller.ex"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the mailer delivery functions to flag when
        called from a web-layer file. Defaults to `[:deliver, :deliver!]`.
        """,
        module_suffixes: """
        A list of suffixes identifying a mailer module by its last alias
        segment as written at the call site — `MyApp.Mailer` and, under
        `alias MyApp.Mailer`, the bare `Mailer` both end in `"Mailer"`.
        Defaults to `["Mailer"]`.
        """,
        included_paths: """
        A list of path fragments and file suffixes marking a file as
        web-layer. An entry ending in `/` that also starts with `_` is a
        directory-name-suffix convention, matched per path segment
        (`SourceFilter.matches_segment_suffix?/2` — `"_web/"` matches
        `apps/my_app_web/...`); any other entry ending in `/` is matched at a
        path-segment boundary (`SourceFilter.matches_fragment?/2`); any other
        entry is matched as a filename suffix
        (`SourceFilter.matches_suffix?/2`). Defaults to `["_web/",
        "controllers/", "live/", "_live.ex", "_controller.ex"]`. A
        `_test.exs` file, and any file under a `test/` path segment, is
        always out of scope, regardless of this list.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Web-layer code — controllers and LiveViews — must not deliver mail inline.

  A synchronous `Mailer.deliver/1` call blocks the request on the mail
  adapter's round trip, and `deliver!/1` on top of that crashes the request
  on any transient adapter failure. Enqueue an Oban worker instead: delivery
  gets its own retries and the request returns immediately.

      # BAD — apps/my_app_web/lib/my_app_web/controllers/signup_controller.ex
      defmodule MyAppWeb.SignupController do
        alias MyApp.Mailer

        def create(conn, params) do
          {:ok, user} = Accounts.create_user(params)
          Mailer.deliver(Emails.welcome(user))
          conn
        end
      end

      # GOOD — apps/my_app_web/lib/my_app_web/controllers/signup_controller.ex
      defmodule MyAppWeb.SignupController do
        alias MyApp.Workers.SendWelcomeEmail

        def create(conn, params) do
          {:ok, user} = Accounts.create_user(params)
          %{user_id: user.id} |> SendWelcomeEmail.new() |> Oban.insert()
          conn
        end
      end

  A mailer module is identified by its last alias segment *as written at the
  call site* — `MyApp.Mailer.deliver(email)` and, under `alias MyApp.Mailer`,
  `Mailer.deliver!(email)` are both caught, piped or not. An unqualified
  `deliver(email)`, as written under `import MyApp.Mailer`, is caught by name
  alone — as is a mailer injected as a dependency, `@mailer.deliver(email)` or
  `mailer.deliver(email)`, the shape the house style prefers over a mocking
  library. A plain field or attribute read with no parentheses — `assigns.deliver`,
  `conn.deliver` — is not a call and is never flagged, even when the receiver
  otherwise looks like an injected mailer.

  A `deliver!` call in a web-layer file is also reported by
  `NoBangMailerDeliver`, with different advice (fix its crash risk, not its
  inline timing) — the Oban fix this check asks for subsumes that one.

  ## Scoping

  In scope: any file matching `:included_paths` — a directory whose name ends
  in `_web` (segment-suffix, e.g. `apps/my_app_web/...`), a directory named
  `controllers`/`live`, or a file whose name ends in `_live.ex` or
  `_controller.ex`. A `_test.exs` file, and any file under a `test/` path
  segment (e.g. `apps/my_app_web/test/support/conn_case.ex`), is always out
  of scope, even one that otherwise matches (e.g. a controller test under
  `test/**/controllers/`), because it never runs as part of handling a live
  request.

  ## Limitations

    * Module identity is a naming heuristic, not alias resolution. A call
      written through an `as:` rename that drops the suffix
      (`alias MyApp.Mailer, as: Notifier`) is invisible.
    * Identity comes from the function name alone wherever the module is not
      a literal alias — an unqualified `deliver(email)`, and an injected
      `@mailer.deliver(email)` or `mailer.deliver(email)`. An unrelated
      `deliver/1` on any of those shapes is flagged. Narrow `:functions` if
      that bites.
    * Indirection through `apply(MyApp.Mailer, :deliver, [email])`, or a
      module spelled as an `:"Elixir.MyApp.Mailer"` atom or an erlang-style
      atom (`:mailer`) rather than an alias path, evades every clause here
      and is silently missed. So does an alias path whose first segment is
      itself computed — `__MODULE__.Mailer.deliver(email)` or
      `@base.Mailer.deliver(email)` — rather than a literal alias.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if in_scope?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp in_scope?(filename, params) do
    not SourceFilter.matches_suffix?(filename, ["_test.exs"]) and
      not SourceFilter.matches_fragment?(filename, ["test/"]) and
      included_path?(filename, included_paths(params))
  end

  defp included_paths(params), do: Params.get(params, :included_paths, __MODULE__)

  defp included_path?(filename, included_paths) do
    {segment_suffixes, rest} = Enum.split_with(included_paths, &directory_suffix_entry?/1)
    {fragments, suffixes} = Enum.split_with(rest, &String.ends_with?(&1, "/"))

    SourceFilter.matches_segment_suffix?(filename, segment_suffixes) or
      SourceFilter.matches_fragment?(filename, fragments) or
      SourceFilter.matches_suffix?(filename, suffixes)
  end

  defp directory_suffix_entry?(entry) do
    String.starts_with?(entry, "_") and String.ends_with?(entry, "/")
  end

  defp build_context(params) do
    %{
      functions: Params.get(params, :functions, __MODULE__),
      module_suffixes: Params.get(params, :module_suffixes, __MODULE__)
    }
  end

  @definition_macros [:def, :defp, :defmacro, :defmacrop, :defdelegate, :defguard, :defguardp]

  # A definition head has the same `{name, meta, args}` shape as a call, so the
  # head is dropped from the walk while the body (or, for `defdelegate`, the
  # `to:` opts) stays traversable.
  defp traverse({definition, meta, [_head, body]}, deliveries, _context)
       when definition in @definition_macros do
    {{definition, meta, [{:__block__, [], []}, body]}, deliveries}
  end

  # A bodiless head (`def deliver(email \\ nil)`, the multi-clause-with-defaults
  # idiom) has no body at all — the definition tuple is 1-arg, not 2 — so there
  # is nothing left to traverse once the head itself is pruned. `defguard`/
  # `defguardp` are always this 1-arg shape (the argument is the head, or a
  # `when`-wrapped head+guard) — a guard body can't call arbitrary functions
  # anyway, so pruning it entirely is safe.
  defp traverse({definition, _meta, [_head]}, deliveries, _context)
       when definition in @definition_macros do
    {nil, deliveries}
  end

  # `@spec`/`@callback`/`@macrocallback`/`@type`/`@typep`/`@opaque` bodies are
  # type expressions, not calls — a function name in a type signature
  # (`@spec deliver(map()) :: :ok`) is not a delivery.
  defp traverse({:@, _meta, [{attribute, _, _}]}, deliveries, _context)
       when attribute in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    {nil, deliveries}
  end

  # Any other module-attribute DEFINITION (`@deliver true`) has the same
  # `{name, meta, [value]}` shape as a call, same trap as a definition head —
  # an attribute happening to be named after a flagged function is not a
  # delivery. Only that `{name, meta, [value]}` wrapper is dropped; `value`
  # is spliced straight into the `@` node's own arg list (not returned bare)
  # so `Macro.prewalk` re-visits it as a fresh node — a delivery written as
  # an attribute's value (`@preview MyApp.Mailer.deliver(:sample)`) stays
  # traversable, the same treatment as a `def` body three clauses up. An
  # attribute READ (`@mailer`) carries `nil`, not a list, in that slot, and
  # never matches here.
  defp traverse({:@, meta, [{_name, _name_meta, [value]}]}, deliveries, _context) do
    {{:@, meta, [value]}, deliveries}
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         deliveries,
         context
       )
       when is_list(args) do
    if literal_alias?(module) and function in context.functions and
         mailer_module?(module, context.module_suffixes) do
      trigger = "#{Enum.join(module, ".")}.#{function}"

      {ast, [delivery(trigger, alias_meta) | deliveries]}
    else
      {ast, deliveries}
    end
  end

  # An injected mailer — `@mailer.deliver(email)` or `mailer.deliver(email)` —
  # carries the module as a value, so identity comes from the function name, as
  # it does for an unqualified call. A no-parens dot access (`meta[:no_parens]`)
  # is a plain struct/map field read, not a call — `assigns.deliver` is not a
  # delivery.
  defp traverse({{:., _, [receiver, function]}, meta, args} = ast, deliveries, context)
       when is_list(args) do
    with true <- is_nil(meta[:no_parens]),
         true <- function in context.functions,
         {:ok, name, receiver_meta} <- receiver_name(receiver) do
      {ast, [delivery("#{name}.#{function}", receiver_meta) | deliveries]}
    else
      _receiver -> {ast, deliveries}
    end
  end

  defp traverse({function, meta, args} = ast, deliveries, context)
       when is_atom(function) and is_list(args) do
    if function in context.functions do
      {ast, [delivery(Atom.to_string(function), meta) | deliveries]}
    else
      {ast, deliveries}
    end
  end

  defp traverse(ast, deliveries, _context), do: {ast, deliveries}

  # An `__aliases__` node's leading segment is a literal `Elixir.Alias` atom
  # only when every segment is one — `__MODULE__.Mailer`, `@base.Mailer`, and
  # `mod.Mailer` all embed a non-atom AST node (`{:__MODULE__, _, nil}`, an
  # attribute read, a variable) in the first slot, which `Enum.join/2` cannot
  # render as a trigger string.
  defp literal_alias?(module), do: Enum.all?(module, &is_atom/1)

  defp mailer_module?(module, module_suffixes) do
    last_segment = module |> List.last() |> Atom.to_string()
    Enum.any?(module_suffixes, &String.ends_with?(last_segment, &1))
  end

  defp receiver_name({:@, meta, [{attribute, _, nil}]}), do: {:ok, "@#{attribute}", meta}
  defp receiver_name({variable, meta, nil}) when is_atom(variable), do: {:ok, "#{variable}", meta}
  defp receiver_name(_receiver), do: :error

  defp delivery(trigger, meta) do
    %{trigger: trigger, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(delivery, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{delivery.trigger} found — delivering mail inline blocks the request; enqueue an Oban worker instead",
      trigger: delivery.trigger,
      line_no: delivery.line_no,
      column: delivery.column
    )
  end
end
