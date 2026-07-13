defmodule MikaCredoRules.NoJasonDeriveOnEctoSchema do
  use Credo.Check,
    base_priority: :high,
    category: :design

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  Ecto schemas must not derive `Jason.Encoder` — serialize in a view or JSON
  layer instead. Schemas must not know about serialization.

  A derived encoder welds the schema's fields to a wire format: adding a field
  silently changes every API response, and every caller is forced through the
  one shape the schema picked. A JSON layer owns the shape explicitly, per
  endpoint.

      # BAD — the schema knows about serialization
      defmodule MyApp.User do
        use Ecto.Schema

        @derive {Jason.Encoder, only: [:id, :name]}
        schema "users" do
          field :name, :string
        end
      end

      # GOOD — the schema stays serialization-free
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end

      # GOOD — a JSON layer owns the shape
      defmodule MyAppWeb.UserJSON do
        def show(%{user: user}), do: %{id: user.id, name: user.name}
      end

  The check is scoped per module, not per file: only a `defmodule` whose own
  body contains `use Ecto.Schema` (embedded schemas use the same module) is
  inspected, and a nested `defmodule` without its own `use Ecto.Schema` is a
  separate scope. Every spelling of both modules is caught — qualified
  (`@derive Jason.Encoder`), aliased (`alias Jason.Encoder` + `@derive Encoder`),
  and the `:"Elixir.Jason.Encoder"` atom — including `@derive` lists such as
  `@derive [Jason.Encoder, Other]` and `@derive [{Jason.Encoder, opts}, Other]`.

  `defimpl Jason.Encoder, for: MyApp.User` is out of scope — a `defimpl` is its
  own module and can live in the JSON layer; only the `@derive` attribute
  inside a schema module is reported.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack. Aliases injected by a macro (via `__using__`) are invisible to
  Credo and cannot be resolved.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    context = %{
      encoder_paths: AstHelpers.resolve_aliases(source_file, [Jason.Encoder]),
      schema_paths: AstHelpers.resolve_aliases(source_file, [Ecto.Schema])
    }

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  # Each defmodule is its own scope: only its own body (nested defmodules
  # excluded) decides whether it is a schema and which @derive attributes it
  # owns. Nested defmodules are still visited by the outer prewalk, so each
  # gets the same treatment independently.
  defp traverse({:defmodule, _, [_name, [{:do, body} | _]]} = ast, derives, context) do
    if uses_ecto_schema?(body, context.schema_paths) do
      {ast, collect_derives(body, context.encoder_paths) ++ derives}
    else
      {ast, derives}
    end
  end

  defp traverse(ast, derives, _context), do: {ast, derives}

  defp uses_ecto_schema?(body, schema_paths) do
    scan_own_body(body, false, fn
      {:use, _, [module | _]}, found -> found or schema_module?(module, schema_paths)
      _node, found -> found
    end)
  end

  defp collect_derives(body, encoder_paths) do
    scan_own_body(body, [], fn
      {:@, meta, [{:derive, _, [arg]}]}, derives ->
        if derives_encoder?(arg, encoder_paths) do
          [%{line_no: meta[:line]} | derives]
        else
          derives
        end

      _node, derives ->
        derives
    end)
  end

  # Walks a module body, pruning nested defmodule subtrees — an inner module
  # neither inherits the outer `use Ecto.Schema` nor contributes its own.
  defp scan_own_body(body, initial, fun) do
    body
    |> Macro.prewalk(initial, fn
      {:defmodule, _, _}, acc -> {nil, acc}
      node, acc -> {node, fun.(node, acc)}
    end)
    |> elem(1)
  end

  defp schema_module?({:__aliases__, _, segments}, schema_paths),
    do: strip_elixir_prefix(segments) in schema_paths

  defp schema_module?(module, _schema_paths) when is_atom(module), do: module === Ecto.Schema

  defp schema_module?(_other, _schema_paths), do: false

  defp derives_encoder?({:__aliases__, _, segments}, encoder_paths),
    do: strip_elixir_prefix(segments) in encoder_paths

  defp derives_encoder?(module, _encoder_paths) when is_atom(module),
    do: module === Jason.Encoder

  defp derives_encoder?({module, _opts}, encoder_paths),
    do: derives_encoder?(module, encoder_paths)

  defp derives_encoder?(protocols, encoder_paths) when is_list(protocols),
    do: Enum.any?(protocols, &derives_encoder?(&1, encoder_paths))

  defp derives_encoder?(_other, _encoder_paths), do: false

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(derive, issue_meta) do
    format_issue(issue_meta,
      message:
        "@derive Jason.Encoder on an Ecto schema found — serialize in a view or JSON layer; schemas must not know about serialization",
      trigger: "@derive",
      line_no: derive.line_no
    )
  end
end
