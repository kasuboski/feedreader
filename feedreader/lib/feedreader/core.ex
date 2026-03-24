defmodule FeedReader.Core do
  @moduledoc "Ash domain exposing feed and entry operations."
  use Ash.Domain

  import SweetXml

  def import_opml(opml_content) do
    categories = opml_content |> xpath(~x"//body/outline"l)

    feeds =
      Enum.flat_map(categories, fn category ->
        category_name = xpath(category, ~x"@text"s) || "Imported"
        category_name = if category_name != "", do: category_name, else: "Imported"

        category
        |> xpath(~x"./outline[@xmlUrl]"l)
        |> Enum.map(fn outline ->
          title = xpath(outline, ~x"@title"s) || xpath(outline, ~x"@text"s) || "Untitled"
          feed_url = xpath(outline, ~x"@xmlUrl"s)
          site_url = xpath(outline, ~x"@htmlUrl"s)

          %{
            feed_url: feed_url,
            name: title,
            site_url: if(site_url != "", do: site_url, else: nil),
            category: category_name
          }
        end)
      end)

    results =
      Enum.map(feeds, fn feed_attrs ->
        case add_feed(feed_attrs) do
          {:ok, feed} -> {:ok, feed}
          {:error, reason} -> {:error, {feed_attrs, reason}}
        end
      end)

    {Enum.count(results, &match?({:ok, _}, &1)), Enum.count(results, &match?({:error, _}, &1))}
  end

  resources do
    resource FeedReader.Core.Feed do
      define :list_feeds, action: :read
      define :get_feed, action: :read, get_by: [:id]
      define :add_feed, action: :add
      define :delete_feed, action: :destroy
      define :log_fetch_success, action: :log_fetch_success
      define :log_fetch_error, action: :log_fetch_error
    end

    resource FeedReader.Core.Entry do
      define :list_entries, action: :read
      define :get_entry, action: :read, get_by: [:id]
      define :list_unread, action: :unread
      define :list_starred, action: :starred
      define :list_history, action: :history
      define :toggle_read, action: :toggle_read
      define :toggle_starred, action: :toggle_starred
      define :upsert_from_feed, action: :upsert_from_feed
      define :update_entry, action: :update
    end
  end
end
