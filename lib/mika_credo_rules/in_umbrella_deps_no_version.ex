defmodule MikaCredoRules.InUmbrellaDepsNoVersion do
  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      mix_files: ["mix.exs"]
    ],
    explanations: [
      params: [
        mix_files: """
        A list of filenames treated as mix.exs files. Matched against the
        source file's **basename**, not a path suffix — `"mix.exs"` must not
        match `lib/remix.exs`, an ordinary module that happens to end with
        the same characters.
        """
      ]
    ]

  alias MikaCredoRules.MixDepsAst
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  An `in_umbrella: true` dependency must not also pin a version requirement.

  An in-umbrella dependency is resolved from the sibling app's own `mix.exs`,
  never from Hex — a version requirement on it is dead weight that can drift
  from the sibling's actual version and never gets enforced.

      # BAD — the version requirement is never checked against anything
      defp deps do
        [
          {:shared_utils, "~> 0.1", in_umbrella: true}
        ]
      end

      # GOOD — the sibling app's own mix.exs is the only source of truth
      defp deps do
        [
          {:shared_utils, in_umbrella: true}
        ]
      end

  Only the 3-tuple form (`{:app, requirement, opts}`) can trigger this — a
  2-tuple `{:app, in_umbrella: true}` has no version slot to remove.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    mix_files = Params.get(params, :mix_files, __MODULE__)

    if SourceFilter.matches_basename?(source_file.filename, mix_files) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> MixDepsAst.deps()
      |> Enum.filter(&versioned_in_umbrella?/1)
      |> Enum.map(&issue_for(&1, issue_meta))
    else
      []
    end
  end

  defp versioned_in_umbrella?(%{requirement: requirement, opts: opts}) do
    is_binary(requirement) and Keyword.get(opts, :in_umbrella) === true
  end

  defp issue_for(dep, issue_meta) do
    trigger = ":#{dep.pkg}"

    format_issue(issue_meta,
      message:
        "#{trigger} in_umbrella dep pins a version requirement found — remove it, " <>
          "e.g. {#{trigger}, in_umbrella: true}",
      trigger: trigger,
      line_no: dep.line_no
    )
  end
end
