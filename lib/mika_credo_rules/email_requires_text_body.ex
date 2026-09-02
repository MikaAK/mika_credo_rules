defmodule MikaCredoRules.EmailRequiresTextBody do
  use Credo.Check,
    base_priority: :low,
    category: :design,
    param_defaults: [
      excluded_paths: ["_test.exs", "test/"]
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments and suffixes naming files this check skips
        (matched on segment boundaries). Defaults to `["_test.exs", "test/"]`
        — an email built only to assert against in a test is not a real
        outgoing message.
        """
      ]
    ]

  alias MikaCredoRules.SourceFilter

  @moduledoc """
  A Swoosh email built with `html_body/2` needs a matching `text_body/2`, or
  it renders empty in a text-only client.

  `html_body/2` and `text_body/2` set independent parts of a multipart
  message. Setting only the HTML part means any client that prefers or
  requires plain text — corporate spam filters and accessibility readers
  among them — shows a blank body instead of falling back sensibly.

      # BAD — no text fallback
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
        end
      end

      # GOOD — both parts set
      defmodule MyApp.Emails.Welcome do
        import Swoosh.Email

        def welcome(user) do
          new()
          |> to(user.email)
          |> subject("Welcome!")
          |> html_body("<h1>Welcome!</h1>")
          |> text_body("Welcome!")
        end
      end

  The check is a module-level heuristic, scoped to each top-level
  `defmodule` or `defimpl` in the file: if `html_body/2` is called anywhere
  in the scope's body — including inside a nested `defmodule` — and
  `text_body/2` is never called anywhere in that same body, one issue is
  reported at the first `html_body` call site. A definition head — `def
  html_body(...)`, a bodiless multi-clause head (`def html_body(user,
  greeting \\\\ "Hi")`), or a `defdelegate html_body(...), to: ...` — is not
  a call and is never counted, nor is a bare variable, or a
  module-attribute definition or read whose own name is
  `@html_body`/`@text_body` (`@html_body "<h1>..."`) — the attribute's own
  name collides with the call shape, not evidence of a real call. A real
  `html_body`/`text_body` call nested inside a differently-named
  attribute's value (`@base new() |> text_body(body)`) is still counted
  normally.

  Both functions are matched by bare, unqualified name — the shape `import
  Swoosh.Email` produces — piped or not, so `email |> html_body(body)` and
  `html_body(email, body)` are both caught: piping drops the implicit
  first argument from the AST, so a genuine call is seen with either one
  argument (piped) or two (direct, matching Swoosh's real `html_body/2`).
  A call with zero, three, or more arguments is not counted.

  ## Limitations

    * A module-qualified call — `Swoosh.Email.html_body(email, body)` — is
      invisible; only the bare, unqualified name is matched.
    * The module body is scanned flat, not per nested `defmodule` or
      `defimpl`: a nested scope that itself calls `text_body/2` satisfies
      the whole enclosing scope. Keep one Swoosh email per top-level module
      to get an accurate scope. A top-level `defprotocol` is never opened as
      its own scope either — moot in practice, since a protocol definition
      may only declare function heads, never bodies with real calls.
    * Only the body of a top-level `defmodule` or `defimpl` is ever scanned.
      Code outside any such block — a bare script invoking `html_body/2` at
      the top level of a `.exs` file, for instance — opens no scope and is
      never checked at all.
    * `Swoosh.Email.new/1` accepts `text_body:`/`html_body:` as keyword
      options (`new(text_body: "hi", html_body: "<h1>hi</h1>")`), applied
      the same as calling the two functions directly. The check does not
      read `new/1`'s options: a module that sets the text body only this
      way is still flagged for a later `html_body` call, and a module that
      sets only the HTML body this way is not flagged at all.
    * The match is name-only: `import Swoosh.Email` is not required, and
      the two functions are matched independently by name. A local helper
      function named `html_body/1` or `html_body/2` with nothing to do
      with Swoosh is indistinguishable from the real one and will be
      flagged. The same is true in reverse, and is the more dangerous
      direction: a local helper function named `text_body`, called with
      one or two arguments anywhere in the scope, satisfies the check even
      when it never touches the email being built — silencing a genuine
      unset HTML-only email instead of flagging it.
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
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  # Each top-level defmodule/defimpl is its own scope, scanned flat with
  # nested scopes included (not pruned) — so the outer walk must prune its
  # own descent here, or a nested scope would be independently re-visited as
  # its own top-level scope with only a partial picture of the enclosing one.
  defp traverse({:defmodule, _, [_name, [{:do, body} | _]]}, issues) do
    open_scope(body, issues)
  end

  # `defimpl` has three legal arg shapes and the do-block is not always the
  # last keyword list's first entry: `defimpl P, for: T do ... end` is a
  # 3-arg call with `[for: T]` and `[do: body]]` as separate trailing lists;
  # `defimpl P do ... end` (implicit `for:`) is 2-arg with `[do: body]`; and
  # `defimpl P, for: T, do: body` (inline) is 2-arg with `[for: T, do:
  # body]` — `:do` second, not first. Looking the key up in the LAST arg
  # (always a keyword list) covers all three regardless of position.
  defp traverse({:defimpl, _, args} = ast, issues) when is_list(args) and args !== [] do
    case defimpl_do_block(args) do
      {:ok, body} -> open_scope(body, issues)
      :error -> {ast, issues}
    end
  end

  defp traverse(ast, issues), do: {ast, issues}

  defp defimpl_do_block(args) do
    case List.last(args) do
      opts when is_list(opts) -> Keyword.fetch(opts, :do)
      _not_a_keyword_list -> :error
    end
  end

  defp open_scope(body, issues) do
    case first_html_body_without_text_body(body) do
      nil -> {nil, issues}
      location -> {nil, [location | issues]}
    end
  end

  defp first_html_body_without_text_body(body) do
    {_ast, {html_locations, text_body_called?}} = Macro.prewalk(body, {[], false}, &collect/2)

    case {Enum.reverse(html_locations), text_body_called?} do
      {[], _no_html_calls} -> nil
      {_locations, true} -> nil
      {[first | _rest], false} -> first
    end
  end

  @definition_macros [:def, :defp, :defmacro, :defmacrop, :defdelegate, :defguard, :defguardp]

  # A definition head has the same `{name, meta, args}` shape as a call, so
  # the head is dropped from the scan while the body (or, for `defdelegate`,
  # the `to:` opts) stays traversable.
  defp collect({definition, meta, [_head, body]}, acc)
       when definition in @definition_macros do
    {{definition, meta, [{:__block__, [], []}, body]}, acc}
  end

  # A bodiless head (`def html_body(user, greeting \\ "Hi")`, the standard
  # multi-clause-with-defaults idiom) has no body at all — the definition
  # tuple is 1-arg, not 2 — so there is nothing left to traverse once the
  # head itself is pruned. `defguard`/`defguardp` are always this 1-arg shape
  # (the argument is the head, or a `when`-wrapped head+guard) — a guard
  # body can't call arbitrary functions anyway, so pruning it entirely is
  # safe.
  defp collect({definition, _meta, [_head]}, acc)
       when definition in @definition_macros do
    {nil, acc}
  end

  # `@spec`/`@callback`/`@macrocallback`/`@type`/`@typep`/`@opaque` bodies are
  # type expressions, not calls — a function name in a type signature
  # (`@spec html_body(map(), String.t()) :: map()`) is not a call to
  # html_body/2, and must be pruned before the html_body/text_body call
  # matchers below ever see it.
  defp collect({:@, _meta, [{attribute, _, _}]}, acc)
       when attribute in [:spec, :callback, :macrocallback, :type, :typep, :opaque] do
    {nil, acc}
  end

  # A module-attribute DEFINITION named after one of the two tracked
  # functions (`@html_body "<h1>..."`) has the same `{name, meta, [value]}`
  # shape as a call to that function — the attribute's own name collides
  # with the call shape, not evidence a real call was ever made — so the
  # guard scopes the prune to those two names ONLY. An attribute with any
  # OTHER name (`@base new() |> text_body(body)`) never matches this
  # clause, so it falls through unpruned and a real call inside its value
  # is still counted. An attribute READ (`@html_body`) carries the
  # enclosing module context, not a list, in that slot, and never matches
  # here regardless.
  defp collect({:@, _meta, [{name, _name_meta, [_ | _]}]}, acc)
       when name in [:html_body, :text_body] do
    {nil, acc}
  end

  # Both functions are matched with 1 argument (the piped shape, where
  # piping drops the implicit first argument from the AST) or 2 (the
  # direct shape, matching Swoosh's real */2 arity) — never 0 or 3+.
  defp collect({:html_body, meta, args} = node, {locations, text_body_called?})
       when is_list(args) and length(args) in [1, 2] do
    {node, {[%{line_no: meta[:line], column: meta[:column]} | locations], text_body_called?}}
  end

  defp collect({:text_body, _meta, args} = node, {locations, _text_body_called?})
       when is_list(args) and length(args) in [1, 2] do
    {node, {locations, true}}
  end

  defp collect(node, acc), do: {node, acc}

  defp issue_for(location, issue_meta) do
    format_issue(issue_meta,
      message:
        "html_body found — module also needs a text_body call, or the email renders empty in text-only clients",
      trigger: "html_body",
      line_no: location.line_no,
      column: location.column
    )
  end
end
