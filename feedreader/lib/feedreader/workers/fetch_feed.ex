defmodule FeedReader.Workers.FetchFeed do
  use Oban.Worker, queue: :default

  require Logger

  alias FeedReader.Core

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"feed_id" => feed_id}}) do
    feed = Core.get_feed!(feed_id)

    case fetch_feed(feed.feed_url) do
      {:ok, entries} ->
        new_entries =
          for entry <- entries do
            case Core.upsert_from_feed(Map.put(entry, :feed_id, feed.id)) do
              {:ok, inserted} -> inserted
              {:error, _} -> nil
            end
          end
          |> Enum.reject(&is_nil/1)

        for entry <- new_entries do
          Phoenix.PubSub.broadcast(Feedreader.PubSub, "entry:created", %{entry: entry})
        end

        Core.log_fetch_success(feed)
        {:ok, length(new_entries)}

      {:error, error} ->
        Core.log_fetch_error(feed, %{fetch_error: inspect(error)})
        {:error, error}
    end
  end

  defp fetch_feed(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        parse_feed(body)

      {:ok, %{status: status}} ->
        {:error, "HTTP status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_feed(body) do
    import SweetXml

    try do
      entries =
        body
        |> xmap(
          items: ~x"//item"l,
          entries: ~x"//entry"l
        )

      items = entries.items ++ entries.entries

      parsed_entries =
        for item <- items do
          guid = xpath(item, ~x"./guid/text()"s)
          title = xpath(item, ~x"./title/text()"s)
          link = xpath(item, ~x"./link/text()"s)
          comments = xpath(item, ~x"./comments/text()"s)

          external_id =
            if guid != nil and guid != "" do
              guid
            else
              link
            end

          %{
            external_id: external_id || link,
            title: title || "",
            content_link: link || "",
            comments_link: if(comments != "", do: comments, else: nil),
            published_at: nil
          }
        end

      {:ok, parsed_entries}
    rescue
      e in RuntimeError ->
        {:error, "XML parse error: #{inspect(e)}"}
    end
  end
end
