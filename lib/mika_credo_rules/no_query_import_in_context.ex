defmodule MikaCredoRules.NoQueryImportInContext do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [
      allowed_paths: ["_pg/", "/schemas/", "priv/", "_test.exs", "test/"],
      modules: [Ecto.Query]
    ],
    explanations: [
      params: [
        allowed_paths: """
        A list of path fragments/suffixes where query composition is allowed —
        the dedicated schema app, migrations, and tests. A source file whose
        path matches any entry is exempt from this check.

        Defaults to `["_pg/", "/schemas/", "priv/", "_test.exs", "test/"]`.

        An entry starting with `_` and ending in `/` (like `_pg/`) is matched
        as a directory-NAME SUFFIX — any path segment ending in that string,
        so `apps/cheddar_flow_pg/...` matches even though no segment is
        literally named `_pg`. `apps/my_pgadmin/...` does not match — the
        segment `my_pgadmin` does not end in `_pg`. The trailing `/` is what
        selects this matcher: `"_pg"` without it falls through to the plain
        path-segment matching below, where it only matches a segment
        literally named `_pg`.

        Every other entry not containing a `.` is matched at a path-segment
        boundary on both sides: a leading `/`, if present, is dropped, and
        a trailing `/` is appended unless it is already there — so
        `"priv"`, `"/priv"`, and `"priv/"` all behave identically and none
        of them match a lookalike segment such as `private/`. `priv/` and
        `test/` match a directory literally named that. `lib/latest/helpers.ex`
        does not match `test/` — it has no segment literally named `test`.

        An entry containing a `.` (a filename-suffix shape, like
        `_test.exs`) is used exactly as written, unchanged — matching is a
        plain `String.ends_with?/2` on the filename. Written bare, with no
        leading `/`, it is an UNANCHORED suffix: `"_test.exs"` matches any
        file ending that way, including `courses_test.exs`. Written with a
        leading `/`, the `/` is kept and anchors the match to a path
        segment: `"/test_helper.exs"` matches only a file literally named
        `test_helper.exs`, never a lookalike such as `my_test_helper.exs`.
        """,
        modules: """
        A list of modules whose `import`, `require`, or qualified
        `from`/`dynamic` call counts as query composition. Defaults to
        `[Ecto.Query]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Query composition belongs in the schema module, not the context.

  `by_*`/`join_*` query fragments live on the schema — conventionally in the
  dedicated database-layer app (`_pg`/`schemas`) — and the context orchestrates
  by calling them. `import Ecto.Query` (or `require Ecto.Query`, or a qualified
  `Ecto.Query.from`/`dynamic` call) outside that app means the context is
  building queries itself instead of delegating.

      # BAD — apps/my_app/lib/my_app/courses.ex builds the query itself
      defmodule MyApp.Courses do
        import Ecto.Query

        def list_open do
          from(course in MyApp.Course, where: course.status == :open)
        end
      end

      # GOOD — apps/my_app/lib/my_app/courses.ex delegates to the schema
      defmodule MyApp.Courses do
        alias MyApp.Course

        def list_open, do: Course.by_status(:open)
      end

  `require Ecto.Query` is caught the same way `import` is. A qualified call to
  `Ecto.Query.from` or `Ecto.Query.dynamic` is caught too, alias-aware —
  `alias Ecto.Query, as: Q` then `Q.from(...)` is the same smell as importing
  it outright. Merely aliasing `Ecto.Query` without ever calling `from` or
  `dynamic` through it is not itself flagged.

  In scope: any file whose path does not match `:allowed_paths` — by default
  the schema app, `priv/` (migrations, seeds), and tests.

  ## Limitations

    * Only `from` and `dynamic`, at any arity, are caught on a qualified
      call — the two functions that actually start composing a query. A
      qualified `Ecto.Query.where/3` (or similar) continuing a query built
      elsewhere is not caught.
    * `apply(Ecto.Query, :from, [...])` evades the qualified-call matcher.
    * An `import`/`require` brought in by a macro (through `__using__`) is
      invisible to Credo and cannot be resolved.
    * Aliases are resolved from a flat, file-level table — an alias declared
      inside one function is treated as applying to the whole file.
    * `require Ecto.Query, as: Q` does not register `Q` as an alias — only
      an `alias` declaration does. `Q.from(...)` after such a `require`
      evades the qualified-call matcher (the `require` itself still fires,
      so the file is not missed entirely).
    * A single-segment `:modules` entry (e.g. `modules: [Query]`) is not
      deshadowed by a local `defmodule Query do ... end` — a reference to
      the file's own same-named module is still flagged as if it were the
      configured module.
  """
  @explanation [check: @moduledoc]

  @query_functions [:from, :dynamic]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if allowed_path?(source_file.filename, allowed_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      module_segments = AstHelpers.resolve_aliases(source_file, modules(params))

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, module_segments))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp allowed_paths(params), do: Params.get(params, :allowed_paths, __MODULE__)
  defp modules(params), do: Params.get(params, :modules, __MODULE__)

  defp allowed_path?(filename, allowed_paths) do
    {suffix_conventions, fragments} =
      Enum.split_with(allowed_paths, &directory_suffix_convention?/1)

    SourceFilter.matches_fragment?(filename, Enum.map(fragments, &normalize_fragment/1)) or
      SourceFilter.matches_segment_suffix?(filename, suffix_conventions)
  end

  defp directory_suffix_convention?(entry) do
    String.starts_with?(entry, "_") and String.ends_with?(entry, "/")
  end

  defp normalize_fragment(entry) do
    if String.contains?(entry, ".") do
      entry
    else
      bound_trailing_edge(String.trim_leading(entry, "/"))
    end
  end

  defp bound_trailing_edge(fragment) do
    if String.ends_with?(fragment, "/") do
      fragment
    else
      fragment <> "/"
    end
  end

  defp traverse(
         {keyword, meta, [module_node | _rest]} = ast,
         references,
         module_segments
       )
       when keyword in [:import, :require] do
    if AstHelpers.use_module?(module_node, module_segments) do
      {ast, [import_reference(keyword, module_node, meta) | references]}
    else
      {ast, references}
    end
  end

  defp traverse(
         {{:., dot_meta, [module_node, function]}, _call_meta, args} = ast,
         references,
         module_segments
       )
       when is_list(args) do
    if function in @query_functions and AstHelpers.use_module?(module_node, module_segments) do
      {ast, [qualified_reference(module_node, function, dot_meta) | references]}
    else
      {ast, references}
    end
  end

  defp traverse(ast, references, _module_segments), do: {ast, references}

  defp import_reference(keyword, {:__aliases__, _, module}, meta) do
    display = "#{keyword} #{Enum.join(module, ".")}"
    reference(display, display, meta)
  end

  # An `Elixir.`-prefixed atom module (`import :"Elixir.Ecto.Query"`) has no
  # contiguous "keyword Module" substring in the source — the atom's quoting
  # interrupts it — so there is no meaningful trigger token to point at, even
  # though the message can still name the module.
  defp import_reference(keyword, module, meta) when is_atom(module) do
    reference(Issue.no_trigger(), "#{keyword} #{module}", meta)
  end

  defp qualified_reference({:__aliases__, alias_meta, module}, function, _dot_meta) do
    display = "#{Enum.join(module, ".")}.#{function}"
    reference(display, display, alias_meta)
  end

  defp qualified_reference(module, function, dot_meta) when is_atom(module) do
    reference(Issue.no_trigger(), "#{module}.#{function}", dot_meta)
  end

  defp reference(trigger, display, meta),
    do: %{trigger: trigger, display: display, line_no: meta[:line], column: meta[:column]}

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{reference.display} found — query composition belongs in the schema module (by_*/join_* fragments); let the context orchestrate instead",
      trigger: reference.trigger,
      line_no: reference.line_no,
      column: reference.column
    )
  end
end
