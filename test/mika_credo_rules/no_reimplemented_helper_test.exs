defmodule MikaCredoRules.NoReimplementedHelperTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoReimplementedHelper

  @worker_file "apps/my_app/lib/my_app/worker.ex"
  @shared_utils_file "apps/shared_utils/lib/shared_utils/map.ex"

  describe "&run/2 flags local definitions of shared helpers" do
    test "reports defp atomize_keys" do
      """
      defmodule MyApp.Worker do
        defp atomize_keys(map) do
          Map.new(map, fn {key, value} -> {String.to_existing_atom(key), value} end)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ "defp atomize_keys found"
        assert issue.message =~ "SharedUtils.Enum.atomize_keys/1"
      end)
    end

    test "reports def deep_merge with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def deep_merge(left, right) do
          Map.merge(left, right, fn _key, one, two -> deep_merge(one, two) end)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def deep_merge found — already exists as SharedUtils.Map.merge_deep_left/2, use it"
      end)
    end

    test "reports every helper in the default map" do
      """
      defmodule MyApp.Helpers do
        def atomize_keys(map), do: map
        def stringify_keys(map), do: map
        def deep_merge(left, right), do: Map.merge(left, right)
        def deep_struct_to_map(struct), do: struct
        def reject_nil_values(list), do: list
        def random_string(length), do: length
        def valid_email?(email), do: email =~ "@"
        def pluck(list, key), do: {list, key}
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issues(fn issues -> assert length(issues) === 8 end)
    end

    test "reports a definition with a guard clause" do
      """
      defmodule MyApp.Worker do
        def random_string(length) when is_integer(length) do
          length |> :crypto.strong_rand_bytes() |> Base.encode16()
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue -> assert issue.message =~ "def random_string found" end)
    end

    test "reports each definition site with its own line number" do
      """
      defmodule MyApp.Worker do
        defp atomize_keys(map), do: map
        defp stringify_keys(map), do: map
        defp pluck(list, key), do: {list, key}
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 3, 4]
      end)
    end
  end

  describe "&run/2 passes unrelated code" do
    test "does not report unrelated function names" do
      """
      defmodule MyApp.Worker do
        def process(map), do: normalize_keys(map)

        defp normalize_keys(map), do: map
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> refute_issues()
    end

    test "does not report calls to the shared helpers" do
      """
      defmodule MyApp.Worker do
        def process(map), do: SharedUtils.Enum.atomize_keys(map)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the keys of a custom map" do
      """
      defmodule MyApp.Worker do
        defp atomize_keys(map), do: map
        defp local_helper(map), do: map
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper,
        functions: %{local_helper: "MyApp.Shared.local_helper/1"}
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ "defp local_helper found"
        assert issue.message =~ "MyApp.Shared.local_helper/1"
      end)
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "exempts the shared_utils app by default" do
      """
      defmodule SharedUtils.Map do
        def atomize_keys(map), do: map
        def deep_merge(left, right), do: Map.merge(left, right)
      end
      """
      |> to_source_file(@shared_utils_file)
      |> run_check(NoReimplementedHelper)
      |> refute_issues()
    end

    test "exempts a custom path fragment" do
      """
      defmodule MyApp.Legacy.Helpers do
        def atomize_keys(map), do: map
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/helpers.ex")
      |> run_check(NoReimplementedHelper, excluded_paths: ["legacy/"])
      |> refute_issues()
    end

    test "exempts a path starting with a fragment" do
      """
      defmodule MyApp.Support.Helpers do
        def atomize_keys(map), do: map
      end
      """
      |> to_source_file("test/support/helpers.exs")
      |> run_check(NoReimplementedHelper, excluded_paths: ["test/"])
      |> refute_issues()
    end

    test "does not let a fragment match inside a path segment" do
      """
      defmodule MyApp.Latest.Helpers do
        defp atomize_keys(map), do: map
      end
      """
      |> to_source_file("lib/latest/helpers.ex")
      |> run_check(NoReimplementedHelper, excluded_paths: ["test/"])
      |> assert_issue(fn issue -> assert issue.message =~ "defp atomize_keys found" end)
    end

    test "flags shared_utils once it is no longer excluded" do
      """
      defmodule SharedUtils.Map do
        def atomize_keys(map), do: map
      end
      """
      |> to_source_file(@shared_utils_file)
      |> run_check(NoReimplementedHelper, excluded_paths: [])
      |> assert_issue(fn issue -> assert issue.message =~ "def atomize_keys found" end)
    end
  end
end
