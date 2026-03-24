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

  def parse_feed(body) do
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

          # Try pubDate (RSS) or published (Atom)
          published_raw =
            xpath(item, ~x"./pubDate/text()"s) || xpath(item, ~x"./published/text()"s) ||
              xpath(item, ~x"./updated/text()"s)

          published_at = parse_date(published_raw)

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
            published_at: published_at
          }
        end

      {:ok, parsed_entries}
    rescue
      e in RuntimeError ->
        {:error, "XML parse error: #{inspect(e)}"}
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      _ -> parse_rfc822(date_string)
    end
  end

  defp parse_rfc822(""), do: nil

  defp parse_rfc822(date_string) do
    month_map = %{
      "Jan" => 1,
      "Feb" => 2,
      "Mar" => 3,
      "Apr" => 4,
      "May" => 5,
      "Jun" => 6,
      "Jul" => 7,
      "Aug" => 8,
      "Sep" => 9,
      "Oct" => 10,
      "Nov" => 11,
      "Dec" => 12
    }

    # Normalize: remove day name, handle various timezone formats
    normalized =
      date_string
      # Remove day name
      |> String.replace(~r/^[A-Za-z]{3},?\s*/, "")
      |> String.trim()

    parts = String.split(normalized, " ")

    case parts do
      [day, month, year, time | _rest] ->
        with {d, ""} <- Integer.parse(day),
             {y, ""} <- Integer.parse(year),
             {h, ":" <> rest} <- Integer.parse(time),
             {m, ":" <> s_rest} <- Integer.parse(rest),
             {s, ""} <- Integer.parse(s_rest),
             {:ok, month_num} <- Map.fetch(month_map, month),
             {:ok, date} <- Date.new(y, month_num, d),
             {:ok, time_struct} <- Time.new(h, m, s, 0),
             {:ok, datetime} <- DateTime.new(date, time_struct) do
          # Determine timezone offset
          tz_string = List.last(parts)
          offset = parse_tz_offset(tz_string)
          DateTime.add(datetime, offset, :minute)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_tz_offset(tz) when tz in ["GMT", "UT", "UTC", "Z"], do: 0

  defp parse_tz_offset("+" <> rest) do
    case Integer.parse(rest) do
      {offset, ""} -> offset
      _ -> 0
    end
  end

  defp parse_tz_offset("-" <> rest) do
    case Integer.parse(rest) do
      {offset, ""} -> -offset
      _ -> 0
    end
  end

  defp parse_tz_offset(tz) when is_binary(tz) do
    # Handle "EST", "PST" etc abbreviations
    case tz do
      "EST" -> -300
      "EDT" -> -240
      "CST" -> -360
      "CDT" -> -300
      "MST" -> -420
      "MDT" -> -360
      "PST" -> -480
      "PDT" -> -420
      _ -> 0
    end
  end

  defp parse_tz_offset(_), do: 0
end
