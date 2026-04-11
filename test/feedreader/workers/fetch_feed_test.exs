defmodule FeedReader.Workers.FetchFeedTest do
  use Feedreader.DataCase, async: false

  alias FeedReader.Workers.FetchFeed
  alias FeedReader.Core

  describe "parse_feed/1" do
    test "parses RSS feed with pubDate" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-1</guid>
            <title>Test Entry</title>
            <link>https://example.com/entry1</link>
            <pubDate>2024-01-15T10:30:00Z</pubDate>
          </item>
        </channel>
      </rss>
      """

      {:ok, entries} = FetchFeed.parse_feed(rss)
      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.title == "Test Entry"
      assert entry.external_id == "entry-1"
      assert entry.content_link == "https://example.com/entry1"
      assert entry.published_at != nil
    end

    test "handles missing dates gracefully" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-3</guid>
            <title>No Date Entry</title>
            <link>https://example.com/entry3</link>
          </item>
        </channel>
      </rss>
      """

      {:ok, entries} = FetchFeed.parse_feed(rss)
      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.published_at == nil
    end

    test "parses ISO8601 dates" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-4</guid>
            <title>Date Entry</title>
            <link>https://example.com/entry4</link>
            <pubDate>2024-06-15T14:30:00Z</pubDate>
          </item>
        </channel>
      </rss>
      """

      {:ok, entries} = FetchFeed.parse_feed(rss)
      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.published_at.year == 2024
      assert entry.published_at.month == 6
      assert entry.published_at.day == 15
    end

    test "parses Atom feed dates from <updated> when <published> is absent" do
      atom = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Atom Feed</title>
        <entry>
          <title>Atom Entry</title>
          <link href="https://example.com/atom1"/>
          <id>https://example.com/atom1</id>
          <updated>2026-03-24T07:00:00.000Z</updated>
        </entry>
      </feed>
      """

      {:ok, entries} = FetchFeed.parse_feed(atom)
      assert length(entries) == 1
      entry = Enum.at(entries, 0)
      assert entry.title == "Atom Entry"
      assert entry.published_at != nil
      assert entry.published_at.year == 2026
      assert entry.published_at.month == 3
      assert entry.published_at.day == 24
    end

    test "converts RFC822 +timezone to UTC correctly" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>tz-pos</guid>
            <title>Pos TZ</title>
            <link>https://example.com/tz</link>
            <pubDate>15 Jan 2026 10:00:00 +0500</pubDate>
          </item>
        </channel>
      </rss>
      """

      {:ok, [entry]} = FetchFeed.parse_feed(rss)
      # +0500 means local is 5h ahead of UTC, so 10:00 +0500 = 05:00 UTC
      assert entry.published_at.hour == 5
    end

    test "converts RFC822 -timezone to UTC correctly" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>tz-neg</guid>
            <title>Neg TZ</title>
            <link>https://example.com/tz</link>
            <pubDate>15 Jan 2026 10:00:00 -0500</pubDate>
          </item>
        </channel>
      </rss>
      """

      {:ok, [entry]} = FetchFeed.parse_feed(rss)
      # -0500 means local is 5h behind UTC, so 10:00 -0500 = 15:00 UTC
      assert entry.published_at.hour == 15
    end

    test "prefers <pubDate> over <published> and <updated> in RSS" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>entry-5</guid>
            <title>Priority Entry</title>
            <link>https://example.com/entry5</link>
            <pubDate>2024-02-01T08:00:00Z</pubDate>
          </item>
        </channel>
      </rss>
      """

      {:ok, entries} = FetchFeed.parse_feed(rss)
      entry = Enum.at(entries, 0)
      assert entry.published_at.month == 2
    end
  end

  describe "Core upsert/lookup" do
    setup do
      feed =
        Core.add_feed!(%{
          feed_url: "http://localhost:0/test.xml",
          name: "Test Feed"
        })

      %{feed: feed}
    end

    test "lookup distinguishes new from existing entries", %{feed: feed} do
      # No entry exists yet - lookup should return nil
      assert {:ok, nil} = Core.get_entry_by_feed_and_external_id(feed.id, "brand-new")

      # Insert an entry
      Core.upsert_from_feed!(%{
        external_id: "brand-new",
        title: "Now Exists",
        content_link: "https://example.com/brand-new",
        feed_id: feed.id
      })

      # Lookup should now find it
      assert {:ok, entry} = Core.get_entry_by_feed_and_external_id(feed.id, "brand-new")
      assert entry.title == "Now Exists"
    end

    test "upsert updates existing entry without creating duplicate", %{feed: feed} do
      Core.upsert_from_feed!(%{
        external_id: "dedup-1",
        title: "Original",
        content_link: "https://example.com/original",
        feed_id: feed.id
      })

      Core.upsert_from_feed!(%{
        external_id: "dedup-1",
        title: "Updated",
        content_link: "https://example.com/updated",
        feed_id: feed.id
      })

      entries = Core.list_entries!().results
      assert length(entries) == 1
      assert hd(entries).title == "Updated"
    end

    test "insert logic only flags truly new entries as inserted", %{feed: feed} do
      # Pre-insert one entry
      Core.upsert_from_feed!(%{
        external_id: "existing-logic",
        title: "Already Here",
        content_link: "https://example.com/existing",
        feed_id: feed.id
      })

      incoming = [
        %{external_id: "existing-logic", title: "Already Here Updated"},
        %{external_id: "brand-new-logic", title: "Actually New"}
      ]

      {inserted, updated} =
        Enum.reduce(incoming, {[], []}, fn entry, {ins, upd} ->
          attrs = Map.put(entry, :feed_id, feed.id)

          existed? =
            case Core.get_entry_by_feed_and_external_id(feed.id, entry.external_id) do
              {:ok, record} when record != nil -> true
              _ -> false
            end

          {:ok, record} = Core.upsert_from_feed(attrs)

          if existed? do
            {ins, [record | upd]}
          else
            {[record | ins], upd}
          end
        end)

      assert length(inserted) == 1
      assert hd(inserted).external_id == "brand-new-logic"
      assert length(updated) == 1
      assert hd(updated).external_id == "existing-logic"
    end
  end
end
