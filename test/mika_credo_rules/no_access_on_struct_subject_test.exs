defmodule MikaCredoRules.NoAccessOnStructSubjectTest do
  use Credo.Test.Case

  alias MikaCredoRules.NoAccessOnStructSubject

  @lib_file "apps/my_app/lib/my_app/worker.ex"

  describe "&run/2 flags Access reads on a known-struct variable name" do
    test "reports changeset[:name]" do
      """
      defmodule MyApp.Worker do
        def name(changeset), do: changeset[:name]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issue(fn issue ->
        assert issue.line_no === 2
        assert issue.trigger === "changeset[:name]"
        assert issue.message =~ "changeset[:name] found"
        assert issue.message =~ "UndefinedFunctionError"
      end)
    end

    test "reports conn[:assigns]" do
      """
      defmodule MyApp.Worker do
        def assigns(conn), do: conn[:assigns]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issue(fn issue -> assert issue.trigger === "conn[:assigns]" end)
    end

    test "reports socket[:assigns]" do
      """
      defmodule MyApp.Worker do
        def assigns(socket), do: socket[:assigns]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issue(fn issue -> assert issue.trigger === "socket[:assigns]" end)
    end

    test "reports two accesses on their own columns when repeated on one line" do
      """
      defmodule MyApp.Worker do
        def both(changeset), do: changeset[:a] && changeset[:b]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issues(fn issues -> assert length(issues) === 2 end)
    end
  end

  describe "&run/2 flags Access reads on a struct literal" do
    test "reports %User{}[:name]" do
      """
      defmodule MyApp.Worker do
        def name, do: %MyApp.User{}[:name]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issue(fn issue -> assert issue.trigger === "%MyApp.User{}[:name]" end)
    end
  end

  describe "&run/2 leaves plain maps and keyword lists alone" do
    test "does not report params[\"id\"]" do
      """
      defmodule MyApp.Worker do
        def id(params), do: params["id"]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end

    test "does not report opts[:timeout]" do
      """
      defmodule MyApp.Worker do
        def timeout(opts), do: opts[:timeout]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end

    test "does not report nested access where the subject is itself an access expression" do
      """
      defmodule MyApp.Worker do
        def nested(opts), do: opts[:a][:b]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end

    test "does not report struct.field access" do
      """
      defmodule MyApp.Worker do
        def name(changeset), do: changeset.name
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end

    test "does not report Ecto.Changeset.get_field/2" do
      """
      defmodule MyApp.Worker do
        def name(changeset), do: Ecto.Changeset.get_field(changeset, :name)
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end
  end

  describe "&run/2 honors :subject_names" do
    test "does not report a variable not in the configured list" do
      """
      defmodule MyApp.Worker do
        def value(record), do: record[:name]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end

    test "reports a custom subject name" do
      """
      defmodule MyApp.Worker do
        def value(record), do: record[:name]
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject, subject_names: [:record])
      |> assert_issue(fn issue -> assert issue.trigger === "record[:name]" end)
    end
  end

  describe "&run/2 honors :excluded_paths" do
    test "does not report inside an excluded path" do
      """
      defmodule MyApp.Legacy.Worker do
        def name(changeset), do: changeset[:name]
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/legacy/worker.ex")
      |> run_check(NoAccessOnStructSubject, excluded_paths: ["legacy/"])
      |> refute_issues()
    end
  end

  describe "moduledoc examples" do
    test "reports the moduledoc BAD examples" do
      """
      def name(changeset), do: changeset[:name]
      def assigns(conn), do: conn[:assigns]
      def assigns(socket), do: socket[:assigns]
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> assert_issues(fn issues -> assert length(issues) === 3 end)
    end

    test "does not report the moduledoc GOOD examples" do
      """
      def name(changeset), do: Ecto.Changeset.get_field(changeset, :name)
      def assigns(conn), do: conn.assigns
      def assigns(socket), do: socket.assigns
      def id(params), do: params["id"]
      def timeout(opts), do: opts[:timeout]
      """
      |> to_source_file(@lib_file)
      |> run_check(NoAccessOnStructSubject)
      |> refute_issues()
    end
  end
end
