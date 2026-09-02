# credo:disable-for-this-file MikaCredoRules.NoBannedModules
defmodule MikaCredoRules.NoBannedModulesTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoBannedModules

  @lib_file "apps/my_app/lib/my_app/auth.ex"
  @test_file "apps/my_app/test/my_app/auth_test.exs"

  @moduledoc_examples NoBannedModules
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoBannedModules"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  describe "&run/2 flags banned modules however they're referenced" do
    test "reports use Guardian" do
      """
      defmodule MyApp.Auth do
        use Guardian, otp_app: :my_app
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "Guardian"
        assert issue.message =~ "Guardian found"
        assert issue.message =~ "Redis tokens"
      end)
    end

    test "reports a Guardian remote call" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "Guardian"
      end)
    end

    test "reports a Joken remote call" do
      """
      defmodule MyApp.Auth do
        def sign(claims), do: Joken.generate_and_sign(claims)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Joken"
        assert issue.message =~ "Joken found"
      end)
    end

    test "reports a project alias later invoked with a bare use" do
      """
      defmodule MyApp.Auth do
        alias Guardian

        use Guardian, otp_app: :my_app
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() === [2, 4]
      end)
    end

    test "reports a module reference inside an attribute" do
      """
      defmodule MyApp.Auth do
        @behaviour Guardian
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "Guardian"
      end)
    end
  end

  describe "&run/2 flags submodules of a banned module" do
    test "reports use Joken.Config, Joken's own canonical entry point" do
      """
      defmodule MyApp.Auth do
        use Joken.Config

        @impl Joken.Config
        def token_config, do: default_claims()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        assert Enum.all?(issues, &(&1.trigger === "Joken.Config"))
        assert Enum.all?(issues, &(&1.message =~ "Joken.Config found"))
      end)
    end

    test "reports a multi-alias submodule (alias Guardian.{Plug, Permissions})" do
      """
      defmodule MyApp.Auth do
        alias Guardian.{Plug, Permissions}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        assert Enum.map(issues, & &1.trigger) |> Enum.sort() === ["Permissions", "Plug"]
      end)
    end

    test "does not report a fully qualified project module sharing no leading segment" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: MyApp.Guardian.Helper.sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "does not report a submodule of a locally shadowed stub" do
      """
      defmodule MyApp.AuthStub do
        defmodule Guardian do
          def encode_and_sign(user), do: {:ok, user}
        end

        def sign_in(user), do: Guardian.Helper.wrap(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  describe "&run/2 has a documented gap: aliasing a submodule of a banned module" do
    # AstHelpers.resolve_aliases/2's ADD half matches an alias target
    # EXACTLY against a banned entry (see moduledoc Limitations) — it does
    # not extend to a target that is merely PREFIXED by one. `alias
    # Guardian.Plug` only registers the local name `Plug` as pointing back
    # at `Guardian.Plug` itself, which is not in the entry list (only
    # `Guardian` is) — so the alias never resolves, and a later bare
    # `Plug.sign_in(...)` is silent. This pins the current, documented
    # behaviour rather than the ideal one.
    test "does not recognize a bare call reached through an alias of the banned module's own submodule" do
      """
      defmodule MyApp.Auth do
        alias Guardian.Plug

        def sign_in(conn), do: Plug.sign_in(conn, :user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.line_no === 2 end)
    end

    test "still recognizes the fully qualified submodule spelling, alias or not" do
      """
      defmodule MyApp.Auth do
        def sign_in(conn), do: Guardian.Plug.sign_in(conn, :user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Guardian.Plug" end)
    end
  end

  describe "&run/2 flags the Elixir.-prefixed atom spelling of a banned module" do
    test "reports a bare-atom module slot in a remote call" do
      """
      defmodule MyApp.Auth do
        def go(user), do: :"Elixir.Guardian".encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Elixir.Guardian"
        assert issue.message =~ "Guardian found"
      end)
    end

    test "the atom spelling still fires even when the bare name is locally shadowed" do
      """
      defmodule MyApp.AuthStub do
        defmodule Guardian do
          def encode_and_sign(user), do: {:ok, user}
        end

        def go(user), do: :"Elixir.Guardian".encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Guardian" end)
    end

    test "an ordinary erlang atom module is not mistaken for an Elixir module" do
      """
      defmodule MyApp.Auth do
        def go, do: :ets.new(:table, [:set])
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "reports the atom spelling passed as a bare attribute value" do
      """
      defmodule MyApp.Auth do
        @behaviour :"Elixir.Guardian"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Elixir.Guardian"
        assert issue.message =~ "Guardian found"
      end)
    end

    test "an alias-form attribute value is not double reported by the atom-spelling clause" do
      """
      defmodule MyApp.Auth do
        @behaviour Guardian
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Guardian" end)
    end
  end

  describe "&run/2 stays total over a non-atom __aliases__ segment" do
    test "does not crash on a __MODULE__-qualified submodule call" do
      """
      defmodule MyApp.Auth do
        def go(user), do: __MODULE__.Sub.run(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "does not crash on a __MODULE__-qualified type reference" do
      """
      defmodule MyApp.Auth do
        @type t :: %{sub: __MODULE__.Sub.t()}
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  describe "&run/2 raises for an unsupported :modules entry shape" do
    # Called directly (bypassing run_check/2's Task.async_stream) so the raise
    # surfaces in this process where assert_raise can catch it — under the
    # real Credo pipeline the same error still reaches the user, as a crashed
    # check run rather than a caught exception (Credo.Check.check.ex reraises
    # under `crash_on_error: true`, which Credo.Test.Case always sets).
    test "raises on an erlang-style atom module (no Module.split/1 support)" do
      source_file =
        """
        defmodule MyApp.Worker do
          def run, do: :ok
        end
        """
        |> to_source_file(@lib_file)

      assert_raise ArgumentError,
                   ~r/NoBannedModules: the :modules param entry .*:meck.* must be a/,
                   fn ->
                     NoBannedModules.run(source_file, modules: [{:meck, "no meck"}])
                   end
    end

    test "raises on a bare module with no {module, reason} tuple" do
      source_file =
        """
        defmodule MyApp.Worker do
          def run, do: :ok
        end
        """
        |> to_source_file(@lib_file)

      assert_raise ArgumentError,
                   ~r/NoBannedModules: the :modules param entry Guardian must be a/,
                   fn ->
                     NoBannedModules.run(source_file, modules: [Guardian])
                   end
    end
  end

  describe "&run/2 exempts project modules and mere mentions" do
    test "does not report a fully qualified project module of the same name" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: MyApp.Guardian.sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "does not report a string or atom that merely mentions a banned name" do
      """
      defmodule MyApp.Auth do
        def log_expired, do: Logger.warning("Guardian token expired")
        def error_kind, do: :guardian_error
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "does not report a mix.exs-style Hex dependency atom" do
      """
      defmodule MyApp.MixProject do
        defp deps do
          [{:guardian, "~> 2.0"}]
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  describe "&run/2 treats a locally defined module as shadowing" do
    test "does not report a local Guardian stub used by bare name" do
      """
      defmodule MyApp.AuthStub do
        defmodule Guardian do
          def encode_and_sign(user), do: {:ok, user}
        end

        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "still reports the fully qualified spelling of a shadowed name" do
      """
      defmodule MyApp.AuthStub do
        defmodule Guardian do
          def encode_and_sign(user), do: {:ok, user}
        end

        def sign_in(user), do: Elixir.Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Elixir.Guardian"
        assert issue.message =~ "Guardian found"
      end)
    end

    # `shadow_name/1` ignores the nested?/top-level distinction for a
    # single-segment name (see moduledoc Limitations) — a TOP-LEVEL
    # `defmodule Guardian do ... end` shadows the bare name file-wide, the
    # same as a nested one would, because a lone segment always shadows
    # regardless of nesting.
    test "a top-level single-segment defmodule also shadows the bare name file-wide" do
      """
      defmodule Guardian do
        def encode_and_sign(user), do: {:ok, user}
      end

      defmodule MyApp.Auth do
        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end
  end

  describe "&run/2 treats a project alias as shadowing (alias MyApp.Guardian)" do
    test "does not report a bare call once a project alias shadows the banned name" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Guardian

        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "does not report a qualified project reference resolved by the alias" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Guardian

        def sign_in(user), do: MyApp.Guardian.sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> refute_issues()
    end

    test "still reports the Elixir.-qualified spelling of an alias-shadowed name" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Guardian

        def sign_in(user), do: Elixir.Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.trigger === "Elixir.Guardian"
        assert issue.message =~ "Guardian found"
      end)
    end

    test "still reports the atom spelling of an alias-shadowed name" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Guardian

        def go(user), do: :"Elixir.Guardian".encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Guardian" end)
    end

    test "still reports an Elixir.-qualified submodule of an alias-shadowed name" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Guardian

        def sign_in(conn), do: Elixir.Guardian.Plug.sign_in(conn, :user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Guardian.Plug" end)
    end

    test "still reports the atom spelling of an alias-shadowed name in an attribute" do
      """
      defmodule MyApp.Auth do
        alias MyApp.Thing, as: Joken

        @behaviour :"Elixir.Joken"
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.trigger === "Elixir.Joken" end)
    end
  end

  describe "&run/2 honours the :modules param" do
    test "flags only the configured module, with its own reason in the message" do
      """
      defmodule MyApp.Worker do
        def run, do: SomeBannedLib.call()
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules, modules: [{SomeBannedLib, "use MyApp.Approved instead"}])
      |> assert_issue(fn issue ->
        assert issue.trigger === "SomeBannedLib"
        assert issue.message === "SomeBannedLib found — use MyApp.Approved instead"
      end)
    end

    test "no longer flags a default-banned module once :modules is overridden" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules, modules: [{SomeBannedLib, "banned"}])
      |> refute_issues()
    end
  end

  describe "&run/2 honours the :excluded_paths param" do
    test "reports a test file by default (excluded_paths defaults to [])" do
      """
      defmodule MyApp.AuthTest do
        def setup_auth, do: Guardian.encode_and_sign(:user)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBannedModules)
      |> assert_issue()
    end

    test "does not report a test file once :excluded_paths opts it out" do
      """
      defmodule MyApp.AuthTest do
        def setup_auth, do: Guardian.encode_and_sign(:user)
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoBannedModules, excluded_paths: ["_test.exs", "test/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file("apps/my_app/lib/latest/auth.ex")
      |> run_check(NoBannedModules, excluded_paths: ["test/"])
      |> assert_issue()
    end
  end

  describe "&run/2 locates each reference independently" do
    test "reports a column, so Credo can validate the trigger" do
      """
      defmodule MyApp.Auth do
        def sign_in(user), do: Guardian.encode_and_sign(user)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue -> assert issue.column === 26 end)
    end

    test "gives each of two references on one line its own column" do
      """
      defmodule MyApp.Auth do
        def sign_in(a, b), do: Guardian.encode_and_sign(a) && Guardian.encode_and_sign(b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end

    # Two atom-spelled references to the same module on one line collapse
    # onto the first match's column — a documented precision (not
    # correctness) tradeoff, see the traverse clause's comment.
    test "collapses two atom-spelled references on one line onto the same column" do
      """
      defmodule MyApp.Auth do
        def go(a, b), do: :"Elixir.Guardian".encode_and_sign(a) && :"Elixir.Guardian".encode_and_sign(b)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column === second.column
      end)
    end

    test "locates an attribute value written on a later line than the @" do
      """
      defmodule MyApp.Auth do
        @behaviour(
          :"Elixir.Guardian"
        )
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoBannedModules)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "Elixir.Guardian"
      end)
    end
  end
end
