defmodule MikaCredoRules.NoDirectHttpClientTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoDirectHttpClient

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags direct HTTP client references" do
    test "reports a Finch remote call" do
      """
      defmodule MyApp.Worker do
        def fetch(url) do
          Finch.build(:get, url) |> Finch.request(MyApp.Finch)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 3]
      end)
    end

    test "reports alias-free Finch.build/3" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: Finch.build(:get, url, [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ "Finch.build/3 found" end)
    end

    test "reports use Tesla" do
      """
      defmodule MyApp.Client do
        use Tesla
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ "Tesla found" end)
    end

    test "reports HTTPoison.get/1" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: HTTPoison.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ "HTTPoison.get/1 found" end)
    end

    test "reports Req.get!/1" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: Req.get!(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ "Req.get!/1 found" end)
    end
  end

  describe "&run/2 flags erlang HTTP modules" do
    test "reports :httpc.request/1" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: :httpc.request(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ ":httpc.request/1 found" end)
    end

    test "reports :hackney.get/1" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: :hackney.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issue(fn issue -> assert issue.message =~ ":hackney.get/1 found" end)
    end

    test "does not report other erlang remote calls" do
      """
      defmodule MyApp.Worker do
        def wait, do: :timer.sleep(10)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end
  end

  describe "&run/2 passes code without a direct HTTP client" do
    test "does not report SharedUtils.HTTP calls" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: SharedUtils.HTTP.get(url, [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end

    test "does not report a module that merely contains a banned name" do
      """
      defmodule MyApp.Worker do
        alias MyApp.ReqIssueTracker

        def fetch, do: ReqIssueTracker.list()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end

    test "does not report a project submodule grouped in a multi-alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.{Req, Worker}

        def build, do: Worker.build(Req)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end

    test "does not report bare uses of a name shadowed by a project alias" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Req

        def fetch(url), do: Req.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of banned modules" do
    test "reports uses through a renamed HTTP client alias" do
      """
      defmodule MyApp.Worker do
        alias Req, as: R

        def fetch(url), do: R.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 4]
      end)
    end
  end

  describe "&run/2 honours :excluded_paths" do
    test "does not report a file under shared_utils/" do
      """
      defmodule SharedUtils.HTTP do
        def get(url), do: Finch.build(:get, url) |> Finch.request(SharedUtils.Finch)
      end
      """
      |> to_source_file("apps/shared_utils/lib/shared_utils/http.ex")
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end

    test "does not report a file under a literal _api/ directory" do
      """
      defmodule VendorApi.HTTP do
        def get(url), do: Finch.build(:get, url) |> Finch.request(VendorApi.Finch)
      end
      """
      |> to_source_file("apps/_api/lib/vendor_api/http.ex")
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end

    test "does not exempt a whole app directory that merely ends in _api" do
      """
      defmodule TiingoApi.HTTP do
        def get(url), do: Finch.build(:get, url) |> Finch.request(TiingoApi.Finch)
      end
      """
      |> to_source_file("apps/tiingo_api/lib/tiingo_api/http.ex")
      |> run_check(NoDirectHttpClient)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "does not exempt a lookalike path (rest_api_notes)" do
      """
      defmodule MyApp.RestApiNotes do
        def fetch(url), do: Finch.build(:get, url) |> Finch.request(MyApp.Finch)
      end
      """
      |> to_source_file("apps/my_app/lib/vendor/rest_api_notes/thing.ex")
      |> run_check(NoDirectHttpClient)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end
  end

  describe "&run/2 honours the :modules param" do
    test "flags only the listed modules" do
      """
      defmodule MyApp.Worker do
        def old, do: HTTPoison.get(url)
        def new, do: FakeLib.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient, modules: [FakeLib])
      |> assert_issue(fn issue -> assert issue.message =~ "FakeLib.get" end)
    end
  end

  describe "&run/2 honours the :erlang_modules param" do
    test "flags only the listed erlang modules" do
      """
      defmodule MyApp.Worker do
        def old, do: :httpc.request(url)
        def new, do: :my_http.request(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient, erlang_modules: [:my_http])
      |> assert_issue(fn issue -> assert issue.message =~ ":my_http.request/1 found" end)
    end
  end

  describe "moduledoc examples" do
    test "BAD example fires" do
      """
      defmodule MyApp.Worker do
        def fetch(url) do
          Finch.build(:get, url) |> Finch.request(MyFinch)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end

    test "GOOD example is clean" do
      """
      defmodule MyApp.Worker do
        def fetch(url), do: SharedUtils.HTTP.get(url, [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoDirectHttpClient)
      |> refute_issues()
    end
  end
end
