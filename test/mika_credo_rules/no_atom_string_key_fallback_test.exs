defmodule MikaCredoRules.NoAtomStringKeyFallbackTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoAtomStringKeyFallback

  @lib_file "apps/my_app/lib/my_app/worker.ex"
  @test_file "apps/my_app/test/my_app/worker_test.exs"

  describe "&run/2 flags mixed atom/string key fallbacks" do
    test "reports Map.get with a string key falling back to the atom key" do
      """
      defmodule MyApp.Worker do
        def link(payload) do
          Map.get(payload, "link") || Map.get(payload, :link)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "||"
        assert issue.message =~ "mixed atom/string key fallback"
        assert issue.message =~ "normalize the map's keys at its boundary"
      end)
    end

    test "reports bracket access with a string key falling back to the atom key" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || params[:id]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the atom key first" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params[:id] || params["id"]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports bracket access falling back to Map.get" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || Map.get(params, :id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports Map.get falling back to bracket access" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          Map.get(params, :id) || params["id"]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports Map.get/3 with a default" do
      """
      defmodule MyApp.Worker do
        def link(payload) do
          Map.get(payload, "link", nil) || Map.get(payload, :link, nil)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the mixed pair at the head of a chained fallback" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || params[:id] || default_id()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the mixed pair at the tail of a chained fallback" do
      """
      defmodule MyApp.Worker do
        def id(params, fallback) do
          fallback || params["id"] || params[:id]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the mixed pair across an explicitly right-nested fallback" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || (params[:id] || default_id())
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports a dotted subject on both sides" do
      """
      defmodule MyApp.Worker do
        def page(socket) do
          socket.assigns["page"] || socket.assigns[:page]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end

    test "reports the fallback at its own column, not the first || on the line" do
      """
      defmodule MyApp.Worker do
        def id(params, flag) do
          flag || params["id"] || params[:id]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.column === 26
      end)
    end

    test "reports lib and test files alike" do
      """
      defmodule MyApp.WorkerTest do
        test "reads the id" do
          assert params["id"] || params[:id]
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 allows honest fallbacks" do
    test "does not report different key names" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params[:id] || params[:uuid]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report different key names across key types" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || params[:uuid]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report same-type keys" do
      """
      defmodule MyApp.Worker do
        def name(params) do
          params["first_name"] || params["last_name"]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report different subjects" do
      """
      defmodule MyApp.Worker do
        def id(first, second) do
          first["id"] || second[:id]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report lookup-or-default" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] || %{}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report &&" do
      """
      defmodule MyApp.Worker do
        def id(params) do
          params["id"] && params[:id]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report non-literal keys" do
      """
      defmodule MyApp.Worker do
        def fetch(params, key) do
          params[key] || params[key]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end

    test "does not report reads of a boundary-normalized map" do
      """
      defmodule MyApp.Worker do
        def handle_webhook(payload) do
          payload = payload_keys_to_strings(payload)

          payload["link"]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases of Map" do
    test "reports Map aliased with as:" do
      """
      defmodule MyApp.Worker do
        alias Map, as: M

        def id(params) do
          M.get(params, "id") || M.get(params, :id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report a project module shadowing Map" do
      """
      defmodule MyApp.Worker do
        alias MyApp.Map

        def id(params) do
          Map.get(params, "id") || Map.get(params, :id)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAtomStringKeyFallback)
      |> refute_issues()
    end
  end
end
