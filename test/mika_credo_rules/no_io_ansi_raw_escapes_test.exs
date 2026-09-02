defmodule MikaCredoRules.NoIOANSIRawEscapesTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoIOANSIRawEscapes

  @lib_file "apps/my_app/lib/my_app/cli/banner.ex"
  @escaped_file "apps/my_app/lib/latest/banner.ex"

  @moduledoc_examples NoIOANSIRawEscapes
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoIOANSIRawEscapes"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a raw ANSI escape literal" do
    test "reports a bare escape sequence and locates it in the source" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "\e[32mDeploy succeeded\e[0m"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "raw"
        assert issue.message =~ "IO.ANSI.format"
      end)
    end

    test "reports an escape sequence built with <> concatenation, on distinct columns" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(text) do
          "\e[31m" <> text <> "\e[0m"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 3
        assert second.line_no === 3
        assert first.column !== second.column
      end)
    end

    test "reports an escape sequence in the static prefix of an interpolated string" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(name) do
          "\e[32mHello #{name}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue()
    end

    test "gives each single-line def its own line even when its literal holds two escapes" do
      ~S"""
      defmodule MyApp.Cli.CoverageBanner do
        def coverage1, do: "\e[32m100%\e[0m label1"
        def coverage2, do: "\e[33m50%\e[0m label2"
        def coverage3, do: "\e[31m0%\e[0m label3"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) === [2, 3, 4]
      end)
    end

    test "attributes the issue to the real violation, not a doc string spelling the escape as text above it" do
      ~S"""
      defmodule MyApp.Docs.EscapeCodes do
        @doc "the ANSI prefix is written \\e[ in source"
        def note, do: :ok

        def show, do: "\e[32mreal\e[0m"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "locates a \\x1b[ escape at the def's own line, not the module line" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show, do: "\x1b[32mok"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "locates a backslash-u-001b escape at the def's own line, not the module line" do
      # Built from char codes rather than typed literally so this source file
      # never carries a raw ESC byte or an already-decoded \u escape.
      u_escape = <<?\\, ?u, ?0, ?0, ?1, ?b>>

      """
      defmodule MyApp.Cli.Banner do
        def show, do: "#{u_escape}[32mok"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end
  end

  describe "&run/2 locates a raw escape precisely, even off its enclosing node's line" do
    test "locates a \\x1b[ literal below its enclosing node, at the literal's own column" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def hex, do: "\x1b[32mhex"

        def esc do
          "\e[31mesc"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 2
        assert first.column === 16
        assert second.line_no === 5
        assert second.column === 5
      end)
    end

    test "attributes to the real escape on the next line, not a decoy on the statement's own line" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          note = "written \\e[ in docs"
          "\e[32mreal"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.column === 5
      end)
    end

    test "locates a \\x1b[ literal inside a case clause body, not the arrow's own line" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          case :ok do
            :ok ->
              "\x1b[32mok"
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.column === 9
      end)
    end
  end

  describe "&run/2 locates a literal via its own AST position, never a source-text scan" do
    test "locates a literal that pipes into a multi-line call, not the operator's line" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "\e[32mDeploy succeeded\e[0m"
          |> String.trim()
          |> IO.puts()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        refute is_nil(issue.column)
      end)
    end

    test "does not let an earlier literal steal a later literal's position across a pipe chain" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def a do
          "\e[32mfirst"
          |> IO.puts()

          "\e[31msecond"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 3
        refute is_nil(first.column)
        assert second.line_no === 6
        refute is_nil(second.column)
      end)
    end

    test "does not let a single-backslash escape spelling in a comment steal the real violation's position" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          # writes \e[32m to stdout
          "\e[32mok"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "locates a \\u{1b}[ literal without stealing the next def's position" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def a, do: "\u{1b}[32mhex"

        def b, do: "\e[31mesc"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 2
        refute is_nil(first.column)
        assert second.line_no === 4
        refute is_nil(second.column)
      end)
    end

    test "does not flag a same-line text decoy, only the genuine escape literal after it" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "\\e[ looks real" <> "\e[32mreal"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue()
    end

    test "gives the second of two literals on one line its own position, not the first literal's leftover escape" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def a(t), do: "\e[32mx\e[0m" <> t <> "\e[31my"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === 2
        assert first.column === 17
        assert second.line_no === 2
        assert second.column === 40
      end)
    end
  end

  describe "&run/2 allows a real backslash-e that is not the ESC byte" do
    test "does not report literal backslash-e text" do
      ~S"""
      defmodule MyApp.Docs.EscapeCodes do
        def note do
          "the ANSI escape prefix is written as \\e[ in source"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report the ESC byte when it is not followed by [" do
      ~S"""
      defmodule MyApp.Docs.EscapeCodes do
        def note do
          "\e is the ESC control byte"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a 0-arity IO.ANSI call interpolated into a string" do
    test "reports a fully qualified IO.ANSI.green() interpolated with reset" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(text) do
          "#{IO.ANSI.green()}#{text}#{IO.ANSI.reset()}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn issues -> assert Enum.count(issues) === 2 end)
    end

    test "reports the line, trigger and message for a single interpolated call" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(text) do
          "#{text}#{IO.ANSI.reset()}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "IO.ANSI.reset"
        assert issue.message =~ "IO.ANSI.reset"
        assert issue.message =~ "interpolat"
      end)
    end

    test "reports a short alias under alias IO.ANSI" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        alias IO.ANSI

        def show(text) do
          "#{ANSI.green()}#{text}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue -> assert issue.trigger === "ANSI.green" end)
    end

    test "reports an interpolated call through an as: rename of IO.ANSI" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        alias IO.ANSI, as: Color

        def show(text) do
          "#{Color.green()}#{text}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "Color.green"
      end)
    end

    test "does not report a same-named alias to a different module" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        alias MyApp.ANSI

        def show(text) do
          "#{ANSI.green()}#{text}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "gives two interpolated calls on one line distinct columns" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(text) do
          "#{IO.ANSI.green()}#{text}#{IO.ANSI.reset()}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 allows IO.ANSI usage that never bypasses format/2" do
    test "does not report IO.ANSI.format/2 building ansidata" do
      """
      defmodule MyApp.Cli.Banner do
        def show(text) do
          IO.ANSI.format(["ok", :green, text], true)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report IO.ANSI.green() used outside string interpolation" do
      """
      defmodule MyApp.Cli.Banner do
        def show(text) do
          [IO.ANSI.green(), text, IO.ANSI.reset()]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report Kernel.to_string/1 hand-written around an IO.ANSI call" do
      """
      defmodule MyApp.Cli.Banner do
        def show do
          Kernel.to_string(IO.ANSI.green())
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report a hand-written to_string/1 call on the bare Kernel atom" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          :"Elixir.Kernel".to_string(IO.ANSI.green())
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report a plain variable interpolated into a string" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show(name) do
          "hello #{name}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end

    test "does not report a multi-arity IO.ANSI call interpolated into a string" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "#{IO.ANSI.color(1, 2, 3)}"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIOANSIRawEscapes)
      |> refute_issues()
    end
  end

  describe "&run/2 path scoping via :excluded_paths" do
    test "does not report an excluded path when opted in" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "\e[32mok\e[0m"
        end
      end
      """
      |> to_source_file("apps/my_app/lib/skip/banner.ex")
      |> run_check(NoIOANSIRawEscapes, excluded_paths: ["skip/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      ~S"""
      defmodule MyApp.Cli.Banner do
        def show do
          "\e[32mok\e[0m"
        end
      end
      """
      |> to_source_file(@escaped_file)
      |> run_check(NoIOANSIRawEscapes, excluded_paths: ["test/"])
      |> assert_issue()
    end
  end
end
