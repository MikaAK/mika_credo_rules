defmodule MikaCredoRules.HttpWrapperRequiresPoolNameTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.HttpWrapperRequiresPoolName

  @lib_file "apps/my_app/lib/my_app/courses.ex"
  @test_file "apps/my_app/test/my_app/courses_test.exs"

  @moduledoc_examples HttpWrapperRequiresPoolName
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "HttpWrapperRequiresPoolName"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end
  end

  describe "&run/2 flags an adapter attribute with no way to carry name:" do
    test "reports a bare adapter module with no opts position at all" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "@adapter"
        assert issue.message =~ "name:"
        assert issue.message =~ "KeyError"
      end)
    end

    test "reports an adapter tuple with an empty literal opts list" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, []}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end

    test "reports an adapter tuple whose literal opts lack name:" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, pool_size: 10}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue()
    end
  end

  describe "&run/2 allows a literal name: and non-matching attributes" do
    test "does not report a literal opts list containing name:" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, name: __MODULE__}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report opts held in a nested attribute" do
      """
      defmodule MyApp.Courses do
        @default_adapter_opts [name: __MODULE__]
        @adapter {Tesla.Adapter.Finch, @default_adapter_opts}

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], @adapter, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report opts built from a function call" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, adapter_opts()}

        defp adapter_opts, do: [name: __MODULE__]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report a literal opts list holding a plain string, not a keyword pair" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, ["name"]}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report a literal opts list with a string-keyed pair instead of an atom key" do
      """
      defmodule MyApp.Courses do
        @adapter {Tesla.Adapter.Finch, [{"name", __MODULE__}]}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report a non-configured adapter module" do
      """
      defmodule MyApp.Courses do
        @adapter {MyApp.VendorAdapter, []}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not report a differently-named attribute" do
      """
      defmodule MyApp.Courses do
        @pool_size Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end
  end

  describe "&run/2 is alias-aware" do
    test "resolves an aliased adapter module back to Tesla.Adapter.Finch" do
      """
      defmodule MyApp.Courses do
        alias Tesla.Adapter.Finch

        @adapter {Finch, []}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end

    test "does not report a project module that shadows the bare alias name" do
      """
      defmodule MyApp.Courses do
        alias MyApp.Finch

        @adapter Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end
  end

  describe "&run/2 recognises an Erlang-atom-literal module spelling" do
    test "fires on a bare adapter written as an Elixir-prefixed atom literal" do
      """
      defmodule MyApp.Courses do
        @adapter :"Elixir.Tesla.Adapter.Finch"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end

    test "fires on a tuple adapter written as an Elixir-prefixed atom literal" do
      """
      defmodule MyApp.Courses do
        @adapter {:"Elixir.Tesla.Adapter.Finch", []}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue()
    end

    test "does not report a tuple adapter atom literal that already carries name:" do
      """
      defmodule MyApp.Courses do
        @adapter {:"Elixir.Tesla.Adapter.Finch", name: __MODULE__}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "stays silent, not crashing, on an Erlang atom that is not an Elixir module" do
      """
      defmodule MyApp.Courses do
        @adapter :maps
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not fire on a bare atom-literal spelling that only matches through an alias's local name" do
      """
      defmodule MyApp.Courses do
        alias Tesla.Adapter.Finch

        @adapter :"Elixir.Finch"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "does not fire on a tuple atom-literal spelling that only matches through an alias's local name" do
      """
      defmodule MyApp.Courses do
        alias Tesla.Adapter.Finch

        @adapter {:"Elixir.Finch", []}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end
  end

  describe "&run/2 path scoping" do
    test "does not report a test file by default" do
      """
      defmodule MyApp.CoursesTest do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file("apps/my_app/lib/latest/courses.ex")
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.CoursesTest do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(HttpWrapperRequiresPoolName, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 params override" do
    test "respects a custom :attribute name" do
      """
      defmodule MyApp.Courses do
        @pool_adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, attribute: :pool_adapter)
      |> assert_issue(fn issue -> assert issue.trigger === "@pool_adapter" end)
    end

    test "respects a custom :adapter_modules list" do
      """
      defmodule MyApp.Courses do
        @adapter {MyApp.VendorAdapter, []}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, adapter_modules: [MyApp.VendorAdapter])
      |> assert_issue()
    end

    test "accepts :attribute as a string, matching the same atom name" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, attribute: "adapter")
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end
  end

  describe "&run/2 params hardening" do
    test "does not crash on a bare (non-list) :adapter_modules value" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, adapter_modules: Tesla.Adapter.Finch)
      |> assert_issue()
    end

    test "silently ignores a non-module entry in :adapter_modules rather than raising" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName,
        adapter_modules: [:tesla_finch, "Tesla.Adapter.Finch", Tesla.Adapter.Finch]
      )
      |> assert_issue()
    end

    test "stays silent, not crashing, when every :adapter_modules entry is non-module" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, adapter_modules: [:tesla_finch])
      |> refute_issues()
    end

    test "does not crash on a bare (non-list) :excluded_paths value" do
      """
      defmodule MyApp.CoursesTest do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(HttpWrapperRequiresPoolName, excluded_paths: "test/")
      |> refute_issues()
    end

    test "does not crash when :excluded_paths holds only non-binary entries" do
      """
      defmodule MyApp.CoursesTest do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(HttpWrapperRequiresPoolName, excluded_paths: [:test, nil])
      |> assert_issue()
    end

    test "still respects a valid entry alongside a non-binary one in :excluded_paths" do
      """
      defmodule MyApp.CoursesTest do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@test_file)
      |> run_check(HttpWrapperRequiresPoolName, excluded_paths: [:test, "test/"])
      |> refute_issues()
    end

    test "does not crash on a non-atom, non-binary :attribute value, falling back to the default" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName, attribute: [:adapter])
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end
  end

  describe "&run/2 known false positive (documented, not fixed)" do
    test "still fires on a bare attribute even when the call site splices name: around it" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch

        def new(opts \\\\ []) do
          SharedUtils.HTTP.client([], {@adapter, name: __MODULE__}, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue -> assert issue.trigger === "@adapter" end)
    end
  end

  describe "&run/2 locates the issue at the attribute" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issue(fn issue -> assert issue.column === 3 end)
    end

    test "gives each of two attributes on one line its own column" do
      """
      defmodule MyApp.Courses do
        @adapter Tesla.Adapter.Finch; @adapter Tesla.Adapter.Finch
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(HttpWrapperRequiresPoolName)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
