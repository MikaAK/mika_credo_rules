defmodule MikaCredoRules.NoReimplementedHelperTest do
  use Credo.Test.Case, async: true

  alias Credo.Check.Params
  alias MikaCredoRules.NoReimplementedHelper

  @worker_file "apps/my_app/lib/my_app/worker.ex"
  @shared_utils_file "apps/shared_utils/lib/shared_utils/map.ex"
  @shared_utils_roots_env "MIKA_CREDO_SHARED_UTILS_ROOTS"
  @default_shared_utils_roots [
    "/Users/mika/GitHub/cheddar_flow_ex_umbrella/apps/shared_utils/lib/shared_utils",
    "/Users/mika/GitHub/trader_fira_umbrella/apps/shared_utils/lib",
    "/Users/mika/GitHub/notification_platform_umbrella/apps/shared_utils/lib"
  ]

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
        def deep_merge(left, right), do: left
        def deep_struct_to_map(struct), do: struct
        def deep_transform(map, fun), do: map
        def drop_nil_values(map), do: map
        def pluck(list, key), do: list
        def random_string(length), do: length
        def reject_nil_values(list), do: list
        def stringify_keys(map), do: map
        def title_case(string), do: string
        def valid_email?(email), do: email
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issues(fn issues -> assert length(issues) === 13 end)
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

    test "reports defp atomize_params with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        defp atomize_params(params) do
          Map.new(params, fn {key, value} -> {String.to_existing_atom(key), value} end)
        end
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "defp atomize_params found — already exists as SharedUtils.Enum.atomize_keys/1, use it"
      end)
    end

    test "reports defp atom_if_exists pointing at String.to_existing_atom/1, not atomize_keys" do
      """
      defmodule MyApp.Worker do
        defp atom_if_exists(key), do: String.to_existing_atom(key)
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "defp atom_if_exists found — already exists as String.to_existing_atom/1, use it"
      end)
    end

    test "reports def deep_merge with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def deep_merge(left, right) do
          Map.merge(left, right, fn _key, left_value, right_value ->
            deep_merge(left_value, right_value)
          end)
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

    test "reports def pluck with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def pluck(list, key), do: Enum.map(list, &Map.get(&1, key))
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def pluck found — already exists as SharedUtils.Collection.pluck/2, use it"
      end)
    end

    test "reports def valid_email? with its replacement in the message" do
      """
      defmodule MyApp.Worker do
        def valid_email?(email), do: email =~ ~r/.+@.+\\..+/
      end
      """
      |> to_source_file(@worker_file)
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "def valid_email? found — already exists as SharedUtils.String.valid_email?/1, use it"
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

    test "does not report a defmacro definition of a banned name — a documented limitation" do
      """
      defmodule MyApp.Worker do
        defmacro atomize_keys(map) do
          quote do: unquote(map)
        end
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

    test "does not exempt a lookalike file named shared_utils.ex outside the shared_utils app" do
      """
      defmodule MyApp.SharedUtils do
        def atomize_keys(map), do: map
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/shared_utils.ex")
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue -> assert issue.message =~ "def atomize_keys found" end)
    end

    test "does not exempt a lookalike file named shared_utils_helpers.ex" do
      """
      defmodule MyApp.SharedUtilsHelpers do
        def atomize_keys(map), do: map
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/shared_utils_helpers.ex")
      |> run_check(NoReimplementedHelper)
      |> assert_issue(fn issue -> assert issue.message =~ "def atomize_keys found" end)
    end
  end

  describe "the default :functions map is ground-truthed against real SharedUtils checkouts" do
    # The workspace has THREE divergent SharedUtils libraries (cheddar_flow_ex_umbrella,
    # trader_fira_umbrella, notification_platform_umbrella) — a pointer only needs to
    # resolve in one of them to be real, since `:functions` defaults to the common core
    # plus helpers present in at least two trees, never all three.
    #
    # Runs only on machines with at least one of those checkouts next to this repo (or
    # roots given via #{@shared_utils_roots_env}). IO.warn's LOUDLY and skips everywhere
    # else (CI, other contributors) instead of silently reporting a green 0-assertion
    # pass — a previous version of this test went dark with no skip marker when its
    # hardcoded directory stopped existing. Run it locally after touching the
    # :functions default.
    test "every default pointer resolves to a public def at the stated arity in a real tree" do
      case available_shared_utils_roots() do
        [] ->
          IO.warn(
            "#{__MODULE__}: no SharedUtils checkout found, ground-truth test SKIPPED. " <>
              "Tried: #{inspect(shared_utils_roots())} — set #{@shared_utils_roots_env} " <>
              "(comma-separated) to point at real checkouts."
          )

        roots ->
          functions = Params.get([], :functions, NoReimplementedHelper)

          Enum.each(functions, fn {banned_name, pointer} ->
            assert pointer_resolves_in_any_root?(pointer, roots),
                   "#{banned_name} points at #{pointer}, but no matching `def` was found " <>
                     "under any of #{inspect(roots)}"
          end)
      end
    end

    defp shared_utils_roots do
      case System.get_env(@shared_utils_roots_env) do
        nil -> @default_shared_utils_roots
        roots -> String.split(roots, ",")
      end
    end

    defp available_shared_utils_roots do
      shared_utils_roots() |> Enum.filter(&File.dir?/1)
    end

    defp pointer_resolves_in_any_root?(pointer, roots) do
      {module_segments, function_name, arity} = parse_pointer(pointer)

      case module_segments do
        ["SharedUtils" | _] ->
          Enum.any?(
            roots,
            &shared_utils_pointer_resolves?(&1, module_segments, function_name, arity)
          )

        _stdlib_or_kernel_module ->
          stdlib_pointer_resolves?(module_segments, function_name, arity)
      end
    end

    defp parse_pointer(pointer) do
      [module_and_function, arity_string] = String.split(pointer, "/")
      segments = String.split(module_and_function, ".")

      {module_segments, [function_name]} = Enum.split(segments, -1)

      {module_segments, function_name, String.to_integer(arity_string)}
    end

    defp shared_utils_pointer_resolves?(root, module_segments, function_name, arity) do
      file = module_source_file(root, module_segments)

      File.exists?(file) and
        file |> File.read!() |> defines_public_function?(function_name, arity)
    end

    # `module_segments` is rooted at "SharedUtils", and `root` already points at the
    # directory that IS SharedUtils's own namespace — so the file path is every
    # remaining segment, underscored and joined, e.g. ["SharedUtils", "Ecto", "Changeset"]
    # resolves to "<root>/ecto/changeset.ex", never the wrong flattened "<root>/changeset.ex".
    defp module_source_file(root, ["SharedUtils" | nested_segments]) do
      relative_path = Enum.map_join(nested_segments, "/", &Macro.underscore/1)
      Path.join(root, "#{relative_path}.ex")
    end

    defp stdlib_pointer_resolves?(module_segments, function_name, arity) do
      module = Module.concat(module_segments)
      function = String.to_existing_atom(function_name)

      Code.ensure_loaded?(module) and function_exported?(module, function, arity)
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

    defp matches_definition?(_unrecognized_head, _function_name, _arity), do: false
  end
end
