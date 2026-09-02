defmodule MikaCredoRules.NoSharedUtilsHTTPOutsideApiAppsTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoSharedUtilsHTTPOutsideApiApps

  @lib_file "apps/my_app/lib/my_app/courses.ex"

  @moduledoc_examples NoSharedUtilsHTTPOutsideApiApps
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoSharedUtilsHTTPOutsideApiApps"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a direct SharedUtils.HTTP call in domain code" do
    test "reports a fully qualified SharedUtils.HTTP.get/1" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "SharedUtils.HTTP.get"
        assert issue.message =~ "SharedUtils.HTTP.get"
        assert issue.message =~ "*_api"
      end)
    end

    test "reports an aliased HTTP.post/2 under alias SharedUtils.HTTP" do
      """
      defmodule MyApp.Courses do
        alias SharedUtils.HTTP

        def enroll(id) do
          HTTP.post(id, %{})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "HTTP.post"
      end)
    end
  end

  describe "&run/2 leaves unrelated modules alone" do
    test "does not report MyApp.HTTP.get (a project module, not SharedUtils.HTTP)" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          MyApp.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report a bare HTTP.get shadowed by an unrelated alias" do
      """
      defmodule MyApp.Courses do
        alias MyApp.HTTP

        def fetch(id) do
          HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 prunes typespecs — a typespec reference is never flagged" do
    test "does not report a @spec return type naming a request-verb function of the transport" do
      """
      defmodule MyApp.Courses do
        @spec fetch(String.t()) :: SharedUtils.HTTP.get()
        def fetch(id), do: MyApp.CoursesApi.fetch(id)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report a @type body naming a request-verb function of the transport" do
      """
      defmodule MyApp.Courses do
        @type result :: SharedUtils.HTTP.request()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 only flags request-verb functions, not module-wide references" do
    test "does not report SharedUtils.HTTP.child_spec/1 (supervision setup)" do
      """
      defmodule MyApp.Http do
        def child_spec(opts) do
          opts
          |> Keyword.put_new(:name, __MODULE__)
          |> SharedUtils.HTTP.child_spec()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report SharedUtils.HTTP.client/3 (Tesla client construction)" do
      """
      defmodule MyApp.Http do
        def new(opts) do
          SharedUtils.HTTP.client([], {Tesla.Adapter.Finch, name: __MODULE__}, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "still reports SharedUtils.HTTP.get/2 in the same module" do
      """
      defmodule MyApp.Http do
        def child_spec(opts), do: SharedUtils.HTTP.child_spec(opts)

        def fetch(url, opts) do
          SharedUtils.HTTP.get(url, opts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end
  end

  describe "&run/2 exempts a defmodule that declares @behaviour naming a banned module" do
    test "does not report a wrapper module's own get/post calls, outside an _api path" do
      """
      defmodule MyApp.VendorClient do
        @behaviour SharedUtils.HTTP

        @impl SharedUtils.HTTP
        def new(opts), do: SharedUtils.HTTP.client([], nil, opts)

        def fetch(url) do
          SharedUtils.HTTP.get(new(), url, [])
        end

        def enroll(url, body) do
          SharedUtils.HTTP.post(new(), url, body, [])
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/vendor_client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "still reports the same shape when the module lacks the @behaviour declaration" do
      """
      defmodule MyApp.VendorClient do
        def new(opts), do: SharedUtils.HTTP.client([], nil, opts)

        def fetch(url) do
          SharedUtils.HTTP.get(new(), url, [])
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/vendor_client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end

    test "still reports a sibling module in the same file that is not itself the wrapper" do
      """
      defmodule MyApp.VendorClient do
        @behaviour SharedUtils.HTTP

        @impl SharedUtils.HTTP
        def new(opts), do: SharedUtils.HTTP.client([], nil, opts)
      end

      defmodule MyApp.VendorCaller do
        def fetch(url) do
          SharedUtils.HTTP.get(url)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/vendor_client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end
  end

  describe "&run/2 scopes per defmodule, including nested modules" do
    test "reports a call inside a nested defmodule exactly once" do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          def fetch(url), do: SharedUtils.HTTP.get(url)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "a nested module's @behaviour does not exempt its parent module's own calls" do
      """
      defmodule MyApp.Outer do
        def fetch(url), do: SharedUtils.HTTP.get(url)

        defmodule Inner do
          @behaviour SharedUtils.HTTP
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "a @behaviour written inside a quote block does not exempt the defining module" do
      """
      defmodule MyApp.Courses do
        defmacro __using__(_opts) do
          quote do
            @behaviour SharedUtils.HTTP
          end
        end

        def fetch(url), do: SharedUtils.HTTP.get(url)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.line_no === 8 end)
    end
  end

  describe "&run/2 is blind to calls outside a defmodule body" do
    test "does not report a call at the top level of a .exs script" do
      """
      SharedUtils.HTTP.get("https://example.com", [])
      """
      |> to_source_file("apps/my_app/priv/repo/seeds.exs")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report a call inside a defimpl block" do
      """
      defimpl MyApp.Fetchable, for: MyApp.Course do
        def fetch(course), do: SharedUtils.HTTP.get(course.url, [])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :functions param" do
    test "flags a custom function name in place of the default request verbs" do
      """
      defmodule MyApp.Http do
        def child_spec(opts), do: SharedUtils.HTTP.child_spec(opts)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, functions: [:child_spec])
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.child_spec" end)
    end

    test "no longer flags SharedUtils.HTTP.get once :functions excludes it" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, functions: [:child_spec])
      |> refute_issues()
    end
  end

  describe "&run/2 tolerates a single non-list param value instead of a list" do
    test "does not crash when :modules is a bare module atom" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: SharedUtils.HTTP)
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end

    test "does not crash when :allowed_paths is a bare string" do
      """
      defmodule MyApp.Support.HttpHelper do
        def sample(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_app/test/support/http_helper.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, allowed_paths: "test/")
      |> refute_issues()
    end

    test "does not crash when :modules contains a string instead of a module atom" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: ["SharedUtils.HTTP"])
      |> refute_issues()
    end

    test "does not crash when :modules contains an erlang-style atom" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: [:maps])
      |> refute_issues()
    end

    test "still flags a genuine module entry mixed alongside an erlang-style atom" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: [:maps, SharedUtils.HTTP])
      |> assert_issue(fn issue -> assert issue.trigger === "SharedUtils.HTTP.get" end)
    end
  end

  describe "&run/2 keeps traversing into a flagged call's arguments" do
    test "reports both a transport call and a second transport call nested in its arguments" do
      """
      defmodule MyApp.Courses do
        def fetch(url, other_url) do
          SharedUtils.HTTP.post(
            url,
            SharedUtils.HTTP.get(other_url)
          )
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [3, 5]
      end)
    end
  end

  describe "&run/2 resolves the Elixir-prefixed spelling correctly" do
    test "still reports Elixir.SharedUtils.HTTP.get (explicit prefix on the banned module)" do
      """
      defmodule MyApp.Courses do
        def fetch(url) do
          Elixir.SharedUtils.HTTP.get(url, [])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.SharedUtils.HTTP.get" end)
    end

    test "does not report Elixir.Transport.get after alias SharedUtils.HTTP, as: Transport" do
      """
      defmodule MyApp.Courses do
        alias SharedUtils.HTTP, as: Transport

        def fetch(url) do
          Elixir.Transport.get(url)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 exempts wrapper and infrastructure paths" do
    test "does not report inside a nested *_api directory within an ordinary app (intended)" do
      """
      defmodule MyApp.ScoresApi.Fetcher do
        def fetch(url) do
          SharedUtils.HTTP.get(url)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/scores_api/fetcher.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report inside a *_api wrapper app (git_hub_api)" do
      """
      defmodule GitHubApi.Client do
        def fetch_repo(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/git_hub_api/lib/git_hub_api/client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report inside shared_utils itself" do
      """
      defmodule SharedUtils.HTTP do
        def get(url) do
          SharedUtils.HTTP.Transport.get(url)
        end
      end
      """
      |> to_source_file("apps/shared_utils/lib/shared_utils/http.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report a _test.exs file living directly under lib/" do
      """
      defmodule MyApp.CoursesTest do
        def sample(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/courses_test.exs")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end

    test "does not report inside a test/ directory even without a _test.exs suffix" do
      """
      defmodule MyApp.Support.HttpHelper do
        def sample(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_app/test/support/http_helper.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> refute_issues()
    end
  end

  describe "&run/2 keeps checking boundary-lookalike paths" do
    test "still checks apps/my_apility/lib (contains '_api' but is not an _api app)" do
      """
      defmodule MyApility.Client do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_apility/lib/my_apility/client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue()
    end

    test "still checks apps/my_app/lib/latest (contains 'test' but is not a test dir)" do
      """
      defmodule MyApp.Latest.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/courses.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue()
    end

    test "still checks a dir that merely contains 'shared_utils' as part of a longer name" do
      """
      defmodule MySharedUtilsHelper.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_shared_utils_helper/lib/courses.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue()
    end
  end

  describe "&run/2 honours the :modules param" do
    test "flags a custom module in place of the default" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          MyApp.RawClient.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: [MyApp.RawClient])
      |> assert_issue(fn issue -> assert issue.trigger === "MyApp.RawClient.get" end)
    end

    test "no longer flags SharedUtils.HTTP once :modules is overridden" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, modules: [MyApp.RawClient])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :allowed_paths param" do
    test "no longer exempts the default _api/ suffix once :allowed_paths is overridden" do
      """
      defmodule GitHubApi.Client do
        def fetch_repo(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/git_hub_api/lib/git_hub_api/client.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, allowed_paths: [])
      |> assert_issue()
    end

    test "exempts a custom path fragment once added to :allowed_paths" do
      """
      defmodule MyCustomDir.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file("apps/my_custom_dir/lib/courses.ex")
      |> run_check(NoSharedUtilsHTTPOutsideApiApps, allowed_paths: ["my_custom_dir/"])
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the module segment" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Courses do
        def fetch(id) do
          SharedUtils.HTTP.get(id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two calls on one line its own column" do
      """
      defmodule MyApp.Courses do
        def fetch(first, second) do
          SharedUtils.HTTP.get(first) && SharedUtils.HTTP.get(second)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoSharedUtilsHTTPOutsideApiApps)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
