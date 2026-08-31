defmodule MikaCredoRules.NoEctoSchemaInWebApp do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      modules: [Ecto.Schema],
      banned_path_fragments: ["_web/"],
      excluded_paths: []
    ],
    explanations: [
      params: [
        modules: """
        A list of modules whose `use` counts as declaring an Ecto schema.
        Defaults to `[Ecto.Schema]`; add a project wrapper (`MyApp.Schema`) here
        if one exists.
        """,
        banned_path_fragments: """
        A list of directory-name suffixes that mark a web app. A source file is in
        scope when any path segment ends with one of these. Defaults to
        `["_web/"]`, matching the Phoenix convention of naming the web app
        `<name>_web` (`apps/my_app_web/...`).

        Include the leading underscore. A fragment of `"web"` (no underscore) is a
        segment SUFFIX match, not a word match — it over-matches any directory
        merely ending in those letters, e.g. `apps/cobweb/...`, which has nothing
        to do with a Phoenix web app.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips even inside a
        banned directory — a carve-out for a specific subfolder. Matched via
        `SourceFilter.matches_fragment?/2` (segment-boundary). Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `use Ecto.Schema` must not appear in a web app — schemas belong in a dedicated
  database-layer app (conventionally named `_pg` or `schemas`).

  A schema defined inside the web app couples the wire/UI layer to the database
  layer: every other app that wants the schema has to depend on the whole web
  app to get it, and a change to the web app can now break a migration.

      # BAD — apps/my_web/lib/my_web/user.ex
      defmodule MyWeb.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end

      # GOOD — apps/my_pg/lib/my_pg/user.ex
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end

  `embedded_schema` is caught too — it is a macro `use Ecto.Schema` itself
  provides, so any module using it already trips the `use Ecto.Schema` match.
  Every spelling of the module is caught: aliased (`alias Ecto.Schema` then
  `use Schema`) and the `:"Elixir.Ecto.Schema"` atom. `import Ecto.Schema`
  (rather than `use`) is not flagged — `schema/2` and `embedded_schema/1` are
  macros only `use` brings into scope.

  ## Scoping

  In scope: any source file with a directory segment ending in a
  `banned_path_fragments` entry (default `_web`, so `apps/my_app_web/...`), not
  matching `excluded_paths`. Segment matching, not substring matching —
  `lib/cobweb/user.ex` does not end with `_web` and is never flagged.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if in_scope?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      schema_paths = schema_paths(source_file, params)

      source_file
      |> Credo.Code.prewalk(&collect_schema_uses(&1, &2, schema_paths))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp in_scope?(filename, params) do
    banned_path?(filename, banned_path_fragments(params)) and
      not excluded_path?(filename, excluded_paths(params))
  end

  defp banned_path_fragments(params), do: Params.get(params, :banned_path_fragments, __MODULE__)
  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp banned_path?(filename, fragments) do
    SourceFilter.matches_segment_suffix?(filename, fragments)
  end

  defp schema_paths(source_file, params) do
    AstHelpers.resolve_aliases(source_file, Params.get(params, :modules, __MODULE__))
  end

  defp collect_schema_uses({:use, meta, [module | _opts]} = ast, uses, schema_paths) do
    if schema_module?(module, schema_paths) do
      {ast, [meta[:line] | uses]}
    else
      {ast, uses}
    end
  end

  defp collect_schema_uses(ast, uses, _schema_paths), do: {ast, uses}

  defp schema_module?({:__aliases__, _, segments}, schema_paths) do
    strip_elixir_prefix(segments) in schema_paths
  end

  defp schema_module?(module, schema_paths) when is_atom(module) do
    if elixir_module_atom?(module) do
      [stripped | _elixir_prefixed] = AstHelpers.module_paths(module)
      stripped in schema_paths
    else
      false
    end
  end

  defp schema_module?(_other, _schema_paths), do: false

  defp elixir_module_atom?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> true
      _erlang_name -> false
    end
  end

  defp strip_elixir_prefix([Elixir | segments]), do: segments
  defp strip_elixir_prefix(segments), do: segments

  defp issue_for(line_no, issue_meta) do
    format_issue(issue_meta,
      message:
        "use Ecto.Schema found in a web app — move the schema to the dedicated _pg/schemas app",
      trigger: "use",
      line_no: line_no
    )
  end
end
