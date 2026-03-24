defmodule FeedReader.Core.EntryTest do
  use Feedreader.DataCase, async: false

  alias FeedReader.Core

  setup do
    feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml", name: "Test"})
    %{feed: feed}
  end

  describe "toggle_starred/1" do
    test "toggles is_starred from false to true", %{feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "entry-1",
          title: "Test Entry",
          content_link: "https://example.com/entry1",
          feed_id: feed.id
        })

      refute entry.is_starred

      assert {:ok, updated} = Core.toggle_starred(entry)

      assert updated.is_starred == true
    end

    test "toggles is_starred from true to false", %{feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "entry-1",
          title: "Test Entry",
          content_link: "https://example.com/entry1",
          feed_id: feed.id,
          is_starred: true
        })

      assert entry.is_starred == true

      assert {:ok, updated} = Core.toggle_starred(entry)

      assert updated.is_starred == false
    end
  end

  describe "toggle_read/1" do
    test "toggles is_read from false to true", %{feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "entry-1",
          title: "Test Entry",
          content_link: "https://example.com/entry1",
          feed_id: feed.id
        })

      refute entry.is_read

      assert {:ok, updated} = Core.toggle_read(entry)

      assert updated.is_read == true
    end
  end

  describe "upsert_from_feed/1" do
    test "creates a new entry", %{feed: feed} do
      attrs = %{
        external_id: "unique-entry-id",
        title: "New Entry",
        content_link: "https://example.com/entry",
        feed_id: feed.id
      }

      entry = Core.upsert_from_feed!(attrs)

      assert entry.title == "New Entry"
      assert entry.external_id == "unique-entry-id"
    end

    test "upserts entry with same external_id does not create duplicate", %{feed: feed} do
      attrs = %{
        external_id: "duplicate-test",
        title: "First Entry",
        content_link: "https://example.com/entry1",
        feed_id: feed.id
      }

      assert %FeedReader.Core.Entry{} = Core.upsert_from_feed!(attrs)

      attrs2 = %{
        external_id: "duplicate-test",
        title: "Updated Entry",
        content_link: "https://example.com/entry1-updated",
        feed_id: feed.id
      }

      entry2 = Core.upsert_from_feed!(attrs2)

      assert entry2.title == "Updated Entry"

      entries = Core.list_entries!()
      assert length(entries) == 1
    end
  end

  describe "unread/0" do
    test "returns only unread entries", %{feed: feed} do
      _entry1 =
        Core.upsert_from_feed!(%{
          external_id: "unread-1",
          title: "Unread Entry",
          content_link: "https://example.com/unread1",
          feed_id: feed.id
        })

      entry2 =
        Core.upsert_from_feed!(%{
          external_id: "read-1",
          title: "Read Entry",
          content_link: "https://example.com/read1",
          feed_id: feed.id,
          is_read: true
        })

      assert entry2.is_read == true

      {:ok, updated_entry2} = Core.toggle_read(entry2)

      assert updated_entry2.is_read == false

      {:ok, results} = Core.list_unread()

      assert length(results.results) == 2
    end
  end

  describe "starred/0" do
    test "returns only starred entries", %{feed: feed} do
      _entry1 =
        Core.upsert_from_feed!(%{
          external_id: "starred-1",
          title: "Starred Entry",
          content_link: "https://example.com/starred1",
          feed_id: feed.id,
          is_starred: true
        })

      _entry2 =
        Core.upsert_from_feed!(%{
          external_id: "unstarred-1",
          title: "Unstarred Entry",
          content_link: "https://example.com/unstarred1",
          feed_id: feed.id,
          is_starred: false
        })

      {:ok, results} = Core.list_starred()

      assert length(results.results) == 1
      assert hd(results.results).title == "Starred Entry"
    end
  end

  describe "pagination" do
    test "list_unread accepts page limit option", %{feed: feed} do
      for i <- 1..15 do
        Core.upsert_from_feed!(%{
          external_id: "pagination-#{i}",
          title: "Entry #{i}",
          content_link: "https://example.com/#{i}",
          feed_id: feed.id
        })
      end

      {:ok, results} = Core.list_unread(page: [limit: 10])
      assert length(results.results) == 10
    end

    test "list_unread returns correct count", %{feed: feed} do
      for i <- 1..5 do
        Core.upsert_from_feed!(%{
          external_id: "count-test-#{i}",
          title: "Count Entry #{i}",
          content_link: "https://example.com/count-#{i}",
          feed_id: feed.id
        })
      end

      {:ok, results} = Core.list_unread(page: [limit: 100])
      assert length(results.results) == 5
    end
  end
end
