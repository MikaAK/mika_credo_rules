defmodule MikaCredoRules.NoCastAllKeys do
  use Credo.Check,
    base_priority: :higher,
    category: :warning

  alias MikaCredoRules.AstHelpers

  @moduledoc """
  `cast` must receive an explicit list of permitted fields, never
  `Map.keys(params)`.

  `Ecto.Changeset.cast/3,4` exists to whitelist which client-supplied keys may
  reach the changeset. Passing `Map.keys(params)` as the permitted list turns
  the whitelist into "whatever the client sent" — a mass-assignment hole that
  lets a request set fields the endpoint never meant to expose (`role`,
  `admin`, `balance`). Enumerate the permitted fields instead.

      # BAD — every client-supplied key is cast
      def changeset(user, attrs), do: user |> cast(attrs, Map.keys(attrs)) |> validate_required([:email])

      # BAD — same hole, non-piped spelling
      def changeset(user, attrs) do
        cast(user, attrs, Map.keys(attrs))
      end

      # GOOD — the permitted fields are enumerated
      def changeset(user, attrs) do
        user
        |> cast(attrs, [:name, :email])
        |> validate_required([:email])
      end

  Every spelling of the call is caught: local/imported `cast(...)` with 3 or 4
  arguments, piped `|> cast(...)`, qualified `Ecto.Changeset.cast(...)`, and
  `Changeset.cast(...)` under `alias Ecto.Changeset` (including `as:` renames).
  The permitted list is the 3rd argument of a standalone call and the 2nd
  argument of a piped call.

  ## Limitations

    * Only a literal `Map.keys(...)` call in the permitted position is
      detected. Indirection through a variable (`fields = Map.keys(attrs)`
      then `cast(user, attrs, fields)`) is invisible to this check — literal
      lists, module attributes, and variables are all left alone.
    * Unqualified `cast` is matched by name, so a local `cast/3` that is not
      Ecto's but receives `Map.keys(...)` as its third argument is still
      flagged.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    context = build_context(source_file)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, context))
    |> Enum.map(&issue_for(&1, issue_meta))
  end

  defp build_context(source_file) do
    %{
      changeset_modules: AstHelpers.resolve_aliases(source_file, [Ecto.Changeset]),
      map_modules: AstHelpers.resolve_aliases(source_file, [Map])
    }
  end

  # A piped cast is consumed here: its permitted list is checked in the piped
  # position, and the call's head is rewritten to a block (arguments stay
  # traversable) so the standalone clause below never re-examines the same
  # call in the wrong position.
  defp traverse({:|>, pipe_meta, [lhs, piped_call]} = ast, casts, context) do
    case cast_call(piped_call, context) do
      {meta, args} ->
        {{:|>, pipe_meta, [lhs, {:__block__, [], args}]},
         collect_cast(casts, args, :piped, meta, context)}

      nil ->
        {ast, casts}
    end
  end

  defp traverse(ast, casts, context) do
    case cast_call(ast, context) do
      {meta, args} -> {ast, collect_cast(casts, args, :standalone, meta, context)}
      nil -> {ast, casts}
    end
  end

  defp collect_cast(casts, args, position, meta, context) do
    if args |> permitted_arg(position) |> map_keys_call?(context) do
      [%{line_no: meta[:line], column: meta[:column]} | casts]
    else
      casts
    end
  end

  # In `cast(data, params, permitted)` the permitted list is the 3rd argument;
  # in `data |> cast(params, permitted)` it is the call node's 2nd argument.
  defp permitted_arg(args, :standalone) when length(args) in [3, 4], do: Enum.at(args, 2)
  defp permitted_arg(args, :piped) when length(args) in [2, 3], do: Enum.at(args, 1)
  defp permitted_arg(_args, _position), do: nil

  defp cast_call({:cast, meta, args}, _context) when is_list(args), do: {meta, args}

  defp cast_call({{:., _, [{:__aliases__, _, module}, :cast]}, meta, args}, context)
       when is_list(args) do
    if module in context.changeset_modules, do: {meta, args}
  end

  defp cast_call(_ast, _context), do: nil

  defp map_keys_call?({{:., _, [{:__aliases__, _, module}, :keys]}, _, [_map]}, context) do
    module in context.map_modules
  end

  defp map_keys_call?(_ast, _context), do: false

  defp issue_for(cast, issue_meta) do
    format_issue(issue_meta,
      message: "cast with Map.keys(params) found — enumerate the permitted fields explicitly",
      trigger: "cast",
      line_no: cast.line_no,
      column: cast.column
    )
  end
end
