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
        flagged. A nested `defmodule Mock do ... end` also shadows the bare name
        for the rest of the file, and a nested, dotted `defmodule Bar.Baz do ...
        end` shadows only its first segment (`Bar`). A top-level, dotted
        defmodule shadows nothing. Only the fully-qualified `Elixir.Mock`
        spelling always stays flagged.
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

  A locally defined module also shadows a banned bare name, but only the single
  segment that Elixir's own implicit nested-module aliasing actually introduces.
  A nested, single-segment `defmodule Mock do ... end` shadows `Mock` outright —
  a test helper named `Mock` is a project module, not a reference to the `Mock`
  library:

      # GOOD — a local, nested `Mock` helper module, not a reference to the
      # Mock library
      defmodule MyApp.WorkerTest do
        defmodule Mock do
          def build(response), do: response
        end

        test "builds a response" do
          assert Mock.build(:ok) === :ok
        end
      end

  A nested, dotted `defmodule Bar.Baz do ... end` shadows only its first
  segment (`Bar`) — `Baz` alone stays unshadowed. A *top-level*, dotted
  `defmodule MyApp.Mock do ... end` shadows nothing at all, since nothing in
  the file aliases the bare name `Mock` to it:

      # BAD — a top-level, dotted defmodule shadows nothing; `Mock` still
      # means the banned library
      defmodule MyApp.Mock do
        def go, do: Mock.expect(:x)
      end

  Only the bare spelling is shadowed — writing out the fully-qualified
  `Elixir.Mock` still reports, since that spelling is unambiguous.
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
    module_segments = AstHelpers.resolve_aliases(source_file, banned)

    %{
      module_segments: module_segments,
      shadowed_names: shadowed_names(source_file, module_segments),
      erlang_modules: Params.get(params, :erlang_modules, __MODULE__)
    }
  end

  # A locally defined `defmodule` is a third shadowing source that alias
  # resolution does not cover — it emits the same bare `[:Mock]` AST as a
  # reference to a banned single-segment name. A single-segment defmodule name
  # (`Mock`) always shadows the bare name. A dotted, multi-segment name
  # (`Bar.Baz`) shadows only its first segment (`Bar`, not `Baz`) — and only
  # when the defmodule is nested inside another module, the way Elixir's own
  # implicit nested-module aliasing works. A top-level `defmodule MyApp.Mock`
  # defines a fully qualified module that nothing in the file aliases to a
  # bare name, so it shadows nothing.
  defp shadowed_names(source_file, module_segments) do
    source_file
    |> defmodule_definitions()
    |> Enum.map(&shadow_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1 in module_segments))
  end

  defp shadow_name({[single_segment], _nested?}), do: [single_segment]
  defp shadow_name({name_segments, true}), do: [List.first(name_segments)]
  defp shadow_name({_name_segments, false}), do: nil

  # Every `defmodule` in the file, paired with whether it is nested inside
  # another module. The outer pass collects only top-level defmodules and
  # prunes their bodies (`{nil, acc}`) so nested ones are never double
  # counted here; each top-level body is then rescanned on its own to find
  # every defmodule nested inside it, at any depth.
  defp defmodule_definitions(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_top_level_defmodule/2)
    |> Enum.flat_map(fn {name_segments, body} ->
      [{name_segments, false} | nested_defmodule_names(body)]
    end)
  end

  defp collect_top_level_defmodule(
         {:defmodule, _meta, [{:__aliases__, _, name_segments}, [do: body]]},
         definitions
       ) do
    {nil, [{name_segments, body} | definitions]}
  end

  defp collect_top_level_defmodule(ast, definitions), do: {ast, definitions}

  defp nested_defmodule_names(body) do
    body
    |> Macro.prewalk([], fn
      {:defmodule, _meta, [{:__aliases__, _, name_segments}, _inner_body]} = ast, names ->
        {ast, [{name_segments, true} | names]}

      ast, names ->
        {ast, names}
    end)
    |> elem(1)
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
    stripped = strip_elixir_prefix(module_segments)

    cond do
      not elixir_prefixed?(module_segments) and stripped in context.shadowed_names ->
        references

      stripped in context.module_segments ->
        [reference(Enum.join(module_segments, "."), meta) | references]

      true ->
        references
    end
  end

  defp elixir_prefixed?([Elixir | _rest]), do: true
  defp elixir_prefixed?(_module_segments), do: false

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
