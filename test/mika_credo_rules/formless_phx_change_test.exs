defmodule MikaCredoRules.FormlessPhxChangeTest do
  use Credo.Test.Case, async: true

  alias MikaCredoRules.DocExamples
  alias MikaCredoRules.FormlessPhxChange

  @filename "apps/my_app_web/lib/my_app_web/live/comp.ex"

  @moduledoc_examples FormlessPhxChange
                      |> DocExamples.moduledoc()
                      |> DocExamples.indented_blocks()
                      |> DocExamples.bad_good_examples()

  @readme_examples "FormlessPhxChange"
                   |> DocExamples.readme_section()
                   |> DocExamples.fenced_blocks()
                   |> DocExamples.bad_good_examples()

  for {index, "BAD", code} <- @moduledoc_examples do
    test "moduledoc BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @moduledoc_examples do
    test "moduledoc GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  for {index, "BAD", code} <- @readme_examples do
    test "README BAD example #{index} fires" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue()
    end
  end

  for {index, "GOOD", code} <- @readme_examples do
    test "README GOOD example #{index} is clean" do
      unquote(code)
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 flags phx-change on a bare form control" do
    test "reports phx-change on a bare <input> with no form marker anywhere" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <div>
            <input type="text" phx-change="update_q" />
          </div>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue ->
        assert issue.line_no === 5
        assert issue.trigger === "<input"
        assert issue.message =~ "phx-change"
        assert issue.message =~ "form"
        assert issue.message =~ "reaches the server instead of throwing"
        refute issue.message =~ "actually fires in a real browser"
      end)
    end

    test "reports phx-change on a bare <select> with no form marker anywhere" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <select phx-change="update_kind">
            <option value="a">A</option>
          </select>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<select" end)
    end

    test "reports phx-change on a bare <textarea> with no form marker anywhere" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <textarea phx-change="update_body"></textarea>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<textarea" end)
    end

    test "reports phx-change given as a dynamic attribute ({...})" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change={@handler} />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "reports phx-change on an ~F body (default :sigils)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end
  end

  describe "&run/2 stays silent once any form marker is in the sigil" do
    test "does not report an input wrapped in <.form>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form for={@form} phx-change="update_q">
            <input type="text" phx-change="update_q" name="q" />
          </.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report phx-change placed directly on <.form> (no input at all)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form for={@form} phx-change="update_q">
            <p>no input here</p>
          </.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report an input wrapped in a plain <form>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <form phx-change="update_q">
            <input type="text" phx-change="update_q" name="q" />
          </form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report an input wrapped in <.simple_form>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.simple_form for={@form} phx-change="update_q">
            <input type="text" phx-change="update_q" name="q" />
          </.simple_form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a second formless input in the same sigil as a <.form> stays silent" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form for={@form} phx-change="update_q">
            <input type="text" name="q" />
          </.form>
          <input type="text" phx-change="unrelated" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a form marker left inside a HEEx comment still exempts the whole sigil" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%!-- <.form for={@form}> --%>
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a form marker left inside an HTML comment still exempts the whole sigil" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <!-- <.form for={@form}> -->
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a > inside an attribute value ends the tag scan early, silencing a real phx-change" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input value={if @count > 1, do: "many"} phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 stays silent on a form-associated element via the HTML form= attribute" do
    test "does not report an input with no form marker in the sigil but a form= attribute on the tag" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input form="checkout" name="q" phx-change="validate" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a form= substring inside a different attribute's quoted value on an <input> silences a real violation" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input placeholder="pick a form='x' value" phx-change="update_q" name="q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: a form= substring inside a different attribute's quoted value on a <select> silences a real violation" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <select title="a form='b'" phx-change="update_kind"><option>a</option></select>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "documented limitation: an empty form=\"\" still exempts the input even though it names no form owner" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input form="" phx-change="validate" name="q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 matches :form_markers at a boundary, not as a bare substring" do
    test "still reports a formless input when the sigil only contains <.form_group>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form_group />
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "still reports a formless input when the sigil only contains <.form_field>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form_field />
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "still reports a formless input when the sigil only contains <.formatting_help>" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.formatting_help />
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end
  end

  describe "&run/2 only scans raw input/select/textarea tags" do
    test "does not report phx-change on a custom component tag (<MyInput>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <MyInput.text_field phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report a bare input with no phx-change at all" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" name="q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report a tag-name lookalike (<inputmask>)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <inputmask type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 recognizes every phx-change attribute spelling" do
    test "reports a single-quoted phx-change value" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change='update_q' />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "reports phx-change with whitespace around the =" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change = "update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "does not report an attribute merely ending in phx-change (data-phx-change)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" data-phx-change="noop" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 documented false positives" do
    test "fires on a field-group component composed inside a sibling function's <.form>" do
      """
      defmodule MyAppWeb.Comp do
        def address_fields(assigns) do
          ~H\"\"\"
          <input type="text" name="street" phx-change="validate" />
          \"\"\"
        end

        def render(assigns) do
          ~H\"\"\"
          <.form for={@form} phx-change="validate">
            <.address_fields />
          </.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "fires on an input wrapped in a HEEx comment" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <%!-- <input type="text" phx-change="update_q" /> --%>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "fires on an input wrapped in an HTML comment" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <!-- <input type="text" phx-change="update_q" /> -->
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "fires on a raw input inside Surface's <Form> component by default (:sigil_F)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~F\"\"\"
          <Form for={@changeset} change="validate"><input type="text" name="q" phx-change="validate" /></Form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "fires on a raw input inside a module-qualified (remote) form component by default" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <Phoenix.Component.form for={@form} phx-change="validate">
            <input type="text" name="q" phx-change="validate" />
          </Phoenix.Component.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "fires on phx-change appearing inside a different attribute's quoted value" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input placeholder=" phx-change='x'" name="q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end
  end

  describe "&run/2 respects :sigils" do
    test "a ~H phx-change is silent once :sigils excludes sigil_H" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange, sigils: [:sigil_F])
      |> refute_issues()
    end

    test "does not report a phx-change-lookalike inside a ~HOLO body (different framework)" do
      """
      defmodule MyAppWeb.Comp do
        def template(assigns) do
          ~HOLO\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end

    test "does not report phx-change inside an ~S string (not a template sigil)" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~S\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> refute_issues()
    end
  end

  describe "&run/2 respects :form_markers" do
    test "still reports once :form_markers no longer includes <.form" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <.form for={@form} phx-change="update_q">
            <input type="text" phx-change="update_q" name="q" />
          </.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange, form_markers: ["<.simple_form"])
      |> assert_issue(fn issue -> assert issue.trigger === "<input" end)
    end

    test "does not report a module-qualified (remote) form component once \".form\" is added to :form_markers" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <Phoenix.Component.form for={@form} phx-change="validate">
            <input type="text" name="q" phx-change="validate" />
          </Phoenix.Component.form>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange, form_markers: ["<.form", "<form", "<.simple_form", ".form"])
      |> refute_issues()
    end
  end

  describe "&run/2 respects :excluded_paths" do
    test "does not report a file under an excluded path" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/generated/comp.ex")
      |> run_check(FormlessPhxChange, excluded_paths: ["generated/"])
      |> refute_issues()
    end

    test "still checks a boundary-lookalike path (autogenerated/ contains 'generated/')" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change="update_q" />
          \"\"\"
        end
      end
      """
      |> to_source_file("apps/my_app_web/lib/autogenerated/comp.ex")
      |> run_check(FormlessPhxChange, excluded_paths: ["generated/"])
      |> assert_issue()
    end
  end

  describe "&run/2 locates each trigger with a column" do
    test "gives two phx-change controls on one line distinct columns" do
      """
      defmodule MyAppWeb.Comp do
        def render(assigns) do
          ~H\"\"\"
          <input type="text" phx-change="a" /><select phx-change="b"></select>
          \"\"\"
        end
      end
      """
      |> to_source_file(@filename)
      |> run_check(FormlessPhxChange)
      |> assert_issues(fn issues ->
        assert length(issues) === 2
        [first, second] = issues
        assert first.line_no === second.line_no
        assert first.column !== second.column
      end)
    end
  end
end
