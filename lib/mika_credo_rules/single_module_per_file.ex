defmodule MikaCredoRules.SingleModulePerFile do
  use Credo.Check,
    base_priority: :normal,
    category: :design,
    param_defaults: [excluded_paths: ["test/", "test/support/", "_test.exs"]],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments and filename suffixes exempt from the check.
        A source file is exempt when its path starts or ends with an entry, or
        contains one after a `/` — matching happens on path-segment boundaries,
        so `test/` does not exempt `lib/latest/`. Filename suffixes such as
        `_test.exs` match through the ends-with half, so this one param covers
        both directory and suffix exclusion.

        Defaults to `["test/", "test/support/", "_test.exs"]` — sibling
        test-helper modules are idiomatic in test files.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  One top-level module per file — a second sibling module gets its own file.

  A file that defines several top-level modules causes cyclic compilation
  dependencies: the modules recompile together, so anything depending on one
  of them is recompiled whenever any co-located module changes, and mutual
  references between the co-located modules can grow into cycles the compiler
  cannot split apart.

      # BAD — two sibling modules in one file
      defmodule MyApp.Worker do
        def run, do: :ok
      end

      defmodule MyApp.WorkerSupervisor do
        def start_link, do: :ok
      end

      # GOOD — exactly one top-level module per file
      defmodule MyApp.Worker do
        def run, do: :ok
      end

      # GOOD — a nested module belongs to its parent and is never flagged
      defmodule MyApp.Worker do
        defmodule State do
          defstruct [:status]
        end

        def run, do: :ok
      end

  Only top-level `defmodule`s count: a module nested inside another module is
  part of its parent and is never flagged. `defimpl` and `defprotocol` are not
  `defmodule` and are never flagged, and `defmodule` inside a `quote` block is
  skipped — a macro that generates a module defines it at the call site, not
  in this file.

  Test files are excluded by default (`test/`, `test/support/`, and the
  `_test.exs` suffix via `:excluded_paths`) — sibling test-helper modules are
  idiomatic there.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse/2)
      |> Enum.reverse()
      |> Enum.drop(1)
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # `quote do defmodule ... end` defines a module at the macro's call site,
  # not in this file — don't descend into quoted code.
  defp traverse({:quote, _, args}, modules) when is_list(args) do
    {nil, modules}
  end

  # Pruning the defmodule subtree keeps the count to TOP-LEVEL modules only —
  # a module nested inside another is part of its parent, never flagged.
  defp traverse({:defmodule, meta, [name | _]}, modules) do
    {nil, [%{name: Macro.to_string(name), line_no: meta[:line]} | modules]}
  end

  defp traverse(ast, modules), do: {ast, modules}

  defp issue_for(module, issue_meta) do
    format_issue(issue_meta,
      message: "multiple modules in one file found — move #{module.name} to its own file",
      trigger: "defmodule",
      line_no: module.line_no
    )
  end
end
