defmodule MikaCredoRules.PubSubRequiresMessageStructTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.PubSubRequiresMessageStruct

  @lib_file "apps/my_app/lib/my_app/live/course_live.ex"
  @test_file "apps/my_app/test/my_app/live/course_live_test.exs"

  @moduledoc_examples PubSubRequiresMessageStruct
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
  @readme_examples "docs/readme_sections/PubSubRequiresMessageStruct.md"
                   |> File.read!()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  if @readme_examples === [] do
    raise "docs/readme_sections/PubSubRequiresMessageStruct.md doc-gate found zero BAD/GOOD examples"
  end

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a bare atom/tuple/map payload on Phoenix.PubSub broadcast/broadcast!/local_broadcast" do
    test "reports a bare atom payload on broadcast/3" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.trigger === "broadcast"
        assert issue.message =~ ":updated"
        assert issue.message =~ "message struct"
      end)
    end

    test "reports a 2-element tuple payload on broadcast!/3" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, course) do
          Phoenix.PubSub.broadcast!(pubsub, topic, {:course_updated, course})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "{:course_updated, course}"
      end)
    end

    test "reports a 3-element tuple payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, {:a, :b, :c})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ "{:a, :b, :c}" end)
    end

    test "reports a bare map payload without __struct__ on local_broadcast/3" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.local_broadcast(pubsub, topic, %{event: :updated})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ "%{event: :updated}"
      end)
    end

    test "reports a map-update payload even when the base is already a message struct" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, base) do
          Phoenix.PubSub.broadcast(pubsub, topic, %{base | event: :updated})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ "%{base | event: :updated}" end)
    end

    test "reports a bare module-alias payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, MyApp.Event)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Event" end)
    end

    test "reports a bare atom payload with a trailing dispatcher argument" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated, MyApp.Dispatcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue()
    end

    test "reports a piped broadcast call at the payload's shifted position" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          pubsub |> Phoenix.PubSub.broadcast(topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ ":updated"
      end)
    end

    test "does not report a piped broadcast call's variable payload as its trailing dispatcher" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, message) do
          pubsub |> Phoenix.PubSub.broadcast(topic, message, :my_dispatcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "reports exactly one issue for a piped broadcast call with a trailing dispatcher argument" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          pubsub |> Phoenix.PubSub.broadcast(topic, :updated, :my_dispatcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ ":updated" end)
    end
  end

  describe "&run/2 handles broadcast_from/broadcast_from! at their own payload position" do
    test "reports a bare atom payload on broadcast_from/4" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast_from(pubsub, self(), topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue ->
        assert issue.line_no === 3
        assert issue.message =~ ":updated"
      end)
    end

    test "reports a bare tuple payload on broadcast_from!/4" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, course) do
          Phoenix.PubSub.broadcast_from!(pubsub, self(), topic, {:course_updated, course})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ "{:course_updated, course}" end)
    end

    test "does not misread broadcast/3's payload as broadcast_from's would be positioned" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, message) do
          Phoenix.PubSub.broadcast(pubsub, topic, message, :my_dispatcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "reports a piped broadcast_from call at its shifted payload position" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          pubsub |> Phoenix.PubSub.broadcast_from(self(), topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ ":updated" end)
    end

    test "reports broadcast_from's payload at its own index even with a trailing dispatcher argument" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast_from(pubsub, self(), topic, :updated, MyApp.Dispatcher)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.message =~ ":updated" end)
    end
  end

  describe "&run/2 leaves a message struct, variable, or unrecognised payload alone" do
    test "does not report a message struct payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, %MyApp.PubSub.Message{event: :updated})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a __MODULE__ struct payload" do
      """
      defmodule MyApp.PubSub.Message do
        defstruct [:event]

        def broadcast_self(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, %__MODULE__{event: :updated})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a hand-written map literal carrying a __struct__ key" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, %{__struct__: MyApp.Message, event: :updated})
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a variable payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, message) do
          Phoenix.PubSub.broadcast(pubsub, topic, message)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a function-call payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic, course) do
          Phoenix.PubSub.broadcast(pubsub, topic, build_message(course))
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a list literal payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, [:updated, 1])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a string payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, "course_updated")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a number payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, 42)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a charlist payload" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, ~c"updated")
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a call reached through the atom-spelled module form" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          :"Elixir.Phoenix.PubSub".broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a call reached through apply/3" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          apply(Phoenix.PubSub, :broadcast, [pubsub, topic, :updated])
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report an unqualified call reached through import Phoenix.PubSub" do
      """
      defmodule MyApp.Courses do
        import Phoenix.PubSub

        def notify(pubsub, topic) do
          broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end
  end

  describe "&run/2 resolves Phoenix.PubSub through aliasing, not by function name alone" do
    test "reports a call through an alias Phoenix.PubSub short name" do
      """
      defmodule MyApp.Courses do
        alias Phoenix.PubSub

        def notify(pubsub, topic) do
          PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "does not report a same-named function on an unrelated module" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          MyApp.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "does not report a bare PubSub call shadowed by an alias to a different module" do
      """
      defmodule MyApp.Courses do
        alias MyApp.PubSub

        def notify(pubsub, topic) do
          PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "fires inside the project's own pubsub wrapper module, no path exemption" do
      """
      defmodule MyApp.PubSub.Broadcaster do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/my_app/pubsub/broadcaster.ex")
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue()
    end
  end

  describe "&run/2 respects :excluded_paths" do
    test "does not report a _test.exs file by default" do
      """
      defmodule MyApp.CourseLiveTest do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.CourseLive do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/course_live.ex")
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue()
    end

    test "reports a test file when :excluded_paths is overridden" do
      """
      defmodule MyApp.CourseLiveTest do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(PubSubRequiresMessageStruct, excluded_paths: [])
      |> assert_issue()
    end
  end

  describe "&run/2 respects a custom :functions list" do
    test "does not report local_broadcast when :functions is narrowed to broadcast only" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.local_broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct, functions: [:broadcast])
      |> refute_issues()
    end

    test "still reports broadcast when :functions is narrowed to broadcast only" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.broadcast(pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct, functions: [:broadcast])
      |> assert_issue()
    end

    test "does not report local_broadcast_from, which is absent from the default :functions list" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub, topic) do
          Phoenix.PubSub.local_broadcast_from(pubsub, self(), topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end

    test "reports direct_broadcast's payload at its own index, not its topic argument" do
      """
      defmodule MyApp.Courses do
        def notify(node_name, pubsub, topic) do
          Phoenix.PubSub.direct_broadcast(node_name, pubsub, topic, :updated)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct, functions: [:direct_broadcast])
      |> assert_issue(fn issue -> assert issue.message =~ ":updated" end)
    end

    test "does not misread direct_broadcast's atom topic as its payload" do
      """
      defmodule MyApp.Courses do
        def notify(node_name, pubsub, message) do
          Phoenix.PubSub.direct_broadcast(node_name, pubsub, :my_topic, message)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct, functions: [:direct_broadcast])
      |> refute_issues()
    end
  end

  describe "&run/2 resolves aliases file-wide, not lexically (documented limitation)" do
    test "false positive: a later, unrelated alias Phoenix.PubSub darkens an earlier module's own PubSub wrapper call" do
      """
      defmodule MyApp.ModuleA do
        alias MyApp.PubSub

        def notify(pubsub, topic) do
          PubSub.broadcast(pubsub, topic, :updated)
        end
      end

      defmodule MyApp.ModuleB do
        alias Phoenix.PubSub
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issue(fn issue -> assert issue.line_no === 5 end)
    end

    test "false negative: a later, unrelated alias MyApp.PubSub darkens an earlier module's real Phoenix.PubSub call" do
      """
      defmodule MyApp.ModuleA do
        alias Phoenix.PubSub

        def notify(pubsub, topic) do
          PubSub.broadcast(pubsub, topic, :updated)
        end
      end

      defmodule MyApp.ModuleB do
        alias MyApp.PubSub
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> refute_issues()
    end
  end

  describe "&run/2 gives two offending broadcasts on one line distinct columns" do
    test "each call on the same line gets its own column" do
      """
      defmodule MyApp.Courses do
        def notify(pubsub) do
          Phoenix.PubSub.broadcast(pubsub, "a", :x); Phoenix.PubSub.broadcast(pubsub, "b", :y)
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(PubSubRequiresMessageStruct)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
