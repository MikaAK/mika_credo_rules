defmodule MikaCredoRules.NoRawEtsTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoRawEts

  @lib_file "apps/my_app/lib/my_app/price_cache.ex"
  @test_file "apps/my_app/test/my_app/price_cache_test.exs"

  describe "&run/2 flags raw :ets calls" do
    test "reports :ets.new/2" do
      """
      defmodule MyApp.PriceCache do
        def start, do: :ets.new(:price_cache, [:set, :named_table])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.message =~ ":ets.new/2 found"
      end)
    end

    test "reports :ets.insert/2" do
      """
      defmodule MyApp.PriceCache do
        def put(table, entry), do: :ets.insert(table, entry)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> assert_issue(fn issue -> assert issue.message =~ ":ets.insert/2 found" end)
    end

    test "reports :ets.lookup/2" do
      """
      defmodule MyApp.PriceCache do
        def get(table, key), do: :ets.lookup(table, key)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> assert_issue(fn issue -> assert issue.message =~ ":ets.lookup/2 found" end)
    end

    test "reports raw :ets in test files too" do
      """
      defmodule MyApp.PriceCacheTest do
        use ExUnit.Case

        setup do
          table = :ets.new(:price_cache, [:set])
          {:ok, table: table}
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRawEts)
      |> assert_issue(fn issue -> assert issue.message =~ ":ets.new/2 found" end)
    end
  end

  describe "&run/2 allows diagnostic functions" do
    test "does not report :ets.info/1" do
      """
      defmodule MyApp.PriceCache do
        def describe(table), do: :ets.info(table)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> refute_issues()
    end

    test "does not report :ets.whereis/1" do
      """
      defmodule MyApp.PriceCache do
        def find(name), do: :ets.whereis(name)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> refute_issues()
    end

    test "does not report :ets.all/0" do
      """
      defmodule MyApp.PriceCache do
        def tables, do: :ets.all()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> refute_issues()
    end
  end

  describe "&run/2 does not report other erlang modules" do
    test "does not report :dets by default" do
      """
      defmodule MyApp.PriceCache do
        def open, do: :dets.open_file(:price_cache)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> refute_issues()
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report a file under elixir_cache/" do
      """
      defmodule Cache.ETS do
        def new(name), do: :ets.new(name, [:set, :named_table])
      end
      """
      |> to_source_file("apps/elixir_cache/lib/cache/ets.ex")
      |> run_check(NoRawEts)
      |> refute_issues()
    end

    test "does not exempt a lookalike path" do
      """
      defmodule MyApp.FakeElixirCacheHelper do
        def new(name), do: :ets.new(name, [:set, :named_table])
      end
      """
      |> to_source_file("apps/my_app/lib/fake_elixir_cache_helper.ex")
      |> run_check(NoRawEts)
      |> assert_issue(fn issue -> assert issue.message =~ ":ets.new/2 found" end)
    end
  end

  describe "&run/2 honours the :erlang_modules param" do
    test "flags :dets when opted in" do
      """
      defmodule MyApp.PriceCache do
        def open, do: :dets.open_file(:price_cache)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts, erlang_modules: [:ets, :dets])
      |> assert_issue(fn issue -> assert issue.message =~ ":dets.open_file/1 found" end)
    end
  end

  describe "&run/2 honours the :allowed_functions param" do
    test "allows an additional function when configured" do
      """
      defmodule MyApp.PriceCache do
        def size(table), do: :ets.tab2list(table)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts, allowed_functions: [:info, :whereis, :all, :tab2list])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "BAD example fires" do
      """
      defmodule MyApp.PriceCache do
        def start do
          table = :ets.new(:price_cache, [:set, :named_table, read_concurrency: true])
          :ets.insert(table, {"AAPL", 150.25})
        end

        def fetch(table), do: :ets.lookup(table, "AAPL")
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> assert_issues(fn issues -> assert length(issues) === 3 end)
    end

    test "GOOD example is clean" do
      """
      defmodule MyApp.PriceCache do
        use Cache, adapter: Cache.ETS, name: :price_cache, sandbox?: Mix.env() === :test
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRawEts)
      |> refute_issues()
    end
  end
end
