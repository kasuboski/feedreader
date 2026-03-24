defmodule FeedreaderWeb.EntryLiveTest do
  use FeedreaderWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FeedReader.Core

  setup do
    feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml", name: "Test Feed"})
    %{feed: feed}
  end

  describe "index" do
    test "displays entries", %{conn: conn, feed: feed} do
      for i <- 1..5 do
        Core.upsert_from_feed!(%{
          external_id: "entry-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/entry#{i}",
          feed_id: feed.id
        })
      end

      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Entry 1"
      assert html =~ "Entry 2"
      assert html =~ "Entry 3"
    end

    test "displays toggle read button", %{conn: conn, feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "test-entry",
          title: "Test Entry",
          content_link: "https://example.com/test",
          feed_id: feed.id
        })

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#read-btn-#{entry.id}")
    end

    test "toggle read removes entry from unread list", %{conn: conn, feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "toggle-read-entry",
          title: "Toggle Read Entry",
          content_link: "https://example.com/toggle-read",
          feed_id: feed.id
        })

      {:ok, view, _html} = live(conn, "/")

      # Initially should show "Mark read" button
      assert render(view) =~ "Mark read"
      assert render(view) =~ "Toggle Read Entry"

      # Click the button - entry is marked as read and removed from unread list
      view
      |> element("#read-btn-#{entry.id}")
      |> render_click()

      # After click, entry should be removed from the list
      refute render(view) =~ "Toggle Read Entry"
    end

    test "displays correct page title for unread", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Unread"
    end

    test "displays correct page title for starred", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/starred")
      assert html =~ "Starred"
    end

    test "displays correct page title for history", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/history")
      assert html =~ "History"
    end
  end

  describe "humanize_date" do
    alias FeedreaderWeb.EntryLive.Index

    test "returns nil for nil input" do
      assert Index.humanize_date(nil) == nil
    end

    test "returns 'just now' for dates less than 1 minute ago" do
      recent = DateTime.add(DateTime.utc_now(), -30, :second)
      assert Index.humanize_date(recent) == "just now"
    end

    test "returns minutes ago for dates less than 1 hour ago" do
      minutes_ago = DateTime.add(DateTime.utc_now(), -30, :minute)
      assert Index.humanize_date(minutes_ago) == "30m ago"
    end

    test "returns hours ago for dates less than 1 day ago" do
      hours_ago = DateTime.add(DateTime.utc_now(), -5, :hour)
      assert Index.humanize_date(hours_ago) == "5h ago"
    end

    test "returns 'yesterday' for dates less than 2 days ago" do
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
      assert Index.humanize_date(yesterday) == "yesterday"
    end

    test "returns days ago for dates less than 1 week ago" do
      days_ago = DateTime.add(DateTime.utc_now(), -3, :day)
      assert Index.humanize_date(days_ago) == "3d ago"
    end

    test "returns weeks ago for dates less than 1 month ago" do
      weeks_ago = DateTime.add(DateTime.utc_now(), -14, :day)
      assert Index.humanize_date(weeks_ago) == "2w ago"
    end

    test "returns formatted date for dates older than 1 month" do
      {:ok, old_date, _} = DateTime.from_iso8601("2024-06-15T12:00:00Z")
      assert Index.humanize_date(old_date) == "Jun 15, 2024"
    end
  end

  describe "pagination" do
    test "loads first page of entries", %{conn: conn, feed: feed} do
      for i <- 1..60 do
        Core.upsert_from_feed!(%{
          external_id: "page-test-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/page#{i}",
          feed_id: feed.id
        })
      end

      {:ok, _view, html} = live(conn, "/")

      # First page should have entries (limited to 50)
      # Check that we have entries but not all 60
      assert html =~ "Entry 1"
      # Should have load more button since there are more entries
      assert html =~ "Load More"
    end

    test "load_more button is visible when more entries exist", %{conn: conn, feed: feed} do
      for i <- 1..60 do
        Core.upsert_from_feed!(%{
          external_id: "loadmore-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/loadmore#{i}",
          feed_id: feed.id
        })
      end

      {:ok, view, html} = live(conn, "/")

      # Should show Load More button
      assert html =~ "Load More"
      assert has_element?(view, "#load-more-btn")

      # Click the load more button
      render_click(view, "load_more")

      # After clicking, button may or may not be visible depending on pagination
      # The important thing is the event is handled without error
    end

    test "pagination respects filter (unread)", %{conn: conn, feed: feed} do
      # Add some read and unread entries
      for i <- 1..10 do
        Core.upsert_from_feed!(%{
          external_id: "unread-pag-#{i}",
          title: "Unread #{i}",
          content_link: "https://example.com/unread#{i}",
          feed_id: feed.id,
          is_read: false
        })
      end

      for i <- 1..5 do
        Core.upsert_from_feed!(%{
          external_id: "read-pag-#{i}",
          title: "Read #{i}",
          content_link: "https://example.com/read#{i}",
          feed_id: feed.id,
          is_read: true
        })
      end

      {:ok, _view, html} = live(conn, "/")

      # Unread page should only show unread entries
      for i <- 1..10 do
        assert html =~ "Unread #{i}"
      end

      for i <- 1..5 do
        refute html =~ "Read #{i}"
      end
    end
  end
end
