defmodule MikaCredoRules.EctoSchemaRequiresTypeTTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.EctoSchemaRequiresTypeT

  @lib_file "apps/my_app/lib/my_app/accounts/user.ex"
  @test_lib_file "apps/my_app/test/support/user_fixture.ex"
  @test_scoped_file "apps/my_app/test/my_app/accounts/user_test.exs"
  @lookalike_lib_file "apps/my_app/lib/latest/user.ex"
  @non_test_dir_test_file "apps/my_app/integration/user_test.exs"

  @moduledoc_examples EctoSchemaRequiresTypeT
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  # DocExamples.readme_section/1 reads README.md, which does not carry this
  # check's section until the integrator merges it — until then it returns ""
  # and the four `for` comprehensions below would silently expand to zero
  # tests. Read our own docs/readme_sections copy instead (the integrator
  # merges it into README.md verbatim), and assert it actually produced
  # examples so a broken fence or a renamed file fails loudly instead of
  # quietly generating nothing.
  @readme_examples "docs/readme_sections/EctoSchemaRequiresTypeT.md"
                   |> File.read!()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  if @readme_examples === [] do
    raise "docs/readme_sections/EctoSchemaRequiresTypeT.md doc-gate found zero BAD/GOOD examples"
  end

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a schema without @type t" do
    test "reports a plain schema module" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "use Ecto.Schema"
        assert issue.message =~ "use Ecto.Schema"
        assert issue.message =~ "@type t"
      end)
    end

    test "reports an embedded_schema module" do
      """
      defmodule MyApp.Accounts.Address do
        use Ecto.Schema

        embedded_schema do
          field :city, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Ecto.Schema" end)
    end

    test "reports a schema whose only type is @type t(inner) at a different arity" do
      """
      defmodule MyApp.Accounts.Wrapper do
        use Ecto.Schema

        @type t(inner) :: %{__struct__: __MODULE__, payload: inner}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Ecto.Schema" end)
    end
  end

  describe "&run/2 allows a schema with @type t" do
    test "does not report a bare @type t :: %__MODULE__{}" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @type t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report @type t() :: %__MODULE__{} with explicit parens" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @type t() :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report @type t preceded by a @typedoc" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @typedoc "A user record."
        @type t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a bare @opaque t :: %__MODULE__{}" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @opaque t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a bare @typep t :: %__MODULE__{}" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @typep t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end
  end

  describe "&run/2 stays silent on non-schema modules" do
    test "does not report a module without use Ecto.Schema" do
      """
      defmodule MyApp.Accounts.UserHelper do
        def format_name(user), do: user.name
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a struct module built with defstruct" do
      """
      defmodule MyApp.Accounts.UserParams do
        defstruct [:name, :email]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a bare use Ecto.Schema with no schema block at all" do
      """
      defmodule MyApp.Accounts.NoStructBase do
        use Ecto.Schema
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a __using__ base module whose use Ecto.Schema lives in a quote block" do
      """
      defmodule MyApp.Schemas.Base do
        defmacro __using__(_opts) do
          quote do
            use Ecto.Schema
            @primary_key {:id, :binary_id, autogenerate: true}
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a __using__ base module whose quote block also calls schema itself" do
      """
      defmodule MyApp.Schemas.Base do
        defmacro __using__(opts) do
          quote do
            use Ecto.Schema

            schema unquote(opts[:table]) do
              field :name, :string
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a function definition named schema/1, not a schema call" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        def schema(name), do: name
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a zero-arity function definition named schema/0" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        def schema(), do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a @spec naming schema/1, not a schema call" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @spec schema(atom()) :: term()
        def build(name), do: name
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a defmacro head that pattern-matches its last arg as do: (Ecto's own schema/2 signature)" do
      """
      defmodule MyApp.Schemas.Wrapper do
        use Ecto.Schema

        defmacro schema(source, do: block) do
          quote do
            unquote(source)
            unquote(block)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a def head that pattern-matches its last arg as do:" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        def schema(name, do: block), do: {name, block}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes each defmodule independently" do
    test "reports only the nested schema module missing its own @type t" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        @type t :: %__MODULE__{}

        schema "users" do
          field :name, :string
        end

        defmodule Nested do
          use Ecto.Schema

          embedded_schema do
            field :note, :string
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.line_no === 11 end)
    end

    test "does not report a nested plain helper module inside a schema module missing @type t" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end

        defmodule Helper do
          def format(user), do: user.name
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Ecto.Schema" end)
    end

    test "reports the outer schema module even when a nested schema module already has @type t" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end

        defmodule Nested do
          use Ecto.Schema

          @type t :: %__MODULE__{}

          embedded_schema do
            field :note, :string
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports the nested schema module exactly once, not the non-schema wrapper too" do
      """
      defmodule MyApp.Accounts.Wrapper do
        defmodule Inner do
          use Ecto.Schema

          schema "users" do
            field :name, :string
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.line_no === 3 end)
    end
  end

  describe "&run/2 resolves aliases" do
    test "reports a use under a short alias" do
      """
      defmodule MyApp.Accounts.User do
        alias Ecto.Schema
        use Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Schema" end)
    end

    test "reports a fully qualified use Elixir.Ecto.Schema" do
      """
      defmodule MyApp.Accounts.User do
        use Elixir.Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Elixir.Ecto.Schema" end)
    end

    test "reports a parenthesized use(Ecto.Schema) with a trigger that matches the source at its column" do
      """
      defmodule MyApp.Accounts.User do
        use(Ecto.Schema)

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue ->
        assert issue.trigger === "use"
        assert issue.column === 3
        assert issue.message =~ "use Ecto.Schema"
      end)
    end

    test "reports an atom-spelled use with a trigger that matches the source at its column" do
      """
      defmodule MyApp.Accounts.User do
        use :"Elixir.Ecto.Schema"

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue ->
        assert issue.trigger === "use"
        assert issue.column === 3
        assert issue.message =~ "use Ecto.Schema"
      end)
    end

    test "stays silent once the bare name is shadowed by another alias" do
      """
      defmodule MyApp.Accounts.User do
        alias Ecto.Schema
        alias MyApp.Something, as: Schema
        use Schema

        def perform, do: :ok
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "still reports a schema even when an unrelated local defmodule shares the alias's bare name" do
      """
      alias Ecto.Schema

      defmodule Schema do
        def build, do: :ok
      end

      defmodule MyApp.Accounts.User do
        use Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.trigger === "use Schema" end)
    end
  end

  describe "&run/2 excludes test paths by default" do
    test "does not report a _test.exs file" do
      """
      defmodule MyApp.Accounts.UserTest do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@test_scoped_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a file under a test/ directory" do
      """
      defmodule MyApp.UserFixture do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@test_lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "does not report a _test.exs file outside any test/ directory" do
      """
      defmodule MyApp.Accounts.UserTest do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@non_test_dir_test_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> refute_issues()
    end

    test "still checks a boundary lookalike path (lib/latest/ contains 'test')" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lookalike_lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.Accounts.UserTest do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@test_scoped_file)
      |> run_check(EctoSchemaRequiresTypeT, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 respects a custom :schema_modules" do
    test "reports a use of a custom schema module" do
      """
      defmodule MyApp.Accounts.User do
        use MyApp.CustomSchema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT, schema_modules: [MyApp.CustomSchema])
      |> assert_issue(fn issue -> assert issue.trigger === "use MyApp.CustomSchema" end)
    end

    test "no longer reports plain Ecto.Schema when :schema_modules is overridden" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT, schema_modules: [MyApp.CustomSchema])
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the use line" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issue(fn issue -> assert issue.column === 3 end)
    end
  end

  describe "&run/2 reports two triggers on one line" do
    test "reports both defmodules with distinct columns" do
      (~s'defmodule A do use Ecto.Schema; schema "a", do: nil end; ' <>
         ~s'defmodule B do use Ecto.Schema; schema "b", do: nil end')
      |> to_source_file(@lib_file)
      |> run_check(EctoSchemaRequiresTypeT)
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.column) === [73, 16]
        assert Enum.all?(issues, &(&1.line_no === 1))
      end)
    end
  end
end
