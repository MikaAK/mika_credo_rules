defmodule MikaCredoRules.CredoConfigNamedDefault do
  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [
      config_files: [".credo.exs"],
      allowed_names: ["default"]
    ],
    explanations: [
      params: [
        config_files: """
        A list of file path suffixes treated as Credo config files.

        Defaults to `[".credo.exs"]`, which matches the standard config file
        name and any additional named profile that follows the same
        `*.credo.exs` convention (e.g. `strict.credo.exs`).
        """,
        allowed_names: """
        Config names Credo will actually select without an explicit
        `--config-name` flag. Defaults to `["default"]`, Credo's own
        selection default.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A `.credo.exs` must have a config named `"default"` (or one of
  `:allowed_names`).

  `mix credo` selects the config named `"default"` unless `--config-name` is
  passed. If no config in the file has that name, Credo silently falls back
  to its own stock checks — printing a green run that executed none of the
  checks this file defines.

      # BAD — no config is named "default"; Credo silently runs its own defaults
      %{
        configs: [
          %{
            name: "mika",
            checks: []
          }
        ]
      }

      # GOOD — a config named "default" exists
      %{
        configs: [
          %{
            name: "default",
            checks: []
          }
        ]
      }

  Only the literal `%{configs: [...]}` shape is inspected. A `.credo.exs`
  that builds its config dynamically (e.g. `Code.eval_file/1`, a function
  call) is skipped — this check can only verify what it can parse
  statically, and a dynamic file is not a false positive risk the same way a
  naive scan would be.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    config_files = Params.get(params, :config_files, __MODULE__)

    if SourceFilter.matches_suffix?(source_file.filename, config_files) do
      allowed_names = Params.get(params, :allowed_names, __MODULE__)
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, allowed_names))
      |> Enum.map(&issue_for(&1, issue_meta, allowed_names))
    else
      []
    end
  end

  defp traverse({:%{}, meta, pairs} = ast, line_nos, allowed_names) do
    case Keyword.fetch(pairs, :configs) do
      {:ok, configs} when is_list(configs) ->
        if named_default?(configs, allowed_names) do
          {nil, line_nos}
        else
          {nil, [meta[:line] | line_nos]}
        end

      _ ->
        {ast, line_nos}
    end
  end

  defp traverse(ast, line_nos, _allowed_names), do: {ast, line_nos}

  defp named_default?(configs, allowed_names) do
    Enum.any?(configs, fn
      {:%{}, _, pairs} -> Keyword.get(pairs, :name) in allowed_names
      _ -> false
    end)
  end

  defp issue_for(line_no, issue_meta, allowed_names) do
    format_issue(issue_meta,
      message:
        "configs: found — no config is named #{inspect(allowed_names)}; Credo silently " <>
          "falls back to its own stock checks and reports a green run that executed none " <>
          "of these",
      trigger: "configs:",
      line_no: line_no
    )
  end
end
