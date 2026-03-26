defmodule FeedReader.Core.FeedTest do
  use Feedreader.DataCase, async: false

  alias FeedReader.Core

  describe "add/1" do
    test "creates a feed with valid attributes" do
      attrs = %{
        name: "Test Feed",
        site_url: "https://example.com",
        feed_url: "https://example.com/feed.xml",
        category: "Tech"
      }

      feed = Core.add_feed!(attrs)

      assert feed.name == "Test Feed"
      assert feed.feed_url == "https://example.com/feed.xml"
      assert feed.category == "Tech"
    end

    test "creates a feed with default category" do
      attrs = %{
        feed_url: "https://example.com/feed.xml"
      }

      feed = Core.add_feed!(attrs)

      assert feed.category == "Uncategorized"
    end

    test "rejects duplicate feed_url" do
      attrs = %{
        name: "Test Feed",
        feed_url: "https://example.com/feed.xml"
      }

      assert %FeedReader.Core.Feed{} = Core.add_feed!(attrs)

      assert_raise Ash.Error.Invalid, fn ->
        Core.add_feed!(attrs)
      end
    end
  end

  describe "import_opml/1" do
    test "imports feeds from opml file" do
      opml_content = File.read!("#{__DIR__}/../../fixtures/feeds.opml")
      {success_count, _errors} = Core.import_opml(opml_content)

      assert success_count > 0
    end

    test "extracts categories from nested outlines" do
      opml_content = File.read!("#{__DIR__}/../../fixtures/feeds.opml")
      {_success_count, _errors} = Core.import_opml(opml_content)

      feeds = Core.list_feeds!()
      categories = Enum.map(feeds, & &1.category) |> Enum.uniq()

      assert "Tech" in categories
      assert "Austin" in categories
    end
  end

  describe "log_fetch_success/1" do
    test "updates last_fetched_at and clears fetch_error" do
      feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml"})

      {:ok, updated} = Core.log_fetch_success(feed)

      assert updated.last_fetched_at != nil
      assert updated.fetch_error == nil
    end
  end

  describe "log_fetch_error/1" do
    test "sets fetch_error" do
      feed = Core.add_feed!(%{feed_url: "https://example.com/feed.xml"})

      {:ok, updated} = Core.log_fetch_error(feed, %{fetch_error: "Network error"})

      assert updated.fetch_error == "Network error"
    end
  end
end
