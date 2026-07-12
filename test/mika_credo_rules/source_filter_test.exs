defmodule MikaCredoRules.SourceFilterTest do
  use ExUnit.Case, async: true

  alias MikaCredoRules.SourceFilter

  doctest MikaCredoRules.SourceFilter

  describe "matches_suffix?/2" do
    test "matches a filename ending with a suffix" do
      assert SourceFilter.matches_suffix?("test/my_app/worker_test.exs", ["_test.exs"])
      assert SourceFilter.matches_suffix?("apps/my_app/lib/my_app/config.ex", ["config.ex"])
    end

    test "does not match a suffix appearing elsewhere in the path" do
      refute SourceFilter.matches_suffix?("test/support/factory.ex", ["_test.exs"])
    end

    test "matches any of several suffixes" do
      assert SourceFilter.matches_suffix?("lib/my_app/settings.ex", ["config.ex", "settings.ex"])
    end

    test "empty suffix list matches nothing" do
      refute SourceFilter.matches_suffix?("lib/my_app/config.ex", [])
    end
  end

  describe "matches_fragment?/2" do
    test "matches a fragment after a directory separator" do
      assert SourceFilter.matches_fragment?("apps/my_app/lib/mix/tasks/deploy.ex", ["mix/tasks/"])
      assert SourceFilter.matches_fragment?("apps/shared_utils/lib/map.ex", ["shared_utils"])
    end

    test "matches a fragment at the start of the path" do
      assert SourceFilter.matches_fragment?("test/support/factory.ex", ["test/"])
      assert SourceFilter.matches_fragment?("mix/tasks/deploy.ex", ["mix/tasks/"])
    end

    test "matches a fragment at the end of the path" do
      assert SourceFilter.matches_fragment?("lib/my_app/worker_test.exs", ["_test.exs"])
    end

    test "does not match a fragment inside a path segment" do
      refute SourceFilter.matches_fragment?("lib/latest/helpers.ex", ["test/"])
      refute SourceFilter.matches_fragment?("lib/vendor/remix/tasks/thing.ex", ["mix/tasks/"])
      refute SourceFilter.matches_fragment?("lib/webhooks/handler.ex", ["web/"])
      refute SourceFilter.matches_fragment?("lib/scorecard/report.ex", ["core/"])
    end

    test "matches any of several fragments" do
      assert SourceFilter.matches_fragment?("lib/legacy/helpers.ex", ["vendor/", "legacy/"])
    end

    test "empty fragment list matches nothing" do
      refute SourceFilter.matches_fragment?("lib/my_app/worker.ex", [])
    end
  end

  describe "script_file?/1" do
    test "true for .exs files" do
      assert SourceFilter.script_file?("mix.exs")
      assert SourceFilter.script_file?("config/config.exs")
      assert SourceFilter.script_file?("test/my_app/worker_test.exs")
    end

    test "false for compiled files" do
      refute SourceFilter.script_file?("lib/my_app/worker.ex")
      refute SourceFilter.script_file?("lib/my_app/worker.exs.ex")
    end
  end
end
