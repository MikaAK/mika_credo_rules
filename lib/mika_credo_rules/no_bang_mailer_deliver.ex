defmodule MikaCredoRules.NoBangMailerDeliver do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [
      functions: [:deliver!],
      module_suffixes: ["Mailer"],
      excluded_paths: ["_test.exs", "test/"]
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
        segment boundaries). Defaults to `["_test.exs", "test/"]`.
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
  `Mailer.deliver!(email)` are both caught, piped or not. This is a naming
  heuristic, not full alias resolution: a call written through an `as:` rename
  that drops the `Mailer` suffix (`alias MyApp.Mailer, as: Notifier`) is
  invisible to this check.

  Test files are skipped by default (see `:excluded_paths`).
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

  defp traverse(
         {{:., _, [{:__aliases__, _, module}, function]}, meta, args} = ast,
         deliveries,
         context
       )
       when is_list(args) do
    if function in context.functions and mailer_module?(module, context.module_suffixes) do
      {ast, [delivery(module, function, meta) | deliveries]}
    else
      {ast, deliveries}
    end
  end

  defp traverse(ast, deliveries, _context), do: {ast, deliveries}

  defp mailer_module?(module, module_suffixes) do
    last_segment = module |> List.last() |> Atom.to_string()
    Enum.any?(module_suffixes, &String.ends_with?(last_segment, &1))
  end

  defp delivery(module, function, meta) do
    %{trigger: "#{Enum.join(module, ".")}.#{function}", line_no: meta[:line]}
  end

  defp issue_for(delivery, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{delivery.trigger} found — deliver! crashes on SES failure; use deliver/1 and handle {:error, reason}",
      trigger: delivery.trigger,
      line_no: delivery.line_no
    )
  end
end
