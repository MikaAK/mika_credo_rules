defmodule MikaCredoRules.SourceFilter do
  @moduledoc """
  Pure filename predicates shared by the scoping guards of every check.

  Checks must scope themselves inside `run/2` against `source_file.filename` —
  the `files:` param is pruned at Credo's pipeline level, which `Credo.Test.Case`
  bypasses entirely, so a check scoped only by `files:` passes its whole suite
  while doing nothing in production. These predicates are the single shared
  implementation for that `run/2` guard.

  No AST, no Credo types — strings in, boolean out.
  """

  @doc """
  True when `filename` ends with any of `suffixes`.

  Suffix matching is inherently boundary-safe — use it for whole-file-name
  scoping params such as `config_files` and `test_files`.

      iex> MikaCredoRules.SourceFilter.matches_suffix?("test/worker_test.exs", ["_test.exs"])
      true

      iex> MikaCredoRules.SourceFilter.matches_suffix?("test/support/factory.ex", ["_test.exs"])
      false
  """
  @spec matches_suffix?(String.t(), [String.t()]) :: boolean()
  def matches_suffix?(filename, suffixes) do
    Enum.any?(suffixes, &String.ends_with?(filename, &1))
  end

  @doc """
  True when `filename` matches any of `fragments` at a path-segment boundary.

  A fragment matches when the path starts with it, ends with it, or contains it
  immediately after a `/`. Naive `String.contains?/2` is wrong here and has
  already shipped a bug: `"lib/latest/helpers.ex"` contains the substring
  `"test/"` (inside `"la-test/"`), so a naive exclusion on `"test/"` silently
  disables a check on a real lib file. Same class: `"web/"` matches
  `webhooks/`, `"mix/tasks/"` matches `vendor/remix/tasks/`.

      iex> MikaCredoRules.SourceFilter.matches_fragment?("lib/mix/tasks/deploy.ex", ["mix/tasks/"])
      true

      iex> MikaCredoRules.SourceFilter.matches_fragment?("lib/vendor/remix/tasks/thing.ex", ["mix/tasks/"])
      false
  """
  @spec matches_fragment?(String.t(), [String.t()]) :: boolean()
  def matches_fragment?(filename, fragments) do
    Enum.any?(fragments, &fragment_matches?(filename, &1))
  end

  @doc """
  True when `filename`'s basename exactly equals one of `names`.

  Some whole-filenames are only safe to match by basename, not suffix — a
  suffix like `"mix.exs"` also matches `"lib/remix.exs"` (an ordinary module
  that happens to end the same way), and `matches_fragment?/2`'s
  `ends_with?` branch has the identical flaw for any fragment lacking a
  leading path separator. Use this for filenames with no natural boundary
  character before them, such as `mix.exs`.

      iex> MikaCredoRules.SourceFilter.matches_basename?("apps/my_app/mix.exs", ["mix.exs"])
      true

      iex> MikaCredoRules.SourceFilter.matches_basename?("lib/remix.exs", ["mix.exs"])
      false
  """
  @spec matches_basename?(String.t(), [String.t()]) :: boolean()
  def matches_basename?(filename, names) do
    Path.basename(filename) in names
  end

  @doc """
  True when `filename` is an Elixir script (`.exs`) — mix.exs, config, tests.
  """
  @spec script_file?(String.t()) :: boolean()
  def script_file?(filename), do: String.ends_with?(filename, ".exs")

  defp fragment_matches?(filename, fragment) do
    String.ends_with?(filename, fragment) or String.starts_with?(filename, fragment) or
      String.contains?(filename, "/#{fragment}")
  end
end
