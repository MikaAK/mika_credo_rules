# credo:disable-for-this-file MikaCredoRules.NoBannedModules
defmodule MikaCredoRules.NoBannedModules do
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      modules: [
        {Guardian, "no JWT here — sessions are Redis tokens (elixir-auth-sessions)"},
        {Joken, "no JWT here — sessions are Redis tokens (elixir-auth-sessions)"}
      ],
      excluded_paths: []
    ],
    explanations: [
      params: [
        modules: """
        A list of `{module, reason}` tuples to ban outright — each `module`
        must be a genuine Elixir module (one `Module.split/1` accepts); an
        erlang-style atom (`:meck`) or a bare module with no `{module,
        reason}` tuple raises when the check reads its params. Any reference
        to `module`, or to any of its submodules — `use`, `alias`, a remote
        call, or a module attribute value — is reported, with `reason`
        appended to the issue message.

        Module names are matched by segment prefix: banning `Guardian` also
        bans `Guardian.Plug` and `Guardian.Config`, the way `use
        Joken.Config` is Joken's own canonical entry point and must still
        count as a `Joken` reference. A project module that merely shares
        the banned name as a LATER segment (`MyApp.Guardian`,
        `MyApp.GuardianToken`) is never flagged — matching starts at the
        first segment. Alias resolution (see
        `MikaCredoRules.AstHelpers.resolve_aliases/2`) is aware of an alias
        of the banned module ITSELF (`alias Guardian` followed by a bare
        `Guardian` reference) but not of an alias of one of its submodules
        — see Limitations. A nested `defmodule Guardian do ... end` also
        shadows the bare name, and every submodule beneath it, for the rest
        of that file — the fully-qualified `Elixir.Guardian` spelling,
        written as a dotted alias, always stays flagged regardless of
        shadowing; the `:"Elixir.Guardian"` atom spelling stays flagged too,
        but only as a dot-call's module receiver or a bare attribute value
        (`@behaviour :"Elixir.Guardian"`), not in every AST position.
        Defaults to banning `Guardian` and `Joken`: this project
        authenticates with Redis-backed session tokens, not JWTs.
        """,
        excluded_paths: """
        A list of path fragments naming files this check skips, matched at a
        path-segment boundary (see
        `MikaCredoRules.SourceFilter.matches_fragment?/2`). Defaults to `[]`
        — a banned module is banned everywhere, tests included, unless a
        project opts specific paths out.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  Generic, param-driven module ban. Some libraries must never appear in this
  codebase, however they're referenced — `use`, `alias`, a remote call, or a
  bare mention in an attribute all count. The default list bans `Guardian`
  and `Joken`: this project authenticates with Redis-backed session tokens
  (see `elixir-auth-sessions`), not JWTs, so either library issuing or
  signing a session token is itself the bug. Code that instead VERIFIES a
  third-party issuer's JWTs (an Auth0/JWKS integration, for example) is a
  legitimate, deliberate exception to the default — opt those files out with
  `excluded_paths` rather than disabling the check outright.

      # BAD — a JWT library wired up directly
      defmodule MyApp.Auth do
        use Guardian, otp_app: :my_app
      end

      # GOOD — Redis-backed session tokens
      defmodule MyApp.Auth do
        def sign_in(user), do: MyApp.Sessions.create(user)
      end

  An explicit alias still resolves back to the banned module, so aliasing it
  away does not help — merely writing the alias is already a reference:

      # BAD — aliasing the banned module is already a reference to it
      defmodule MyApp.Auth do
        alias Guardian
      end

  A banned module's submodules count too — `use Joken.Config` is Joken's own
  canonical entry point, not a different module that happens to share a
  name:

      # BAD — Joken's own canonical `use`, still a reference to Joken
      defmodule MyApp.Auth do
        use Joken.Config
      end

  Banned modules are matched by segment prefix — a project module that
  merely shares the banned name as a LATER segment is a different module
  entirely, and is never flagged:

      # GOOD — a fully qualified project module, not the banned library
      defmodule MyApp.Auth do
        def sign_in(user), do: MyApp.Guardian.sign(user)
      end

  A locally defined module also shadows a banned bare name, the same way a
  project `alias` does — a nested `defmodule Guardian do ... end` deregisters
  the bare name for the rest of that file, so a stub or fake by that name is
  never mistaken for the real library:

      # GOOD — a local Guardian stub, not the banned library
      defmodule MyApp.AuthStub do
        defmodule Guardian do
          def encode_and_sign(user), do: {:ok, user}
        end

        def sign_in(user), do: Guardian.encode_and_sign(user)
      end

  ## Limitations

  Module identity is a naming heuristic, the same as `NoMockingLibraries` and
  `NoBangMailerDeliver` — it matches AST module references, not what a
  library actually does. A string or atom that merely mentions a banned name
  (`"Guardian token expired"`, `:guardian_error`) is never flagged, and
  `mix.exs` dependency declarations (`{:guardian, "~> 2.0"}`) are ordinary
  lowercase Hex-package atoms, not module references, so they never match
  either.

  Aliases are resolved from a flat, file-level table rather than a lexical
  scope stack, and an alias injected by a macro (via `__using__`) is
  invisible to Credo and cannot be resolved. Alias resolution only registers
  an alias whose target EXACTLY matches a banned entry — `alias Guardian`
  resolves, but `alias Guardian.Plug` does not, because `Guardian.Plug`
  itself is not a banned entry (only `Guardian` is). A later bare
  `Plug.sign_in(...)` is therefore silent; writing `Guardian.Plug.sign_in`
  out in full still matches, since that reference needs no alias resolution
  at all. A project `alias` naming the banned module itself is a second
  shadowing source, alongside `defmodule`: `alias MyApp.Guardian` deregisters
  the bare `Guardian` name file-wide (`AstHelpers.resolve_aliases/2`'s REMOVE
  half), so a later bare `Guardian.encode_and_sign(user)` is silent — but the
  `Elixir.Guardian` and `:"Elixir.Guardian"` spellings still fire regardless,
  since those are matched against the module's unaliased identity, never the
  shadowed one. `defmodule` shadowing is file-level the same way: a nested stub
  defined inside one top-level module deregisters the bare name for every
  other top-level module in that file too, not only its own — and a
  TOP-LEVEL, single-segment `defmodule Guardian do ... end` shadows the bare
  name file-wide the same as a nested one would, since a lone segment always
  shadows regardless of nesting. A banned module held in a variable or
  module attribute value, reached via `apply/3`, or referenced by a
  dynamically built alias is not recognised — only a literal AST reference
  to the module's name is.

  The `modules` param expects `{module, reason}` tuples of genuine Elixir
  modules — an erlang-style atom (`:meck`) or a bare module with no `reason`
  tuple raises when the check reads its params, rather than being silently
  ignored; this check offers no `erlang_modules` param the way
  `NoMockingLibraries` does.
  """
  @explanation [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if SourceFilter.matches_fragment?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      context = build_context(source_file, params)

      source_file
      |> Credo.Code.prewalk(&traverse(&1, &2, context))
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp build_context(source_file, params) do
    entries =
      params
      |> Params.get(:modules, __MODULE__)
      |> Enum.map(&build_entry(source_file, &1))

    all_segments = Enum.flat_map(entries, & &1.module_segments)

    %{
      entries: entries,
      shadowed_names: shadowed_names(source_file, all_segments),
      source_file: source_file
    }
  end

  defp build_entry(source_file, {module, reason} = entry) when is_atom(module) do
    if elixir_module?(module) do
      %{
        module_segments: AstHelpers.resolve_aliases(source_file, [module]),
        base_segments: AstHelpers.module_paths(module),
        reason: reason
      }
    else
      raise_invalid_modules_entry(entry)
    end
  end

  defp build_entry(_source_file, entry), do: raise_invalid_modules_entry(entry)

  defp elixir_module?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> true
      _erlang_name -> false
    end
  end

  defp raise_invalid_modules_entry(entry) do
    raise ArgumentError,
          "NoBannedModules: the :modules param entry #{inspect(entry)} must be a " <>
            "{module, reason} tuple naming a genuine Elixir module"
  end

  # A locally defined `defmodule` is a third shadowing source that alias
  # resolution does not cover — it emits the same bare `[:Guardian]` AST as a
  # reference to a banned single-segment name. A single-segment defmodule name
  # always shadows the bare name. A dotted, multi-segment name shadows only
  # its first segment, and only when the defmodule is nested inside another
  # module, the way Elixir's own implicit nested-module aliasing works. A
  # top-level `defmodule MyApp.Guardian` defines a fully qualified module
  # that nothing in the file aliases to a bare name, so it shadows nothing.
  defp shadowed_names(source_file, module_segments) do
    source_file
    |> defmodule_definitions()
    |> Enum.map(&shadow_name/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1 in module_segments))
  end

  defp shadow_name({[single_segment], _nested?}), do: [single_segment]
  defp shadow_name({name_segments, true}), do: [List.first(name_segments)]
  defp shadow_name({_name_segments, false}), do: nil

  # Every `defmodule` in the file, paired with whether it is nested inside
  # another module. The outer pass collects only top-level defmodules and
  # prunes their bodies (`{nil, acc}`) so nested ones are never double
  # counted here; each top-level body is then rescanned on its own to find
  # every defmodule nested inside it, at any depth.
  defp defmodule_definitions(source_file) do
    source_file
    |> Credo.Code.prewalk(&collect_top_level_defmodule/2)
    |> Enum.flat_map(fn {name_segments, body} ->
      [{name_segments, false} | nested_defmodule_names(body)]
    end)
  end

  defp collect_top_level_defmodule(
         {:defmodule, _meta, [{:__aliases__, _, name_segments}, [do: body]]},
         definitions
       ) do
    {nil, [{name_segments, body} | definitions]}
  end

  defp collect_top_level_defmodule(ast, definitions), do: {ast, definitions}

  defp nested_defmodule_names(body) do
    body
    |> Macro.prewalk([], fn
      {:defmodule, _meta, [{:__aliases__, _, name_segments}, _inner_body]} = ast, names ->
        {ast, [{name_segments, true} | names]}

      ast, names ->
        {ast, names}
    end)
    |> elem(1)
  end

  # `alias MyApp.{Guardian, Foo}` — the inner aliases are relative to the
  # base, so check the expanded names and prune the node to keep the bare
  # fragment from being matched a second time on its own. The full
  # `base ++ inner` path is what gets MATCHED (`Guardian.Plug` from `alias
  # Guardian.{Plug, ...}` still bans on a `Guardian` entry), but only the
  # inner fragment (`Plug`) is what's literally written at `inner_meta`'s
  # column — the base is written once before the brace, so the DISPLAYED
  # trigger must stay just the inner text or it stops matching the source.
  defp traverse(
         {{:., _, [{:__aliases__, _, base}, :{}]}, _meta, inner_nodes},
         references,
         context
       ) do
    references =
      Enum.reduce(inner_nodes, references, fn
        {:__aliases__, inner_meta, inner}, acc ->
          maybe_reference(base ++ inner, inner_meta, acc, context, Enum.join(inner, "."))

        _other, acc ->
          acc
      end)

    {nil, references}
  end

  # `alias Guardian, as: G` — only the target is a library reference; prune
  # the node so the `as:` name is not reported a second time on the same
  # line.
  defp traverse({:alias, _, [{:__aliases__, meta, target}, opts]}, references, context)
       when is_list(opts) do
    if all_atoms?(target) do
      {nil, maybe_reference(target, meta, references, context)}
    else
      {nil, references}
    end
  end

  # `__MODULE__.Sub`, `@attr.Sub`, `unquote(mod).Sub` all parse as
  # `__aliases__` too, but with a NON-ATOM leading segment (the AST node for
  # `__MODULE__`/`@attr`/`unquote(...)`, not a plain module-path atom) —
  # `matching_entry/2` and `Enum.join/2` both assume every segment is an
  # atom, so a check must stay total over the AST shapes it recognises
  # (see ast_helpers.ex) rather than crash on the ones it doesn't.
  defp traverse({:__aliases__, meta, module_segments} = ast, references, context) do
    if all_atoms?(module_segments) do
      {ast, maybe_reference(module_segments, meta, references, context)}
    else
      {ast, references}
    end
  end

  # `:"Elixir.Guardian".encode_and_sign(user)` — a bare-atom module slot in a
  # dot-call, the third AST spelling of "module" alongside `__aliases__` and
  # an ordinary erlang atom (see writing-credo-checks). Only the
  # `Elixir.`-prefixed spelling names an Elixir module; any other atom here is
  # an erlang module (`:ets`, `:meck`, ...) and out of scope for this check.
  # The atom carries no meta of its own — Elixir sets the call's own meta to
  # the FUNCTION name's column (`encode_and_sign`, not `Elixir.Guardian`) — so
  # the real position is found the same way `no_hardcoded_secret_literals.ex`
  # locates a value with no AST position: search the source text for the
  # trigger itself (see `locate_reference/3`). Two atom-spelled references to
  # the same module on one line would collapse onto the first match's column;
  # this spelling is rare enough that the smaller-column-precision tradeoff,
  # not a correctness one (both issues still fire), is an acceptable ceiling.
  defp traverse({{:., _, [module, function]}, meta, args} = ast, references, context)
       when is_atom(module) and is_atom(function) and is_list(args) do
    case atom_module_segments(module) do
      nil ->
        {ast, references}

      segments ->
        display = Enum.join(segments, ".")
        {line, column} = locate_reference(context.source_file, meta, display)
        located_meta = [line: line, column: column]

        {ast, maybe_reference(segments, located_meta, references, context, display)}
    end
  end

  # `@behaviour :"Elixir.Guardian"` — the same atom-literal spelling as the
  # dot-call case above, but standing alone as an attribute's value rather
  # than in a dot-call's module slot, so the dot-call clause never sees it.
  # A bare atom carries no meta of its own; the enclosing `@` node's meta
  # gives a starting line, and `locate_reference/3` finds the real line and
  # column the same way the dot-call clause does — a parenthesized attribute
  # value (`@behaviour(\n  :"Elixir.Guardian"\n)`) can push the atom onto a
  # later line than the `@` itself.
  defp traverse({:@, meta, [{_attribute, _attribute_meta, args}]} = ast, references, context)
       when is_list(args) do
    case Enum.find_value(args, &atom_argument_module_segments/1) do
      nil ->
        {ast, references}

      segments ->
        display = Enum.join(segments, ".")
        {line, column} = locate_reference(context.source_file, meta, display)
        located_meta = [line: line, column: column]

        {ast, maybe_reference(segments, located_meta, references, context, display)}
    end
  end

  defp traverse(ast, references, _context), do: {ast, references}

  defp atom_argument_module_segments(arg) when is_atom(arg), do: atom_module_segments(arg)
  defp atom_argument_module_segments(_arg), do: nil

  defp atom_module_segments(module) do
    case Atom.to_string(module) do
      "Elixir." <> _rest -> [Elixir | module |> Module.split() |> Enum.map(&String.to_atom/1)]
      _erlang_name -> nil
    end
  end

  # An atom-spelled trigger carries no AST position of its own — the
  # enclosing node's meta only pins the line the node itself STARTS on
  # (`@behaviour(`, not the atom inside it), and a parenthesized attribute
  # value can push the atom onto a later line. Scan forward from the node's
  # own line for the first line actually containing the trigger text, rather
  # than assuming it is on the node's own line.
  defp locate_reference(source_file, meta, text) do
    lines =
      source_file
      |> Credo.SourceFile.source()
      |> String.split("\n")

    located =
      lines
      |> Enum.drop(meta[:line] - 1)
      |> Enum.with_index(meta[:line])
      |> Enum.find_value(fn {line, line_no} ->
        case :binary.match(line, text) do
          {start, _length} -> {line_no, start + 1}
          :nomatch -> nil
        end
      end)

    case located do
      nil -> {meta[:line], meta[:column]}
      found -> found
    end
  end

  defp maybe_reference(module_segments, meta, references, context) do
    maybe_reference(module_segments, meta, references, context, Enum.join(module_segments, "."))
  end

  # An `Elixir.`-prefixed reference is unambiguous — it always names the real
  # module, never a locally aliased or shadowed one — so it bypasses BOTH
  # shadowing sources (defmodule and alias) and matches against each entry's
  # unaliased `base_segments`, not the alias-resolved `module_segments`. A
  # project alias that shadows the banned module (`alias MyApp.Guardian`)
  # removes the bare form from `module_segments` (see
  # `AstHelpers.resolve_aliases/2`'s REMOVE half) — matching a stripped
  # `Elixir.`-prefixed reference against that same alias-resolved set would
  # therefore go dark on exactly the spelling meant to survive shadowing.
  defp maybe_reference(module_segments, meta, references, context, display) do
    stripped = strip_elixir_prefix(module_segments)
    elixir_prefixed = elixir_prefixed?(module_segments)

    if not elixir_prefixed and shadowed?(stripped, context.shadowed_names) do
      references
    else
      segments_field = if elixir_prefixed, do: :base_segments, else: :module_segments

      case matching_entry(context.entries, stripped, segments_field) do
        nil -> references
        entry -> [reference(display, meta, entry.reason) | references]
      end
    end
  end

  # Banned modules are matched by segment PREFIX, not exact equality — banning
  # `Guardian` also bans every submodule beneath it (`Guardian.Plug`,
  # `Guardian.Config`), the same way `use Joken.Config` is Joken's own
  # canonical entry point and must still count as a reference to `Joken`. A
  # local shadow (a nested `defmodule Guardian do ... end`) shadows the same
  # way: a reference into ITS OWN submodule (`Guardian.Helper`, defined
  # nowhere, but resolved against the stub) must not be mistaken for the real
  # library's submodule.
  defp matching_entry(entries, stripped, segments_field) do
    Enum.find(
      entries,
      &Enum.any?(Map.fetch!(&1, segments_field), fn path ->
        segments_start_with?(stripped, path)
      end)
    )
  end

  defp shadowed?(stripped, shadowed_names) do
    Enum.any?(shadowed_names, &segments_start_with?(stripped, &1))
  end

  defp segments_start_with?(segments, prefix) do
    length(prefix) <= length(segments) and Enum.take(segments, length(prefix)) === prefix
  end

  defp all_atoms?(segments), do: Enum.all?(segments, &is_atom/1)

  defp elixir_prefixed?([Elixir | _rest]), do: true
  defp elixir_prefixed?(_module_segments), do: false

  defp strip_elixir_prefix([Elixir | module_segments]), do: module_segments
  defp strip_elixir_prefix(module_segments), do: module_segments

  defp reference(trigger, meta, reason) do
    %{trigger: trigger, line_no: meta[:line], column: meta[:column], reason: reason}
  end

  defp issue_for(reference, issue_meta) do
    format_issue(issue_meta,
      message: "#{reference.trigger} found — #{reference.reason}",
      trigger: reference.trigger,
      line_no: reference.line_no,
      column: reference.column
    )
  end
end
