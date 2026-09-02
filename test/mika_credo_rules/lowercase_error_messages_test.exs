defmodule MikaCredoRules.LowercaseErrorMessagesTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.LowercaseErrorMessages

  @lib_file "apps/my_app/lib/my_app/users.ex"

  @moduledoc_examples LowercaseErrorMessages
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "LowercaseErrorMessages"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a trailing . or ! on an ErrorMessage constructor" do
    test "reports a trailing period on ErrorMessage.not_found/1" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "ErrorMessage.not_found"
        assert issue.message =~ "trailing . or !"
      end)
    end

    test "reports a trailing bang on ErrorMessage.bad_request/1" do
      """
      defmodule MyApp.Users do
        def create(nil) do
          ErrorMessage.bad_request("Missing params!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue -> assert issue.trigger === "ErrorMessage.bad_request" end)
    end

    test "does not report a message with no trailing punctuation" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("user not found")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report a trailing question mark" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("did you mean this user?")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report an interpolated string whose last segment is the interpolation" do
      """
      defmodule MyApp.Users do
        def find(id) do
          ErrorMessage.not_found("missing: \#{id}")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "reports an interpolated string whose last segment is a literal terminator" do
      """
      defmodule MyApp.Users do
        def find(id) do
          ErrorMessage.not_found("missing: \#{id}.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue()
    end

    test "does not report a non-string first argument" do
      """
      defmodule MyApp.Users do
        def find(reason) do
          ErrorMessage.not_found(reason)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "only inspects the first argument, never the details argument" do
      """
      defmodule MyApp.Users do
        def find(id) do
          ErrorMessage.not_found("user not found", %{reason: "expired."})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report an unrelated module sharing a constructor name" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          Other.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report a constructor outside the default :functions list" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.length_required("Content-Length is required.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a trailing . or ! on raise/2" do
    test "reports raise Mod, \"message.\"" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise ArgumentError, "Bad input!"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "raise"
        assert issue.message =~ "trailing . or !"
      end)
    end

    test "reports raise Mod, message: \"message.\"" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise ArgumentError, message: "Bad input!"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue -> assert issue.trigger === "raise" end)
    end

    test "does not report raise Mod, message: \"message\" with no trailing punctuation" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise ArgumentError, message: "bad input"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report raise Mod, opts without a :message key" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise ArgumentError, plug_status: 400
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report raise Mod with no message" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise ArgumentError
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report raise/1 with a bare string, unpiped" do
      """
      defmodule MyApp.Users do
        def validate!(:invalid) do
          raise "Bad input!"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a piped raise, which folds the LHS into raise/1's argument" do
    test "reports Mod |> raise(\"message.\")" do
      """
      defmodule MyApp.Users do
        def go, do: ArgumentError |> raise("Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 32
        assert issue.trigger === "raise"
      end)
    end

    test "reports Mod |> raise(message: \"message.\")" do
      """
      defmodule MyApp.Users do
        def go, do: ArgumentError |> raise(message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue -> assert issue.trigger === "raise" end)
    end

    test "does not report a piped raise with no trailing punctuation" do
      """
      defmodule MyApp.Users do
        def go, do: ArgumentError |> raise("bad input")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  describe "&run/2 raise/2: the deleted source-scanner's location bugs no longer exist" do
    test "positional form: an identical literal in the exception argument no longer steals the column" do
      """
      defmodule MyApp.Users do
        def go, do: raise(MyErr.new("Bad!"), "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "raise"
      end)
    end

    test "keyword form, single line: an identical literal in an earlier key never could and still cannot steal the column" do
      """
      defmodule MyApp.Users do
        def go, do: raise(ArgumentError, code: "Bad!", message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "raise"
      end)
    end

    test "keyword form, multi-line: an identical literal on an earlier line no longer steals the line" do
      """
      defmodule MyApp.Users do
        def go do
          raise(ArgumentError,
            code: "Bad!",
            message: "Bad!"
          )
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "raise"
      end)
    end

    test "a message: key nested in an earlier sibling value on the same line no longer steals the column" do
      """
      defmodule MyApp.Users do
        def go, do: raise(ArgumentError, details: %{message: "Bad!"}, message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "raise"
      end)
    end

    test "a message: key nested in an earlier sibling value on an earlier line no longer steals the line" do
      """
      defmodule MyApp.Users do
        def go do
          raise(ArgumentError,
            details: %{message: "Bad!"},
            message: "Bad!"
          )
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "raise"
      end)
    end

    test "a message: key inside the EXCEPTION argument (not a sibling) does not steal the location either" do
      """
      defmodule MyApp.Users do
        def go, do: raise(MyErr.exception(%{message: "Bad!"}), message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "raise"
      end)
    end
  end

  describe "&run/2 raise/2 positional form: two raises on one line each get their own issue" do
    test "two raises sharing one line each get their own issue, not one stolen match" do
      """
      defmodule MyApp.Users do
        def go(x), do: if(x, do: raise(A, "Bad!"), else: raise(B, "Bad!"))
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 2
        assert first.column === 28
        assert second.line_no === 2
        assert second.column === 52
      end)
    end

    test "a trailing comment repeating the message does not affect the reported column" do
      """
      defmodule MyApp.Users do
        def go, do: raise(ArgumentError, "Bad!") # was "Bad!" before
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "raise"
      end)
    end
  end

  describe "&run/2 raise/2 keyword form: each raise resolves to its own line" do
    test "does not let a sibling function-head pattern's message: key affect the column" do
      """
      defmodule MyApp.Users do
        def go(%{message: "Bad!"}), do: raise(ArgumentError, message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 35
        assert issue.trigger === "raise"
      end)
    end

    test "resolves two raises to their own line, never swapped" do
      """
      defmodule MyApp.Users do
        def a, do: raise(ArgumentError, [{:message, "Bad!"}])
        def b, do: raise(ArgumentError, message: "Bad!")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 2
        assert second.line_no === 3
      end)
    end
  end

  describe "&run/2 gates the uppercase-first rule behind :enforce_lowercase_first" do
    test "does not report an uppercase-first message by default" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.bad_request("Cannot do that")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "reports an uppercase-first message when :enforce_lowercase_first is true" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.bad_request("Cannot do that")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, enforce_lowercase_first: true)
      |> assert_issue(fn issue ->
        assert issue.trigger === "ErrorMessage.bad_request"
        assert issue.message =~ "lowercase letter"
      end)
    end

    test "still allows a lowercase-first message when :enforce_lowercase_first is true" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.bad_request("cannot do that")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, enforce_lowercase_first: true)
      |> refute_issues()
    end

    test "reports an interpolation-last message when :enforce_lowercase_first is true" do
      """
      defmodule MyApp.Users do
        def find(id) do
          ErrorMessage.not_found("User \#{id}")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, enforce_lowercase_first: true)
      |> assert_issue(fn issue -> assert issue.message =~ "lowercase letter" end)
    end
  end

  describe "&run/2 respects a custom :functions list" do
    test "reports a narrowed constructor" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.bad_request("Bad request.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, functions: [:bad_request])
      |> assert_issue()
    end

    test "silences a default constructor dropped from the list" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, functions: [:bad_request])
      |> refute_issues()
    end
  end

  describe "&run/2 resolves ErrorMessage module identity through aliasing" do
    test "reports through a fully qualified Elixir.ErrorMessage" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          Elixir.ErrorMessage.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.ErrorMessage.not_found" end)
    end

    test "reports through an as: rename, with the trigger spelled as written at the call site" do
      """
      defmodule MyApp.Users do
        alias ErrorMessage, as: EM

        def find(nil) do
          EM.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.column === 5
        assert issue.trigger === "EM.not_found"
      end)
    end

    test "does not report once ErrorMessage is shadowed by a project alias" do
      """
      defmodule MyApp.Users do
        alias MyApp.Errors.ErrorMessage

        def find(nil) do
          ErrorMessage.not_found("User not found.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report once ErrorMessage is shadowed by a top-level defmodule" do
      """
      defmodule ErrorMessage do
        def wrap(reason) do
          ErrorMessage.not_found("Wrapped: \#{reason}.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report once ErrorMessage is shadowed by a nested defmodule" do
      """
      defmodule MyApp.Support do
        defmodule ErrorMessage do
          def not_found(reason), do: reason
        end

        def wrap(reason) do
          ErrorMessage.not_found("Wrapped: \#{reason}.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end
  end

  describe "&run/2 handles the piped constructor spelling" do
    test "reports message |> ErrorMessage.not_found()" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          "User not found." |> ErrorMessage.not_found()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 26
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "does not report a piped message with no trailing punctuation" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          "user not found" |> ErrorMessage.not_found()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report the details argument on a piped call" do
      """
      defmodule MyApp.Users do
        def go(msg) do
          msg |> ErrorMessage.not_found("expired.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "resolves two multi-line piped violations to their own call's line, not swapped" do
      """
      defmodule MyApp.Users do
        def a do
          "boom."
          |> ErrorMessage.not_found()
        end

        def b do
          "boom."
          |> ErrorMessage.bad_request()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 4
        assert second.line_no === 9
      end)
    end
  end

  describe "&run/2 anchors every issue at the call's own position, never at the message" do
    test "a multi-line direct call reports the call's own line, not the message's later line" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found(
            "User not found."
          )
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
      end)
    end

    test "a multi-line piped call reports the call's own line, not the message's earlier line" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          "User not found."
          |> ErrorMessage.not_found()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.column === 8
      end)
    end
  end

  describe "&run/2 locates each violation with a distinct column" do
    test "gives two violations on one line their own columns" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("User not found.") && ErrorMessage.bad_request("Bad request!")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end

    test "gives two IDENTICAL messages on one line their own columns" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found("Nope.") || ErrorMessage.bad_request("Nope.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end

    test "does not point at an earlier, non-call occurrence of the same literal" do
      """
      defmodule MyApp.Users do
        def find(%{reason: "Nope."}), do: ErrorMessage.not_found("Nope.")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 37
      end)
    end

    test "does not point at an earlier, non-call occurrence for a piped message" do
      """
      defmodule MyApp.Users do
        def find(%{r: "Nope."}), do: "Nope." |> ErrorMessage.not_found()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 43
      end)
    end

    test "reports a character-based column when a multibyte character precedes the trigger" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          log("café") && ErrorMessage.not_found("Nope.")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 20
      end)
    end

    test "reports the piped constructor's own line and column even with a multibyte character earlier on the line" do
      """
      defmodule MyApp.Users do
        def go, do: wrap("a😂", "Bad." |> ErrorMessage.not_found())
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 36
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "reports the piped constructor's own line, not an earlier same-text decoy on another line" do
      """
      defmodule MyApp.Users do
        def other, do: "Bad."
        def go, do: wrap("→→", "Bad." |> ErrorMessage.not_found())
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 36
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end
  end

  describe "&run/2 and heredoc messages" do
    test "does not report a sigil-built message" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found(~s(User not found.))
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "does not report a plain heredoc, whose trailing newline defeats the check" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found(\"\"\"
          User not found.
          \"\"\")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> refute_issues()
    end

    test "reports a line-continuation heredoc, at the call's own line and column" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found(\"\"\"
          User not found.\\
          \"\"\")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "reports a plain heredoc at the call's own line and column when :enforce_lowercase_first is true" do
      """
      defmodule MyApp.Users do
        def find(nil) do
          ErrorMessage.not_found(\"\"\"
          User not found
          \"\"\")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, enforce_lowercase_first: true)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "reports a line-continuation heredoc WITH interpolation at the call's own line and column" do
      """
      defmodule MyApp.Users do
        def go(id) do
          ErrorMessage.not_found(\"\"\"
          user \#{id} not found.\\
          \"\"\")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "reports an interpolated heredoc at the call's own line and column when :enforce_lowercase_first is true" do
      """
      defmodule MyApp.Users do
        def go(id) do
          ErrorMessage.not_found(\"\"\"
          User \#{id} not found
          \"\"\")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages, enforce_lowercase_first: true)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 5
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end

    test "reports a violation even when the compiled value differs from the literal source text (an escape sequence)" do
      """
      defmodule MyApp.Users do
        def go, do: ErrorMessage.not_found("bad\\x21")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(LowercaseErrorMessages)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 15
        assert issue.trigger === "ErrorMessage.not_found"
      end)
    end
  end
end
