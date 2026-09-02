defmodule MikaCredoRules.NoDirectFunWithFlags do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      functions: [:enabled?, :get_flag, :all_flags, :all_flag_names],
      allowed_paths: ["feature_flags", "feature_flag"],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming `FunWithFlags` read functions to ban. Defaults to
        `[:enabled?, :get_flag, :all_flags, :all_flag_names]`.
        """,
        allowed_paths: """
        A list of path fragments naming where the app's own feature-flag
        wrapper module is expected to live. An entry with no `/` (e.g.
        `"feature_flags"`) matches at a whole path-segment boundary
        (`lib/my_app/feature_flags/manager.ex`), as a file basename with its
        extension stripped (`lib/my_app/feature_flags.ex`), OR as a
        segment-name suffix (`lib/my_app_feature_flag/manager.ex`,
        `lib/my_app/legacy_feature_flags.ex`) — all three forms apply to
        every such entry. An entry containing `/` matches only as a literal,
        consecutive run of whole path segments. A file matching any entry is
        exempt. Defaults to `["feature_flags", "feature_flag"]`.
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
  `FunWithFlags` must be read through the app's own feature-flag wrapper
  module, never directly from application code. `FunWithFlags` matches a flag
  by atom identity — a typo'd flag name (`:new_checkot` vs `:new_checkout`)
  scattered across call sites silently returns `false` at every one of them,
  instead of being caught in the one place a wrapper module would centralize
  the name.

      # BAD — reads FunWithFlags directly from a context
      defmodule MyApp.Courses do
        def new_checkout_visible?(user) do
          FunWithFlags.enabled?(:new_checkout, for: user)
        end
      end

      # GOOD — routed through the app's own feature-flag wrapper module
      defmodule MyApp.Courses do
        def new_checkout_visible?(user) do
          MyApp.FeatureFlags.new_checkout_visible?(user)
        end
      end

  An explicit `alias FunWithFlags` still fires the same way, since the alias
  resolves the bare name right back to the library it names:

      # BAD — an explicit alias still resolves to the banned module
      defmodule MyApp.Courses do
        alias FunWithFlags

        def new_checkout_visible?(user) do
          FunWithFlags.enabled?(:new_checkout, for: user)
        end
      end

  `FunWithFlags` is a single-segment name, so unlike a namespaced module it
  can be shadowed by a module locally defined in the same file. A nested
  `defmodule FunWithFlags do ... end` deregisters the bare name for the rest
  of that file — every later bare `FunWithFlags.enabled?(...)` then resolves
  to the local module, not the library, and stays silent:

      # GOOD — a locally defined FunWithFlags module shadows the banned name
      defmodule MyApp.CourseFlagStub do
        defmodule FunWithFlags do
          def enabled?(_flag, _opts), do: true
        end

        def new_checkout_visible?(user) do
          FunWithFlags.enabled?(:new_checkout, for: user)
        end
      end

  Files under `:allowed_paths` (default `["feature_flags", "feature_flag"]`)
  are exempt — that is where the wrapper module itself is expected to live,
  whether as a single file (`lib/my_app/feature_flags.ex`) or a directory
  (`lib/my_app/feature_flags/manager.ex`, `lib/my_app_feature_flag/manager.ex`).
  Test files (`:excluded_paths`, default `["_test.exs", "test/"]`) are exempt
  too.

  ## Limitations

  Only a literal `FunWithFlags.function(...)` call, alias-aware, is
  recognised. A `FunWithFlags` value held in a variable or module attribute
  (`flags = FunWithFlags; flags.enabled?(:x)`),
  `apply(FunWithFlags, :enabled?, [:x])`, and a bare call reached via `import
  FunWithFlags` are all undetected.

  A project module is exempted purely by module identity, never by name
  resemblance — `MyApp.FeatureFlags.enabled?(:x)` stays silent because its
  module segments are not `FunWithFlags`, regardless of what its own name
  contains.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack, and an alias injected by a macro (via `__using__`) is
  invisible to Credo and cannot be resolved.

  The default `:functions` list covers only `FunWithFlags`'s read API —
  `enable/1,2`, `disable/1,2`, and `clear/1,2` (the mutating half of the API)
  are not banned by default. Add them to `:functions` if your app wants
  writes routed through the wrapper too.

  Only the bare `FunWithFlags` spelling can be shadowed by a local
  `defmodule` — the fully-qualified `Elixir.FunWithFlags` spelling always
  still fires, the same as an unshadowed alias.

  The segment-suffix form of `:allowed_paths` is name-based, not
  content-based — any path segment or basename merely ENDING in
  `feature_flag`/`feature_flags` is exempt, whether or not that file is
  actually the wrapper (`lib/my_app_web/live/course_feature_flag.ex` is
  silently exempt the same as the real wrapper module).
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

  # Two independent, boundary-safe match shapes, checked against a version of
  # the path with the file's extension stripped — the app's feature-flag
  # wrapper is as likely to be a single file (`lib/my_app/feature_flags.ex`)
  # as a directory (`lib/my_app/feature_flags/manager.ex`), and without
  # stripping the extension, neither the literal-segment match nor the
  # segment-suffix match could ever match the basename of a plain file
  # (`"feature_flags.ex"` is not the segment `"feature_flags"`, and does not
  # END with `"feature_flags"` either — it ends with `".ex"`).
  defp allowed_path?(filename, allowed_paths) do
    path_no_ext = Path.rootname(filename)
    segments = String.split(path_no_ext, "/")

    Enum.any?(allowed_paths, &segment_path_match?(segments, &1)) or
      SourceFilter.matches_segment_suffix?(path_no_ext, allowed_paths)
  end

  # Matches `allowed_path` as a literal, consecutive run of whole path
  # segments — boundary-safe on both ends since segments are compared for
  # equality, never substring-contained. A leading/trailing "/" on
  # `allowed_path` is ignored.
  defp segment_path_match?(segments, allowed_path) do
    fragment_segments = allowed_path |> String.trim("/") |> String.split("/")
    fragment_length = length(fragment_segments)

    segments
    |> Enum.chunk_every(fragment_length, 1, :discard)
    |> Enum.any?(&(&1 === fragment_segments))
  end

  defp build_context(source_file, params) do
    resolved = AstHelpers.resolve_aliases(source_file, [FunWithFlags])

    %{
      modules:
        if(shadowed_by_defmodule?(source_file), do: resolved -- [[:FunWithFlags]], else: resolved),
      functions: Params.get(params, :functions, __MODULE__)
    }
  end

  # `FunWithFlags` is a single-segment name, the one shape `resolve_aliases/2`
  # cannot shadow on its own — a locally nested `defmodule FunWithFlags do
  # ... end` emits the same bare `[:FunWithFlags]` AST as a reference to the
  # library, and deregisters the name for the rest of the file the same way a
  # shadowing `alias` would, per `AstHelpers.defined_module_names/1`.
  defp shadowed_by_defmodule?(source_file) do
    [:FunWithFlags] in AstHelpers.defined_module_names(source_file)
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

  # The `Elixir.FunWithFlags` bare-atom spelling of the module — a plain atom
  # in the module slot, not an `__aliases__` node (an erlang module call
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
          # spelling (`:"Elixir.FunWithFlags"`), so only the function name
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
        "#{call.trigger} found — call through your app's feature-flag wrapper module instead of FunWithFlags directly",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
