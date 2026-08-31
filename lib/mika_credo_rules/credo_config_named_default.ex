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
  naive scan would be. A `name:` that isn't a string literal (a variable, a
  module attribute, an interpolation) is treated the same way: the config it
  belongs to counts as a possible `"default"` rather than being flagged,
  since the check cannot evaluate it.

  ## Limitations

  A `configs:` key is matched wherever it appears in the file, not only at
  the top level — an unrelated nested map that happens to carry a
  `configs:` key of its own (e.g. while assembling several named profiles
  before merging them) is treated as if it were the real Credo config.
  Likewise, a `configs:` list built with the cons operator
  (`[%{name: "default"} | rest]`) is not walked into, so a `"default"` entry
  hidden behind `|` goes unseen and the file is flagged as missing one even
  though it isn't. Write `configs:` as a plain list literal to avoid this.
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
    Enum.any?(configs, &config_matches_allowed_name?(&1, allowed_names))
  end

  defp config_matches_allowed_name?({:%{}, _, pairs}, allowed_names) do
    case Keyword.get(pairs, :name) do
      name when is_binary(name) -> name in allowed_names
      _non_literal -> true
    end
  end

  defp config_matches_allowed_name?(_other, _allowed_names), do: false

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
