defmodule FeedReader.Core.FeedDeleteTest do
  use Feedreader.DataCase, async: false

  alias FeedReader.Core

  describe "delete_feed/1" do
    test "deletes a feed with no entries" do
      feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml"})

      result = Core.delete_feed(feed)

      assert result == :ok
      assert Core.list_feeds!() |> Enum.filter(&(&1.id == feed.id)) == []
    end

    test "deletes a feed and cascades to its entries" do
      feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml"})

      entry_attrs = %{
        external_id: "entry-1",
        title: "Test Entry",
        content_link: "https://example.com/entry-1",
        feed_id: feed.id
      }

      Core.upsert_from_feed!(entry_attrs)

      # Verify entry was created
      entries = Core.list_entries!().results
      assert length(entries) == 1

      result = Core.delete_feed(feed)

      assert result == :ok

      # Feed should be gone
      feeds = Core.list_feeds!()
      refute Enum.any?(feeds, &(&1.id == feed.id))

      # Entries should be cascaded
      remaining_entries = Core.list_entries!().results
      assert Enum.all?(remaining_entries, &(&1.feed_id != feed.id))
    end

    test "deletes a feed with many entries" do
      feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml"})

      for i <- 1..150 do
        Core.upsert_from_feed!(%{
          external_id: "entry-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/entry-#{i}",
          feed_id: feed.id
        })
      end

      {:ok, page} = Core.list_entries(page: [limit: 200])
      assert length(page.results) == 150

      result = Core.delete_feed(feed)

      assert result == :ok

      feeds = Core.list_feeds!()
      refute Enum.any?(feeds, &(&1.id == feed.id))

      {:ok, remaining} = Core.list_entries(page: [limit: 200])
      assert Enum.all?(remaining.results, &(&1.feed_id != feed.id))
    end
  end
end
