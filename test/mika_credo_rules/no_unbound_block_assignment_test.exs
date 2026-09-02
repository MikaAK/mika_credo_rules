defmodule MikaCredoRules.NoUnboundBlockAssignmentTest do
  use Credo.Test.Case

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoUnboundBlockAssignment

  @lib_file "apps/my_app/lib/my_app/live/session_live.ex"
  @test_file "apps/my_app/test/my_app/live/session_live_test.exs"

  @moduledoc_examples NoUnboundBlockAssignment
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoUnboundBlockAssignment"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 flags an `if` in statement position ending in a bare assignment" do
    test "reports the classic socket = assign(...) LiveView bug" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "socket"
        assert issue.message =~ "socket"
        assert issue.message =~ "discarded"
      end)
    end

    test "reports an assignment in the else branch" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            :ok
          else
            socket = fallback(socket, val)
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports an unless branch ending in a bare assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, flag) do
          unless flag do
            socket = reset(socket)
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end
  end

  describe "&run/2 flags case/cond branches ending in a bare assignment" do
    test "reports a case branch ending in a bare assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, msg) do
          case msg do
            :connect -> socket = assign(socket, :connected, true)
            _ -> :ok
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "socket"
      end)
    end

    test "reports a cond branch ending in a bare assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, flag) do
          cond do
            flag -> socket = assign(socket, :flag, true)
            true -> :ok
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "does not confuse a case clause head's `=` pattern with a branch body assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, msg) do
          case msg do
            pair = {:ok, val} -> log(pair, val)
            _ -> :ok
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 chases a branch's tail through nested if/case/cond/unless" do
    test "reports a bare assignment nested two ifs deep" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            if ready?(socket) do
              socket = assign(socket, :val, val)
            end
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports a nested if preceded by another statement in the outer branch" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            Logger.info("connecting")

            if ready?(socket) do
              socket = assign(socket, :val, val)
            end
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports an if nested in a case branch" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, action) do
          case action do
            :save ->
              if valid?(socket) do
                socket = put_flash(socket, :info, "saved")
              end

            _ ->
              :noop
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports a case nested in an if" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, msg) do
          if connected?(socket) do
            case msg do
              :a -> socket = assign(socket, :val, 1)
              _ -> :ok
            end
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports an if nested in a cond branch" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, flag) do
          cond do
            flag ->
              if connected?(socket) do
                socket = assign(socket, :flag, true)
              end

            true ->
              :ok
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "reports an unless nested in another unless" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, flag) do
          unless flag do
            unless connected?(socket) do
              socket = reset(socket)
            end
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "socket" end)
    end

    test "does not report a nested if that is truly the function's own return value" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            if ready?(socket) do
              socket = assign(socket, :val, val)
            end
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not chase through a with whose own tail is a bare assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            with {:ok, val} <- fetch(val) do
              socket = assign(socket, :val, val)
            end
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 stays silent when the block's result is used" do
    test "does not report when the if's own result is bound" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          socket = if connected?(socket), do: assign(socket, :val, val), else: socket
          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report an if in return position as the function's last expression" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report an if in tail position of a multi-statement block" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          Logger.info("connecting")

          if connected?(socket) do
            socket = assign(socket, :val, val)
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report a case in tail position of a multi-statement block" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, msg) do
          Logger.info("connecting")

          case msg do
            :connect -> socket = assign(socket, :connected, true)
            _ -> :ok
          end
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report an assignment that is not the branch's own tail statement" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
            Logger.info("assigned \#{inspect(socket)}")
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report a branch ending in a plain call" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            Logger.info("connected")
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report a branch ending in a bare :ok" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            :ok
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report a destructuring tail assignment" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            {a, b} = compute(val)
            use_pair(a, b)
          end

          if connected?(socket) do
            {a, b} = compute(val)
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report an assignment to the wildcard `_`" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            _ = log(val)
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end

    test "does not report an assignment to an underscore-prefixed name" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            _socket = assign(socket, :val, val)
          end

          socket
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 locates the issue at the assigned variable" do
    test "reports a column pointing at the variable, not the `=`" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue(fn issue -> assert issue.column === 7 end)
    end

    test "gives two unbound assignments on one line distinct columns" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, first_flag, second_flag) do
          if first_flag, do: first = compute_first(); if second_flag, do: second = compute_second()
          {:noreply, socket, first, second}
        end
      end
      """
      |> to_source_file(@lib_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issues(fn [first, second] ->
        assert first.line_no === second.line_no
        assert first.column !== second.column
        assert first.trigger !== second.trigger
      end)
    end
  end

  describe "&run/2 path scoping via :excluded_paths" do
    test "checks a test file by default" do
      """
      defmodule MyApp.SessionLiveTest do
        def setup_session(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end

          socket
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoUnboundBlockAssignment)
      |> assert_issue()
    end

    test "does not report an excluded path when :excluded_paths is overridden" do
      """
      defmodule MyApp.SessionLiveTest do
        def setup_session(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end

          socket
        end
      end
      """
      |> to_source_file(@test_file)
      |> run_check(NoUnboundBlockAssignment, excluded_paths: ["test/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path with the same override (lib/latest/ contains 'test/')" do
      """
      defmodule MyApp.SessionLive do
        def handle(socket, val) do
          if connected?(socket) do
            socket = assign(socket, :val, val)
          end

          {:noreply, socket}
        end
      end
      """
      |> to_source_file("apps/my_app/lib/latest/session_live.ex")
      |> run_check(NoUnboundBlockAssignment, excluded_paths: ["test/"])
      |> assert_issue()
    end
  end
end
