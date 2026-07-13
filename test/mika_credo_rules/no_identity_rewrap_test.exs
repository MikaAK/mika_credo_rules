defmodule MikaCredoRules.NoIdentityRewrapTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoIdentityRewrap

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags cases where every clause is an identity re-wrap" do
    test "reports the moduledoc BAD example — two-clause ok/error identity" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "case"
        assert issue.message =~ "identity re-wrap case"
        assert issue.message =~ "return the value directly"
      end)
    end

    test "reports a single-clause identity case" do
      """
      defmodule MyApp.Worker do
        def unwrap(value) do
          case value do
            result -> result
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a three-clause all-identity case" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, reason}
            :timeout -> :timeout
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports bare atom identity clauses" do
      """
      defmodule MyApp.Worker do
        def ping(server) do
          case send_ping(server) do
            :ok -> :ok
            :error -> :error
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports multi-line clauses whose pattern and body sit on different lines" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, %{name: name, age: age}} ->
              {:ok, %{name: name, age: age}}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports each offending case with its own line number" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, reason}
          end
        end

        def find(id) do
          case find_user(id) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 10]
      end)
    end
  end

  describe "&run/2 allows cases that do real work" do
    test "does not report the moduledoc GOOD example — returning the call directly" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          fetch_user(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report the moduledoc GOOD example — a transforming error clause" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> {:error, {:user_fetch_failed, reason}}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report a case with a guarded clause" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} when is_map(user) -> {:ok, user}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report a multi-expression clause body" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} ->
              track_fetch(user)
              {:ok, user}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report a re-tagging fallback clause" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, user} -> {:ok, user}
            other -> {:error, other}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report clauses that bind different variable names in the body" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          case fetch_user(id) do
            {:ok, u} -> {:ok, user}
            {:error, r} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report a pinned pattern" do
      """
      defmodule MyApp.Worker do
        def fetch(id, expected) do
          case fetch_user(id) do
            {:ok, ^expected} -> {:ok, expected}
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes to case expressions only" do
    test "does not report an identity fn" do
      """
      defmodule MyApp.Worker do
        def passthrough(list) do
          Enum.map(list, fn x -> x end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report a cond whose heads repeat in the bodies" do
      """
      defmodule MyApp.Worker do
        def pick(valid?) do
          cond do
            valid? -> valid?
            true -> true
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end

    test "does not report identity clauses in a with else block" do
      """
      defmodule MyApp.Worker do
        def fetch(id) do
          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoIdentityRewrap)
      |> refute_issues()
    end
  end
end
