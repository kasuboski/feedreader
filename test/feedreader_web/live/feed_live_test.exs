defmodule FeedreaderWeb.FeedLiveTest do
  use FeedreaderWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FeedReader.Core

  setup do
    feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml", name: "Test Feed"})
    %{feed: feed}
  end

  describe "feeds index" do
    test "lists feeds", %{conn: conn, feed: feed} do
      {:ok, _view, html} = live(conn, "/feeds")

      assert html =~ feed.name
    end

    test "deletes a feed with no entries", %{conn: conn, feed: feed} do
      {:ok, view, _html} = live(conn, "/feeds")

      html =
        view
        |> element("button[phx-click='delete_feed'][phx-value-id='#{feed.id}']")
        |> render_click()

      assert html =~ "Feed deleted"
      refute html =~ feed.name
    end

    test "deletes a feed and cascades to its entries", %{conn: conn, feed: feed} do
      for i <- 1..3 do
        Core.upsert_from_feed!(%{
          external_id: "entry-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/entry#{i}",
          feed_id: feed.id
        })
      end

      {:ok, view, _html} = live(conn, "/feeds")

      html =
        view
        |> element("button[phx-click='delete_feed'][phx-value-id='#{feed.id}']")
        |> render_click()

      assert html =~ "Feed deleted"
      refute html =~ feed.name
    end
  end
end
