defmodule MikaCredoRules.ImportComponentsNotAliasTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.ImportComponentsNotAlias

  @lib_file "apps/my_app_web/lib/my_app_web/live/course_show_live.ex"
  @test_file "apps/my_app_web/test/my_app_web/live/course_show_live_test.exs"

  @moduledoc_examples ImportComponentsNotAlias
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "ImportComponentsNotAlias"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end
  end

  describe "&run/2 flags aliasing a *Components module" do
    test "reports a plain alias of a *Components module" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CourseShowComponents

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "MyAppWeb.CourseShowComponents"
        assert issue.message =~ "import"
        assert issue.category === :readability
      end)
    end

    test "reports an alias renamed with as:, ignoring the rename" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CourseShowComponents, as: CSC

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue -> assert issue.trigger === "MyAppWeb.CourseShowComponents" end)
    end

    test "reports a components module nested more than one segment deep" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.Admin.CourseShowComponents

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue ->
        assert issue.trigger === "MyAppWeb.Admin.CourseShowComponents"
      end)
    end

    test "flags only the matching segment in a multi-alias group" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.{CourseShowComponents, Layouts}

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue ->
        assert issue.trigger === "CourseShowComponents"
        assert issue.column === 19
        assert issue.message =~ "MyAppWeb.CourseShowComponents"
      end)
    end

    test "flags a multi-alias group followed by a trailing options list" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.{CourseShowComponents, Layouts}, warn: false

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue -> assert issue.trigger === "CourseShowComponents" end)
    end
  end

  describe "&run/2 leaves import and non-Components aliases alone" do
    test "does not report an import of a *Components module" do
      """
      defmodule MyAppWeb.CourseShowLive do
        import MyAppWeb.CourseShowComponents

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not report a module whose last segment does not end with the suffix" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.Components.Card

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not report a name that contains but does not end with the suffix" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyApp.ComponentsRegistry

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not report a multi-alias group with no matching segments" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.{Layouts, Endpoint}

        def render(assigns) do
          assigns
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not report a namespace whose last segment exactly equals the suffix" do
      """
      defmodule MyAppWeb.CoreComponents do
        alias MyAppWeb.Components

        def render(assigns), do: Components.Icons.icon(assigns)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not report a deeply nested namespace whose last segment exactly equals the suffix" do
      """
      defmodule MyAppWeb do
        alias MyAppWeb.Live.Components

        def render(assigns), do: Components.Icons.icon(assigns)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end
  end

  describe "&run/2 stays silent on relative and macro-built alias targets (documented limitation)" do
    test "does not crash and does not report a plain __MODULE__-relative alias" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias __MODULE__.CardComponents

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not crash and does not report a __MODULE__-relative multi-alias group" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias __MODULE__.{CardComponents, Layouts}

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    # `__MODULE__.{A, B}` (no segment between) parses its base as bare
    # `{:__MODULE__, _, nil}`, which never matches the group clause's
    # `{:__aliases__, _, base}` pattern at all — the test above never
    # reaches `literal_alias?`, it just doesn't match the clause. Nesting a
    # segment between `__MODULE__` and the group (`__MODULE__.Nested.{...}`)
    # DOES produce an `__aliases__`-wrapped base, so this is the fixture
    # that actually exercises the group clause's `literal_alias?` guard.
    test "does not crash and does not report a __MODULE__-relative NESTED multi-alias group" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias __MODULE__.Nested.{CardComponents, Layouts}

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "does not crash and does not report an unquote-built alias target" do
      """
      defmodule MyMacro do
        defmacro build(mod) do
          quote do
            alias unquote(mod).CardComponents
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end
  end

  describe "&run/2 flags the Elixir-prefixed atom spelling of an alias target" do
    test "reports the :\"Elixir.MyAppWeb.CourseShowComponents\" atom spelling" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias :"Elixir.MyAppWeb.CourseShowComponents"

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === Credo.Issue.no_trigger()
        assert issue.message =~ "MyAppWeb.CourseShowComponents"
        assert issue.category === :readability
      end)
    end

    test "does not crash and does not report a bare erlang atom alias target" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias :application

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "drops the leading Elixir segment from the dotted spelling's message, matching the atom spelling" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias Elixir.MyAppWeb.CourseShowComponents

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 9
        assert issue.trigger === "Elixir.MyAppWeb.CourseShowComponents"
        assert issue.message =~ "import MyAppWeb.CourseShowComponents instead"
        refute issue.message =~ "Elixir."
      end)
    end
  end

  describe "&run/2 excludes test files by default" do
    test "does not report a components alias in a test file" do
      """
      defmodule MyAppWeb.CourseShowLiveTest do
        alias MyAppWeb.CourseShowComponents

        def build(assigns), do: CourseShowComponents.card(assigns)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(ImportComponentsNotAlias)
      |> refute_issues()
    end

    test "reports a components alias in a test file when :excluded_paths is overridden" do
      """
      defmodule MyAppWeb.CourseShowLiveTest do
        alias MyAppWeb.CourseShowComponents

        def build(assigns), do: CourseShowComponents.card(assigns)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(ImportComponentsNotAlias, excluded_paths: [])
      |> assert_issue()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CourseShowComponents

        def render(assigns), do: assigns
      end
      """
      |> to_source_file("apps/my_app_web/lib/latest/course_show_live.ex")
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue()
    end
  end

  describe "&run/2 respects a custom :suffixes param" do
    test "reports a module matching the overridden suffix instead of the default" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CardWidgets

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias, suffixes: ["Widgets"])
      |> assert_issue(fn issue -> assert issue.trigger === "MyAppWeb.CardWidgets" end)
    end

    test "does not report the default suffix once :suffixes is overridden" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CourseShowComponents

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias, suffixes: ["Widgets"])
      |> refute_issues()
    end
  end

  describe "&run/2 locates each match with its own column" do
    test "reports the column of the module segment, not the alias keyword" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.CourseShowComponents

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issue(fn issue -> assert issue.column === 9 end)
    end

    test "gives two matching segments in one multi-alias group distinct columns" do
      """
      defmodule MyAppWeb.CourseShowLive do
        alias MyAppWeb.{CourseShowComponents, CardComponents}

        def render(assigns), do: assigns
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(ImportComponentsNotAlias)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
