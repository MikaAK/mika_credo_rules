defmodule MikaCredoRules.NoFunWithFlagsMutationInTests do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:enable, :disable, :clear],
      included_paths: ["_test.exs", "test/"],
      wrapper_suffixes: ["FeatureFlags"],
      excluded_paths: []
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the mutating `FunWithFlags` functions to flag.
        Defaults to `[:enable, :disable, :clear]` — `enabled?/1` and
        `get_flag/1` are reads, not mutations, and are never in this list. A
        non-list value is wrapped as a single-element list.
        """,
        included_paths: """
        A list of path fragments identifying test files, matched at a
        path-segment boundary (see `SourceFilter.matches_fragment?/2`). The
        check runs ONLY on a file that matches one of these — unlike the
        checks scoped by `excluded_paths`, and in line with the `test_files`
        scoping of the other test-only checks, since a `FunWithFlags`
        mutation outside a test is the library working as intended, not a
        bug. Defaults to `["_test.exs", "test/"]`. A non-list value is
        wrapped as a single-element list.
        """,
        wrapper_suffixes: """
        A list of suffixes identifying a project's own flag facade by the
        last segment of the module named at the call site, in addition to
        `FunWithFlags` itself — a wrapper mutates the same global store
        underneath. Defaults to `["FeatureFlags"]`. A non-list value is
        wrapped as a single-element list.
        """,
        excluded_paths: """
        A list of path fragments (matched the same way as `:included_paths`)
        naming test files this check skips even though they match
        `:included_paths` — the escape hatch for a suite that installs its
        own per-process flag sandbox, where the mutation never reaches the
        shared store this check exists to protect (see `## Limitations`).
        Defaults to `[]`. A non-list value is wrapped as a single-element
        list.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  `FunWithFlags.enable/disable/clear` mutate GLOBAL flag state — never call
  them directly in a test.

  `FunWithFlags` persists flags in a store shared by the whole test run
  (often Redis- or Ecto-backed), not per-process. A test that flips a flag
  leaks that change into whatever else runs concurrently, poisoning any other
  `async: true` test that happens to check the same flag.

      # BAD — leaks into every other async test
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          FunWithFlags.enable(:beta_banner)
          assert MyApp.Banner.visible?()
        end
      end

      # GOOD — the code under test takes the flag as an argument
      defmodule MyApp.BannerTest do
        test "shows the beta banner" do
          assert MyApp.Banner.visible?(beta_banner: true)
        end
      end

  A project's own flag facade (`MyApp.FeatureFlags.enable/1`, say) mutates the
  same underlying store and is caught too, via the `:wrapper_suffixes` param —
  a module is a wrapper when the last segment named at the call site ends
  with one of those suffixes, aliased or fully qualified.

  A suite that installs its own per-process flag sandbox — a mock adapter
  keyed on the test's `self()`, the pattern a flag facade's own test suite
  typically uses to test its own `enable/1`/`disable/1`/`clear/1` wrappers —
  never reaches the shared store this check exists to protect, and is a
  deliberate false positive here (see `## Limitations`). Add that file, or
  its directory, to `:excluded_paths` to silence it.

  Only test files are in scope, identified via `:included_paths` — unlike the
  checks scoped by `excluded_paths`, and in line with the `test_files`
  scoping of the other test-only checks, since a `FunWithFlags` mutation in
  `lib/` code (an admin action, a migration task) is the library doing its
  job, not a violation.

  ## Limitations

    * A suite that installs its own per-process flag sandbox (a mock adapter
      keyed on `self()`) is a known false positive — the mutation is
      process-local, so it never poisons another async test, and "inject the
      flag value into the code under test instead" does not apply when the
      flag store itself is the code under test. This is the shape of a flag
      facade's own test suite, testing its own `enable/1`/`disable/1`/`clear/1`
      wrappers. Add the file, or its directory, to `:excluded_paths`, or use
      `# credo:disable-for-this-file MikaCredoRules.NoFunWithFlagsMutationInTests`
      inline.
    * `apply(FunWithFlags, :enable, [:foo])` is invisible — this check only
      matches the `Module.function(args)` call shape, not dynamic dispatch.
    * Module identity is a naming heuristic on the last segment written at the
      call site, not full alias resolution — a wrapper injected as a
      dependency (`@flags.enable(:foo)`) or renamed via `as:` to drop its
      suffix is invisible, and an unrelated local module that happens to
      share a wrapper suffix would be a false positive.
    * A call rooted in `__MODULE__` or `unquote/1` (e.g.
      `__MODULE__.FeatureFlags.enable(:x)`, or `unquote(mod).FeatureFlags.enable(:x)`
      inside a `quote` block) is invisible — module identity is read off the
      raw `__aliases__` segments, which are atoms only for a literal alias
      path.
    * The Elixir-prefixed atom spelling (`:"Elixir.FunWithFlags".enable(:foo)`)
      is invisible — only the `__aliases__` call shape is matched, not a bare
      atom in the module slot.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if checked_path?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp checked_path?(filename, params) do
    SourceFilter.matches_fragment?(filename, included_paths(params)) and
      not SourceFilter.matches_fragment?(filename, excluded_paths(params))
  end

  defp included_paths(params), do: List.wrap(Params.get(params, :included_paths, __MODULE__))
  defp excluded_paths(params), do: List.wrap(Params.get(params, :excluded_paths, __MODULE__))

  defp build_context(params) do
    %{
      functions: List.wrap(Params.get(params, :functions, __MODULE__)),
      wrapper_suffixes: List.wrap(Params.get(params, :wrapper_suffixes, __MODULE__))
    }
  end

  defp traverse(
         {{:., _, [{:__aliases__, alias_meta, module}, function]}, _meta, args} = ast,
         mutations,
         context
       )
       when is_list(args) do
    if function in context.functions and fun_with_flags_module?(module, context.wrapper_suffixes) do
      {ast, [flag_mutation(module, function, alias_meta) | mutations]}
    else
      {ast, mutations}
    end
  end

  defp traverse(ast, mutations, _context), do: {ast, mutations}

  defp fun_with_flags_module?(module, wrapper_suffixes) do
    Enum.all?(module, &is_atom/1) and
      (last_segment(module) === "FunWithFlags" or
         Enum.any?(wrapper_suffixes, &String.ends_with?(last_segment(module), &1)))
  end

  defp last_segment(module), do: module |> List.last() |> Atom.to_string()

  defp flag_mutation(module, function, meta) do
    %{
      trigger: "#{Enum.join(module, ".")}.#{function}",
      line_no: meta[:line],
      column: meta[:column]
    }
  end

  defp issue_for(mutation, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{mutation.trigger} found — mutates global flag state, poisoning other async tests; inject the flag value into the code under test instead",
      trigger: mutation.trigger,
      line_no: mutation.line_no,
      column: mutation.column
    )
  end
end
