### `NoIOANSIRawEscapes`

Terminal color must go through `IO.ANSI.format/2`, never a raw escape
literal or a live `IO.ANSI` call interpolated straight into a string. A raw
`\e[Nm` byte sequence always prints, even when `IO.ANSI.format/2` would have
been called with `emit` false for a non-tty, and it means nothing to a
reader without decoding the byte. Interpolating `IO.ANSI.green()` directly
into a string bypasses `format/2` the same way, just spelled with a
function call instead of a literal byte.

```elixir
# BAD — a raw escape sequence hardcodes the terminal control bytes
def banner, do: "\e[32mDeploy succeeded\e[0m"

# BAD — a live IO.ANSI call interpolated straight into the string
def banner(text), do: "#{IO.ANSI.green()}#{text}"

# GOOD — build ansidata and let IO.ANSI.format/2 emit the codes
def banner(text), do: IO.ANSI.format([:green, text], true)
```

Only a string literal containing the actual ESC control byte (`0x1B`)
immediately followed by `[` is flagged — a doc string spelling out the
escape as literal text (`"\\e["`, a backslash then `e`) is a different
binary and is left alone. A 0-arity, dot-qualified `IO.ANSI.<fun>()` call is
flagged only when it is the interpolated expression itself — through any
alias of `IO.ANSI`, including an `as:` rename — the same call built into an
iolist by hand (`[IO.ANSI.green(), text]`) never goes through string
interpolation and is left alone.

**Limitations:** a concatenated or dynamically built escape sequence
(`<<0x1B>> <> "[32m"`, or an ANSI code held in a variable before being
interpolated) is invisible — static analysis only sees the literal source
text. Only a 0-arity, dot-qualified `IO.ANSI.<fun>()` call interpolated
directly is caught; a multi-arity call interpolated the same way
(`"#{IO.ANSI.color(1, 2, 3)}"`), or an unqualified call reached through
`import IO.ANSI`, is not. A charlist escape (`~c"\e[32mok"`) is invisible —
only a string literal is scanned. A `~s`/`~S` sigil escape (`~s"\e[32mok"`)
is invisible too — a sigil holds its raw, undecoded source text in the AST,
so the ESC byte is never present for the check to see.

| Param | Default | Meaning |
|---|---|---|
| `excluded_paths` | `[]` | Path fragments naming files this check skips. |
