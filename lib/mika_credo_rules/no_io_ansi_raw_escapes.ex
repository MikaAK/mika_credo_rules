# credo:disable-for-this-file MikaCredoRules.NoIOANSIRawEscapes
defmodule MikaCredoRules.NoIOANSIRawEscapes do
  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [
      excluded_paths: []
    ],
    explanations: [
      params: [
        excluded_paths: """
        A list of path fragments naming files this check skips (matched on
        segment boundaries). Defaults to `[]`.
        """
      ]
    ]

  alias MikaCredoRules.AstHelpers
  alias MikaCredoRules.SourceFilter

  @moduledoc """
  ANSI color codes must go through `IO.ANSI.format/2`, never a raw escape
  literal or a live `IO.ANSI` call interpolated straight into a string.

  A raw escape literal (the ESC control byte followed by `[`) hardcodes a
  terminal control sequence that `IO.ANSI.format/2` would otherwise emit
  conditionally — it always prints the color, even when `IO.ANSI.format/2`
  would have been called with `emit` false for a non-tty, and it carries no
  meaning to a reader without decoding the byte. Interpolating a live
  `IO.ANSI.<fun>()` call directly into a string bypasses `format/2` the same
  way, just spelled with a function call instead of a literal byte.

      # BAD — a raw escape sequence hardcodes the terminal control bytes
      def banner do
        "\e[32mDeploy succeeded\e[0m"
      end

      # BAD — a live IO.ANSI call interpolated straight into the string
      def banner(text) do
        "\#{IO.ANSI.green()}\#{text}"
      end

      # GOOD — build ansidata and let IO.ANSI.format/2 emit the codes
      def banner(text) do
        IO.ANSI.format([:green, text], true)
      end

  Only a string literal containing the actual ESC control byte (`0x1B`)
  immediately followed by `[` is flagged, however it is spelled in source
  (`\\e[`, `\\x1B[`, `\\u001B[`, `\\u{1B}[`, ...) — a decoded literal never
  contains that byte unless the source really meant it, so a doc string
  spelling the escape as plain text (a literal backslash then `e`, such as
  `"\\\\e[" `) is a different binary and is left alone. Only a dot-qualified,
  0-arity `IO.ANSI.<fun>()` call is flagged when it is the interpolated
  expression itself — through any alias of `IO.ANSI`, including an `as:`
  rename — the same call built into an iolist by hand, e.g.
  `[IO.ANSI.green(), text]`, never goes through string interpolation and is
  left alone.

  ## Limitations

    * A concatenated or dynamically built escape sequence (`<<0x1B>> <>
      "[32m"`, or an ANSI code held in a variable before being interpolated)
      is invisible — static analysis only sees the literal source text.
    * Only a 0-arity, dot-qualified `IO.ANSI.<fun>()` call interpolated
      directly is caught. A multi-arity call interpolated the same way
      (`"\#{IO.ANSI.color(1, 2, 3)}"`), or an unqualified call reached through
      `import IO.ANSI`, is not.
    * A charlist escape (`~c"\e[32mok"`) is invisible — only a string
      (`is_binary/1`) literal is scanned.
    * A `~s`/`~S` sigil escape (`~s"\e[32mok"`) is invisible too — a sigil
      holds its raw, undecoded source text in the AST, so the ESC byte is
      never present for the check to see.
  """
  @explanation [check: @moduledoc]

  @escape_byte_pattern <<0x1B, ?[>>
  @parse_opts [columns: true, token_metadata: true, emit_warnings: false]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    if excluded_path?(source_file.filename, excluded_paths(params)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ansi_modules = AstHelpers.resolve_aliases(source_file, [IO.ANSI])

      (interpolation_matches(source_file, ansi_modules) ++ raw_escape_matches(source_file))
      |> Enum.sort_by(&{&1.line_no, &1.column})
      |> Enum.map(&issue_for(&1, issue_meta))
    end
  end

  defp excluded_paths(params), do: Params.get(params, :excluded_paths, __MODULE__)

  defp excluded_path?(filename, excluded_paths) do
    SourceFilter.matches_fragment?(filename, excluded_paths)
  end

  defp interpolation_matches(source_file, ansi_modules) do
    Credo.Code.prewalk(source_file, &traverse(&1, &2, ansi_modules), [])
  end

  # Compiler-desugared string interpolation: `"#{IO.ANSI.green()}"` expands to
  # a `Kernel.to_string/1` call whose module slot is the bare atom `Kernel`
  # (never `{:__aliases__, _, [:Kernel]}`, which is what a hand-written
  # `Kernel.to_string(...)` call parses to), and whose own meta carries
  # `from_interpolation: true`. Only a 0-arity, dot-qualified `IO.ANSI.<fun>()`
  # call as the interpolated expression matches. The enclosing `__aliases__`
  # node already carries the real line/column for this call, so no extra
  # position work is needed here.
  defp traverse(
         {{:., _, [Kernel, :to_string]}, meta,
          [{{:., _, [{:__aliases__, alias_meta, module}, function]}, _, []}]} = ast,
         matches,
         ansi_modules
       ) do
    if meta[:from_interpolation] && module in ansi_modules do
      trigger = "#{Enum.join(module, ".")}.#{function}"

      match = %{
        kind: :interpolation,
        trigger: trigger,
        line_no: alias_meta[:line],
        column: alias_meta[:column]
      }

      {ast, [match | matches]}
    else
      {ast, matches}
    end
  end

  defp traverse(ast, matches, _ansi_modules), do: {ast, matches}

  # Credo's own AST (`Credo.Code.ast/1`, used above for interpolation) is
  # parsed WITHOUT a `literal_encoder`, so a bare string leaf carries no
  # position of its own — locating a raw escape used to mean scanning the
  # file's raw source text outward from the nearest ancestor node's line,
  # which could land on the wrong line entirely (an ancestor's line is not
  # always at-or-before a multi-line operand's line) or match a decoy
  # spelling sitting between the anchor and the real literal (a comment, a
  # doc string). Parsing the source a second time, here, with a
  # `literal_encoder` that wraps every literal in a `__block__` node fixes
  # that at the root: each string literal then carries its OWN exact
  # `line`/`column` straight from the tokenizer, so no scanning is needed —
  # and no other node's position can ever be attributed to it. A string
  # literal's decoded runtime value is what the encoder receives, so every
  # source spelling of the ESC byte (backslash-e, backslash-x1B,
  # backslash-u001B, backslash-u-brace-1B-brace, the raw byte itself, ...)
  # shows up identically, and a decoy spelled as literal text (a doubled
  # backslash before the letter e) decodes to a real backslash character,
  # never the ESC byte — no separate parity check is needed either.
  defp raw_escape_matches(source_file) do
    source = Credo.SourceFile.source(source_file)

    case Code.string_to_quoted(source, [{:literal_encoder, &literal_encoder/2} | @parse_opts]) do
      {:ok, ast} ->
        {_ast, matches} = Macro.prewalk(ast, [], &collect_raw_escape/2)
        matches

      {:error, _reason} ->
        []
    end
  end

  defp literal_encoder(literal, meta), do: {:ok, {:__block__, meta, [literal]}}

  # A plain (non-interpolated) string literal — the common case.
  defp collect_raw_escape({:__block__, meta, [literal]} = ast, matches) when is_binary(literal) do
    {ast, add_raw_escape_match(matches, literal, meta)}
  end

  # An interpolated string's STATIC segments are not run through the
  # `literal_encoder` (only the whole `<<>>` node and the dynamic
  # `to_string(...)` segments carry position info), so a raw escape sitting
  # in the static text is attributed to the enclosing `<<>>` node instead of
  # a segment of its own.
  defp collect_raw_escape({:<<>>, meta, segments} = ast, matches) when is_list(segments) do
    if Enum.any?(segments, &raw_escape_segment?/1) do
      {ast, [raw_escape_match(meta) | matches]}
    else
      {ast, matches}
    end
  end

  defp collect_raw_escape(ast, matches), do: {ast, matches}

  defp raw_escape_segment?(segment) when is_binary(segment) do
    String.contains?(segment, @escape_byte_pattern)
  end

  defp raw_escape_segment?(_segment), do: false

  defp add_raw_escape_match(matches, literal, meta) do
    if String.contains?(literal, @escape_byte_pattern) do
      [raw_escape_match(meta) | matches]
    else
      matches
    end
  end

  # `delimiter` is the opening quote character sitting at this exact
  # line/column, so it doubles as a real, self-validating trigger — no
  # `Issue.no_trigger()` needed.
  defp raw_escape_match(meta) do
    %{kind: :raw_escape, trigger: meta[:delimiter], line_no: meta[:line], column: meta[:column]}
  end

  defp issue_for(match, issue_meta) do
    format_issue(issue_meta,
      message: message_for(match),
      trigger: match.trigger,
      line_no: match.line_no,
      column: match.column
    )
  end

  defp message_for(%{kind: :interpolation, trigger: trigger}) do
    "#{trigger} found — interpolating a live IO.ANSI call bypasses IO.ANSI.format/2; build ansidata and pass it through format/2 instead"
  end

  defp message_for(%{kind: :raw_escape}) do
    "raw ANSI escape found — bypasses IO.ANSI.format/2; build ansidata (e.g. [:green, \"text\"]) and pass it through format/2 instead"
  end
end
