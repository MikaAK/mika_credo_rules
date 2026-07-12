# credo:disable-for-this-file MikaCredoRules.NoMockingLibraries
defmodule MikaCredoRules.NoMockingLibraries do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      modules: [Mox, Hammox, Mock, Mimic, Patch],
      erlang_modules: [:meck]
    ],
    explanations: [
      params: [
        modules: """
        A list of Elixir mocking library modules to ban. Any reference to one of
        these — `import`, `alias`, `use`, or a remote call — is reported.

        Module names are matched on their exact segments, so a project module that
        merely contains a banned name (`MyApp.MockingBird`, `MyApp.Mock`) is never
        flagged.
        """,
        erlang_modules: """
        A list of erlang mocking module atoms to ban. Any remote call on one of
        these (`:meck.new/1`, `:meck.expect/3`, ...) is reported.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  Mocking libraries must not be used — define a behaviour and inject the
  implementation instead.

  Mocks couple tests to call sequences instead of contracts, and their global or
  process-wide stubbing breaks down under async tests. A behaviour with a test
  implementation keeps the contract explicit and the test data local.

      # BAD — Mox mock wired to the behaviour
      Mox.defmock(MyApp.ClientMock, for: MyApp.Client)
      expect(MyApp.ClientMock, :fetch, fn id -> {:ok, %{id: id}} end)

      # GOOD — behaviour + injected test implementation
      defmodule MyApp.TestClient do
        @behaviour MyApp.Client

        @impl MyApp.Client
        def fetch(id), do: {:ok, %{id: id}}
      end

      MyApp.Worker.fetch(1, client: MyApp.TestClient)

  Banned modules are matched on their exact segments — `MyApp.MockingBird` and
  `MyApp.Mock` are project modules, not mocking libraries, and are never flagged.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file, params) do
    banned = Params.get(params, :modules, __MODULE__)

    %{
      module_segments: AstHelpers.resolve_aliases(source_file, banned),
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__)
    }
  end

  # `alias MyApp.{Mock, Foo}` — the inner aliases are relative to the base, so
  # check the expanded names and prune the node to keep the bare `[:Mock]`
  # fragment from being matched on its own.
  defp traverse(
         {{:., _, [{:__aliases__, _, base}, :{}]}, _meta, inner_nodes},
         references,
         context
       ) do
    references =
      Enum.reduce(inner_nodes, references, fn
        {:__aliases__, inner_meta, inner}, acc ->
          maybe_reference(base ++ inner, inner_meta, acc, context)

        _other, acc ->
          acc
      end)

    {nil, references}
  end

  # `alias Mox, as: M` — only the target is a library reference; prune the node
  # so the `as:` name is not reported a second time on the same line.
  defp traverse({:alias, _, [{:__aliases__, meta, target}, opts]}, references, context)
       when is_list(opts) do
    {nil, maybe_reference(target, meta, references, context)}
  end

  defp traverse({:__aliases__, meta, module_segments} = ast, references, context) do
    {ast, maybe_reference(module_segments, meta, references, context)}
  end

  defp traverse({{:., _, [erlang_module, function]}, meta, args} = ast, references, context)
       when is_atom(erlang_module) and is_list(args) do
    if erlang_module in context.erlang_modules do
      trigger = "#{inspect(erlang_module)}.#{function}/#{length(args)}"

      {ast, [reference(trigger, meta) | references]}
    else
      {ast, references}
    end
  end

  defp traverse(ast, references, _context), do: {ast, references}

  defp maybe_reference(module_segments, meta, references, context) do
    if strip_elixir_prefix(module_segments) in context.module_segments do
      [reference(Enum.join(module_segments, "."), meta) | references]
    else
      references
    end
  end

  defp strip_elixir_prefix([Elixir | module_segments]), do: module_segments
  defp strip_elixir_prefix(module_segments), do: module_segments

  defp reference(trigger, meta), do: %{trigger: trigger, line_no: meta[:line]}

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reference.trigger} found — mocking libraries are banned, define a behaviour and inject the implementation instead",
      trigger: reference.trigger,
      line_no: reference.line_no
    )
  end
end
