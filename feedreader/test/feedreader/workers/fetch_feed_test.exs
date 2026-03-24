defmodule FeedReader.Workers.FetchFeedTest do
  use Feedreader.DataCase, async: false

  alias FeedReader.Workers.FetchFeed

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
  end
end
