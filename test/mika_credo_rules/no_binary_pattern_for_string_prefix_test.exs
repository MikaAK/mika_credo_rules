defmodule MikaCredoRules.NoBinaryPatternForStringPrefixTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoBinaryPatternForStringPrefix

  @lib_file "apps/my_app/lib/my_app/parser.ex"

  describe "&run/2 flags a string-prefix binary pattern" do
    test "reports a match on the left-hand side of =" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          <<"my", rest::binary>> = str
          rest
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "<<"

        assert issue.message ===
                 "<<>> string-prefix pattern found — match with concatenation instead"
      end)
    end

    test "reports a bare-variable segment (no explicit ::binary)" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          <<"GET ", rest>> = str
          rest
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a ::bytes-typed segment" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          <<"GET ", rest::bytes>> = str
          rest
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a function-clause head" do
      """
      defmodule MyApp.Parser do
        def parse(<<"GET ", path::binary>>), do: path
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports a function-clause head with a guard" do
      """
      defmodule MyApp.Parser do
        def parse(<<"GET ", path::binary>>) when byte_size(path) > 0 do
          path
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports a case clause pattern" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          case data do
            <<"GET ", path::binary>> -> path
            _other -> :unknown
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a fn clause pattern" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          handler = fn
            <<"GET ", path::binary>> -> path
            _other -> :unknown
          end

          handler.(data)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a with <- pattern" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          with <<"GET ", path::binary>> <- data do
            path
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a for <- generator pattern" do
      """
      defmodule MyApp.Parser do
        def parse(lines) do
          for <<"GET ", path::binary>> <- lines, do: path
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a nested pattern inside a tuple on the left-hand side of =" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          {:ok, <<"GET ", path::binary>>} = data
          path
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a one-liner def" do
      """
      defmodule MyApp.Parser do
        def parse(<<"GET ", path::binary>>), do: path
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports a pattern nested inside an if body" do
      """
      defmodule MyApp.Parser do
        def parse(data, flag) do
          if flag do
            <<"GET ", path::binary>> = data
            path
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end
  end

  describe "&run/2 allows genuine binary parsing" do
    test "does not report a ::size(n)-style segment" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          <<size::32, rest::binary>> = data
          {size, rest}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "does not report a ::8-typed segment mixed with a string literal" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          <<"GET", _::8, path::binary>> = data
          path
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "does not report a first segment that is not a string literal" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          <<byte::8, rest::binary>> = data
          {byte, rest}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end
  end

  describe "&run/2 allows a <<>> constructor" do
    test "does not report the right-hand side of =" do
      """
      defmodule MyApp.Parser do
        def build(rest) do
          x = <<"GET ", rest::binary>>
          x
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "does not report a call argument" do
      """
      defmodule MyApp.Parser do
        def build(rest) do
          IO.inspect(<<"GET ", rest::binary>>)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "does not report a cond clause head (an expression, not a pattern)" do
      """
      defmodule MyApp.Parser do
        def build(rest) do
          cond do
            <<"GET ", rest::binary>> === "GET x" -> 1
            true -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end
  end

  describe "&run/2 respects the excluded_paths param" do
    test "does not report a pattern in an excluded path" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          <<"GET ", rest::binary>> = str
          rest
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/parser.ex")
      |> run_check(NoBinaryPatternForStringPrefix, excluded_paths: ["legacy/"])
      |> refute_issues()
    end

    test "does not exempt a lookalike path (lib/legacy_helpers/parser.ex)" do
      """
      defmodule MyApp.LegacyHelpers.Parser do
        def parse(str) do
          <<"GET ", rest::binary>> = str
          rest
        end
      end
      """
      |> to_source_file("apps/my_app/lib/legacy_helpers/parser.ex")
      |> run_check(NoBinaryPatternForStringPrefix, excluded_paths: ["legacy/"])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example 1 (= match) fires" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          <<"my", rest::binary>> = str
          rest
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue()
    end

    test "moduledoc BAD example 2 (function head) fires" do
      """
      defmodule MyApp.Parser do
        def parse(<<"GET ", path::binary>>), do: path
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> assert_issue()
    end

    test "moduledoc GOOD example 1 (= match with <>) is clean" do
      """
      defmodule MyApp.Parser do
        def parse(str) do
          "my" <> rest = str
          rest
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "moduledoc GOOD example 2 (function head with <>) is clean" do
      """
      defmodule MyApp.Parser do
        def parse("GET " <> path), do: path
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "moduledoc GOOD example 3 (real byte-level parsing) is clean" do
      """
      defmodule MyApp.Parser do
        def parse(data) do
          <<size::32, rest::binary>> = data
          <<"GET", _::8, path::binary>> = rest
          {size, path}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end

    test "moduledoc GOOD example 4 (<<>> constructor) is clean" do
      """
      defmodule MyApp.Parser do
        def build(rest) do
          x = <<"GET ", rest::binary>>
          IO.inspect(<<"GET ", rest::binary>>)
          x
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBinaryPatternForStringPrefix)
      |> refute_issues()
    end
  end
end
