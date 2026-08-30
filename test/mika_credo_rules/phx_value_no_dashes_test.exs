defmodule MikaCredoRules.PhxValueNoDashesTest do
  use Credo.Test.Case

  alias MikaCredoRules.PhxValueNoDashes

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  describe "&run/2 flags a dashed multiword phx-value key" do
    test "reports phx-value-group-id" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-click="del" phx-value-group-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "phx-value-group-id"

        assert issue.message ===
                 "phx-value-group-id found — " <>
                   "use underscores in multiword phx-value keys (phx-value-group_id)"
      end)
    end

    test "reports a key with more than one dash" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-foo-bar-baz="1">x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-foo-bar-baz" end)
    end

    test "reports each dashed occurrence with its own line" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-group-id={@id}>x</button>
          <button phx-value-order-id={@oid}>y</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [4, 5]
      end)
    end
  end

  describe "&run/2 leaves valid phx-value keys alone" do
    test "does not report a single-word key" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> refute_issues()
    end

    test "does not report an underscored multiword key" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-group_id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> refute_issues()
    end

    test "does not report a dash inside the attribute's value" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-id="a-b">x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> refute_issues()
    end
  end

  describe "&run/2 sigils param" do
    test "inspects ~F bodies when configured" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <button phx-value-group-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-group-id" end)
    end

    test "ignores every sigil not listed in :sigils" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <button phx-value-group-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes, sigils: [:sigil_H])
      |> refute_issues()
    end
  end

  describe "&run/2 scoping" do
    test "excludes configured paths" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-value-group-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes, excluded_paths: ["live/"])
      |> refute_issues()
    end
  end

  describe "&run/2 accepts every sigil form" do
    test "single-line ~H form" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns), do: ~H(<button phx-value-group-id={@id}>x</button>)
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-group-id" end)
    end

    test "fires inside a .exs test file" do
      """
      defmodule MyAppWeb.CompTest do
        use ExUnit.Case

        def render(assigns) do
          ~H\"\"\"
          <button phx-value-group-id={@id}>x</button>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/test/my_app_web/comp_test.exs")
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-group-id" end)
    end
  end

  describe "moduledoc examples" do
    test "the BAD example fires" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-click="del" phx-value-group-id={@id}>
            Delete
          </button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> assert_issue(fn issue -> assert issue.trigger === "phx-value-group-id" end)
    end

    test "the GOOD example is clean" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <button phx-click="del" phx-value-group_id={@id}>
            Delete
          </button>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(PhxValueNoDashes)
      |> refute_issues()
    end
  end
end
