defmodule MikaCredoRules.NoJasonDeriveOnEctoSchemaTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoJasonDeriveOnEctoSchema

  @schema_file "apps/my_app/lib/my_app/user.ex"

  describe "&run/2 flags @derive Jason.Encoder inside Ecto schema modules" do
    test "reports a bare @derive Jason.Encoder" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive Jason.Encoder

        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "@derive"
        assert issue.message =~ "@derive Jason.Encoder on an Ecto schema"
        assert issue.message =~ "view or JSON layer"
      end)
    end

    test "reports the moduledoc BAD example (tuple form with :only opts)" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive {Jason.Encoder, only: [:id, :name]}
        schema "users" do
          field :name, :string
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "@derive"
      end)
    end

    test "reports @derive with a protocol list" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive [Jason.Encoder, Inspect]

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports @derive with a list of protocol tuples" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive [{Jason.Encoder, only: [:id]}, Inspect]

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports @derive in an embedded schema" do
      """
      defmodule MyApp.Money do
        use Ecto.Schema

        @derive Jason.Encoder

        embedded_schema do
          field :amount, :integer
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports each schema module's @derive with its own line number" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive Jason.Encoder

        schema "users" do
        end
      end

      defmodule MyApp.Post do
        use Ecto.Schema

        @derive Jason.Encoder

        schema "posts" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [4, 13]
      end)
    end
  end

  describe "&run/2 resolves every module spelling" do
    test "reports @derive Encoder under alias Jason.Encoder" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        alias Jason.Encoder

        @derive Encoder

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports @derive {Encoder, only: []} under alias Jason.Encoder" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        alias Jason.Encoder

        @derive {Encoder, only: []}

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "reports the Elixir-prefixed atom spellings of both modules" do
      """
      defmodule MyApp.User do
        use :"Elixir.Ecto.Schema"

        @derive :"Elixir.Jason.Encoder"

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 4 end)
    end

    test "reports use Schema under alias Ecto.Schema" do
      """
      defmodule MyApp.User do
        alias Ecto.Schema

        use Schema

        @derive Jason.Encoder

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 6 end)
    end

    test "does not report @derive Encoder when Encoder is a project module" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        alias MyApp.Encoder

        @derive Encoder

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end
  end

  describe "&run/2 scopes per defmodule, not per file" do
    test "reports a schema module nested inside a plain module" do
      """
      defmodule MyApp.Accounts do
        defmodule User do
          use Ecto.Schema

          @derive Jason.Encoder

          schema "users" do
          end
        end

        def list_users, do: []
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report @derive on a plain module sharing a file with a schema" do
      """
      defmodule MyApp.Token do
        @derive Jason.Encoder
        defstruct [:value]
      end

      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end

    test "does not report @derive in a nested non-schema module inside a schema" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
        end

        defmodule Meta do
          @derive Jason.Encoder
          defstruct [:source]
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end
  end

  describe "&run/2 leaves non-schema modules and other derives alone" do
    test "does not report @derive of another protocol on a schema" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        @derive Inspect

        schema "users" do
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end

    test "does not report @derive Jason.Encoder in a plain module" do
      """
      defmodule MyApp.Token do
        @derive Jason.Encoder
        defstruct [:value]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end

    test "does not report import Ecto.Schema as a schema module" do
      """
      defmodule MyApp.Token do
        import Ecto.Schema

        @derive Jason.Encoder
        defstruct [:value]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end

    test "does not report defimpl Jason.Encoder" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
        end
      end

      defimpl Jason.Encoder, for: MyApp.User do
        def encode(user, opts), do: Jason.Encode.map(%{id: user.id}, opts)
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end

    test "does not report the moduledoc GOOD examples" do
      """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end

      defmodule MyAppWeb.UserJSON do
        def show(%{user: user}), do: %{id: user.id, name: user.name}
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(NoJasonDeriveOnEctoSchema)
      |> refute_issues()
    end
  end
end
