defmodule MikaCredoRules.NoBarePatternMatchOnFallibleTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoBarePatternMatchOnFallible

  @lib_file "apps/my_app/lib/my_app/sync.ex"
  @test_file "apps/my_app/test/my_app/sync_test.exs"
  @application_file "apps/my_app/lib/my_app/application.ex"

  describe "&run/2 flags a bare match on a fallible call" do
    test "reports a bare match on a remote call, mid-block" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "="

        assert issue.message ===
                 "{:ok, _} = call found — handle the failure with `case` or `with`"
      end)
    end

    test "reports a bare match that is the sole expression of a function body" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a bare match on a local call" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a bare match on a piped call" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = id |> Accounts.fetch()
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a bare match inside an if body" do
      """
      defmodule MyApp.Sync do
        def sync(id, flag) do
          if flag do
            {:ok, user} = Accounts.fetch(id)
            broadcast(user)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports a bare match inside a case clause body" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          case lookup(id) do
            :found ->
              {:ok, user} = Accounts.fetch(id)
              broadcast(user)

            :missing ->
              :ok
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "reports a bare match on an :error tag" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:error, reason} = Accounts.fetch(id)
          handle(reason)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue ->
        assert issue.message ===
                 "{:error, _} = call found — handle the failure with `case` or `with`"
      end)
    end

    test "pins the column to the = operator" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.column === 17 end)
    end
  end

  describe "&run/2 does not flag -> clause heads" do
    test "does not report a case clause head that binds a shape (`{:ok, _} = result ->`)" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          case fetch(id) do
            {:ok, _} = result -> handle(result)
            {:error, _} = error -> error
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a fn clause head that binds a shape" do
      """
      defmodule MyApp.Sync do
        def sync(results) do
          Enum.map(results, fn {:ok, _} = result -> handle(result) end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "still reports a bare match inside a case clause body next to an exempt head" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          case fetch(id) do
            {:ok, _} = result ->
              {:ok, user} = Accounts.fetch(id)
              broadcast(user)

            {:error, _} = error ->
              error
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end
  end

  describe "&run/2 does not flag <- in with/for" do
    test "does not report a with clause" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          with {:ok, user} <- Accounts.fetch(id) do
            broadcast(user)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a for generator" do
      """
      defmodule MyApp.Sync do
        def sync(ids) do
          for {:ok, user} <- Enum.map(ids, &Accounts.fetch/1), do: broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag a rebind of an existing value" do
    test "does not report {:ok, x} = some_var" do
      """
      defmodule MyApp.Sync do
        def log(result) do
          {:ok, user} = result
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a literal tuple rhs" do
      """
      defmodule MyApp.Sync do
        def sync(_id) do
          {:ok, user} = {:ok, %{id: 1}}
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a struct literal rhs" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = %User{id: id}
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a map literal rhs" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = %{id: id}
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a case expression rhs" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = case fetch(id) do
            :found -> {:ok, id}
            :missing -> {:error, :missing}
          end

          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a parenless dot-read of a struct/map field" do
      """
      defmodule MyApp.Sync do
        def sync(state) do
          {:ok, x} = state.result
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a chained parenless dot-read" do
      """
      defmodule MyApp.Sync do
        def sync(state) do
          {:ok, x} = state.inner.result
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report an Access bracket read" do
      """
      defmodule MyApp.Sync do
        def sync(opts) do
          {:ok, x} = opts[:result]
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a module attribute read" do
      """
      defmodule MyApp.Sync do
        @cfg {:ok, %{}}

        def sync(_id) do
          {:ok, x} = @cfg
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a || fallback rhs" do
      """
      defmodule MyApp.Sync do
        def sync(cached, other) do
          {:ok, x} = cached || other
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "still reports a parenless zero-arity remote call" do
      """
      defmodule MyApp.Sync do
        def sync(_id) do
          {:ok, user} = Accounts.fetch
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a bare match on an anonymous function call" do
      """
      defmodule MyApp.Sync do
        def sync(fun) do
          {:ok, x} = fun.()
          broadcast(x)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 respects the excluded_paths param" do
    test "does not report assert {:ok, _} = ... in a test file" do
      """
      defmodule MyApp.SyncTest do
        test "syncs" do
          assert {:ok, user} = Accounts.fetch(id)
          assert user.id === id
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not report a boot-time supervisor match in application.ex" do
      """
      defmodule MyApp.Application do
        def start(_type, _args) do
          {:ok, pid} = Supervisor.start_link(children(), strategy: :one_for_one)
          {:ok, pid}
        end
      end
      """
      |> to_source_file(@application_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "does not exempt a lookalike lib path (lib/latest/helpers.ex)" do
      """
      defmodule MyApp.Latest.Helpers do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/helpers.ex")
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "does not exempt a lookalike application filename (web_application.ex)" do
      """
      defmodule MyApp.WebApplication do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/web_application.ex")
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "does not report a boot-time match in priv/repo/seeds.exs" do
      """
      defmodule MyApp.Repo.Seeds do
        def run do
          {:ok, _user} = Accounts.create(%{name: "seed"})
        end
      end
      """
      |> to_source_file("apps/my_app/priv/repo/seeds.exs")
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "excluded_paths param can be narrowed to exclude nothing" do
      """
      defmodule MyApp.SyncTest do
        test "syncs" do
          assert {:ok, user} = Accounts.fetch(id)
          assert user.id === id
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBarePatternMatchOnFallible, excluded_paths: [])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 respects the tags param" do
    test "does not report a tag outside the default list" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:done, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "reports a custom tag when configured" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:done, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible, tags: [:done])
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "moduledoc examples" do
    test "moduledoc BAD example fires" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          {:ok, user} = Accounts.fetch(id)
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> assert_issue()
    end

    test "moduledoc GOOD with example is clean" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          with {:ok, user} <- Accounts.fetch(id) do
            broadcast(user)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "moduledoc GOOD rebind example is clean" do
      """
      defmodule MyApp.Sync do
        def log(result) do
          {:ok, user} = result
          broadcast(user)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end

    test "moduledoc GOOD case-head example is clean" do
      """
      defmodule MyApp.Sync do
        def sync(id) do
          case fetch(id) do
            {:ok, _} = result -> handle(result)
            {:error, _} = error -> error
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBarePatternMatchOnFallible)
      |> refute_issues()
    end
  end
end
