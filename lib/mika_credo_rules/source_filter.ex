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
  True when any path segment of `filename` ends with any of `suffixes`.

  This is the matcher for directory-NAME suffixes — app directories that follow
  a naming convention (`*_api`, `*_web`, `*_icons`) rather than containing a
  literal directory. `matches_fragment?/2` cannot express this: its
  middle-of-path branch requires the fragment to start a segment, so `"_api/"`
  only ever matches a directory literally named `_api`, never `tiingo_api`.

  Segments are pre-split on `/`, so matching is naturally boundary-safe — a
  suffix never matches across a segment boundary or inside a basename's
  extension. A trailing `/` on a suffix is trimmed.

      iex> MikaCredoRules.SourceFilter.matches_segment_suffix?("apps/tiingo_api/lib/client.ex", ["_api"])
      true

      iex> MikaCredoRules.SourceFilter.matches_segment_suffix?("lib/vendor/rest_api_notes/x.ex", ["_api"])
      false
  """
  @spec matches_segment_suffix?(String.t(), [String.t()]) :: boolean()
  def matches_segment_suffix?(filename, suffixes) do
    segments = String.split(filename, "/")

    Enum.any?(suffixes, fn suffix ->
      trimmed = String.trim_trailing(suffix, "/")

      Enum.any?(segments, &String.ends_with?(&1, trimmed))
    end)
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
