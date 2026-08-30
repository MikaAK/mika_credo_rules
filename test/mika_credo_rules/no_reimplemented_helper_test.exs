defmodule MikaCredoRules.NoReimplementedHelperTest do
  use Credo.Test.Case

  alias Credo.Check.Params
  alias MikaCredoRules.NoReimplementedHelper

  @worker_file "apps/my_app/lib/my_app/worker.ex"
  @shared_utils_file "apps/shared_utils/lib/shared_utils/map.ex"
  @real_shared_utils_source_dir "/Users/mika/GitHub/cheddar_flow_ex_umbrella/apps/shared_utils/lib/shared_utils"

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

    test "reports def deep_struct_to_map with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def deep_struct_to_map(struct) do
          struct |> Map.from_struct() |> Map.new()
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def deep_struct_to_map found — already exists as SharedUtils.Map.deep_struct_to_map/1, use it"
      end)
    end

    test "reports every helper in the default map" do
      """
      defmodule MyApp.Helpers do
        def atom_if_exists(key), do: key
        def atomize_keys(map), do: map
        def atomize_params(params), do: params
        def deep_struct_to_map(struct), do: struct
        def deep_transform(map, fun), do: map
        def drop_nil_values(map), do: map
        def random_string(length), do: length
        def reject_nil_values(list), do: list
        def stringify_keys(map), do: map
        def title_case(string), do: string
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issues(fn issues -> assert length(issues) === 10 end)
    end

    test "reports def deep_transform with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def deep_transform(map, fun) when is_map(map) do
          Enum.into(map, %{}, fun)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def deep_transform found — already exists as SharedUtils.Enum.deep_transform/2, use it"
      end)
    end

    test "reports defp drop_nil_values with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "defp drop_nil_values found — already exists as SharedUtils.Enum.reject_nil_values/1, use it"
      end)
    end

    test "reports defp atomize_params and defp atom_if_exists, both pointing at atomize_keys" do
      """
      defmodule MyApp.Worker do
        defp atomize_params(params) do
          Map.new(params, fn {key, value} -> {atom_if_exists(key), value} end)
        end

        defp atom_if_exists(key), do: String.to_existing_atom(key)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.trigger) |> Enum.sort() === [
                 "atom_if_exists",
                 "atomize_params"
               ]

        assert Enum.all?(issues, &(&1.message =~ "SharedUtils.Enum.atomize_keys/1"))
      end)
    end

    test "reports def title_case with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def title_case(string), do: string |> String.downcase() |> String.capitalize()
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def title_case found — already exists as SharedUtils.String.title_case/1, use it"
      end)
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
        defp drop_nil_values(map), do: map
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

    test "does not report deep_merge, pluck, or valid_email? — dropped, no real SharedUtils target" do
      """
      defmodule MyApp.Worker do
        def deep_merge(left, right), do: Map.merge(left, right)
        def pluck(list, key), do: Enum.map(list, &Map.get(&1, key))
        def valid_email?(email), do: email =~ "@"
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
        def deep_transform(map, fun), do: map
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

  describe "the default :functions map is ground-truthed against the real SharedUtils source" do
    # Runs only on machines with a checkout of cheddar_flow_ex_umbrella next to this
    # repo — the source of truth for every pointer this check's default map emits.
    # Skips silently everywhere else (CI, other contributors) so the suite stays
    # green without that repo; run it locally after touching the :functions default.
    test "every default pointer resolves to a public def at the stated arity" do
      if File.dir?(@real_shared_utils_source_dir) do
        functions = Params.get([], :functions, NoReimplementedHelper)

        Enum.each(functions, fn {banned_name, pointer} ->
          assert pointer_resolves?(pointer),
                 "#{banned_name} points at #{pointer}, but no matching `def` was found under " <>
                   @real_shared_utils_source_dir
        end)
      end
    end

    defp pointer_resolves?(pointer) do
      {module_segments, function_name, arity} = parse_pointer(pointer)
      file = module_source_file(module_segments)

      File.exists?(file) and
        file |> File.read!() |> defines_public_function?(function_name, arity)
    end

    defp parse_pointer(pointer) do
      [module_and_function, arity_string] = String.split(pointer, "/")
      segments = String.split(module_and_function, ".")

      {module_segments, [function_name]} = Enum.split(segments, -1)

      {module_segments, function_name, String.to_integer(arity_string)}
    end

    defp module_source_file(module_segments) do
      file_name = module_segments |> List.last() |> Macro.underscore()
      Path.join(@real_shared_utils_source_dir, "#{file_name}.ex")
    end

    defp defines_public_function?(source, function_name, arity) do
      {:ok, ast} = Code.string_to_quoted(source)
      {_ast, definitions} = Macro.prewalk(ast, [], &collect_public_defs/2)

      Enum.any?(definitions, &matches_definition?(&1, function_name, arity))
    end

    defp collect_public_defs({:def, _, [head | _]} = node, definitions) do
      {node, [head | definitions]}
    end

    defp collect_public_defs(node, definitions), do: {node, definitions}

    defp matches_definition?({:when, _, [head | _]}, function_name, arity) do
      matches_definition?(head, function_name, arity)
    end

    defp matches_definition?({name, _, args}, function_name, arity) when is_atom(name) do
      to_string(name) === function_name and length(List.wrap(args)) === arity
    end
  end
end
