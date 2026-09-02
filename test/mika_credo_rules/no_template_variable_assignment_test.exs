defmodule MikaCredoRules.NoTemplateVariableAssignmentTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.NoTemplateVariableAssignment

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  @moduledoc_examples NoTemplateVariableAssignment
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "NoTemplateVariableAssignment"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 flags a <% var = ... %> assignment" do
    test "reports a plain assignment inside a ~H body" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div>
            <% user = @current_user %>
            <p>{user.name}</p>
          </div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "user ="
        assert issue.message =~ "user ="
        assert issue.message =~ "change tracking"
      end)
    end

    test "reports a discard assignment (<% _ = something %>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% _ = Logger.debug("rendering") %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "_ =" end)
    end

    test "reports a `?`-suffixed predicate variable name" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% valid? = @user.ok %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "valid? =" end)
    end

    test "reports a `!`-suffixed variable name" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% loaded! = @user.ok %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "loaded! =" end)
    end

    test "reports an assignment inside a ~F body (default :sigils)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <% total = compute_total(@items) %>
          <p>{total}</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "total =" end)
    end
  end

  describe "&run/2 allows non-assignment EEx tags" do
    test "does not report an output tag (<%= %>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <p><%= @user.name %></p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report an EEx comment tag (<%# %>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%# this renders the greeting %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report an escaped literal tag (<%% %>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%% var = foo %>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report an == comparison inside an if tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% if x == y do %>
            <p>match</p>
          <% end %>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report a <= comparison inside an if tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% if x <= 10 do %>
            <p>small</p>
          <% end %>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report a bare == comparison (closest lookalike to the positive case)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% user == @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report a =~ match operator" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% name =~ "abc" %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end

    test "does not report x = y inside a {...} attribute interpolation" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div class={width = "50%"}>hi</div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 allows an uppercase (module-alias) left-hand side" do
    test "does not report <% Foo = compute() %>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% Foo = compute() %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 documented limitation: destructuring assignment" do
    test "does not report a pattern-match left-hand side" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% {first, second} = compute_pair() %>
          <p>{first}</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 documented limitation: only the first assignment in a shared tag" do
    test "reports only the first of two assignments packed into one <% %> tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% a = 1; b = 2 %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "a =" end)
    end
  end

  describe "&run/2 by design: an output tag assignment is silent" do
    test "does not report <%= user = @current_user %>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%= user = @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 documented false positive: HEEx comment wrapped assignment" do
    test "still reports an assignment whose text is wrapped in <%!-- --%>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%!-- <% legacy = @thing %> --%>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue -> assert issue.trigger === "legacy =" end)
    end
  end

  describe "&run/2 respects :sigils" do
    test "a ~H assignment is silent once :sigils excludes sigil_H" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% user = @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment, sigils: [:sigil_F])
      |> refute_issues()
    end

    test "does not report an assignment-lookalike inside a ~HOLO body (different framework)" do
      """
      defmodule MyAppWeb.Comp do
        def template(assigns) do
          ~HOLO\"\"\"
          <% user = @current_user %>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> refute_issues()
    end
  end

  describe "&run/2 respects :excluded_paths" do
    test "does not report a file under an excluded path" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% user = @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/generated/comp.ex")
      |> run_check(NoTemplateVariableAssignment, excluded_paths: ["generated/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (autogenerated/ contains 'generated/')" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% user = @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/autogenerated/comp.ex")
      |> run_check(NoTemplateVariableAssignment, excluded_paths: ["generated/"])
      |> assert_issue()
    end
  end

  describe "&run/2 locates each trigger with a column" do
    test "gives each of two assignments on one line its own column" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% a = 1 %><% b = 2 %>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        [first, second] = issues
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end

    test "clamps the trigger to one line when whitespace before = spans a newline" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <% user
             = @current_user %>
          <p>hi</p>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(NoTemplateVariableAssignment)
      |> assert_issue(fn issue ->
        assert issue.line_no === 4
        assert issue.trigger === "user"
        refute issue.trigger =~ "\n"
      end)
    end
  end
end
