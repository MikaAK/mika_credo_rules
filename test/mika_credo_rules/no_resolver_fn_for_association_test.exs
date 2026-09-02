defmodule MikaCredoRules.NoResolverFnForAssociationTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoResolverFnForAssociation

  @lib_file "apps/my_app_web/lib/my_app_web/schema.ex"
  @test_file "apps/my_app_web/test/my_app_web/schema_test.exs"

  @moduledoc_examples NoResolverFnForAssociation
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoResolverFnForAssociation"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a trivial pass-through resolve fn" do
    test "reports {:ok, root.field} at 3-arity" do
      """
      defmodule MyAppWeb.Schema do
        object :user do
          field :owner, :user do
            resolve fn root, _args, _info ->
              {:ok, root.owner}
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "resolve"
        assert issue.message =~ "root.owner"
        assert issue.message =~ "dataloader"
      end)
    end

    test "reports {:ok, Map.get(root, :field)}" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            {:ok, Map.get(root, :owner)}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.trigger === "resolve"
        assert issue.message =~ "Map.get(root, :owner)"
      end)
    end

    test "reports the resolve call with no parens the same as with parens" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve(fn root, _args, _info -> {:ok, root.owner} end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end
  end

  describe "&run/2 allows the closest lookalikes" do
    test "does not report a resolver with real computation" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            {:ok, format_owner(root.owner)}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report whole-root passthrough {:ok, root}" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            {:ok, root}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a capture passed to resolve" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve &Resolvers.Accounts.owner/3
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a dataloader call passed to resolve" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve dataloader(Accounts)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report the same fn shape when it is not a resolve argument" do
      """
      defmodule MyAppWeb.Schema do
        def build(root) do
          Enum.map([root], fn root, _args, _info -> {:ok, root.owner} end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a destructured second parameter" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn _args, %{source: root} ->
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report Map.get with a variable key" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, key ->
            {:ok, Map.get(root, key)}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a field access on a variable that is not a fn parameter" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn _root, _args, _info ->
            other = %{owner: :nobody}
            {:ok, other.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a resolve: pair inside a map literal" do
      """
      defmodule MyAppWeb.Schema do
        def config, do: %{resolve: fn root, _args, _info -> {:ok, root.owner} end}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a resolve: pair passed to a qualified call like Keyword.merge/2" do
      """
      defmodule MyAppWeb.Schema do
        def config(root) do
          Keyword.merge([], resolve: fn root, _args, _info -> {:ok, root.owner} end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a resolve fn assigned to a module attribute" do
      """
      defmodule MyAppWeb.Schema do
        @resolve fn root, _args, _info -> {:ok, root.owner} end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves a resolver alone when the first parameter is reassigned" do
    test "does not report a resolve fn that reassigns root before the final expression" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            root = MyApp.Repo.preload(root, :owner)
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a resolve fn that destructures root in a tuple rebind (round-3 finding)" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            {root, _meta} = MyApp.Repo.preload_with_meta(root, :owner)
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "still reports when root is only PINNED, not rebound (round-4 finding)" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            {^root, _meta} = MyApp.Repo.check(root)
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue -> assert issue.message =~ "root.owner" end)
    end
  end

  describe "&run/2 inspects only the last expression of the clause body" do
    test "fires when a preceding statement comes before the matching last expression" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            Logger.debug("resolving")
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "resolve"
      end)
    end

    test "stays silent when the matching shape is not the last expression" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info ->
            result = root.owner
            {:ok, result}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 matches the resolve: keyword form" do
    test "reports {:ok, root.field} passed as a keyword value" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user, resolve: fn root, _args, _info -> {:ok, root.owner} end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.column === 24
        assert issue.trigger === "resolve"
        assert issue.message =~ "root.owner"
      end)
    end

    test "reports with no trigger token when resolve: and the fn are split across lines" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user,
          resolve:
            fn root, _args, _info -> {:ok, root.owner} end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.column === 7
        assert issue.trigger === Credo.Issue.no_trigger()
      end)
    end

    test "gives each of two field calls with a resolve: keyword its own column on one line" do
      """
      defmodule MyAppWeb.Schema do
        field(:a, :string, resolve: fn r, _args, _info -> {:ok, r.a} end); field(:b, :string, resolve: fn r, _args, _info -> {:ok, r.b} end)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end

  describe "&run/2 finds the resolve: keyword form past a trailing do block (review finding 2)" do
    test "reports {:ok, root.field} when a do block follows the resolve: attrs list" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user, resolve: fn root, _args, _info -> {:ok, root.owner} end do
          description "the owning user"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.trigger === "resolve"
        assert issue.message =~ "root.owner"
      end)
    end

    test "reports the 3-arg field/attrs/do-block spelling the same way" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, resolve: fn root, _args, _info -> {:ok, root.owner} end do
          description "the owning user"
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end
  end

  describe "&run/2 ignores operator and attribute lookalikes (review finding 1)" do
    test "does not report a plain assignment whose value is a resolve keyword list" do
      """
      defmodule MyAppWeb.Schema do
        def build(conn) do
          table = [resolve: fn conn, _args, _info -> {:ok, conn.assigns} end]
          table
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a list concatenation whose result is a resolve keyword list" do
      """
      defmodule MyAppWeb.Schema do
        def build(root) do
          [name: :a] ++ [resolve: fn root, _args, _info -> {:ok, root.owner} end]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a module attribute whose value is a resolve keyword list" do
      """
      defmodule MyAppWeb.Schema do
        @dispatch_table [resolve: fn root, _args, _info -> {:ok, root.owner} end]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a 3+-element tuple literal whose last element is a resolve keyword list (round-3 finding)" do
      """
      defmodule MyAppWeb.Schema do
        def build(conn) do
          {:a, :b, [resolve: fn conn, _args, _info -> {:ok, conn.assigns} end]}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 qualifies the drop-the-resolver advice (review finding 3)" do
    test "message does not promise dropping the resolver is always safe" do
      """
      defmodule MyAppWeb.Schema do
        field :creator, :user do
          resolve fn post, _args, _info -> {:ok, post.creator} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue ->
        assert issue.message =~ "only if the field name already matches"
      end)
    end
  end

  describe "&run/2 requires a 3-arity clause (round-4 finding)" do
    test "does not report {:ok, root.field} at 2-arity (param 1 is args, not source)" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args ->
            {:ok, root.owner}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report the arity-2 args idiom (fn args, _info -> {:ok, args.message} end)" do
      """
      defmodule MyAppWeb.Schema do
        field :echo, :string do
          arg :message, non_null(:string)
          resolve fn args, _info -> {:ok, args.message} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report at 1-arity (not a valid Absinthe resolver)" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report at 4-arity (not a valid Absinthe resolver)" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info, _extra -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 considers only the fn's first parameter" do
    test "does not report a field read off the second (args) parameter" do
      """
      defmodule MyAppWeb.Schema do
        field :echo, :string do
          arg :message, non_null(:string)
          resolve fn _root, args, _info -> {:ok, args.message} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a field read off the third (info) parameter" do
      """
      defmodule MyAppWeb.Schema do
        field :context, :string do
          resolve fn _root, _args, info -> {:ok, info.context} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves Map identity through aliasing" do
    test "reports the Elixir.-prefixed spelling of Map" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, Elixir.Map.get(root, :owner)} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end

    test "does not report Map.get once the file aliases another module as Map" do
      """
      defmodule MyAppWeb.Schema do
        alias MyApp.Map

        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, Map.get(root, :owner)} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report Map.get once the file defines its own nested Map module" do
      """
      defmodule MyAppWeb.Schema do
        defmodule Map do
          def get(_source, _field), do: nil
        end

        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, Map.get(root, :owner)} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves a piped resolver silent (documented limitation)" do
    test "does not report a fn piped into resolve()" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          fn root, _args, _info -> {:ok, root.owner} end |> resolve()
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end
  end

  describe "&run/2 excludes test paths by default" do
    test "does not report a test file matching the _test.exs suffix" do
      """
      defmodule MyAppWeb.SchemaTest do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "does not report a file under a test/ directory that does not itself end in _test.exs" do
      """
      defmodule MyAppWeb.SchemaFixtures do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file("apps/my_app_web/test/support/schema_fixtures.ex")
      |> run_check(NoResolverFnForAssociation)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test')" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/latest/schema.ex")
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyAppWeb.SchemaTest do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoResolverFnForAssociation, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 locates the issue at resolve" do
    test "reports a column so Credo can validate the trigger" do
      """
      defmodule MyAppWeb.Schema do
        field :owner, :user do
          resolve fn root, _args, _info -> {:ok, root.owner} end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issue(fn issue -> assert issue.column === 5 end)
    end

    test "gives each of two resolve calls on one line its own column" do
      """
      defmodule MyAppWeb.Schema do
        def combined(root) do
          resolve(fn root, _, _ -> {:ok, root.a} end) && resolve(fn root, _, _ -> {:ok, root.b} end)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoResolverFnForAssociation)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
