defmodule MikaCredoRules.NoAtomStringKeyFallback do
  use Credo.Check,
    base_priority: :high,
    category: :warning

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  Reading the same key under both spellings (`params["id"] || params[:id]`)
  must not be used — normalize the map's keys at its boundary instead.

  A map with mixed atom/string keys has no reliable shape: every read site has
  to guess, the fallback gets copy-pasted everywhere the map is read, and any
  site that forgets it becomes a bug. Converting the keys once, where the data
  enters the system, makes every read after that unambiguous.

      # BAD — every read site guesses at the map's shape
      Map.get(payload, "link") || Map.get(payload, :link)
      params["id"] || params[:id]

      # GOOD — normalize once at the context boundary, read plainly after
      def handle_webhook(payload) do
        payload = payload_keys_to_strings(payload)

        payload["link"]
      end

  A fallback is reported when both sides of a `||` read the same subject with
  literal counterpart keys — one atom and one string spelling the same name —
  in either order. `Map.get/2`, `Map.get/3`, and bracket access all count, in
  any combination, including adjacent reads inside a chained fallback.

  Different key names (`params[:id] || params[:uuid]`), same-type keys,
  different subjects, and plain lookup-or-default (`params["id"] || %{}`) are
  never flagged.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    map_modules = AstHelpers.resolve_aliases(source_file, [Map])

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, map_modules))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  # `||` chains nest — `a || b || c` parses as `(a || b) || c`, and explicit
  # parens can nest the other way — so the operands adjacent at this `||` are
  # the rightmost leaf of its left subtree and the leftmost leaf of its right.
  defp traverse({:||, meta, [left, right]} = ast, fallbacks, map_modules) do
    if mixed_key_fallback?(spine_tail(left), spine_head(right), map_modules) do
      {ast, [%{line_no: meta[:line], column: meta[:column]} | fallbacks]}
    else
      {ast, fallbacks}
    end
  end

  defp traverse(ast, fallbacks, _map_modules), do: {ast, fallbacks}

  defp spine_tail({:||, _, [_left, right]}), do: spine_tail(right)
  defp spine_tail(ast), do: ast

  defp spine_head({:||, _, [left, _right]}), do: spine_head(left)
  defp spine_head(ast), do: ast

  defp mixed_key_fallback?(left, right, map_modules) do
    case {lookup(left, map_modules), lookup(right, map_modules)} do
      {{left_subject, left_key}, {right_subject, right_key}} ->
        counterpart_keys?(left_key, right_key) and
          strip_meta(left_subject) === strip_meta(right_subject)

      _lookups ->
        false
    end
  end

  # `subject[key]` — bracket access desugars to a dot-call with the bare
  # `Access` atom in the module slot, not an `__aliases__` node.
  defp lookup({{:., _, [Access, :get]}, _, [subject, key]}, _map_modules) do
    {subject, key}
  end

  # `Map.get(subject, key)` / `Map.get(subject, key, default)` — only on Map
  # itself or an alias of it (`alias Map, as: M`), never on a project module
  # shadowing the name (`alias MyApp.Map`).
  defp lookup({{:., _, [{:__aliases__, _, module}, :get]}, _, args}, map_modules) do
    if module in map_modules do
      lookup_args(args)
    else
      nil
    end
  end

  defp lookup(_ast, _map_modules), do: nil

  defp lookup_args([subject, key]), do: {subject, key}
  defp lookup_args([subject, key, _default]), do: {subject, key}
  defp lookup_args(_args), do: nil

  # Keys count only as literals: an atom node is a literal atom, a binary node
  # is a literal string — variables and interpolations are 3-tuples and fall
  # through to the catch-all.
  defp counterpart_keys?(atom_key, string_key)
       when is_atom(atom_key) and is_binary(string_key) do
    Atom.to_string(atom_key) === string_key
  end

  defp counterpart_keys?(string_key, atom_key)
       when is_binary(string_key) and is_atom(atom_key) do
    Atom.to_string(atom_key) === string_key
  end

  defp counterpart_keys?(_left_key, _right_key), do: false

  # Structural equality of subjects must ignore line/column noise, so every
  # node's metadata is emptied before comparing.
  defp strip_meta(ast) do
    Macro.prewalk(ast, &Macro.update_meta(&1, fn _meta -> [] end))
  end

  defp issue_for(fallback, issue_meta) do
    format_issue(issue_meta,
      message:
        "mixed atom/string key fallback found — normalize the map's keys at its boundary instead of falling back at the read site",
      trigger: "||",
      line_no: fallback.line_no,
      column: fallback.column
    )
  end
end
