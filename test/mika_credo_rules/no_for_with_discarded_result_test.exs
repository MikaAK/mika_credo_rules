defmodule MikaCredoRules.NoForWithDiscardedResultTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoForWithDiscardedResult

  @lib_file "apps/my_app/lib/my_app/sync.ex"

  describe "&run/2 flags a for in statement position" do
    test "reports a for followed by another statement" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items do
            Cache.put(item)
          end

          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "for"

        assert issue.message ===
                 "for comprehension with discarded result found — use Enum.each/2 for side effects"
      end)
    end

    test "reports a one-liner for followed by another statement" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items, do: Cache.put(item)
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a for with into: in statement position" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items, into: %{}, do: {item, true}
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a for with reduce: in statement position" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items, reduce: %{} do
            acc -> Map.put(acc, item, true)
          end

          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a for inside an if branch, followed by another statement" do
      """
      defmodule MyApp.Sync do
        def sync(items, flag) do
          if flag do
            for item <- items, do: Cache.put(item)
            :ok
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a for inside a case clause body, followed by another statement" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          case items do
            [] ->
              :ok

            _list ->
              for item <- items, do: Cache.put(item)
              :ok
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue(fn issue -> assert issue.line_no === 8 end)
    end

    test "reports every discarded for in a block with its own line number" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items, do: Cache.put(item)
          for item <- items, do: Cache.warm(item)
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 4]
      end)
    end
  end

  describe "&run/2 allows a consumed for" do
    test "does not report a for that is the sole/last expression of a function body" do
      """
      defmodule MyApp.Sync do
        def user_ids(users) do
          for user <- users, do: user.id
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "does not report a for that is the last expression of a multi-statement block" do
      """
      defmodule MyApp.Sync do
        def user_ids(users) do
          Logger.debug("computing ids")

          for user <- users, do: user.id
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "does not report a for that is the whole body of a one-liner def" do
      """
      defmodule MyApp.Sync do
        def user_ids(users), do: for(user <- users, do: user.id)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "does not report a for assigned via =" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          ids = for item <- items, do: item.id
          broadcast(ids)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "does not report a for used as a call argument" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          IO.inspect(for item <- items, do: item.id)
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "does not report a for as a pipe stage" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for(item <- items, do: item.id) |> Enum.each(&IO.puts/1)
          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end
  end

  describe "&run/2 respects the excluded_paths param" do
    test "does not report a discarded for in an excluded path" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items, do: Cache.put(item)
          :ok
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/scripts/backfill.ex")
      |> run_check(NoForWithDiscardedResult, excluded_paths: ["scripts/"])
      |> refute_issues()
    end

    test "does not exempt a lookalike path (lib/vendor/remix/scripts/thing.ex)" do
      """
      defmodule MyApp.Vendor.Remix.Scripts.Thing do
        def sync(items) do
          for item <- items, do: Cache.put(item)
          :ok
        end
      end
      """
      |> to_source_file("apps/my_app/lib/vendor/remix/scripts/thing.ex")
      |> run_check(NoForWithDiscardedResult, excluded_paths: ["mix/scripts/"])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          for item <- items do
            Cache.put(item)
          end

          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> assert_issue()
    end

    test "moduledoc GOOD (Enum.each) example is clean" do
      """
      defmodule MyApp.Sync do
        def sync(items) do
          Enum.each(items, fn item ->
            Cache.put(item)
          end)

          :ok
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end

    test "moduledoc GOOD (return value) example is clean" do
      """
      defmodule MyApp.Sync do
        def user_ids(users) do
          for user <- users, do: user.id
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoForWithDiscardedResult)
      |> refute_issues()
    end
  end
end
