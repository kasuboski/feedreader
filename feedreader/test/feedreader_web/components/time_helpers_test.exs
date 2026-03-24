defmodule FeedreaderWeb.TimeHelpersTest do
  use ExUnit.Case, async: true

  alias FeedreaderWeb.TimeHelpers

  describe "humanize_date/1" do
    test "returns nil for nil input" do
      assert TimeHelpers.humanize_date(nil) == nil
    end

    test "returns 'just now' for dates less than 1 minute ago" do
      recent = DateTime.add(DateTime.utc_now(), -30, :second)
      assert TimeHelpers.humanize_date(recent) == "just now"
    end

    test "returns minutes ago for dates less than 1 hour ago" do
      minutes_ago = DateTime.add(DateTime.utc_now(), -30, :minute)
      assert TimeHelpers.humanize_date(minutes_ago) == "30m ago"
    end

    test "returns hours ago for dates less than 1 day ago" do
      hours_ago = DateTime.add(DateTime.utc_now(), -5, :hour)
      assert TimeHelpers.humanize_date(hours_ago) == "5h ago"
    end

    test "returns 'yesterday' for dates less than 2 days ago" do
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
      assert TimeHelpers.humanize_date(yesterday) == "yesterday"
    end

    test "returns days ago for dates less than 1 week ago" do
      days_ago = DateTime.add(DateTime.utc_now(), -3, :day)
      assert TimeHelpers.humanize_date(days_ago) == "3d ago"
    end

    test "returns weeks ago for dates less than 1 month ago" do
      weeks_ago = DateTime.add(DateTime.utc_now(), -14, :day)
      assert TimeHelpers.humanize_date(weeks_ago) == "2w ago"
    end

    test "returns formatted date for dates older than 1 month" do
      {:ok, old_date, _} = DateTime.from_iso8601("2024-06-15T12:00:00Z")
      assert TimeHelpers.humanize_date(old_date) == "Jun 15, 2024"
    end
  end
end
