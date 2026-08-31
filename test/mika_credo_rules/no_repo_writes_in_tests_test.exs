defmodule MikaCredoRules.NoRepoWritesInTestsTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoRepoWritesInTests

  @test_file "apps/my_app/test/my_app/orders_test.exs"
  @lib_file "apps/my_app/lib/my_app/orders.ex"
  @support_file "apps/my_app/test/support/factory.ex"
  @support_test_file "apps/my_app/test/support/some_test.exs"
  @lookalike_test_file "apps/my_app/test/supporting_docs_test.exs"

  describe "&run/2 flags write-side Repo calls in a test file" do
    test "reports Repo.insert!/1" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message === "Repo.insert! found — use FactoryEx for test data"
      end)
    end

    test "reports Repo.insert/1" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          Repo.insert(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert" end)
    end

    test "reports Repo.insert_all/2" do
      """
      defmodule MyApp.OrdersTest do
        test "bulk inserts orders" do
          Repo.insert_all(Order, rows)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert_all" end)
    end

    test "reports Repo.delete!/1" do
      """
      defmodule MyApp.OrdersTest do
        test "removes an order" do
          Repo.delete!(order)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.delete!" end)
    end

    test "reports the piped form" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          %Order{total: 10} |> Repo.insert!()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert!" end)
    end

    test "reports each call site with its own line number" do
      """
      defmodule MyApp.OrdersTest do
        test "writes twice" do
          Repo.insert!(%Order{total: 1})
          Repo.insert!(%Order{total: 2})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 4]
      end)
    end
  end

  describe "&run/2 identifies a repo by its last alias segment" do
    test "reports a bare Repo alias" do
      """
      defmodule MyApp.OrdersTest do
        alias MyApp.Repo

        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert!" end)
    end

    test "reports a repo aliased alongside other modules" do
      """
      defmodule MyApp.OrdersTest do
        alias MyApp.{Repo, Accounts}

        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert!" end)
    end

    test "reports a fully qualified oddly-namespaced repo without an alias" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          Schemas.Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Schemas.Repo.insert!" end)
    end
  end

  describe "&run/2 ignores reads" do
    test "does not report Repo.get/2" do
      """
      defmodule MyApp.OrdersTest do
        test "fetches an order" do
          assert %Order{} = Repo.get(Order, order.id)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report Repo.all/1" do
      """
      defmodule MyApp.OrdersTest do
        test "lists orders" do
          assert Repo.all(Order) === []
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report Repo.one/1 and Repo.preload/2" do
      """
      defmodule MyApp.OrdersTest do
        test "loads with preload" do
          order = Repo.one(Order)
          Repo.preload(order, :items)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 ignores non-test files" do
    test "does not report Repo.insert! in a lib file" do
      """
      defmodule MyApp.Orders do
        def create(attrs), do: Repo.insert!(struct(Order, attrs))
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report Repo.insert! in a lib file living under lib/latest/" do
      """
      defmodule MyApp.Orders do
        def create(attrs), do: Repo.insert!(struct(Order, attrs))
      end
      """
      |> to_source_file("apps/my_app/lib/latest/orders.ex")
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the default :excluded_paths" do
    test "does not report Repo.insert! under test/support/" do
      """
      defmodule MyApp.Support.SomeTest do
        def seed, do: Repo.insert!(%Order{total: 10})
      end
      """
      |> to_source_file(@support_test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report Repo.insert! in a factory under test/support/" do
      """
      defmodule MyApp.Support.Factory do
        def build, do: Repo.insert!(%Order{total: 10})
      end
      """
      |> to_source_file(@support_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "still reports a lookalike path that merely starts with 'supporting'" do
      """
      defmodule MyApp.SupportingDocsTest do
        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@lookalike_test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.insert!" end)
    end
  end

  describe "&run/2 honours the :repo_modules param" do
    test "does not report an oddly-named repo by default" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          DataStore.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "reports an oddly-named repo once listed in :repo_modules" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          MyApp.DataStore.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, repo_modules: [MyApp.DataStore])
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.DataStore.insert!" end)
    end

    test "reports an aliased oddly-named repo listed in :repo_modules" do
      """
      defmodule MyApp.OrdersTest do
        alias MyApp.DataStore

        test "creates an order" do
          DataStore.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, repo_modules: [MyApp.DataStore])
      |> assert_issue(fn issue -> assert issue.message =~ "DataStore.insert!" end)
    end

    test "does not report a repo name shadowed by an unrelated alias" do
      """
      defmodule MyApp.OrdersTest do
        alias Other.NotADataStore, as: DataStore

        test "does something unrelated" do
          DataStore.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, repo_modules: [DataStore])
      |> refute_issues()
    end
  end

  describe "&run/2 and the :as false negative (documented in the moduledoc)" do
    test "does not report a repo renamed via alias ..., as: by default" do
      """
      defmodule MyApp.OrdersTest do
        alias MyApp.Repo, as: DB

        test "creates an order" do
          DB.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "reports the renamed repo once :repo_modules names the real module" do
      """
      defmodule MyApp.OrdersTest do
        alias MyApp.Repo, as: DB

        test "creates an order" do
          DB.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, repo_modules: [MyApp.Repo])
      |> assert_issue(fn issue -> assert issue.message =~ "DB.insert!" end)
    end
  end

  describe "&run/2 known limitations" do
    test "flags a teardown cleanup call, though FactoryEx is not the applicable fix" do
      """
      defmodule MyApp.OrdersTest do
        setup do
          on_exit(fn -> Repo.delete_all(User) end)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.delete_all" end)
    end

    test "does not report a repo behind a module attribute (@repo.insert!/1)" do
      """
      defmodule MyApp.OrdersTest do
        @repo MyApp.Repo

        test "creates an order" do
          @repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report a repo returned from a function call (repo().insert!/1)" do
      """
      defmodule MyApp.OrdersTest do
        defp repo, do: MyApp.Repo

        test "creates an order" do
          repo().insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report apply/3 dispatch to a repo" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          apply(Repo, :insert!, [%Order{total: 10}])
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "does not report Ecto.Adapters.SQL.query!/3 raw writes" do
      """
      defmodule MyApp.OrdersTest do
        test "cleans up" do
          Ecto.Adapters.SQL.query!(Repo, "DELETE FROM orders", [])
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags only the configured functions" do
      """
      defmodule MyApp.OrdersTest do
        test "writes twice" do
          Repo.insert!(%Order{total: 1})
          Repo.delete!(order)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, functions: [:delete!])
      |> assert_issue(fn issue -> assert issue.message =~ "Repo.delete!" end)
    end
  end

  describe "&run/2 honours the :test_files param" do
    test "treats a custom suffix as a test file" do
      """
      defmodule MyApp.OrdersSpec do
        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file("apps/my_app/spec/my_app/orders_spec.exs")
      |> run_check(NoRepoWritesInTests, test_files: ["_spec.exs"])
      |> assert_issue()
    end

    test "no longer flags _test.exs files once :test_files is overridden" do
      """
      defmodule MyApp.OrdersTest do
        test "creates an order" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests, test_files: ["_spec.exs"])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "excludes a custom fragment" do
      """
      defmodule MyApp.SeedsTest do
        test "seeds the db" do
          Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file("apps/my_app/test/seeds/order_seeds_test.exs")
      |> run_check(NoRepoWritesInTests, excluded_paths: ["test/seeds/"])
      |> refute_issues()
    end
  end

  describe "&run/2 handles non-atom alias segments without raising" do
    test "reports __MODULE__.Repo.insert! instead of crashing" do
      """
      defmodule MyApp.OrdersTest do
        def seed do
          __MODULE__.Repo.insert!(%Order{total: 10})
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "__MODULE__.Repo.insert!" end)
    end

    test "reports unquote(mod).Repo.insert! inside a quote instead of crashing" do
      """
      defmodule MyApp.OrdersTest do
        defmacro seed_via(mod) do
          quote do
            unquote(mod).Repo.insert!(%Order{total: 10})
          end
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issue(fn issue -> assert issue.message =~ "unquote(mod).Repo.insert!" end)
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example 1 fires on all three write calls" do
      """
      defmodule MyApp.OrdersTest do
        test "writes" do
          {:ok, user} = Repo.insert(%User{email: "a@b.c"})
          Repo.insert_all(Order, rows)
          %User{email: "a@b.c"} |> Repo.insert!()
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> assert_issues(fn issues -> assert length(issues) === 3 end)
    end

    test "moduledoc GOOD example 1 is clean" do
      """
      defmodule MyApp.OrdersTest do
        test "writes" do
          user = FactoryEx.insert!(MyApp.Support.Factory.User)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end

    test "moduledoc GOOD example 2 (reads) is clean" do
      """
      defmodule MyApp.OrdersTest do
        test "reads" do
          assert %User{} = Repo.get(User, user.id)
          assert Repo.all(User) === []
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoRepoWritesInTests)
      |> refute_issues()
    end
  end
end
