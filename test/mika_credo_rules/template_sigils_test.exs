defmodule MikaCredoRules.TemplateSigilsTest do
  use Credo.Test.Case

  alias MikaCredoRules.TemplateSigils

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  describe "collect/2 — sigil shapes" do
    test "finds a single-line ~H sigil body in def render(assigns)" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~H"<div>hello</div>"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert sigil.body === "<div>hello</div>"
      assert sigil.line_no === 3
    end

    test "finds a heredoc ~H sigil, content line one below the opening delimiter" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~H\"\"\"
            <div>hello</div>
            \"\"\"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert sigil.body === "<div>hello</div>\n"
      assert sigil.line_no === 4
    end

    test "returns [] when the file has no matching sigil" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns), do: assigns
        end
        """
        |> to_source_file(@filename)

      assert TemplateSigils.collect(source_file, [:sigil_H]) === []
    end

    test "filters by the sigils param — a ~F body is ignored when only :sigil_H is requested" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns), do: ~H"<div/>"
          def other(assigns), do: ~F"<div/>"
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert sigil.body === "<div/>"
    end

    test "returns every matching sigil in source order" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def first(assigns), do: ~H"<div>one</div>"
          def second(assigns), do: ~H"<div>two</div>"
        end
        """
        |> to_source_file(@filename)

      assert [first, second] = TemplateSigils.collect(source_file, [:sigil_H])
      assert first.body === "<div>one</div>"
      assert second.body === "<div>two</div>"
    end

    test "joins only the binary parts of an interpolating sigil, dropping the interpolation node" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~h\"\"\"
            <div>\#{@name}</div>
            \"\"\"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_h])
      assert sigil.body === "<div></div>\n"
    end
  end

  describe "line_at/2" do
    test "resolves the physical source line of a byte offset inside a multi-line body" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~H\"\"\"
            <div class="a">
              <span>Hi</span>
            </div>
            \"\"\"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      {offset, _length} = :binary.match(sigil.body, "<span>")

      assert TemplateSigils.line_at(sigil, offset) === 5
    end

    test "resolves the same line as the sigil for a single-line body" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns), do: ~H"<div>hello</div>"
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      {offset, _length} = :binary.match(sigil.body, "hello")

      assert TemplateSigils.line_at(sigil, offset) === 2
    end
  end

  describe "column_at/2" do
    test "resolves the real file column of a byte offset inside a single-line body" do
      source = """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H(<div style="x">hi</div>)
      end
      """

      source_file = to_source_file(source, @filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      {offset, _length} = :binary.match(sigil.body, "style=")

      raw_line = source |> String.split("\n") |> Enum.at(1)
      {expected_offset, _length} = :binary.match(raw_line, "style=")

      assert TemplateSigils.column_at(sigil, offset) === expected_offset + 1
    end

    test "resolves the real file column of the very first byte of a single-line body" do
      source = """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H"<div/>"
      end
      """

      source_file = to_source_file(source, @filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])

      raw_line = source |> String.split("\n") |> Enum.at(1)
      {expected_offset, _length} = :binary.match(raw_line, "<div/>")

      assert TemplateSigils.column_at(sigil, 0) === expected_offset + 1
    end

    test "adds back the indentation stripped from a heredoc body" do
      source = """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div>
            <span class="a">hi</span>
          </div>
          \"\"\"
        end
      end
      """

      source_file = to_source_file(source, @filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      {offset, _length} = :binary.match(sigil.body, "class=")

      raw_line = source |> String.split("\n") |> Enum.at(4)
      {expected_offset, _length} = :binary.match(raw_line, "class=")

      assert TemplateSigils.column_at(sigil, offset) === expected_offset + 1
    end
  end

  describe "line_count/1" do
    test "counts the number of physical lines a heredoc body spans" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~H\"\"\"
            <div>
              <span>Hi</span>
            </div>
            \"\"\"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert TemplateSigils.line_count(sigil) === 3
    end

    test "counts a single-line body as one line" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns), do: ~H"<div/>"
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert TemplateSigils.line_count(sigil) === 1
    end

    test "counts a genuine trailing blank line inside the body, not just the heredoc's own closing artifact" do
      source_file =
        """
        defmodule MyAppWeb.Comp do
          def render(assigns) do
            ~H\"\"\"
            <div>hi</div>

            \"\"\"
          end
        end
        """
        |> to_source_file(@filename)

      assert [sigil] = TemplateSigils.collect(source_file, [:sigil_H])
      assert TemplateSigils.line_count(sigil) === 2
    end
  end
end
