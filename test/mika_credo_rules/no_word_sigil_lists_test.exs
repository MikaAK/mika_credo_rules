defmodule MikaCredoRules.NoWordSigilListsTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoWordSigilLists

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags ~w sigils" do
    test "reports a ~w(...)a atom list" do
      """
      defmodule MyApp.Worker do
        @enforce_keys ~w(id type changes)a
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "~w"
        assert issue.message =~ "~w found"
        assert issue.message =~ "list literal"
      end)
    end

    test "reports a plain ~w(...) string list" do
      """
      defmodule MyApp.Worker do
        def keys, do: Map.take(%{}, ~w(customer_id customer_name))
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issue(fn issue -> assert issue.trigger === "~w" end)
    end

    test "reports each ~w sigil on its own column when repeated on one line" do
      """
      defmodule MyApp.Worker do
        def keys, do: ~w(a b) ++ ~w(c d)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end
  end

  describe "&run/2 flags ~W sigils" do
    test "reports a ~W(...) list" do
      """
      defmodule MyApp.Worker do
        def keys, do: ~W(a b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issue(fn issue -> assert issue.trigger === "~W" end)
    end
  end

  describe "&run/2 does not flag list literals" do
    test "does not report an atom list literal" do
      """
      defmodule MyApp.Worker do
        @enforce_keys [:id, :type, :changes]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> refute_issues()
    end

    test "does not report a string list literal" do
      """
      defmodule MyApp.Worker do
        def keys, do: Map.take(%{}, ["customer_id"])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> refute_issues()
    end

    test "does not report unrelated sigils" do
      """
      defmodule MyApp.Worker do
        def pattern, do: ~r/abc/
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> refute_issues()
    end
  end

  describe "&run/2 honors :sigils" do
    test "does not report ~w when only ~W is configured" do
      """
      defmodule MyApp.Worker do
        @enforce_keys ~w(id type)a
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists, sigils: [:sigil_W])
      |> refute_issues()
    end

    test "still reports ~W when only ~W is configured" do
      """
      defmodule MyApp.Worker do
        def keys, do: ~W(a b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists, sigils: [:sigil_W])
      |> assert_issue()
    end
  end

  describe "&run/2 requires the real sigil argument shape" do
    test "does not report a user-defined sigil_w/2 function call" do
      """
      defmodule MyApp.Worker do
        import Kernel, except: [sigil_w: 2]

        def sigil_w(term, _mods), do: term

        def keys, do: sigil_w("id type", [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> refute_issues()
    end

    test "still reports a real ~w sigil in the same file" do
      """
      defmodule MyApp.Worker do
        import Kernel, except: [sigil_w: 2]

        def sigil_w(term, _mods), do: term

        def keys, do: ~w(id type)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issue(fn issue -> assert issue.trigger === "~w" end)
    end
  end

  describe "&run/2 honors :excluded_paths" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        @enforce_keys ~w(id type)a
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/worker.ex")
      |> run_check(NoWordSigilLists, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "reports the moduledoc BAD examples" do
      """
      @enforce_keys ~w(id type changes)a
      Map.take(changes, ~w(customer_id customer_name))
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "does not report the moduledoc GOOD examples" do
      """
      @enforce_keys [:id, :type, :changes]
      Map.take(changes, ["customer_id", "customer_name"])
      """
      |> to_source_file(@lib_file)
      |> run_check(NoWordSigilLists)
      |> refute_issues()
    end
  end
end
