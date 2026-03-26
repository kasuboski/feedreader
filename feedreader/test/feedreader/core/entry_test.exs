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
          feed_id: feed.id
        })

      {:ok, entry} = Core.update_entry(entry, %{is_starred: true})

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

    test "toggles is_read from true to false", %{feed: feed} do
      entry =
        Core.upsert_from_feed!(%{
          external_id: "entry-1",
          title: "Test Entry",
          content_link: "https://example.com/entry1",
          feed_id: feed.id
        })

      {:ok, entry} = Core.update_entry(entry, %{is_read: true})

      assert entry.is_read == true

      assert {:ok, updated} = Core.toggle_read(entry)

      assert updated.is_read == false
    end
  end

  describe "get_entry_by_feed_and_external_id/2" do
    test "returns entry when it exists", %{feed: feed} do
      Core.upsert_from_feed!(%{
        external_id: "lookup-1",
        title: "Lookup Entry",
        content_link: "https://example.com/lookup1",
        feed_id: feed.id
      })

      assert {:ok, entry} = Core.get_entry_by_feed_and_external_id(feed.id, "lookup-1")
      assert entry.title == "Lookup Entry"
    end

    test "returns {:ok, nil} when entry does not exist", %{feed: feed} do
      assert {:ok, nil} = Core.get_entry_by_feed_and_external_id(feed.id, "nonexistent")
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
      unread_entry =
        Core.upsert_from_feed!(%{
          external_id: "unread-1",
          title: "Unread Entry",
          content_link: "https://example.com/unread1",
          feed_id: feed.id
        })

      read_entry =
        Core.upsert_from_feed!(%{
          external_id: "read-1",
          title: "Read Entry",
          content_link: "https://example.com/read1",
          feed_id: feed.id
        })

      {:ok, _} = Core.update_entry(read_entry, %{is_read: true})

      {:ok, results} = Core.list_unread()

      assert length(results.results) == 1
      assert hd(results.results).id == unread_entry.id
      assert hd(results.results).title == "Unread Entry"
    end
  end

  describe "starred/0" do
    test "returns only starred entries", %{feed: feed} do
      entry1 =
        Core.upsert_from_feed!(%{
          external_id: "starred-1",
          title: "Starred Entry",
          content_link: "https://example.com/starred1",
          feed_id: feed.id
        })

      {:ok, _} = Core.update_entry(entry1, %{is_starred: true})

      _entry2 =
        Core.upsert_from_feed!(%{
          external_id: "unstarred-1",
          title: "Unstarred Entry",
          content_link: "https://example.com/unstarred1",
          feed_id: feed.id
        })

      {:ok, results} = Core.list_starred()

      assert length(results.results) == 1
      assert hd(results.results).title == "Starred Entry"
    end
  end

  describe "ordering" do
    test "list_unread returns entries sorted by published_at ascending (oldest first)", %{
      feed: feed
    } do
      now = DateTime.utc_now()

      _older =
        Core.upsert_from_feed!(%{
          external_id: "order-1",
          title: "Older Entry",
          content_link: "https://example.com/older",
          feed_id: feed.id,
          published_at: DateTime.add(now, -3600, :second)
        })

      _newer =
        Core.upsert_from_feed!(%{
          external_id: "order-2",
          title: "Newer Entry",
          content_link: "https://example.com/newer",
          feed_id: feed.id,
          published_at: DateTime.add(now, -1800, :second)
        })

      _oldest =
        Core.upsert_from_feed!(%{
          external_id: "order-3",
          title: "Oldest Entry",
          content_link: "https://example.com/oldest",
          feed_id: feed.id,
          published_at: DateTime.add(now, -7200, :second)
        })

      {:ok, results} = Core.list_unread(page: [limit: 100])

      titles = Enum.map(results.results, & &1.title)
      assert titles == ["Oldest Entry", "Older Entry", "Newer Entry"]
    end

    test "list_starred returns entries sorted by published_at ascending", %{feed: feed} do
      now = DateTime.utc_now()

      older =
        Core.upsert_from_feed!(%{
          external_id: "starred-order-1",
          title: "Older Starred",
          content_link: "https://example.com/older",
          feed_id: feed.id,
          published_at: DateTime.add(now, -3600, :second)
        })

      {:ok, _} = Core.update_entry(older, %{is_starred: true})

      newer =
        Core.upsert_from_feed!(%{
          external_id: "starred-order-2",
          title: "Newer Starred",
          content_link: "https://example.com/newer",
          feed_id: feed.id,
          published_at: DateTime.add(now, -1800, :second)
        })

      {:ok, _} = Core.update_entry(newer, %{is_starred: true})

      {:ok, results} = Core.list_starred()

      titles = Enum.map(results.results, & &1.title)
      assert titles == ["Older Starred", "Newer Starred"]
    end

    test "list_history returns entries sorted by published_at descending", %{feed: feed} do
      now = DateTime.utc_now()

      older =
        Core.upsert_from_feed!(%{
          external_id: "history-order-1",
          title: "Older History",
          content_link: "https://example.com/older",
          feed_id: feed.id,
          published_at: DateTime.add(now, -3600, :second)
        })

      {:ok, _} = Core.update_entry(older, %{is_read: true})

      newer =
        Core.upsert_from_feed!(%{
          external_id: "history-order-2",
          title: "Newer History",
          content_link: "https://example.com/newer",
          feed_id: feed.id,
          published_at: DateTime.add(now, -1800, :second)
        })

      {:ok, _} = Core.update_entry(newer, %{is_read: true})

      {:ok, results} = Core.list_history()

      titles = Enum.map(results.results, & &1.title)
      assert titles == ["Newer History", "Older History"]
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
