defmodule MikaCredoRules.CacheOptsNoHardcodedUriTest do
  use Credo.Test.Case

  alias MikaCredoRules.CacheOptsNoHardcodedUri

  @cache_file "apps/my_app/lib/my_app/user_cache.ex"

  describe "&run/2 flags a literal string/integer for a banned key inside opts:" do
    test "reports the moduledoc BAD example" do
      """
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :c,
          sandbox?: Mix.env() === :test,
          opts: [uri: "redis://localhost:6379"]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger =~ "uri:"
        assert issue.message =~ "uri:"
        assert issue.message =~ "runtime config"
      end)
    end

    test "reports a hardcoded host and port" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: [host: "localhost", port: 6379]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "reports a hardcoded password" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: [password: "s3cret"]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> assert_issue()
    end

    test "reports the Elixir-prefixed atom spelling of Cache" do
      """
      defmodule MyApp.UserCache do
        use :"Elixir.Cache", adapter: Cache.Redis, name: :c, opts: [uri: "redis://x"]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> assert_issue()
    end

    test "honors a custom :literal_keys param" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: [database: 3]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri, literal_keys: [:database])
      |> assert_issue()
    end
  end

  describe "&run/2 leaves runtime config and non-literal opts alone" do
    test "does not report the moduledoc GOOD example" do
      """
      defmodule MyApp.UserCache do
        use Cache,
          adapter: Cache.Redis,
          name: :c,
          sandbox?: Mix.env() === :test,
          opts: {MyApp.Config, :redis_opts, []}
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report an application-env opts reference" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: :my_app
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report use Cache, @opts (non-literal use options)" do
      """
      defmodule MyApp.UserCache do
        @cache_opts [adapter: Cache.Redis, name: :c, opts: [uri: "redis://localhost"]]

        use Cache, @cache_opts
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report a variable opts: value" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: redis_opts()
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report an unrelated string value in opts" do
      """
      defmodule MyApp.UserCache do
        use Cache, adapter: Cache.Redis, name: :c, opts: [namespace: "user_cache"]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report use Cache shadowed by a project alias" do
      """
      defmodule MyApp.UserCache do
        alias MyApp.Cache

        use Cache, adapter: Cache.Redis, name: :c, opts: [uri: "redis://localhost"]
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does not report a plain use of an unrelated module" do
      """
      defmodule MyApp.UserWorker do
        use GenServer

        def init(state), do: {:ok, state}
      end
      """
      |> to_source_file(@cache_file)
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end
  end

  describe "&run/2 respects excluded_paths" do
    test "does not report a file matching the default elixir_cache/ exclusion" do
      """
      defmodule ElixirCache.Support.SampleCache do
        use Cache, adapter: Cache.Redis, name: :sample, opts: [uri: "redis://localhost"]
      end
      """
      |> to_source_file("apps/elixir_cache/test/support/sample_cache.ex")
      |> run_check(CacheOptsNoHardcodedUri)
      |> refute_issues()
    end

    test "does report a lookalike path that is not elixir_cache" do
      """
      defmodule MyApp.ElixirCacheHelpers.UserCache do
        use Cache, adapter: Cache.Redis, name: :sample, opts: [uri: "redis://localhost"]
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/elixir_cache_helpers/user_cache.ex")
      |> run_check(CacheOptsNoHardcodedUri)
      |> assert_issue()
    end
  end
end
