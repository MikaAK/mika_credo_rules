defmodule MikaCredoRules.NoBangMailerDeliver do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      functions: [:deliver!],
      module_suffixes: ["Mailer"],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the bang delivery functions to flag. Defaults to
        `[:deliver!]`.
        """,
        module_suffixes: """
        A list of suffixes identifying a mailer module by its last alias
        segment as written at the call site — `MyApp.Mailer` and, under
        `alias MyApp.Mailer`, the bare `Mailer` both end in `"Mailer"`.
        Defaults to `["Mailer"]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]` — test files are in scope,
        because the sanctioned test idiom is `assert_email_sent` over a plain
        `deliver/1`, so a `deliver!` in a test is the same latent crash it is
        anywhere else.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Swoosh mailers must be delivered with `deliver/1`, never `deliver!/1`.

  `deliver!/1` raises on any adapter failure — a transient SES throttle or
  outage crashes the caller instead of returning `{:error, reason}` for the
  caller to retry or log. `deliver/1` returns a tuple either way.

      # BAD — crashes the caller on SES failure
      defmodule MyApp.Workers.SendWelcomeEmail do
        alias MyApp.Mailer

        def perform(email), do: email |> Mailer.deliver!()
      end

      # GOOD — the caller handles the error
      defmodule MyApp.Workers.SendWelcomeEmail do
        alias MyApp.Mailer

        def perform(email) do
          case Mailer.deliver(email) do
            {:ok, _metadata} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end

  A mailer module is identified by its last alias segment *as written at the
  call site* — `MyApp.Mailer.deliver!(email)` and, under `alias MyApp.Mailer`,
  `Mailer.deliver!(email)` are both caught, piped or not. An unqualified
  `deliver!(email)`, as written under `import MyApp.Mailer`, is caught by name
  alone — as is a mailer injected as a dependency, `@mailer.deliver!(email)` or
  `mailer.deliver!(email)`, the shape the house style prefers over a mocking
  library.

  Test files are in scope by default: the sanctioned test idiom is
  `assert_email_sent` over a plain `deliver/1`, so a `deliver!` in a test is
  the same latent crash it is anywhere else.

  ## Limitations

    * Module identity is a naming heuristic, not alias resolution. A call
      written through an `as:` rename that drops the suffix
      (`alias MyApp.Mailer, as: Notifier`) is invisible.
    * Identity comes from the function name alone wherever the module is not a
      literal alias — an unqualified `deliver!(email)`, and an injected
      `@mailer.deliver!(email)` or `mailer.deliver!(email)`. An unrelated
      `deliver!/1` on any of those shapes is flagged. Narrow `:functions` if
      that bites.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp build_context(params) do
    %{
      functions: Params.get(params, :functions, __MODULE__),
      module_suffixes: Params.get(params, :module_suffixes, __MODULE__)
    }
  end

  # A definition head has the same `{name, meta, args}` shape as a call, so the
  # head is dropped from the walk while the body stays traversable.
  defp traverse({definition, meta, [_head, body]}, deliveries, _context)
       when definition in [:def, :defp, :defmacro, :defmacrop] do
    {{definition, meta, [{:__block__, [], []}, body]}, deliveries}
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         deliveries,
         context
       )
       when is_list(args) do
    if function in context.functions and mailer_module?(module, context.module_suffixes) do
      {ast, [delivery(alias_trigger(module, function), alias_meta) | deliveries]}
    else
      {ast, deliveries}
    end
  end

  # An injected mailer — `@mailer.deliver!(email)` or `mailer.deliver!(email)` —
  # carries the module as a value, so identity comes from the function name, as
  # it does for an unqualified call.
  defp traverse({{:., _, [receiver, function]}, _meta, args} = ast, deliveries, context)
       when is_list(args) do
    with true <- function in context.functions,
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

  # An `__aliases__` segment list can carry AST nodes rather than atoms —
  # `__MODULE__.Mailer.deliver!(email)` puts `{:__MODULE__, _, nil}` in the
  # first slot — so identity and trigger building must not assume atoms.
  defp mailer_module?(module, module_suffixes) do
    last_segment = List.last(module)

    is_atom(last_segment) and
      Enum.any?(module_suffixes, &String.ends_with?(Atom.to_string(last_segment), &1))
  end

  # A non-atom segment (`__MODULE__.Mailer.deliver!`) has no source text the
  # alias meta can anchor a trigger to — report without one, at the real
  # column, and name only the function in the message.
  defp alias_trigger(module, function) do
    if Enum.all?(module, &is_atom/1) do
      "#{Enum.map_join(module, ".", &Atom.to_string/1)}.#{function}"
    else
      {Credo.Issue.no_trigger(), Atom.to_string(function)}
    end
  end

  defp receiver_name({:@, meta, [{attribute, _, nil}]}), do: {:ok, "@#{attribute}", meta}
  defp receiver_name({variable, meta, nil}) when is_atom(variable), do: {:ok, "#{variable}", meta}
  defp receiver_name(_receiver), do: :error

  defp delivery({trigger, display}, meta) do
    %{trigger: trigger, display: display, line_no: meta[:line], column: meta[:column]}
  end

  defp delivery(trigger, meta) do
    %{trigger: trigger, display: trigger, line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(delivery, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{delivery.display} found — deliver! crashes on SES failure; use deliver/1 and handle {:error, reason}",
      trigger: delivery.trigger,
      line_no: delivery.line_no,
      column: delivery.column
    )
  end
end
