defmodule MikaCredoRules.NoCondElseAtomTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.NoCondElseAtom

  @lib_file "apps/my_app/lib/my_app/router.ex"

  describe "&run/2 flags a cond whose last clause head is :else" do
    test "reports the last clause" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            :else -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === ":else"

        assert issue.message ===
                 "cond clause head :else found — use `true` as the last cond branch"
      end)
    end

    test "reports a single-clause cond whose only clause is :else" do
      """
      defmodule MyApp.Router do
        def route(_x) do
          cond do
            :else -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports each cond in a file with its own line number" do
      """
      defmodule MyApp.Router do
        def route_a(x) do
          cond do
            a?(x) -> 1
            :else -> 2
          end
        end

        def route_b(x) do
          cond do
            b?(x) -> 1
            :else -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [5, 12]
      end)
    end
  end

  describe "&run/2 allows true and non-last atom heads" do
    test "does not report a cond whose last clause is true" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            true -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> refute_issues()
    end

    test "does not report a cond whose last clause head is a different atom" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            :other -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> refute_issues()
    end

    test "does not report a non-last clause head of :else" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            :else -> 1
            true -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> refute_issues()
    end

    test "does not report a last clause head with a guard" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            x when is_integer(x) -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> refute_issues()
    end
  end

  describe "&run/2 respects the disallowed_atoms param" do
    test "reports a custom disallowed atom" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            :default -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom, disallowed_atoms: [:default])
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report :else once removed from disallowed_atoms" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            :else -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom, disallowed_atoms: [:default])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            :else -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> assert_issue()
    end

    test "moduledoc GOOD example is clean" do
      """
      defmodule MyApp.Router do
        def route(x) do
          cond do
            a?(x) -> 1
            true -> 2
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoCondElseAtom)
      |> refute_issues()
    end
  end
end
