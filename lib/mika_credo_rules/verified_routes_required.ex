defmodule MikaCredoRules.VerifiedRoutesRequired do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: [:push_navigate, :push_patch, :redirect, :live_redirect],
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        functions: """
        A list of atoms naming the navigation functions whose `to:` option is
        checked. Matched by name only — bare, qualified, and piped calls all
        count. Defaults to `[:push_navigate, :push_patch, :redirect, :live_redirect]`.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `["_test.exs", "test/"]`.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A navigation call's `to:` option must be a `~p` verified-route sigil, never
  a plain string.

  A hand-typed path string is only checked when the browser hits it — a typo
  in a route segment or a renamed live route surfaces as a 404 in production.
  `~p"/courses/\#{id}"` is checked by the router at compile time instead: a
  path that does not match any route is a compiler warning at build time (an
  error under `--warnings-as-errors`).

      # BAD — a typo here is a runtime 404, not a build-time warning
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: "/courses/\#{id}")}
        end
      end

      # GOOD — the router checks this route exists at compile time
      defmodule MyAppWeb.CourseLive do
        def handle_event("view_course", %{"id" => id}, socket) do
          {:noreply, push_navigate(socket, to: ~p"/courses/\#{id}")}
        end
      end

  The same applies to a plain literal, not only an interpolated one:

      # BAD — a plain literal is just as unchecked as an interpolated one
      def logout(conn, _params), do: redirect(conn, to: "/login")

      # GOOD
      def logout(conn, _params), do: redirect(conn, to: ~p"/login")

  Only the `to:` option is checked — `external:` takes a full URL, which
  `~p` cannot express, so a plain string there is legitimate and left alone.
  A variable, module attribute, or any other expression under `to:` is left
  alone too, since it cannot be statically proven to be an unchecked literal
  (it may already hold a `~p`-built value).

  ## Limitations

  Matching is by function name alone, regardless of which module a qualified
  call names — a same-named function defined on an unrelated module
  (`MyApp.Reporting.redirect/2`, say) is flagged the same as
  `Phoenix.Controller.redirect/2`, whether called bare or qualified
  (`MyApp.Reporting.redirect(conn, to: "/x")`). Narrow `:functions` if that
  bites. A route string built by a helper (`to: build_path(id)`) is invisible
  to this check — only what is statically a binary, an interpolated `<<>>`
  node, a `~s`/`~S` sigil, or a `<>` concatenation anchored on a binary
  literal (`to: "/courses/" <> id`) is caught.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      functions = Params.get(params, :functions, __MODULE__)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, functions))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # A def/defp/defmacro/defmacrop head is not a call — `defp redirect(conn, to: "/login")`
  # shares the same 3-tuple shape as a real call to `redirect/2`. Blank the
  # head's arguments so the generic clauses below never mistake a pattern
  # match for a navigation call, while the body (`rest`) is left untouched
  # and still fully traversed for genuine calls. A `\\` default-value
  # expression is real evaluated code, not a pattern, so it is pulled out
  # and traversed separately before the head is blanked.
  defp traverse({definer, def_meta, [{name, head_meta, head_args} | rest]}, calls, functions)
       when definer in [:def, :defp, :defmacro, :defmacrop] do
    calls = collect_default_arg_calls(name, head_args, calls, functions)
    {{definer, def_meta, [{name, head_meta, []} | rest]}, calls}
  end

  # A module attribute assignment shares the same 3-tuple call shape as a
  # real call — `@redirect [to: "/login"]` parses to
  # `{:@, meta, [{:redirect, name_meta, [value]}]}`, and the inner
  # `{:redirect, name_meta, [value]}` node looks exactly like a call to a
  # function named `redirect`. Traverse `value` on its own so a genuine
  # navigation call nested inside it still fires
  # (`@paths [push_navigate(nil, to: "/x")]`), but never present the
  # attribute name itself as a call.
  defp traverse({:@, at_meta, [{name, name_meta, [value]}]}, calls, functions) do
    {_ast, updated_calls} = Macro.prewalk(value, calls, &traverse(&1, &2, functions))
    {{:@, at_meta, [{name, name_meta, []}]}, updated_calls}
  end

  defp traverse({function, meta, args} = ast, calls, functions)
       when is_atom(function) and is_list(args) do
    {ast, collect_call(calls, function, meta, args, functions)}
  end

  # Qualified/piped-into-qualified form — `Phoenix.LiveView.push_navigate(...)`
  # or `socket |> LiveView.redirect(...)`. Matched by function name alone,
  # same as the bare form above.
  defp traverse({{:., _dot_meta, [_module, function]}, meta, args} = ast, calls, functions)
       when is_atom(function) and is_list(args) do
    {ast, collect_call(calls, function, meta, args, functions)}
  end

  defp traverse(ast, calls, _functions), do: {ast, calls}

  # A guarded head's signature is nested one level deeper, under `:when` —
  # `def f(x \\ 1) when is_integer(x)` arrives here as
  # `name = :when, head_args = [{:f, meta, real_args}, guard]`.
  defp collect_default_arg_calls(
         :when,
         [{_real_name, _real_meta, real_args}, _guard],
         calls,
         functions
       )
       when is_list(real_args) do
    collect_default_arg_calls(nil, real_args, calls, functions)
  end

  defp collect_default_arg_calls(_name, head_args, calls, functions) when is_list(head_args) do
    head_args
    |> Enum.flat_map(fn
      {:\\, _meta, [_pattern, default]} -> [default]
      _pattern -> []
    end)
    |> Enum.reduce(calls, fn default, acc ->
      {_ast, updated_calls} = Macro.prewalk(default, acc, &traverse(&1, &2, functions))
      updated_calls
    end)
  end

  defp collect_default_arg_calls(_name, _head_args, calls, _functions), do: calls

  defp collect_call(calls, function, meta, args, functions) do
    with true <- function in functions,
         {:ok, value} <- to_option(args),
         true <- unchecked_literal?(value) do
      [call(function, meta) | calls]
    else
      _not_flagged -> calls
    end
  end

  defp to_option(args) do
    case args |> Enum.reverse() |> Enum.find(&Keyword.keyword?/1) do
      nil -> :error
      options -> Keyword.fetch(options, :to)
    end
  end

  defp unchecked_literal?(value) when is_binary(value), do: true
  defp unchecked_literal?({:<<>>, _meta, _parts}), do: true
  defp unchecked_literal?({:sigil_s, _meta, [{:<<>>, _inner_meta, _parts}, _modifiers]}), do: true
  defp unchecked_literal?({:sigil_S, _meta, [{:<<>>, _inner_meta, _parts}, _modifiers]}), do: true
  defp unchecked_literal?({:<>, _meta, [left, _right]}) when is_binary(left), do: true
  defp unchecked_literal?(_value), do: false

  defp call(function, meta) do
    %{trigger: Atom.to_string(function), line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(call, issue_meta) do
    format_issue(issue_meta,
      message:
        "#{call.trigger} found — to: must be a ~p verified route sigil, not a plain string, " <>
          "so a typo is a compiler warning at build time (an error under --warnings-as-errors) " <>
          "instead of a 404",
      trigger: call.trigger,
      line_no: call.line_no,
      column: call.column
    )
  end
end
