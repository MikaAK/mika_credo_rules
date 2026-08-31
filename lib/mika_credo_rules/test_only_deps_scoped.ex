defmodule MikaCredoRules.TestOnlyDepsScoped do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      mix_files: ["mix.exs"],
      test_only_packages: [
        :wallaby,
        :credo,
        :dialyxir,
        :mix_test_watch,
        :excoveralls,
        :ex_doc,
        :mika_credo_rules
      ],
      require_runtime_false: [:wallaby, :credo, :dialyxir, :ex_doc, :mika_credo_rules]
    ],
    explanations: [
      params: [
        mix_files: """
        A list of filenames treated as mix.exs files. Matched against the
        source file's **basename**, not a path suffix — `"mix.exs"` must not
        match `lib/remix.exs`, an ordinary module that happens to end with
        the same characters.
        """,
        test_only_packages: """
        Packages that must never load in a release build — every dep tuple
        for one of these must carry an `only:` option.
        """,
        require_runtime_false: """
        Packages that compile the project but must never start at runtime —
        every dep tuple for one of these must carry `runtime: false`.
        """
      ]
    ]

  alias MikaCredoRules.MixDepsAst
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A dev/test-only dependency must be scoped so it never ships to a release.

  A tool like `:credo` or `:ex_doc` has no business running in production —
  omitting `only:` pulls it (and its own transitive deps) into every
  environment, and omitting `runtime: false` on a compile-time-only tool lets
  it try to start an application that was never meant to run.

      # BAD — no only:, ships to every environment
      defp deps do
        [
          {:credo, "~> 1.7"}
        ]
      end

      # GOOD — scoped to the environments it's actually needed in
      defp deps do
        [
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
          {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
        ]
      end

  `:test_only_packages` and `:require_runtime_false` are checked
  independently — a package on both lists (e.g. `:wallaby`) missing both
  options is reported twice, once per missing option. `only: :dev`, `only:
  :test`, and `only: [:dev, :test]` all satisfy the first check; any
  2-tuple, 3-tuple, or opts-only (git/path) dep shape is recognised.

  ## Limitations

  The `only:` check only rejects values that still include `:prod` (a bare
  `only: :prod` or a list containing it) — it does not validate against a
  fixed list of "real" environments. An unconventional atom like
  `only: :nonsense` satisfies the check just as well as `only: :test`,
  because both keep the dependency out of a production release, which is
  the only invariant this check actually protects.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    mix_files = Params.get(params, :mix_files, __MODULE__)

    if SourceFilter.matches_basename?(source_file.filename, mix_files) do
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(params)

      source_file
      |> MixDepsAst.deps()
      |> Enum.flat_map(&issues_for_dep(&1, source_file, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp build_context(params) do
    %{
      test_only_packages: Params.get(params, :test_only_packages, __MODULE__),
      require_runtime_false: Params.get(params, :require_runtime_false, __MODULE__)
    }
  end

  defp issues_for_dep(dep, source_file, context) do
    []
    |> maybe_flag_missing_only(dep, source_file, context)
    |> maybe_flag_missing_runtime_false(dep, source_file, context)
  end

  defp maybe_flag_missing_only(issues, dep, source_file, context) do
    if dep.pkg in context.test_only_packages and missing_only_scoping?(dep) do
      [violation(dep, source_file, :only) | issues]
    else
      issues
    end
  end

  defp missing_only_scoping?(dep) do
    case Keyword.get(dep.opts, :only) do
      nil -> true
      :prod -> true
      envs when is_list(envs) -> :prod in envs
      _other -> false
    end
  end

  defp maybe_flag_missing_runtime_false(issues, dep, source_file, context) do
    if dep.pkg in context.require_runtime_false and Keyword.get(dep.opts, :runtime) !== false do
      [violation(dep, source_file, :runtime) | issues]
    else
      issues
    end
  end

  defp violation(dep, source_file, kind) do
    %{pkg: dep.pkg, kind: kind, line_no: MixDepsAst.line_no(dep, source_file)}
  end

  defp issue_for(%{kind: :only} = violation, issue_meta) do
    trigger = ":#{violation.pkg}"

    format_issue(issue_meta,
      message:
        "#{trigger} missing only: found — dev/test-only dependency #{trigger} must be scoped " <>
          "with only: :dev, only: :test, or only: [:dev, :test]",
      trigger: trigger,
      line_no: violation.line_no
    )
  end

  defp issue_for(%{kind: :runtime} = violation, issue_meta) do
    trigger = ":#{violation.pkg}"

    format_issue(issue_meta,
      message:
        "#{trigger} missing runtime: false found — #{trigger} must not load at runtime; " <>
          "add runtime: false",
      trigger: trigger,
      line_no: violation.line_no
    )
  end
end
