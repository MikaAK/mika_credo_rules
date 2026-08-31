defmodule MikaCredoRules.CacheRequiresSandboxOptionTest do
  use Credo.Test.Case

  alias MikaCredoRules.CacheRequiresSandboxOption

  @cache_file "apps/my_app/lib/my_app/user_cache.ex"

  describe "&run/2 flags use Cache without :sandbox?" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :my_app_user_cache, opts: :my_app
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "use"
        assert issue.message =~ "sandbox?"
      end)
    end

    test "reports each use Cache with its own line" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.ETS, name: :users
      end

      defmodule MyApp.PostCache do
        use Cache, adapter: Cache.ETS, name: :posts
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 6]
      end)
    end

    test "reports the Elixir-prefixed atom spelling of Cache" do
      """
      defmodule MyApp.UserCache do
        use :"Elixir.Cache", adapter: Cache.ETS, name: :users
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> assert_issue()
    end

    test "honors a custom :required_keys param" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.ETS, sandbox?: Mix.env() === :test
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption, required_keys: [:sandbox?, :ttl])
      |> assert_issue()
    end
  end

  describe "&run/2 leaves compliant and non-literal uses alone" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :my_app_user_cache,
          sandbox?: Mix.env() === :test,
          opts: :my_app
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> refute_issues()
    end

    test "does not report use Cache, @opts (non-literal options)" do
      """
      defmodule MyApp.UserCache do
        @cache_opts [adapter: Cache.ETS, name: :users]

        use Cache, @cache_opts
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> refute_issues()
    end

    test "does not report use Cache shadowed by a project alias" do
      """
      defmodule MyApp.UserCache do
        alias MyApp.Cache

        use Cache, adapter: Cache.ETS, name: :users
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> refute_issues()
    end

    test "does not report a plain use of an unrelated behaviour" do
      """
      defmodule MyApp.UserWorker do
        use GenServer

        def init(state), do: {:ok, state}
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheRequiresSandboxOption)
      |> refute_issues()
    end
  end

  describe "&run/2 respects excluded_paths" do
    test "does not report a file matching excluded_paths" do
      """
      defmodule ElixirCache.Support.SampleCache do
        use Cache, adapter: Cache.ETS, name: :sample
      end
      """
      |> to_source_file("apps/elixir_cache/test/support/sample_cache.ex")
      |> run_check(CacheRequiresSandboxOption, excluded_paths: ["elixir_cache/"])
      |> refute_issues()
    end

    test "does not report a file matching the default elixir_cache/ exclusion" do
      """
      defmodule ElixirCache.Support.SampleCache do
        use Cache, adapter: Cache.ETS, name: :sample
      end
      """
      |> to_source_file("apps/elixir_cache/test/support/sample_cache.ex")
      |> run_check(CacheRequiresSandboxOption)
      |> refute_issues()
    end

    test "does report a lookalike path that is not elixir_cache" do
      """
      defmodule MyApp.ElixirCacheHelpers.UserCache do
        use Cache, adapter: Cache.ETS, name: :sample
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/elixir_cache_helpers/user_cache.ex")
      |> run_check(CacheRequiresSandboxOption)
      |> assert_issue()
    end
  end
end
