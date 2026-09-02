defmodule MikaCredoRules.AbsintheDataloaderPluginRequiredTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.AbsintheDataloaderPluginRequired

  @schema_file "apps/my_app_web/lib/my_app_web/schema.ex"

  describe "&run/2 flags a Dataloader-using schema missing the plugin" do
    test "reports the moduledoc BAD example (no plugins/0 at all)" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx) do
          loader = Dataloader.new() |> Dataloader.add_source(Accounts, Accounts.data())
          Map.put(ctx, :loader, loader)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "use"
        assert issue.message =~ "Absinthe.Middleware.Dataloader"
        assert issue.message =~ "plugins"
      end)
    end

    test "reports a plugins/0 that omits Absinthe.Middleware.Dataloader" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        def plugins, do: Absinthe.Plugin.defaults()
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports when only Dataloader.add_source is used" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx) do
          loader = Dataloader.add_source(Dataloader.new(), Accounts, Accounts.data())
          Map.put(ctx, :loader, loader)
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "reports each offending Absinthe.Schema module independently (nested module scoping)" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        defmodule Helpers do
          def noop, do: :ok
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end
  end

  describe "&run/2 known limitations (documented, not fixed)" do
    test "reports a schema whose plugins/0 is injected by a __using__ macro" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema
        use SchemaMacros

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "does not report an outer schema whose only Dataloader usage lives in a nested module" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        defmodule Helpers do
          def build_loader, do: Dataloader.new()
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 does not flag a correctly configured schema" do
    test "does not report the moduledoc GOOD example (++ Absinthe.Plugin.defaults())" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        def plugins, do: [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end

    test "does not report when the plugin sits on the other side of ++" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        def plugins, do: Absinthe.Plugin.defaults() ++ [Absinthe.Middleware.Dataloader]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end

    test "does not report plugins/0 defined with parens" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        def plugins(), do: [Absinthe.Middleware.Dataloader]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end

    test "does not report a schema that never builds a Dataloader" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        query do
          field :ping, :string
        end
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end

    test "does not report a plugins/0 defined via defdelegate (unverifiable, not missing)" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        defdelegate plugins, to: SchemaPlugins
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end

    test "does not report a Dataloader.new call outside an Absinthe.Schema module" do
      """
      defmodule MyApp.Loader do
        def build, do: Dataloader.new()
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired)
      |> refute_issues()
    end
  end

  describe "&run/2 respects custom params" do
    test "honors a custom required_plugins list" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())

        def plugins, do: [Absinthe.Middleware.Dataloader]
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired, required_plugins: [MyApp.CustomPlugin])
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "honors excluded_paths" do
      """
      defmodule MyAppWeb.Schema do
        use Absinthe.Schema

        def context(ctx), do: Map.put(ctx, :loader, Dataloader.new())
      end
      """
      |> to_source_file(@schema_file)
      |> run_check(AbsintheDataloaderPluginRequired, excluded_paths: ["schema.ex"])
      |> refute_issues()
    end
  end
end
