defmodule MikaCredoRules.MixDepsAst do
  @moduledoc """
  Shared parsing of dependency tuples out of a `deps/0` function
  (`defp deps do [...] end` or `def deps do [...] end`) for every
  mix.exs-scoped check.

  Only the standard 2-tuple (`{:pkg, requirement}` or `{:pkg, opts}`) and
  3-tuple (`{:pkg, requirement, opts}`) shapes are recognised. A `deps/0`
  body that is not a literal list (built by calling another function,
  concatenating lists, etc.) yields no entries — dynamic composition is out
  of scope, not a false positive risk.

  ## Line numbers

  A 3-tuple dep is quoted as `{:{}, meta, [pkg, requirement, opts]}` and
  always carries `meta[:line]`. A 2-tuple dep is a **bare tuple literal** —
  Elixir's quoting only wraps tuples of arity other than 2 in `:{}`, so a
  2-element tuple carries no AST metadata at all. `line_no/2` resolves the
  bare case with a raw source scan for the package's atom text.
  """

  @type dep :: %{
          pkg: atom(),
          requirement: String.t() | nil,
          opts: keyword(),
          line_no: pos_integer() | nil
        }

  @doc """
  Every dependency tuple declared in `source_file`'s `deps/0` function.
  """
  @spec deps(Credo.SourceFile.t()) :: [dep()]
  def deps(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_deps_function/2)
    |> List.flatten()
  end

  @doc """
  The line number of `dep` inside `source_file`.

  Returns the AST-derived line when the tuple already carried one (the
  3-tuple form), otherwise falls back to a scan of `source_file`'s source
  for the opening `{:pkg` of the dependency tuple, with comments, strings,
  charlists, and sigils blanked out first so neither a `plt_add_apps:` list
  naming the same atom nor a comment referencing an old pin can outrank the
  real declaration.

  ## Limitations

  The same package declared twice as 2-tuples still resolves to the first
  occurrence — there is no way to disambiguate duplicate bare-tuple
  declarations from source text alone.
  """
  @spec line_no(dep(), Credo.SourceFile.t()) :: pos_integer() | nil
  def line_no(%{line_no: line_no}, _source_file) when not is_nil(line_no), do: line_no

  def line_no(%{pkg: pkg}, source_file) do
    pattern = ~r/\{\s*:#{Regex.escape(to_string(pkg))}\b/

    source_file
    |> Credo.Code.clean_charlists_strings_sigils_and_comments()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line, line_no} -> if line =~ pattern, do: line_no end)
  end

  defp collect_deps_function({function, _, [{:deps, _, _args}, [{:do, body} | _]]} = ast, acc)
       when function in [:def, :defp] do
    {ast, [extract_dep_tuples(body) | acc]}
  end

  defp collect_deps_function(ast, acc), do: {ast, acc}

  defp extract_dep_tuples(body) when is_list(body) do
    body |> Enum.map(&normalize_dep_tuple/1) |> Enum.reject(&is_nil/1)
  end

  defp extract_dep_tuples(_body), do: []

  defp normalize_dep_tuple({:{}, meta, [pkg, requirement, opts]})
       when is_atom(pkg) and is_binary(requirement) and is_list(opts) do
    %{pkg: pkg, requirement: requirement, opts: opts, line_no: meta[:line]}
  end

  defp normalize_dep_tuple({pkg, requirement}) when is_atom(pkg) and is_binary(requirement) do
    %{pkg: pkg, requirement: requirement, opts: [], line_no: nil}
  end

  defp normalize_dep_tuple({pkg, opts}) when is_atom(pkg) and is_list(opts) do
    %{pkg: pkg, requirement: nil, opts: opts, line_no: nil}
  end

  defp normalize_dep_tuple(_other), do: nil
end
